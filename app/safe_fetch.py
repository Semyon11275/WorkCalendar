"""Bounded public-web retrieval with DNS pinned to validated addresses."""
import http.client
import ipaddress
import socket
import ssl
from urllib.parse import urlsplit, urljoin


def resolve_public(url):
    parts = urlsplit(url)
    if parts.scheme not in ('http', 'https') or not parts.hostname or parts.username or parts.password:
        raise RuntimeError('仅支持无凭据的 http/https 网页地址')
    host = parts.hostname.encode('idna').decode('ascii')
    port = parts.port or (443 if parts.scheme == 'https' else 80)
    if port not in (80, 443):
        raise RuntimeError('抓网页仅允许 80/443 端口')
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError as e:
        raise RuntimeError('域名解析失败') from e
    if not infos:
        raise RuntimeError('域名没有可用地址')
    for family, kind, protocol, _, address in infos:
        ip = ipaddress.ip_address(address[0].split('%')[0])
        if not ip.is_global or ip.is_multicast or ip.is_reserved or getattr(ip, 'ipv4_mapped', None):
            raise RuntimeError('禁止访问非公网地址')
    return parts, host, port, infos


def fetch_raw(url, timeout=15, max_hops=4):
    for _ in range(max_hops):
        parts, host, port, infos = resolve_public(url)
        connection = http.client.HTTPConnection(host, port, timeout=timeout)
        last_error = None
        for family, kind, protocol, _, address in infos:
            sock = socket.socket(family, kind, protocol)
            try:
                sock.settimeout(timeout)
                sock.connect(address)  # Numeric address already validated; no second DNS lookup.
                if parts.scheme == 'https':
                    sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
                connection.sock = sock
                break
            except OSError as e:
                sock.close()
                last_error = e
        if connection.sock is None:
            raise RuntimeError('网页连接失败') from last_error
        try:
            path = parts.path or '/'
            if parts.query:
                path += '?' + parts.query
            connection.request('GET', path, headers={'User-Agent':'WorkCalendar/0.4.2', 'Accept-Encoding':'identity'})
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader('Location')
                if not location:
                    raise RuntimeError('重定向缺少地址')
                url = urljoin(url, location)
                continue
            if response.status != 200:
                raise RuntimeError('抓取失败：HTTP ' + str(response.status))
            raw = response.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                raise RuntimeError('网页超过 1MB 上限')
            return raw.decode(response.headers.get_content_charset() or 'utf-8', errors='replace')
        except (OSError, ValueError, http.client.HTTPException) as e:
            raise RuntimeError('网页读取失败') from e
        finally:
            connection.close()
    raise RuntimeError('重定向次数过多')
