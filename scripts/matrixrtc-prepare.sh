#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
[[ $(python3 scripts/render-config.py --get MATRIX_RTC_ENABLED) == 1 ]] || { echo 'Set MATRIX_RTC_ENABLED=1 and valid CALL_* values in .env first.' >&2; exit 1; }
[[ -f data/synapse/homeserver.yaml ]] || { echo 'Initialize the existing Synapse deployment before preparing MatrixRTC.' >&2; exit 1; }
[[ -f secrets/matrixrtc-tls/fullchain.pem && -f secrets/matrixrtc-tls/privkey.pem ]] || { echo 'Missing secrets/matrixrtc-tls/{fullchain,privkey}.pem for CALL_DOMAIN.' >&2; exit 1; }
mkdir -p secrets/matrixrtc data/matrixrtc
chmod 700 secrets/matrixrtc data/matrixrtc
random_secret() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
for name in livekit-api-key livekit-api-secret as-token hs-token; do
  target="secrets/matrixrtc/$name"
  [[ -f $target ]] || random_secret > "$target"
  chmod 600 "$target"
done
python3 - <<'PY'
from pathlib import Path
root = Path.cwd(); env = {}
for raw in (root / '.env').read_text().splitlines():
    line = raw.strip()
    if line and not line.startswith('#'):
        key, value = line.split('=', 1); env[key] = value
secrets = root / 'secrets/matrixrtc'
values = {
    'CALL_DOMAIN': env['CALL_DOMAIN'], 'CALL_PUBLIC_IP': env['CALL_PUBLIC_IP'],
    'CALL_RTC_TCP_PORT': env['CALL_RTC_TCP_PORT'],
    'CALL_RTC_UDP_MIN_PORT': env['CALL_RTC_UDP_MIN_PORT'],
    'CALL_RTC_UDP_MAX_PORT': env['CALL_RTC_UDP_MAX_PORT'],
    'LIVEKIT_API_KEY': (secrets / 'livekit-api-key').read_text().strip(),
    'LIVEKIT_API_SECRET': (secrets / 'livekit-api-secret').read_text().strip(),
    'AS_TOKEN': (secrets / 'as-token').read_text().strip(),
    'HS_TOKEN': (secrets / 'hs-token').read_text().strip(),
}
def render(template, destination):
    text = (root / template).read_text()
    for key, value in values.items(): text = text.replace(f'__{key}__', value)
    if '__' in text: raise SystemExit(f'unrendered placeholder in {template}')
    destination.write_text(text); destination.chmod(0o600)
render('config/matrixrtc/livekit.yaml.template', root / 'data/matrixrtc/livekit.yaml')
registration = secrets / 'appservice.yaml'
render('config/matrixrtc/appservice.yaml.template', registration)
synapse_registration = root / 'data/synapse/matrixrtc-lk-jwt-service.yaml'
synapse_registration.write_text(registration.read_text()); synapse_registration.chmod(0o600)
PY
python3 scripts/render-config.py --matrixrtc-synapse
echo 'MatrixRTC configuration and private credentials are prepared. No containers were started or restarted.'
