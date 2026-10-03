import tempfile, pathlib, plistlib, zipfile, unittest, json, base64, hashlib, os, shutil, subprocess
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from unittest import mock
import upload_signed_ipa
from upload_signed_ipa import AppleUpload, ipa_metadata, signed_token, validate_ranges

class FakeAppleUpload(AppleUpload):
    def __init__(self):
        self.calls = []
        self.upload_records = []
        self.lose_response = False
        self.file_state = 'UPLOAD_COMPLETE'
    def api(self, path, method='GET', body=None):
        self.calls.append((path, method))
        if path.startswith('apps?'): return {'data': [{'id': 'app'}]}
        if path.startswith('apps/app/buildUploads'): return {'data': self.upload_records}
        if path == 'buildUploads' and method == 'POST':
            self.upload_records = [self.build('AWAITING_UPLOAD')]
            if self.lose_response: raise RuntimeError('response lost')
            return {'data': self.upload_records[0]}
        if path.endswith('/buildUploadFiles'):
            return {'data': [{'id': 'file', 'attributes': {
                'fileName': 'app.ipa', 'fileSize': self.size,
                'assetDeliveryState': {'state': self.file_state}, 'uploadOperations': None}}]}
        if path == 'buildUploads/upload': return {'data': self.build('COMPLETE')}
        raise AssertionError((path, method))
    @staticmethod
    def build(state):
        return {'id': 'upload', 'attributes': {'cfBundleShortVersionString': '0.1.1',
            'cfBundleVersion': '23', 'state': {'state': state}}}

class UploadResumeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ipa = pathlib.Path(self.tmp.name) / 'app.ipa'
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/Sumly.app/Info.plist', plistlib.dumps({
                'CFBundleIdentifier': 'com.oryjk.sumly', 'CFBundleVersion': '23',
                'CFBundleShortVersionString': '0.1.1'}))
        self.state = self.ipa.with_suffix('.asc-upload-state.json')
        self.client = FakeAppleUpload()
        self.client.size = self.ipa.stat().st_size
    def save_reservation(self):
        self.state.write_text(json.dumps({'buildUploadID': 'upload',
            'ipaSHA256': hashlib.sha256(self.ipa.read_bytes()).hexdigest()}))
    def test_unknown_post_outcome_reconciles_without_second_post(self):
        self.client.lose_response = True
        with self.assertRaises(RuntimeError): self.client.upload(self.ipa, self.state)
        self.assertTrue(self.state.exists())
        self.client.upload(self.ipa, self.state)
        self.assertEqual(sum(method == 'POST' for _, method in self.client.calls), 1)
        self.assertEqual(json.loads(self.state.read_text())['buildUploadID'], 'upload')
    def test_unknown_outcome_without_visible_reservation_does_not_recreate(self):
        self.client.lose_response = True
        with self.assertRaises(RuntimeError): self.client.upload(self.ipa, self.state)
        self.client.upload_records = []
        with self.assertRaises(RuntimeError): self.client.upload(self.ipa, self.state)
        self.assertEqual(sum(method == 'POST' for _, method in self.client.calls), 1)
    def test_committed_file_is_polled_without_put(self):
        self.save_reservation()
        # First GET resumes an unfinished task; the next completes processing.
        original = self.client.api
        first = True
        def api(path, method='GET', body=None):
            nonlocal first
            if path == 'buildUploads/upload' and first:
                first = False
                return {'data': self.client.build('AWAITING_UPLOAD')}
            return original(path, method, body)
        self.client.api = api
        self.client.upload(self.ipa, self.state)
    def test_processing_task_only_polls(self):
        self.save_reservation()
        original = self.client.api
        first = True
        def api(path, method='GET', body=None):
            nonlocal first
            if path == 'buildUploads/upload' and first:
                first = False
                return {'data': self.client.build('PROCESSING')}
            return original(path, method, body)
        self.client.api = api
        self.client.upload(self.ipa, self.state)
        self.assertFalse(any(path.endswith('/buildUploadFiles') for path, _ in self.client.calls))
    def test_ambiguous_pending_reservation_stops_without_post(self):
        self.client.lose_response = True
        with self.assertRaises(RuntimeError): self.client.upload(self.ipa, self.state)
        extra = self.client.build('AWAITING_UPLOAD')
        extra['id'] = 'another-upload'
        self.client.upload_records.append(extra)
        with self.assertRaises(RuntimeError): self.client.upload(self.ipa, self.state)
        self.assertEqual(sum(method == 'POST' for _, method in self.client.calls), 1)
    def test_project_version_mismatch_rejected_before_any_apple_request(self):
        self.save_reservation()
        old_state = self.state.read_bytes()
        with mock.patch('sys.argv', ['upload', str(self.ipa), '--expected-version', '0.1.2', '--expected-build', '23']), \
                mock.patch.object(upload_signed_ipa, 'AppleUpload') as client:
            with self.assertRaises(ValueError): upload_signed_ipa.main()
            client.assert_not_called()
        self.assertEqual(self.state.read_bytes(), old_state)

