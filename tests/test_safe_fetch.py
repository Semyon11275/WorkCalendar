import io
import socket
import unittest
from unittest.mock import patch, MagicMock
from app.safe_fetch import resolve_public, fetch_raw


class SafeFetchTests(unittest.TestCase):
    def info(self, ip):
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, '', (ip, 80))]

    def test_private_dns_and_mixed_answers_rejected(self):
        for ip in ['127.0.0.1','10.0.0.1','169.254.169.254','100.64.0.1','224.0.0.1']:
            with patch('socket.getaddrinfo',return_value=self.info(ip)):
                with self.assertRaises(RuntimeError): resolve_public('http://example.test')
        with patch('socket.getaddrinfo',return_value=self.info('8.8.8.8')+self.info('127.0.0.1')):
            with self.assertRaises(RuntimeError): resolve_public('http://example.test')

    def test_connection_pins_validated_ip(self):
        sock=MagicMock()
        sock.makefile.return_value=io.BytesIO(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok')
        with patch('socket.getaddrinfo',side_effect=[self.info('8.8.8.8'),self.info('127.0.0.1')]) as dns, patch('socket.socket',return_value=sock):
            self.assertEqual(fetch_raw('http://example.test'),'ok')
            self.assertEqual(dns.call_count,1)
            sock.connect.assert_called_once_with(('8.8.8.8',80))

    def test_redirect_to_private_rejected(self):
        sock=MagicMock()
        sock.makefile.return_value=io.BytesIO(b'HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1/\r\nContent-Length: 0\r\n\r\n')
        with patch('socket.getaddrinfo',side_effect=[self.info('8.8.8.8'),self.info('127.0.0.1')]), patch('socket.socket',return_value=sock):
            with self.assertRaises(RuntimeError): fetch_raw('http://example.test')

    def test_credentials_scheme_ports_rejected(self):
        for url in ['file:///etc/passwd','http://user:pass@example.test','http://example.test:8080']:
            with self.assertRaises(RuntimeError): resolve_public(url)
