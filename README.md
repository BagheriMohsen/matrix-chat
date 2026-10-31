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

While online, prepare pinned images and verified Element files, initialize, copy Element, install certificates, and start:

~~~sh
ELEMENT_SHA256=04e180516430381d5f5e528ea345a435784bba26f76a84f106a623febd3fcd67 scripts/offline-export.sh
bash scripts/init.sh
cp -a offline-bundle/static/element/. data/element/
chmod 600 secrets/tls/fullchain.pem secrets/tls/privkey.pem
docker compose up -d --pull never
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

make MODE=local up
make MODE=local status
make MODE=local logs
make MODE=local down
~~~

`make up` initializes only when needed, never resets data, starts with already
downloaded images, waits for health checks, and prints a dashboard. It shows the
Element URL, Matrix API URL, and (in local mode) the Admin URL from the rendered
configuration. A URL is marked available only after an HTTP check succeeds.
`make down` uses `docker compose stop`, so it does not remove volumes or user
data. `make help` lists these commands.

## Configuration

Copy .env.example; it documents the small supported configuration surface.

| Variable | Default | Purpose |
| --- | --- | --- |
| MATRIX_SERVER_NAME | example.ir | Lowercase DNS server identity; immutable after initialization. |
| PUBLIC_BASE_URL | https://example.ir | Public HTTPS URL; same domain as server name. |
| POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD | synapse, synapse, placeholder | Database settings; replace the password. |
| MAX_UPLOAD_SIZE | 20M | Per-file Synapse and Nginx limit. |
| MEDIA_UPLOAD_LIMIT_24H, MEDIA_UPLOAD_LIMIT_7D | 100M, 500M | Per-user upload totals for 24 hours and 7 days. |
| LOCAL_HOST, LOCAL_ELEMENT_PORT, LOCAL_ADMIN_PORT | localhost, 8080, 8081 | Local-only URLs and ports. |
| ADMIN_PATH | / | Local Admin path: /, /panel, /admin, or /management. |

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

## Local testing and Admin UI

Stop production first: both stacks use the same persistent data.

~~~sh
bash scripts/local-init.sh
docker compose -p matrix_local -f compose.local.yaml up -d --pull never
python3 scripts/local-admin.py
~~~

Element is http://LOCAL_HOST:LOCAL_ELEMENT_PORT. Admin is http://LOCAL_HOST:LOCAL_ADMIN_PORT plus ADMIN_PATH; for ADMIN_PATH=/panel, use http://localhost:8081/panel/.

The generated local proxy redirects /panel to /panel/, strips the path only before proxying, and supports the pinned Admin UI's relative static assets, refreshes, navigation, and API requests. It remains loopback-only. Production has neither the Admin container nor public Admin API access.

~~~sh
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/users.sh create alice
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/media.sh usage
~~~

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

Do not expose a call button until that optional calling deployment is provisioned
and tested end-to-end. The minimal future plan is an explicit `calls` Compose
profile containing hardened coturn for 1:1 calls; add MatrixRTC/LiveKit only on a
separately sized host after validating its pinned versions, relay port range,
TLS certificate, NAT mapping, and capacity.

scripts/offline-export.sh exports pinned images, verified Element files, and templates. On the target, verify checksums, load images, copy Element into data/element/, then run initialization and docker compose up -d --pull never. It excludes .env, database data, keys, certificates, and media.

Never commit .env, data/, secrets/, backups, or uploaded media. Mobile push can depend on Apple/Google infrastructure and cannot be guaranteed during international internet outages.

## Checks

~~~sh
docker compose config
docker compose exec synapse python3 -m synapse.config -c /data/homeserver.yaml
docker compose exec nginx nginx -t
docker compose ps
~~~

Also test Element login, an encrypted private room, upload/download, rejection above MAX_UPLOAD_SIZE, and public /_synapse/admin/ returning 404. Test mobile E2EE and recovery on real devices before relying on the service.
