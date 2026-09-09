import http.client
import json
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from app.api import ApiServer, ApiHandler
from app.storage import Store


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(self.tmp.name)
        self.store.start()
        self.api = ApiServer(self.store, token='test-owner', web_dir=str(Path(__file__).resolve().parents[1] / 'web'))
        self.api.start()

    def tearDown(self):
        self.api.stop()
        self.store.stop()
        self.tmp.cleanup()

    def request(self, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.api.port, timeout=3)
        try:
            conn.request(method, path, json.dumps(body) if body is not None else None, headers or {})
            r = conn.getresponse()
            raw = r.read()
            try: raw = json.loads(raw)
            except (ValueError, UnicodeDecodeError): pass
            return r.status, dict(r.getheaders()), raw
        finally:
            conn.close()

    def test_cross_origin_bootstrap_rejected(self):
        self.assertEqual(self.request('GET', '/api/bootstrap', headers={'Origin':'https://evil.invalid','X-WorkCalendar-Bootstrap':'1'})[0],403)

    def test_host_rebinding_rejected(self):
        self.assertEqual(self.request('GET', '/api/bootstrap', headers={'Host':'evil.invalid','X-WorkCalendar-Bootstrap':'1'})[0],403)

    def test_bootstrap_requires_custom_header(self):
        self.assertEqual(self.request('GET', '/api/bootstrap')[0],403)

    def test_bootstrap_same_origin(self):
        code, headers, body = self.request('GET','/api/bootstrap',headers={'X-WorkCalendar-Bootstrap':'1'})
        self.assertEqual(code,200)
        self.assertEqual(body['token'],'test-owner')
        self.assertNotEqual(headers.get('Access-Control-Allow-Origin'),'*')

    def test_certificates_require_credentials(self):
        Path(self.store.certificates_dir,'test.txt').write_text('test')
        self.assertEqual(self.request('GET','/certificates/test.txt')[0],401)
        self.assertEqual(self.request('GET','/certificates/test.txt',headers={'X-API-Token':'test-owner'})[0],200)

    def test_remote_cannot_start_or_approve(self):
        with patch.object(ApiHandler,'_client_ip',return_value='192.0.2.5'):
            self.assertEqual(self.request('GET','/api/pair/begin')[0],403)
            self.assertEqual(self.request('POST','/api/pair/approve',{'code':'123456','allow':True})[0],403)

    def test_paired_device_cannot_change_ai_config(self):
        self.api.paired_tokens.add('phone')
        self.assertEqual(self.request('POST','/api/ai_config',{'base_url':'https://evil.invalid'}, {'X-Sync-Token':'phone'})[0],403)

    def test_pair_requires_owner_approval(self):
        owner={'X-API-Token':'test-owner'}
        code=self.request('GET','/api/pair/begin',headers=owner)[2]['code']
        self.assertFalse(self.api.paired_tokens)
        confirmation=self.request('POST','/api/pair/confirm',{'code':code})
        self.assertEqual(confirmation[0],202)
        self.assertFalse(self.api.paired_tokens)
        rid=confirmation[2]['request_id']
        self.assertTrue(self.request('POST','/api/pair/result',{'request_id':rid})[2]['pending'])
        self.assertEqual(self.request('POST','/api/pair/approve',{'code':code,'allow':True})[0],401)
        self.assertEqual(self.request('POST','/api/pair/approve',{'code':code,'allow':True},owner)[0],200)
        confirmed=self.request('POST','/api/pair/result',{'request_id':rid})
        self.assertEqual(confirmed[0],200)
        self.assertIn(confirmed[2]['token'],self.api.paired_tokens)

    def test_attachment_and_ai_status(self):
        self.assertEqual(self.request('GET','/ai_files.js')[0],200)
        self.api.ai_jobs['test']={'running':False,'status':'done','result':{'ok':True,'reply':'done'},'ts':time.time()}
        result=self.request('GET','/api/ai_status?id=test',headers={'X-API-Token':'test-owner'})
        self.assertEqual(result[0],200)
        self.assertEqual(result[2]['reply'],'done')

    def test_empty_token_does_not_disable_auth(self):
        self.api.token=None
        self.assertEqual(self.request('GET','/api/competitions')[0],401)

    def test_pair_denial_and_expiry(self):
        owner={'X-API-Token':'test-owner'}
        code=self.request('GET','/api/pair/begin',headers=owner)[2]['code']
        rid=self.request('POST','/api/pair/confirm',{'code':code})[2]['request_id']
        self.request('POST','/api/pair/approve',{'code':code,'allow':False},owner)
        self.assertEqual(self.request('POST','/api/pair/result',{'request_id':rid})[0],403)
        self.assertFalse(self.api.paired_tokens)
        self.api.pending_pairs[code]['expires']=time.time()-1
        self.assertEqual(self.request('POST','/api/pair/result',{'request_id':rid})[0],403)

    def test_token_write_failure_stops_startup(self):
        from app.main import load_token
        with patch('builtins.open',side_effect=PermissionError('test')):
            with self.assertRaises(RuntimeError): load_token(self.tmp.name)

    def test_certificate_cookie_is_scoped_and_html_sandboxed(self):
        _, headers, _=self.request('GET','/api/bootstrap',headers={'X-WorkCalendar-Bootstrap':'1'})
        cookie=headers['Set-Cookie']
        self.assertIn('HttpOnly',cookie)
        self.assertIn('SameSite=Strict',cookie)
        self.assertIn('Path=/certificates/',cookie)
        Path(self.store.certificates_dir,'test.html').write_text('<script>alert(1)</script>')
        result=self.request('GET','/certificates/test.html',headers={'Cookie':cookie.split(';')[0]})
        self.assertEqual(result[0],200)
        self.assertIn('sandbox',result[1]['Content-Security-Policy'])