class UploadShellResumeTests(unittest.TestCase):
    def run_shell(self, missing_ipa=False):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            scripts = root / 'scripts'
            scripts.mkdir()
            shutil.copy(pathlib.Path(__file__).with_name('upload_app_store.sh'), scripts)
            info = root / 'Sumly/Support/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.1.1', 'CFBundleVersion': '23'}))
            export = root / 'build/ipa-b23'
            export.mkdir(parents=True)
            state = export / 'Sumly.asc-upload-state.json'
            state.write_text('preserve state')
            if not missing_ipa: (export / 'Sumly.ipa').write_text('preserve IPA')
            archive = root / 'build/Sumly-0.1.1-b23.xcarchive'
            archive.mkdir()
            marker = archive / 'keep'
            marker.write_text('preserve archive')
            fake_bin = root / 'bin'
            fake_bin.mkdir()
            for name, code in {'xcodegen': 'exit 0', 'xcodebuild': 'exit 99',
                'python3': 'printf "%s\\n" "$@" > "$FAKE_UPLOAD_ARGS"'}.items():
                file = fake_bin / name
                file.write_text('#!/bin/bash\n' + code + '\n')
                file.chmod(0o755)
            key = root / 'fake.p8'
            key.write_text('test fixture only')
            args = root / 'args'
            env = dict(os.environ, PATH=str(fake_bin) + ':' + os.environ['PATH'],
                ASC_KEY_ID='fixture', ASC_ISSUER_ID='fixture', ASC_KEY_PATH=str(key),
                SUMLY_ASC_CONFIG=str(root / 'missing-config'), FAKE_UPLOAD_ARGS=str(args))
            result = subprocess.run(['bash', str(scripts / 'upload_app_store.sh')], env=env,
                capture_output=True, text=True, timeout=5)
            self.assertEqual(state.read_text(), 'preserve state')
            self.assertEqual(marker.read_text(), 'preserve archive')
            if missing_ipa:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(args.exists())
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('build/ipa-b23/Sumly.ipa', args.read_text())
                self.assertIn('--expected-version\n0.1.1\n--expected-build\n23', args.read_text())
                self.assertEqual((export / 'Sumly.ipa').read_text(), 'preserve IPA')
    def test_default_command_resumes_without_deleting_state_or_rearchiving(self):
        self.run_shell()
    def test_default_command_preserves_state_when_ipa_missing(self):
        self.run_shell(missing_ipa=True)

class UploadSafetyTests(unittest.TestCase):
    def test_metadata_comes_from_signed_package(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)/'app.ipa'
            with zipfile.ZipFile(p,'w') as z:
                z.writestr('Payload/Sumly.app/Info.plist',plistlib.dumps({'CFBundleIdentifier':'com.oryjk.sumly','CFBundleVersion':'23','CFBundleShortVersionString':'0.1.1'}))
                z.writestr('Payload/Sumly.app/Frameworks/Other.framework/Info.plist',b'ignored')
            self.assertEqual(ipa_metadata(p),('com.oryjk.sumly','0.1.1','23'))
    def test_other_app_cannot_be_uploaded_as_sumly(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)/'wrong.ipa'
            with zipfile.ZipFile(p,'w') as z:
                z.writestr('Payload/Other.app/Info.plist',plistlib.dumps({'CFBundleIdentifier':'other','CFBundleVersion':'23','CFBundleShortVersionString':'0.1.1'}))
            with self.assertRaises(ValueError): ipa_metadata(p)
    def test_jwt_signature_and_bounded_lifetime(self):
        key=ec.generate_private_key(ec.SECP256R1())
        token=signed_token(key,'key-id','issuer-id',1000)
        h,p,s=token.split('.')
        decode=lambda v:base64.urlsafe_b64decode(v+'='*(-len(v)%4))
        payload=json.loads(decode(p))
        self.assertEqual(payload,{'iss':'issuer-id','iat':1000,'exp':1900,'aud':'appstoreconnect-v1'})
        signature=decode(s)
        self.assertEqual(len(signature),64)
        der=encode_dss_signature(int.from_bytes(signature[:32],'big'),int.from_bytes(signature[32:],'big'))
        key.public_key().verify(der,(h+'.'+p).encode(),ec.ECDSA(hashes.SHA256()))
    def test_upload_must_cover_exact_file_without_overlapping_ranges(self):
        validate_ranges([{'offset':0,'length':5},{'offset':5,'length':5}],10)
        for ops in [[{'offset':0,'length':11}],[{'offset':0,'length':5}],[{'offset':0,'length':6},{'offset':5,'length':5}]]:
            with self.assertRaises(ValueError):validate_ranges(ops,10)

if __name__=='__main__':unittest.main()
