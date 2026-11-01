# Private Matrix stack

[English](#english) | [فارسی](README.fa.md)

<a id="english"></a>

A small private Matrix stack with Synapse, PostgreSQL, Nginx, and Element Web. Production runs exactly three persistent containers: Nginx, Synapse, and PostgreSQL. Synapse Admin exists only in the localhost-only development stack.

Federation, public registration, guests, public room discovery, aliases, and public Admin API access are disabled. E2EE works, but users must keep recovery keys and verify devices.

## Requirements

AMD64 Linux, Docker Engine and Compose, Python 3, curl, tar, a DNS name, and a CA-issued HTTPS certificate. Put fullchain.pem and privkey.pem (mode 600) in secrets/tls/. This project does not issue or renew certificates.

## Quick installation

~~~sh
git clone https://github.com/BagheriMohsen/matrix-chat.git
cd matrix-chat
cp .env.example .env
~~~

Edit .env before initialization:

~~~dotenv
MATRIX_SERVER_NAME=matrix.example.com
PUBLIC_BASE_URL=https://matrix.example.com
POSTGRES_PASSWORD=use-a-long-random-password-here
~~~

MATRIX_SERVER_NAME is the permanent Matrix identity in user IDs and room addresses. Never change it after scripts/init.sh initializes the server.

Initialize once so the TLS directory exists, install certificates, then start. On
the first online `make up`, pinned images and the checksum-verified Element Web
archive are prepared automatically. Later offline starts reuse a verified
`offline-bundle` when it is present.

~~~sh
bash scripts/init.sh
chmod 600 secrets/tls/fullchain.pem secrets/tls/privkey.pem
make up
scripts/users.sh admin admin
~~~

Element is at PUBLIC_BASE_URL. Production does not include Synapse Admin and returns 404 for /_synapse/admin/. The final command creates the first administrator from inside Synapse and prompts for its password.

## Daily commands

The Makefile defaults safely to production. Select local mode explicitly; it is
never guessed from host state.

~~~sh
make up
make status
make logs
make down
make restart
make update

make MODE=local up
make MODE=local status
make MODE=local logs
make MODE=local down
make MODE=local restart
make MODE=local update
~~~

`make up` initializes only when needed, never resets data, prepares missing
verified Element assets while online (or verifies and reuses `offline-bundle`),
starts with already downloaded images, waits for health checks, and prints a dashboard. It shows the
Element URL, Matrix API URL, and (in local mode) the Admin URL from the rendered
configuration. A URL is marked available only after an HTTP check succeeds.
`make down` uses `docker compose stop`, so it does not remove volumes or user
data. `make restart` re-renders managed configuration and force-recreates only
Synapse/Nginx (plus local Admin or enabled coturn), never PostgreSQL. `make
update` never runs Git: first run `git pull --ff-only` yourself, then it pulls
only missing pinned images, prepares missing verified assets, and performs that
safe restart. Both commands work offline when images/assets are cached. `make
help` lists these commands.

## Configuration

Copy .env.example; it documents the small supported configuration surface.

| Variable | Default | Purpose |
| --- | --- | --- |
| MATRIX_SERVER_NAME | example.ir | Lowercase DNS server identity; immutable after initialization. |
| PUBLIC_BASE_URL | https://example.ir | Public HTTPS URL; same domain as server name. |
| POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD | synapse, synapse, placeholder | Database settings; replace the password. |
| MAX_UPLOAD_SIZE | 20M | Per-file Synapse and Nginx limit. |
| MEDIA_UPLOAD_LIMIT_24H, MEDIA_UPLOAD_LIMIT_7D | 100M, 500M | Per-user upload totals for 24 hours and 7 days. |
| LOCAL_HOST, LOCAL_ELEMENT_PORT, LOCAL_ADMIN_PORT | localhost, 8080, 8081 | Local Element and Ketesa-only admin URLs and ports. |
| TURN_ENABLED | 0 | Enable Synapse TURN credentials and optional coturn. |
| TURN_HOST, TURN_EXTERNAL_IP | empty | Matrix domain and its public IPv4 address. |
| TURN_PORT, TURN_TLS_PORT | 3478, 5349 | TURN and TURNS listening ports. |
| TURN_MIN_PORT, TURN_MAX_PORT | 49160, 49200 | UDP relay range. |
| TURN_SHARED_SECRET | empty | Shared coturn/Synapse secret; at least 32 characters. |

Compose does not interpolate mounted files. scripts/init.sh renders fresh Synapse configuration; scripts/render-config.py renders Nginx, Element, and Admin files under ignored data/. It validates domains, URLs, ports, paths, database names, and sizes without printing secrets.

At first initialization, PostgreSQL receives POSTGRES_DB, POSTGRES_USER, and
POSTGRES_PASSWORD from `.env`; the same values are rendered into Synapse's
database configuration. Changing POSTGRES_PASSWORD later does **not** rotate an
existing PostgreSQL role or database. Treat a password rotation as a separate,
planned database operation; do not change it in `.env` alone.

After changing a proxy, Element, or local Admin setting:

~~~sh
python3 scripts/render-config.py
docker compose up -d --force-recreate nginx
~~~

For Synapse upload-limit changes, update the matching stanza in data/synapse/homeserver.yaml (and homeserver.local.yaml for local use), then restart Synapse. Limits are upload-rate limits, not permanent storage quotas; no automatic media deletion is enabled.

New rooms created locally default to end-to-end encryption through Synapse's
`encryption_enabled_by_default_for_room_type: all` setting. It does not encrypt
existing rooms retroactively, change existing encryption keys, or override a
valid encryption event explicitly supplied by a client at room creation.

## Local testing and Ketesa

Stop production first: both stacks use the same persistent data.

~~~sh
bash scripts/local-init.sh
docker compose -p matrix_local -f compose.local.yaml up -d --pull never
# Create or verify the existing Synapse server-admin account for Ketesa.
python3 scripts/local-admin.py
~~~

Element is http://LOCAL_HOST:LOCAL_ELEMENT_PORT. Ketesa is
http://LOCAL_HOST:LOCAL_ADMIN_PORT/admin/. It remains loopback-only, while the
public listener has no admin API or admin UI route.

~~~sh
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/users.sh create alice
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/media.sh usage
~~~

## Optional Ketesa administration

Ketesa v1.5.1 is the only bundled admin interface. It supports Synapse
v1.150.0 and newer, so it is compatible with this stack's pinned Synapse
v1.161.0 and native username/password administrator accounts. It has no user
database and authenticates against the existing Synapse endpoints.

The service has no published port. Nginx serves its official prebuilt `/admin`
variant only on the existing `127.0.0.1:8081` listener. The public HTTPS
listener returns 404 for `/_synapse/admin/` and has no Ketesa route. `/panel/`
and its subpaths return 404 on both listeners.

The first rollout intentionally requires an explicit Nginx recreation; the
admin Make targets never restart the messaging stack themselves:

~~~sh
# Pull or load the already-pinned image yourself, then explicitly apply only
# the changed Nginx configuration at a chosen maintenance moment.
docker compose -f compose.yaml --profile admin pull ketesa
python3 scripts/render-config.py
docker compose -f compose.yaml up -d --pull never --no-deps --force-recreate nginx

make admin-up
make admin-status
make admin-check
~~~

Open `http://LOCAL_HOST:LOCAL_ADMIN_PORT/admin/` on the host, or tunnel it
without exposing it publicly:

~~~sh
ssh -L 8081:127.0.0.1:8081 operator@server
~~~

Then browse to `http://localhost:8081/admin/` and sign in with an existing
Synapse server-admin account. The Ketesa login is locked to that local URL and
does not follow public well-known discovery, keeping its client and admin API
same-origin. `make admin-down` stops only Ketesa; it changes no Synapse,
PostgreSQL, Element, user, room, or encryption data.

Ketesa exposes the native Synapse management surfaces for users, passwords,
devices/sessions, rooms/memberships, media moderation and usage, rate limits,
server inspection, and user/room statistics. It does not add a custom
administration API. Use its confirmation dialogs carefully: deactivation
removes login material, devices, tokens, and membership; erase, room deletion,
history purge, and media deletion/quarantine may be irreversible and can make
messages or encrypted history inaccessible. Test only on non-production test
accounts and rooms first.

## Optional Matrix Analytics

The lightweight Analytics dashboard is served at `/analytics/`; Ketesa's
supported custom-menu configuration adds an **Analytics** sidebar entry. Sign
in using an existing Synapse server-admin account. The dashboard
keeps the resulting Matrix token only in process memory, uses it only for
read-only Admin API requests, and issues an HttpOnly, same-site dashboard
session cookie.

It records five-minute aggregate snapshots in `data/analytics/metrics.sqlite3`:
registered users, rooms, recent `last_seen_ts` activity windows, and media
statistics when supported by Synapse. It does not collect presence, message
contents, room events, encryption keys, IP addresses, or Docker API data.
Host and cgroup resource figures are exposed only after server-admin login;
container rows use short cgroup IDs because the Docker socket is deliberately
not mounted.

Analytics is part of the normal `make up`, `make update`, `make restart`,
`make down`, `make status`, and `make logs` lifecycle in both modes. On its
first start, those commands create `data/analytics/` with mode 700 for the
current user; an existing directory is never recursively changed or re-owned.
The initial visit receives HTTP 401 until an administrator signs in; no token
or host metric is returned to an unauthenticated browser.

## Chat feature matrix

The pinned Element Web 1.12.33 already supplies the normal Matrix chat UI; no
experimental flags or client forks were enabled. Server-side settings preserve
E2EE, local media, native search, and private room operation.

| Capability | Element Web 1.12.33 | Change / limitation |
| --- | --- | --- |
| Reactions; reply, edit, delete, forward | Available | Existing feature; permissions still follow room power levels. |
| Pinned messages; threads; Spaces | Available | Existing feature; Spaces and threads require client support per user. |
| Files, images, video, voice messages | Available | Existing media store and limits; voice recording needs HTTPS or localhost. |
| Stickers and custom emoji packs | Available where a room has sticker/emoji content | No pack service added; admins/room owners must manage compatible packs. |
| Search and history | Available | Search is per-client/server capability; encrypted history is readable only by devices with keys. |
| Read receipts, typing, notifications, mentions | Available | User notification choices remain client-local. |
| Profiles, avatars, room roles and permissions | Available | Room power levels govern moderation; Ketesa is server administration only. |
| Polls | Available in Element Web | No server toggle is required; verify the actual client version before relying on polls operationally. |
| One-to-one voice/video | Available only after optional TURN setup | Enable `TURN_ENABLED=1` and use `make up CALLS=1`; test two real clients. |
| Group calls / MatrixRTC | Not enabled | Requires a separately sized and tested SFU/LiveKit deployment. |
| Element X Android/iOS parity | Not asserted | Mobile clients have separate release cadence; test each capability and E2EE workflow on the target app. |

## User administration and room permissions

The loopback-only Admin UI uses Synapse's native Admin API. Server admins can
inspect users, deactivate them, manage devices/sessions, and inspect room
membership; it remains unavailable in production. The bundled local helper
covers native actions that may not be exposed by this pinned Admin UI version:

~~~sh
scripts/users.sh devices alice
scripts/users.sh lock alice
scripts/users.sh suspend alice
scripts/users.sh revoke-device alice DEVICE_ID
scripts/users.sh revoke-all alice
scripts/users.sh password alice       # resets password and logs out devices
scripts/users.sh deactivate alice     # preserves messages/media; does not erase
~~~

Lock, suspend, device revocation, and deactivation require typing the shown
confirmation. `unlock` and `unsuspend` reverse their respective restriction;
deactivation is materially destructive because Synapse removes devices, tokens,
password material, and room membership. It does not automatically delete sent
messages, uploaded media, or backups. Device revocation invalidates the selected
device token and can make encrypted history unavailable on that device.

Room ownership is separate from server administration. In Element **Room
Settings**, a room owner/admin uses **People** and **Roles & Permissions** to
invite, remove, ban, and assign Matrix power levels. The normal Matrix power
levels govern sending, invitations, kicks, bans, room state/settings, and
`m.room.retention`; ordinary members receive no server-wide privileges. This
project enables room-admin invitations by removing its former server-wide invite
block. Matrix does not offer a server-managed per-room ACL beyond power levels;
use the room's power-level event for any more granular policy.

Element's **Import room keys** is not chat-history import: it imports a
passphrase-protected export of E2EE Megolm keys into that browser/device. Element
Web 1.12.33 has no supported deployment setting to disable only this local
client feature, and Synapse cannot enforce it. No misleading server-side switch
or encryption UI fork was added; it does not import messages, join rooms, upload
media, or affect the project backup/export scripts.

## Room retention and deletion

Synapse's native retention engine is enabled. Rooms are **Off** by default: a
room starts retention only after an authorized room-state event is set. Synapse
accepts effective message lifetimes from 1 to 90 days and runs its built-in daily
purge job. A room admin (normally power level 100; the room's power levels
ultimately decide) can set `m.room.retention` with a blank state key and one of:

| Choice | `max_lifetime` (milliseconds) |
| --- | ---: |
| Off | `{}` |
| 1 day | `86400000` |
| 7 days | `604800000` |
| 30 days | `2592000000` |
| 90 days | `7776000000` |

Element Web 1.12.33 has no supported Room Settings picker for this experimental
Matrix feature. Without a client fork, an authorized room admin can send the
native state event through Element's `/devtools` command: **Send custom state
event**, type `m.room.retention`, leave the state key blank, and use the selected
JSON content above. Ordinary members cannot send this state event at normal room
power levels; Synapse also clamps any requested lifetime to 1–90 days. Native
Synapse does not restrict policies to only the listed presets.

Retention hides expired timeline events, then purges them from Synapse's database
on a later daily job; existing messages are handled according to a newly set
room policy. It does not remove state events, the final event in a room, client
caches, E2EE plaintext/ciphertext already held by clients, exported copies,
media files, or backups. Re-run `bash scripts/init.sh` after updating this
project to add the managed retention block to an already initialized server,
then restart Synapse.

For permanent server-side room removal, use the loopback-only Synapse Admin UI:
open **Rooms**, inspect the room ID/details, choose **Delete room**, enable
**purge** only after checking the target, and complete its confirmation dialog.
This invokes Synapse's authenticated Delete Room Admin API; only server admins
can use it. Check the deletion status before treating it as complete. It never
automatically runs `scripts/media.sh`, deletes backups, or removes client/E2EE
copies. Room deletion is destructive and may be impossible to reverse.

## Account and device security

The pinned Synapse local-password login and Element Web 1.12.33 do not provide
a complete user-managed TOTP or passkey enrolment, recovery, and disable flow.
No partial 2FA is enabled: it could be bypassed by Matrix mobile clients using
password login. The smallest viable route is a separately planned migration to
a self-hosted OIDC identity provider (or Matrix Authentication Service) that
supports the desired MFA; it adds an authentication service, data migration,
HTTPS endpoints, and compatibility testing, so it is outside this lightweight
stack.

Element Web has no server-configurable PIN/biometric app lock. Use browser/OS
screen lock, full-disk encryption, and Element's device verification and
recovery key. Mobile Element clients may offer a native app lock depending on
their platform and version; configure it on the device. It is local device
protection, not server-side 2FA, and this server never receives a PIN.

## Media, backup, restore, and offline use

~~~sh
scripts/media.sh usage
scripts/media.sh list-user '@alice:matrix.example.com'
scripts/media.sh info 'mxc://matrix.example.com/MEDIA_ID'
scripts/media.sh delete 'mxc://matrix.example.com/MEDIA_ID' --execute
scripts/backup.sh
scripts/restore.sh backups/TIMESTAMP
~~~

Deletion requires confirmation and can break message links. Encrypt backups before transfer; restore moves existing data aside only after confirmation and belongs in a deliberate recovery environment.

## Voice messages and calls

Element Web 1.12.33 supports voice messages. Users can record from the composer,
review/send, download, and play them as normal Matrix media; encrypted rooms and
the existing upload limits apply. Microphone recording requires a secure browser
context: HTTPS in production, or the browser's localhost exception for local
development. Plain LAN HTTP is not a supported microphone-recording context.

Reliable self-hosted calling is intentionally not enabled in this three-container
stack. The Element configuration disables default Jitsi/Element Call entry points
so it cannot silently use Element's public calling infrastructure. Private 1:1
calls require a self-hosted coturn service and Synapse TURN credentials; group
calls require a tested MatrixRTC backend (currently Element Call with LiveKit or
an equivalent supported SFU). These add public UDP/TCP relay ports, NAT/public-IP
configuration, TLS, a shared TURN secret, monitoring, and memory/CPU load. A
2 GB server can run this messaging stack and a small coturn instance, but is not
a realistic single-host target for reliable LiveKit group calls. Federation being
disabled does not prevent local users from calling each other.

Group calling remains out of scope: coturn only enables legacy one-to-one calls;
MatrixRTC/LiveKit needs a separately sized and tested deployment.

### Optional one-to-one calls

Set TURN_HOST to the Matrix domain, TURN_EXTERNAL_IP to the server's public IPv4,
and TURN_ENABLED=1. Generate TURN_SHARED_SECRET without printing or committing it:

~~~sh
openssl rand -base64 48 | tr -d '\n'
make up CALLS=1
~~~

Open provider and host firewalls for TURN_PORT (3478) over UDP/TCP,
TURN_TLS_PORT (5349) over TCP, and every UDP port from TURN_MIN_PORT through
TURN_MAX_PORT. Behind NAT, forward the same ports/range and set TURN_EXTERNAL_IP
to the public address. TURNS uses the existing certificate, so TURN_HOST must
equal MATRIX_SERVER_NAME. UDP TURN is not TLS, although WebRTC media uses
DTLS-SRTP.

Coturn uses Synapse-issued time-limited shared-secret credentials; its CLI and
anonymous access are disabled, private/multicast destinations are blocked, and
TCP relay allocations are disabled. It has a 128 MiB / 0.5 CPU Compose limit;
relayed-call bandwidth remains workload-dependent. `make down` also stops it.

Manual acceptance test: sign into two authenticated Element Web clients on
different networks, place direct audio then video calls, verify both directions,
and check browser WebRTC diagnostics for a `relay` candidate. Repeat on a
restrictive network to force TURN. A healthy coturn container is not proof that
a call works.

scripts/offline-export.sh exports pinned images, verified Element files, and templates. On the target, verify checksums, load images, copy Element into data/element/, then run initialization and docker compose up -d --pull never. It excludes .env, database data, keys, certificates, and media.

Element Web uses locally bundled Vazirmatn v33.003 WOFF2 regular, medium, and
bold fonts for its UI. The SIL Open Font License 1.1 is included with the
assets. The small override preserves emoji, Element icon fonts, and code/
monospace formatting. Asset preparation reapplies it after Element extraction,
offline export, and normal `make` lifecycle operations; it never changes
Element JavaScript bundles.

Never commit .env, data/, secrets/, backups, or uploaded media. Mobile push can depend on Apple/Google infrastructure and cannot be guaranteed during international internet outages.

## Checks

~~~sh
docker compose config
docker compose exec synapse python3 -m synapse.config -c /data/homeserver.yaml
docker compose exec nginx nginx -t
docker compose ps
~~~

Also test Element login, an encrypted private room, upload/download, rejection above MAX_UPLOAD_SIZE, and public /_synapse/admin/ returning 404. Test mobile E2EE and recovery on real devices before relying on the service.
