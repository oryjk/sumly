#!/usr/bin/env python3
"""Upload an exported Sumly IPA with JWT-signed Apple Build Upload API requests.

Reference: https://developer.apple.com/documentation/appstoreconnectapi/build-uploads
Credentials and signed storage URLs are never logged. Interrupted uploads reuse
an on-disk reservation bound to the IPA checksum; POST creates are never retried.
"""
import argparse
import base64
import hashlib
import fcntl
import json
import os
from pathlib import Path
import plistlib
import time
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


def ipa_metadata(path):
    with zipfile.ZipFile(path) as archive:
        names = [n for n in archive.namelist() if len(n.split('/')) == 3
                 and n.startswith('Payload/') and n.split('/')[1].endswith('.app')
                 and n.endswith('/Info.plist')]
        if len(names) != 1:
            raise ValueError('IPA must contain exactly one main app')
        info = plistlib.loads(archive.read(names[0]))
    if info.get('CFBundleIdentifier') != 'com.oryjk.sumly':
        raise ValueError('IPA bundle identifier does not match Sumly')
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not isinstance(version, str) or not isinstance(build, str) or not version or not build:
        raise ValueError('IPA version and build number must be nonempty strings')
    return info['CFBundleIdentifier'], version, build


def signed_token(key, key_id, issuer, now):
    def b64(data):
        return base64.urlsafe_b64encode(data).rstrip(b'=')
    header = b64(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode())
    payload = b64(json.dumps({'iss': issuer, 'iat': now, 'exp': now + 900,
                            'aud': 'appstoreconnect-v1'}).encode())
    message = header + b'.' + payload
    r, s = decode_dss_signature(key.sign(message, ec.ECDSA(hashes.SHA256())))
    signature = b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))
    return (message + b'.' + signature).decode()


def validate_ranges(operations, size):
    boundary = 0
    for op in sorted(operations, key=lambda o: o['offset']):
        if op['offset'] != boundary or op['length'] <= 0:
            raise ValueError('Upload ranges must cover the file without gaps or overlaps')
        boundary += op['length']
    if boundary != size:
        raise ValueError('Upload ranges do not match IPA size')


