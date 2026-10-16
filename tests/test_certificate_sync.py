import base64
from pathlib import Path
from urllib.parse import urlencode
import unittest
from . import test_security
from app.models import new_award


class CertificateSyncTests(unittest.TestCase):
    setUp = test_security.SecurityTests.setUp
    tearDown = test_security.SecurityTests.tearDown
    request = test_security.SecurityTests.request
    def prepare(self):
        self.api.paired_tokens.add('phone')
        self.store.upsert_award(new_award('Test', certificate_files=['same.png', 'same.jpg', '../private.txt']))
        for name, value in [('same.png', b'original PNG'), ('same.jpg', b'original JPG'),
                            ('same.png.preview.jpg', b'PNG preview'), ('same.jpg.preview.jpg', b'JPG preview'),
                            ('unreferenced.txt', b'private')]:
            Path(self.store.certificates_dir, name).write_bytes(value)

    def test_phone_syncs_referenced_original_and_distinct_previews(self):
        self.prepare()
        for name, preview, expected in [('same.png', '', b'original PNG'), ('same.png', '1', b'PNG preview'), ('same.jpg', '1', b'JPG preview')]:
            status, _, data = self.request('GET', '/api/sync_certificate?' + urlencode({'name': name, 'preview': preview}), headers={'X-Sync-Token': 'phone'})
            self.assertEqual(status, 200)
            self.assertEqual(base64.b64decode(data['data']), expected)

    def test_sync_does_not_grant_static_admin_or_unreferenced_access(self):
        self.prepare()
        headers={'X-Sync-Token': 'phone'}
        self.assertEqual(self.request('GET', '/api/sync_certificate?name=same.png')[0], 401)
        self.assertEqual(self.request('GET', '/api/sync_certificate?name=unreferenced.txt', headers=headers)[0], 403)
        self.assertEqual(self.request('GET', '/api/sync_certificate?name=..%2Fprivate.txt', headers=headers)[0], 400)
        self.assertEqual(self.request('POST', '/api/sync_certificate', {}, headers)[0], 405)
        self.assertEqual(self.request('GET', '/certificates/same.png', headers=headers)[0], 401)
        self.assertEqual(self.request('GET', '/api/ai_config', headers=headers)[0], 403)
        self.api.paired_tokens.clear()
        self.assertEqual(self.request('GET', '/api/sync_certificate?name=same.png', headers=headers)[0], 401)

    def test_sync_missing_preview_and_large_original(self):
        self.prepare()
        Path(self.store.certificates_dir,'same.png.preview.jpg').unlink()
        self.assertEqual(self.request('GET','/api/sync_certificate?name=same.png&preview=1',headers={'X-Sync-Token':'phone'})[0],404)
        with Path(self.store.certificates_dir,'same.png').open('wb') as f:
            f.truncate(16*1024*1024+1)
        self.assertEqual(self.request('GET','/api/sync_certificate?name=same.png',headers={'X-Sync-Token':'phone'})[0],413)

    def test_attachment_ticket_opens_external_browser_without_cookie(self):
        """PDF 等附件在外部浏览器（无会话 Cookie）经一次性票据打开。"""
        import http.client
        self.prepare()
        auth = {'X-API-Token': self.api.token}
        status, _, ticket = self.request('POST', '/api/attachment_ticket', {'name': 'same.png'}, headers=auth)
        self.assertEqual(status, 200)
        # 票据直链（无 Cookie）可读
        conn = http.client.HTTPConnection('127.0.0.1', self.api.port, timeout=3)
        conn.request('GET', ticket['url'])
        r = conn.getresponse()
        self.assertEqual(r.status, 200)
        self.assertEqual(r.read(), b'original PNG')
        conn.close()
        # 一次性：重放 401；错名票据 401；未引用附件 404
        self.assertEqual(self.request('GET', ticket['url'])[0], 401)
        s2, _, t2 = self.request('POST', '/api/attachment_ticket', {'name': 'same.png'}, headers=auth)
        self.assertEqual(s2, 200)
        forged = t2['url'].rsplit('?', 1)[0] + '?ticket=' + t2['ticket']
        # 用 same.png 的票据去取 same.jpg → 名不符 → 401
        self.assertEqual(self.request('GET', '/certificates/same.jpg?ticket=' + t2['ticket'])[0], 401)
        self.assertEqual(self.request('POST', '/api/attachment_ticket', {'name': 'unreferenced.txt'}, headers=auth)[0], 404)
        # 配对手机无权开票据（非 phone_paths）
        self.assertEqual(self.request('POST', '/api/attachment_ticket', {'name': 'same.png'},
                                     headers={'X-Sync-Token': 'phone'})[0], 403)

    def test_attachment_ticket_handles_unicode_and_spaces(self):
        """中文/带空格附件名：URL 编码后票据仍能正确绑定与打开（0.5.0 修复项）。"""
        import http.client
        from urllib.parse import quote
        names = ['获奖证书 2026.pdf', '中文凭证.png', 'with space.jpg']
        self.store.upsert_award(new_award('Test2', certificate_files=names))
        for name in names:
            Path(self.store.certificates_dir, name).write_bytes(b'UNICODE-OK ' + name.encode('utf-8'))
        auth = {'X-API-Token': self.api.token}
        for name in names:
            status, _, ticket = self.request('POST', '/api/attachment_ticket', {'name': name}, headers=auth)
            self.assertEqual(status, 200, name)
            self.assertIn(quote(name), ticket['url'])
            conn = http.client.HTTPConnection('127.0.0.1', self.api.port, timeout=3)
            conn.request('GET', ticket['url'])
            r = conn.getresponse()
            body = r.read()
            conn.close()
            self.assertEqual(r.status, 200, name)
            self.assertTrue(body.startswith(b'UNICODE-OK'), name)
        # 手工构造未编码的中文路径 + 有效票据：同样放行（服务端统一解码）
        status, _, ticket = self.request('POST', '/api/attachment_ticket', {'name': names[0]}, headers=auth)
        conn = http.client.HTTPConnection('127.0.0.1', self.api.port, timeout=3)
        conn.request('GET', '/certificates/' + quote(names[0]) + '?ticket=' + ticket['ticket'])
        r = conn.getresponse(); r.read(); conn.close()
        self.assertEqual(r.status, 200)
