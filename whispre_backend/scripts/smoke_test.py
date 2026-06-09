#!/usr/bin/env python3
import argparse
import base64
import json
import secrets
import sys
import uuid
from datetime import UTC, datetime
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


class SmokeTestError(RuntimeError):
    pass


class APIError(SmokeTestError):
    def __init__(self, method: str, path: str, status: int, body: str) -> None:
        super().__init__(f'{method} {path} returned HTTP {status}: {body}')
        self.status = status
        self.body = body


class APIClient:
    def __init__(self, base_url: str, timeout: float) -> None:
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout

    def request(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        headers: dict[str, str] | None = None,
        query: dict[str, str] | None = None,
        body: dict | None = None,
    ):
        url = f'{self.base_url}{path}'
        if query:
            url = f'{url}?{urlencode(query)}'

        request_headers = {'Accept': 'application/json'}
        if token:
            request_headers['Authorization'] = f'Bearer {token}'
        if headers:
            request_headers.update(headers)

        request_body = None
        if body is not None:
            request_body = json.dumps(body).encode('utf-8')
            request_headers['Content-Type'] = 'application/json'

        request = Request(url, data=request_body, headers=request_headers, method=method)
        try:
            with urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
        except HTTPError as exc:
            raw = exc.read().decode('utf-8', errors='replace')
            raise APIError(method, path, exc.code, raw) from exc
        except URLError as exc:
            raise SmokeTestError(f'Cannot reach {url}: {exc.reason}') from exc

        if not raw:
            return None
        return json.loads(raw.decode('utf-8'))


def random_base64(byte_count: int) -> str:
    return base64.b64encode(secrets.token_bytes(byte_count)).decode('ascii')


def device_bundle(device_name: str) -> dict:
    return {
        'device_name': device_name,
        'platform': 'ios',
        'identity_key_pub': random_base64(32),
        'identity_signing_key_pub': random_base64(32),
        'signed_prekey_id': 1,
        'signed_prekey_pub': random_base64(32),
        'signed_prekey_signature': random_base64(64),
        'one_time_prekeys': [
            {
                'prekey_id': 100_000 + index,
                'prekey_pub': random_base64(32),
            }
            for index in range(1, 4)
        ],
    }


def register_user(client: APIClient, label: str, run_id: str) -> dict:
    email = f'whispre-smoke-{label}-{run_id}@example.com'
    username = f'smoke_{label}_{run_id}'
    tokens = client.request(
        'POST',
        '/v1/auth/register',
        body={
            'username': username,
            'email': email,
            'password': f'Smoke-{run_id}-Pass!',
        },
    )
    me = client.request('GET', '/v1/users/me', token=tokens['access_token'])
    return {
        'id': me['id'],
        'username': username,
        'access_token': tokens['access_token'],
        'refresh_token': tokens['refresh_token'],
    }


def register_device(client: APIClient, user: dict, label: str) -> str:
    requested_device_id = str(uuid.uuid4())
    response = client.request(
        'POST',
        '/v1/auth/devices/register',
        token=user['access_token'],
        headers={'X-Device-Id': requested_device_id},
        body=device_bundle(f'Smoke {label} device'),
    )
    if response['device_id'] != requested_device_id:
        raise SmokeTestError('Device registration returned an unexpected device id')
    if response['one_time_prekeys_uploaded'] != 3:
        raise SmokeTestError('Device registration did not upload all one-time prekeys')
    return requested_device_id


def envelope_payload(
    *,
    conversation_id: str,
    sender: dict,
    sender_device_id: str,
    recipient: dict,
    recipient_device_id: str,
) -> dict:
    return {
        'envelope_id': str(uuid.uuid4()),
        'conversation_id': conversation_id,
        'sender_user_id': sender['id'],
        'sender_device_id': sender_device_id,
        'recipient_user_id': recipient['id'],
        'recipient_device_id': recipient_device_id,
        'ciphertext': f'e2e1:{random_base64(96)}',
        'header': {
            'ratchet_pub': f'sess:{uuid.uuid4()}:smoke',
            'pn': 0,
            'n': 1,
            'protocol_version': 2,
            'sender_ephemeral_pub': random_base64(32),
            'signed_prekey_id': 1,
            'one_time_prekey_id': 100_001,
        },
        'sent_at_client': datetime.now(UTC).isoformat(),
    }


def expect_status(expected_status: int, operation) -> None:
    try:
        operation()
    except APIError as exc:
        if exc.status == expected_status:
            return
        raise
    raise SmokeTestError(f'Expected HTTP {expected_status}, but request succeeded')