class AppleUpload:
    def __init__(self, direct):
        self.key_id = os.environ['ASC_KEY_ID']
        self.issuer = os.environ['ASC_ISSUER_ID']
        self.key = serialization.load_pem_private_key(Path(os.environ['ASC_KEY_PATH']).read_bytes(), password=None)
        if not isinstance(self.key, ec.EllipticCurvePrivateKey) or not isinstance(self.key.curve, ec.SECP256R1):
            raise ValueError('API key must use P-256')
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({})) if direct else urllib.request.build_opener()

    def request(self, request, attempts):
        for attempt in range(attempts):
            try:
                with self.opener.open(request, timeout=45) as response:
                    return response.read()
            except urllib.error.HTTPError as error:
                if error.code not in [429, 500, 502, 503, 504] or attempt + 1 == attempts:
                    # The URL may contain temporary storage credentials.
                    raise RuntimeError(f'Apple request failed with HTTP {error.code}') from None
            except (urllib.error.URLError, TimeoutError):
                if attempt + 1 == attempts:
                    raise RuntimeError('Network request failed; reuse the saved reservation on retry') from None
            print('Retrying transient network failure', flush=True)
            time.sleep(2)

    def api(self, path, method='GET', body=None):
        token = signed_token(self.key, self.key_id, self.issuer, int(time.time()))
        request = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/' + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}, method=method)
        raw = self.request(request, 3 if method in ['GET', 'PATCH'] else 1)
        return json.loads(raw) if raw else {}

    def upload(self, ipa, state_path):
        # One process may create/resume this reservation at a time.
        fd = os.open(str(state_path) + '.lock', os.O_CREAT | os.O_WRONLY, 0o600)
        with os.fdopen(fd, 'w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('Another process is uploading this IPA') from None
            self._upload(ipa, state_path)

    @staticmethod
    def save_state(path, saved, exclusive=False):
        if exclusive:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(fd, 'w') as file:
                json.dump(saved, file)
                file.flush()
                os.fsync(file.fileno())
            return
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + '.')
        try:
            with os.fdopen(fd, 'w') as file:
                json.dump(saved, file)
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)

    def reservations(self, app_id, version, build):
        path = 'apps/' + app_id + '/buildUploads?' + urllib.parse.urlencode({
            'filter[cfBundleShortVersionString]': version,
            'filter[cfBundleVersion]': build, 'filter[platform]': 'IOS', 'limit': 200})
        result = []
        while path:
            page = self.api(path)
            result.extend(page['data'])
            next_url = page.get('links', {}).get('next')
            if not next_url: break
            url = urllib.parse.urlsplit(next_url)
            if url.scheme != 'https' or url.netloc != 'api.appstoreconnect.apple.com' or not url.path.startswith('/v1/'):
                raise ValueError('Unexpected reservation pagination URL')
            path = url.path[4:] + ('?' + url.query if url.query else '')
        return result

    def _upload(self, ipa, state_path):
        bundle, version, build = ipa_metadata(ipa)
        apps = self.api('apps?' + urllib.parse.urlencode({'filter[bundleId]': bundle}))['data']
        if len(apps) != 1:
            raise ValueError('Expected exactly one matching App Store app')
        app_id = apps[0]['id']
        checksum = hashlib.sha256(ipa.read_bytes()).hexdigest()
        if state_path.exists():
            saved = json.loads(state_path.read_text())
            if saved['ipaSHA256'] != checksum:
                raise ValueError('Saved reservation belongs to a different IPA')
            if saved.get('appID', app_id) != app_id:
                raise ValueError('Saved reservation belongs to a different app')
            if not saved.get('buildUploadID'):
                candidates = [item for item in self.reservations(app_id, version, build)
                    if item['id'] not in saved['previousUploadIDs']]
                if len(candidates) != 1:
                    raise RuntimeError('Reservation creation outcome is uncertain; keep the state file and inspect Apple uploads before retrying')
                saved['buildUploadID'] = candidates[0]['id']
                self.save_state(state_path, saved)
            upload = self.api('buildUploads/' + saved['buildUploadID'])['data']
            attrs = upload['attributes']
            if (attrs['cfBundleShortVersionString'], attrs['cfBundleVersion']) != (version, build):
                raise ValueError('Saved reservation version does not match IPA')
        else:
            # Persist intent before POST. A lost response must never create a
            # second reservation on restart; reconcile against this baseline.
            saved = {'ipaSHA256': checksum, 'appID': app_id,
                'previousUploadIDs': [item['id'] for item in self.reservations(app_id, version, build)]}
            self.save_state(state_path, saved, exclusive=True)
            upload = self.api('buildUploads', 'POST', {'data': {'type': 'buildUploads',
                'attributes': {'cfBundleShortVersionString': version, 'cfBundleVersion': build, 'platform': 'IOS'},
                'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})['data']
            saved['buildUploadID'] = upload['id']
            self.save_state(state_path, saved)
        uid = upload['id']
        print(f'Build {version} ({build}), upload reservation {uid}', flush=True)
        # COMPLETE is terminal: do not reserve or re-upload a file on reruns.
        if upload['attributes']['state']['state'] == 'COMPLETE':
            print('Apple processing already completed', flush=True)
            return
        if upload['attributes']['state']['state'] == 'PROCESSING':
            self.poll(uid)
            return
        files = self.api('buildUploads/' + uid + '/buildUploadFiles')['data']
        if len(files) > 1:
            raise ValueError('Multiple file reservations require inspection before retry')
        if not files and saved.get('fileReservationPending'):
            raise RuntimeError('File reservation outcome is uncertain; preserve the state and inspect Apple uploads')
        if not files:
            saved['fileReservationPending'] = True
            self.save_state(state_path, saved)
        file = files[0] if files else self.api('buildUploadFiles', 'POST', {'data': {
            'type': 'buildUploadFiles', 'attributes': {'fileName': ipa.name, 'fileSize': ipa.stat().st_size,
                'assetType': 'ASSET', 'uti': 'com.apple.ipa'},
            'relationships': {'buildUpload': {'data': {'type': 'buildUploads', 'id': uid}}}}})['data']
        attrs = file['attributes']
        if attrs['fileSize'] != ipa.stat().st_size or attrs['fileName'] != ipa.name:
            raise ValueError('Saved file reservation does not match IPA')
        if attrs['assetDeliveryState']['state'] not in ['UPLOAD_COMPLETE', 'COMPLETE']:
            operations = attrs.get('uploadOperations') or []
            validate_ranges(operations, ipa.stat().st_size)
            with ipa.open('rb') as source:
                for index, operation in enumerate(operations):
                    if urllib.parse.urlsplit(operation['url']).scheme != 'https' or operation['method'] != 'PUT':
                        raise ValueError('Expected HTTPS PUT upload operation')
                    source.seek(operation['offset'])
                    chunk = source.read(operation['length'])
                    headers = {h['name']: h['value'] for h in operation.get('requestHeaders', [])}
                    # Only Apple-provided storage headers; never forward the API JWT.
                    request = urllib.request.Request(operation['url'], data=chunk, headers=headers, method='PUT')
                    self.request(request, 3)
                    print(f'Uploaded part {index + 1}/{len(operations)}', flush=True)
            self.api('buildUploadFiles/' + file['id'], 'PATCH', {'data': {'type': 'buildUploadFiles', 'id': file['id'],
                'attributes': {'uploaded': True, 'sourceFileChecksums': {'file': {
                    'algorithm': 'MD5', 'hash': hashlib.md5(ipa.read_bytes()).hexdigest()}}}}})
            print('Apple accepted the signed IPA', flush=True)
        self.poll(uid)

    def poll(self, uid):
        deadline = time.monotonic() + 1200
        previous = None
        while time.monotonic() < deadline:
            state = self.api('buildUploads/' + uid)['data']['attributes']['state']
            status = state['state']
            if status != previous:
                print('Apple processing:', status, flush=True)
                previous = status
            if state.get('errors') or status in ['FAILED', 'INVALID']:
                raise RuntimeError('Apple processing failed: ' + json.dumps(state))
            if status == 'COMPLETE':
                return
            time.sleep(20)
        raise RuntimeError('Apple processing is still pending; check the saved upload ID')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--state', type=Path, help='Reuse a known upload reservation')
    parser.add_argument('--direct', action='store_true', help='Bypass proxy for this process only; TLS verification stays enabled')
    parser.add_argument('--expected-version', help='Reject an IPA that does not match the requested project version')
    parser.add_argument('--expected-build', help='Reject an IPA that does not match the requested project build')
    args = parser.parse_args()
    _, version, build = ipa_metadata(args.ipa)
    if ((args.expected_version is not None and args.expected_version != version)
            or (args.expected_build is not None and args.expected_build != build)):
        raise ValueError('Signed IPA does not match the current project version/build; preserve the existing IPA and recovery state')
    state = args.state or args.ipa.with_suffix('.asc-upload-state.json')
    AppleUpload(args.direct).upload(args.ipa.resolve(), state.resolve())


if __name__ == '__main__':
    main()
