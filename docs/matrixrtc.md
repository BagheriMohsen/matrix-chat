# Opt-in MatrixRTC calling

This stages the supported MatrixRTC backend for private 1:1 calls: LiveKit SFU
and Element's MatrixRTC Authorization Service (`lk-jwt-service`). It does not
add a standalone Element Call application, Jitsi, SaaS, guest access, group
calling, or federation. Normal stack commands do not reference this overlay.

## Compatibility and security

The prepared stack targets Synapse `v1.161.0`, Element Web `v1.12.33`, LiveKit
`v1.13.11`, and `lk-jwt-service` `0.9.0`. Synapse 1.161 supports the newer
MatrixRTC transport URL and the legacy authorization URL; both are staged so
Element Web 1.12.x and Element X Android/iOS can discover the service.

The authorization service is a Synapse application service, limited to the
local `MATRIX_SERVER_NAME`; LiveKit refuses automatic room creation and remote
homeservers cannot publish. This retains the existing federation policy.

Matrix signalling remains in the existing encrypted direct-message room.
LiveKit is an SFU and terminates WebRTC media transport, so this is not
media-E2EE. It supports local Android↔Android, Android↔iOS, iOS↔iOS, and
Element Web↔Element X 1:1 audio/video tests.

The existing coturn `calls` profile is a legacy TURN relay only. It does not
provide the MatrixRTC focus, token authorization, or SFU needed by Element X.
HTTPS reverse proxying supplies signalling only; LiveKit also requires public
media ports.

## Prerequisites before approval

1. Pick a new `CALL_DOMAIN`, distinct from Matrix and UnifiedPush domains, and
   create a public DNS A record for the host's actual public IPv4 address.
2. Obtain a separate CA-issued certificate and install it as
   `secrets/matrixrtc-tls/{fullchain.pem,privkey.pem}` mode 600. Do not alter
   existing Matrix or ntfy certificates.
3. Set `MATRIX_RTC_ENABLED=1`, `CALL_DOMAIN`, and `CALL_PUBLIC_IP` in `.env`.
   The supplied overlay fixes ports to TCP/UDP 7881 and UDP 50000-50100.
4. Open/forward only TCP 443 (already Nginx), TCP 7881, UDP 7881, and UDP
   50000-50100. Never expose 7880, 8080, Synapse 8008, PostgreSQL, or private
   network ranges. `CALL_PUBLIC_IP` must not be RFC1918, CGNAT, or a container
   address.

## Production changes requiring separate approval

These commands modify production state; do not run them until the prerequisites
and a maintenance window are approved.

```sh
# Generates private LiveKit/appservice credentials and config; starts nothing.
bash scripts/matrixrtc-prepare.sh

# Static checks only.
docker compose -f compose.yaml -f compose.matrixrtc.yaml --profile matrixrtc config -q

# Starts only new services. Then Synapse must restart once to load the
# appservice registration and MatrixRTC configuration.
docker compose -f compose.yaml -f compose.matrixrtc.yaml --profile matrixrtc up -d --no-deps livekit lk-jwt-service
docker compose -f compose.yaml up -d --no-deps --force-recreate synapse

# Add only the new CALL_DOMAIN vhost after validation.
docker compose exec -T nginx nginx -t
docker compose exec -T nginx nginx -s reload
```

The Synapse restart is unavoidable because it loads the MatrixRTC transport,
OpenID listener resource, experimental MSC support, and application-service
registration on startup. The Nginx reload is unavoidable to serve the new
hostname. Neither action changes users, auth, registration, federation policy,
database settings, existing TLS, ntfy, UnifiedPush, or pusher registrations.

## Verify, rollback, troubleshoot

After deployment, from an external network:

```sh
curl --fail https://CALL_DOMAIN/livekit/jwt/healthz
curl --fail https://MATRIX_SERVER_NAME/.well-known/matrix/client
```

The well-known JSON must retain `m.homeserver` and add the MatrixRTC focus.
Test each client pairing in an encrypted DM, first audio then video, from
separate networks. Also send normal encrypted messages and confirm UnifiedPush
notifications before and after tests.

To stop only new services:

```sh
docker compose -f compose.yaml -f compose.matrixrtc.yaml --profile matrixrtc stop livekit lk-jwt-service
```

Full rollback requires separate approval: set `MATRIX_RTC_ENABLED=0`, run
`python3 scripts/render-config.py --matrixrtc-synapse`, restart Synapse, then
validate and reload Nginx. Keep generated secrets/data until rollback is
verified; close media firewall rules only after services stop. For missing
focus errors, check public well-known/TLS. For signalling without media, check
public UDP/NAT reachability and the advertised public IP.