def run_smoke_test(base_url: str, timeout: float) -> None:
    client = APIClient(base_url, timeout)
    run_id = secrets.token_hex(4)

    print(f'[1/10] Checking gateway health at {base_url}')
    health = client.request('GET', '/health')
    if health.get('status') != 'ok':
        raise SmokeTestError(f'Gateway health is not ok: {health}')

    print('[2/10] Registering Alice and Bob')
    alice = register_user(client, 'alice', run_id)
    bob = register_user(client, 'bob', run_id)

    print('[3/10] Registering both devices and key bundles')
    alice_device_id = register_device(client, alice, 'Alice')
    bob_device_id = register_device(client, bob, 'Bob')

    print('[4/10] Checking Bob key bundle and claiming a one-time prekey')
    bundles = client.request(
        'GET',
        f"/v1/keys/users/{bob['id']}/bundles",
        token=alice['access_token'],
    )
    if not bundles or bundles[0]['device_id'] != bob_device_id:
        raise SmokeTestError('Bob key bundle was not returned')

    claimed_bundle = client.request(
        'POST',
        f"/v1/keys/users/{bob['id']}/one-time-prekey/claim",
        token=alice['access_token'],
        query={'device_id': bob_device_id},
    )
    if not claimed_bundle.get('one_time_prekey'):
        raise SmokeTestError('One-time prekey claim returned no prekey')

    print('[5/10] Creating a direct conversation')
    conversation = client.request(
        'POST',
        '/v1/conversations/direct',
        token=alice['access_token'],
        body={'peer_user_id': bob['id']},
    )
    conversation_id = conversation['id']

    envelope = envelope_payload(
        conversation_id=conversation_id,
        sender=alice,
        sender_device_id=alice_device_id,
        recipient=bob,
        recipient_device_id=bob_device_id,
    )

    print('[6/10] Verifying recipient-device spoofing is rejected')
    spoofed_envelope = dict(envelope)
    spoofed_envelope['envelope_id'] = str(uuid.uuid4())
    spoofed_envelope['recipient_device_id'] = alice_device_id
    expect_status(
        403,
        lambda: client.request(
            'POST',
            '/v1/messages/envelopes:batch',
            token=alice['access_token'],
            body={
                'idempotency_key': str(uuid.uuid4()),
                'envelopes': [spoofed_envelope],
            },
        ),
    )

    print('[7/10] Sending a valid encrypted envelope')
    sent = client.request(
        'POST',
        '/v1/messages/envelopes:batch',
        token=alice['access_token'],
        body={
            'idempotency_key': str(uuid.uuid4()),
            'envelopes': [envelope],
        },
    )
    if sent.get('accepted') != 1:
        raise SmokeTestError(f'Expected one accepted envelope, got: {sent}')

    print('[8/10] Reading Bob pending envelopes')
    pending = client.request(
        'GET',
        '/v1/messages/envelopes/pending',
        token=bob['access_token'],
        query={'device_id': bob_device_id, 'limit': '100'},
    )
    pending_ids = {item['envelope_id'] for item in pending}
    if envelope['envelope_id'] not in pending_ids:
        raise SmokeTestError('Sent envelope was not found in Bob pending queue')

    print('[9/10] Checking conversation history and acknowledging delivery')
    history = client.request(
        'GET',
        f'/v1/messages/conversations/{conversation_id}',
        token=bob['access_token'],
        query={'limit': '100'},
    )
    history_ids = {item['envelope_id'] for item in history}
    if envelope['envelope_id'] not in history_ids:
        raise SmokeTestError('Sent envelope was not found in conversation history')

    client.request(
        'POST',
        f"/v1/messages/envelopes/{envelope['envelope_id']}/ack",
        token=bob['access_token'],
        body={'device_id': bob_device_id},
    )

    print('[10/10] Verifying acknowledged envelope is no longer pending')
    pending_after_ack = client.request(
        'GET',
        '/v1/messages/envelopes/pending',
        token=bob['access_token'],
        query={'device_id': bob_device_id, 'limit': '100'},
    )
    pending_after_ack_ids = {item['envelope_id'] for item in pending_after_ack}
    if envelope['envelope_id'] in pending_after_ack_ids:
        raise SmokeTestError('Acknowledged envelope is still pending')

    print('SMOKE TEST PASSED')
    print(f'Created users: {alice["username"]}, {bob["username"]}')
    print(f'Conversation: {conversation_id}')
    print(f'Envelope: {envelope["envelope_id"]}')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Run the Whispre backend critical-path smoke test.')
    parser.add_argument(
        '--base-url',
        default='http://localhost:8000',
        help='API gateway base URL (default: http://localhost:8000)',
    )
    parser.add_argument(
        '--timeout',
        type=float,
        default=10.0,
        help='HTTP request timeout in seconds (default: 10)',
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        run_smoke_test(args.base_url, args.timeout)
    except (SmokeTestError, json.JSONDecodeError) as exc:
        print(f'SMOKE TEST FAILED: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
