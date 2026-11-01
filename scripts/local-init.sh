#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  [[ ! -d data/postgres && ! -d data/synapse ]] || {
    echo "Existing data has no .env; restore its original credentials before continuing." >&2
    exit 1
  }
  umask 077
  python3 - <<'PY'
from pathlib import Path
import os
import secrets

template = Path('.env.example').read_text()
marker = 'replace-with-a-long-random-password'
if template.count(marker) != 1:
    raise SystemExit('Unexpected .env.example password placeholder')
content = template.replace(marker, secrets.token_urlsafe(48))
with os.fdopen(os.open('.env', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as file:
    file.write(content)
PY
fi

[[ -f .env ]] || { echo '.env is missing.' >&2; exit 1; }
python3 scripts/render-config.py
if grep -q '^POSTGRES_PASSWORD=replace-with-a-long-random-password$' .env; then
  echo 'Replace the example database password before continuing.' >&2
  exit 1
fi

PUBLIC_BASE_URL=$(python3 scripts/render-config.py --get PUBLIC_BASE_URL)
LOCAL_HOST=$(python3 scripts/render-config.py --get LOCAL_HOST)
LOCAL_ELEMENT_PORT=$(python3 scripts/render-config.py --get LOCAL_ELEMENT_PORT)

scripts/init.sh

# Derive the local config without changing the Matrix server identity or signing key.
docker run --rm --pull never -i -v "$PWD/data/synapse:/data" \
  -e PUBLIC_BASE_URL="$PUBLIC_BASE_URL" \
  -e LOCAL_HOST="$LOCAL_HOST" \
  -e LOCAL_ELEMENT_PORT="$LOCAL_ELEMENT_PORT" \
  --entrypoint python3 matrixdotorg/synapse:v1.161.0 - <<'PY'
from pathlib import Path
import os
import re
import yaml

source = Path('/data/homeserver.yaml')
target = Path('/data/homeserver.local.yaml')
original = source.read_text()
old_url = f'public_baseurl: "{os.environ["PUBLIC_BASE_URL"].rstrip("/")}/"'
if original.count(old_url) != 1:
    raise SystemExit('Expected production public_baseurl was not found; preserving existing configuration')

local_url = f'public_baseurl: "http://{os.environ["LOCAL_HOST"]}:{os.environ["LOCAL_ELEMENT_PORT"]}/"'
expected = original.replace(old_url, local_url, 1)

# The production whitelist contains an environment-specific Docker IP. Do not
# copy it into local config, where that address may identify a different host.
# Preserve an existing local whitelist only when it is identical to the expected
# local policy (currently: no explicit whitelist).
def remove_production_whitelist(content):
    return re.sub(
        r'(?m)^# Allow the internal Nginx reverse proxy for push delivery\.\n'
        r'# Keep the default IP blocklist enabled\.\n'
        r'# WARNING: This IP must remain assigned to Nginx\.\n'
        r'ip_range_whitelist:\n(?:[ \t]+- [^\n]+\n)+',
        '',
        content,
        count=1,
    )

expected = remove_production_whitelist(expected)

def without_managed_blocks(content):
    for name in ('retention', 'room permissions', 'room encryption default', 'TURN'):
        content = re.sub(
            rf'(?ms)^# BEGIN managed {re.escape(name)} configuration\n.*?^# END managed {re.escape(name)} configuration\n?',
            '',
            content,
        )
    content = re.sub(r'(?m)^block_non_admin_invites: (?:true|false)\n?', '', content)
    content = re.sub(r'(?m)^encryption_enabled_by_default_for_room_type: .*\n?', '', content)
    return content

def ensure_room_encryption_default(content):
    content = re.sub(
        r'(?ms)^# BEGIN managed room encryption default configuration\n.*?^# END managed room encryption default configuration\n?',
        '',
        content,
    )
    content = re.sub(r'(?m)^encryption_enabled_by_default_for_room_type: .*\n?', '', content)
    anchor = re.search(r'(?m)^signing_key_path:', content)
    if not anchor:
        raise SystemExit('Could not find signing_key_path in local Synapse config')
    managed = (
        '# BEGIN managed room encryption default configuration\n'
        '# Applies only to rooms created after Synapse reads this configuration.\n'
        'encryption_enabled_by_default_for_room_type: all\n'
        '# END managed room encryption default configuration\n\n'
    )
    return content[:anchor.start()] + managed + content[anchor.start():]

def normalized(content):
    result = yaml.safe_load(without_managed_blocks(content))
    if not isinstance(result, dict):
        raise SystemExit('Invalid Synapse configuration: expected YAML mapping')
    return result

if target.exists():
    original_current = target.read_text()
    current = ensure_room_encryption_default(original_current)
    if normalized(current) != normalized(expected):
        current_data = normalized(current)
        expected_data = normalized(expected)
        changed = sorted(k for k in current_data.keys() | expected_data.keys()
                         if current_data.get(k) != expected_data.get(k))
        raise SystemExit(
            'Existing local Synapse config has meaningful differences in: '
            + ', '.join(changed)
            + '; refusing to overwrite it'
        )
    # Preserve the existing local config byte-for-byte when equivalent.
    if current != original_current:
        target.write_text(current)
        print('Added the managed room-encryption default to the existing local Synapse configuration.')
    else:
        print('Existing local Synapse config is compatible; preserving it.')
else:
    # Do not silently create a local config containing a production-specific IP.
    if 'ip_range_whitelist' in normalized(expected):
        raise SystemExit('Production IP whitelist could not be safely removed for local use')
    with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as file:
        file.write(expected)
    os.chown(target, 991, 991)
    print('Created local Synapse configuration.')
PY

python3 scripts/render-config.py
mkdir -p data/element
if [[ ! -f data/element/index.html ]]; then
  [[ -f offline-bundle/static/element/index.html ]] || {
    echo 'Element assets missing; run the verified offline export before local setup.' >&2
    exit 1
  }
  cp -a offline-bundle/static/element/. data/element/
fi
chmod 755 data/element
echo 'Local assets and configuration are ready. Existing data and credentials were preserved.'
