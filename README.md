# Private Matrix stack

The production configuration is a deployment template for `ct.koten.ir`, not a
deployment tool. It runs exactly three persistent containers: Nginx, Synapse,
and PostgreSQL. It has no
federation listener, federation is denied by Synapse, public registration and
guests are disabled, and the public proxy returns 404 for the Admin API.

## Local development

The local Compose file reuses the production PostgreSQL and Synapse services,
adds a localhost-only Nginx site and a pinned Synapse Admin UI. Keep only one
stack running at a time because both use the same persistent data. From the
repository root, with Docker running and the existing verified Element assets
in `offline-bundle/static/element/`, start it with:

```sh
bash scripts/local-init.sh
docker compose -p matrix_local -f compose.local.yaml up -d
python3 scripts/local-admin.py
```

`local-init.sh` creates `.env` with a random database password when absent,
initializes Synapse once, and creates a local client URL configuration while
keeping the server identity `ct.koten.ir` and existing signing key. Repeat it
safely; it refuses incomplete data or changed local configuration. On a fresh
machine, pull the pinned images in `compose.local.yaml` and prepare the verified
Element assets with `scripts/offline-export.sh` first. Once images are cached,
start or restart without network access using
`docker compose -p matrix_local -f compose.local.yaml up -d --pull never`.

- Element Web: <http://localhost:8080>
- Synapse Admin: <http://localhost:8081>

`local-admin.py` creates `@admin:ct.koten.ir` through Synapse's shared-secret
registration API and verifies login and Admin API access. It keeps the random
password in ignored `secrets/local-admin-password` (mode 600); read that file
locally to sign in. Running it again verifies the existing account and does not
change its password. To create another user interactively, run
`COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/users.sh create alice`.
For a separate administrator, use `scripts/users.sh admin LOCALPART` with the
same two environment variables. To inspect media, run
`COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/media.sh usage`
or the `list-user` and `info` commands below.

Shut down local services without removing data with
`docker compose -p matrix_local -f compose.local.yaml stop`. Restart them with
the `up -d --pull never` command above. To return to the unchanged production
stack, stop the local services, provide the production TLS files, and run
`docker compose up -d` using `compose.yaml`. Production does not include the
Admin UI or localhost ports. Neither local URL requires public DNS or TLS.

## Prepare while online

Use an AMD64 Linux host with Docker Compose, `curl`, `tar`, and Python
3. Copy `.env.example` to `.env`, choose a long random database password, and
run `scripts/init.sh`. It refuses to replace existing data. The script creates
the Synapse signing key and registration secret under ignored `data/`.

Install a CA-issued certificate as `secrets/tls/fullchain.pem` and
`secrets/tls/privkey.pem` (`chmod 600`). For an existing certificate, copy the
two files there. To obtain one online, stop any process using port 80 and use a
reviewed ACME client with HTTP-01 for exactly `ct.koten.ir`; place its output in
those paths, then start Nginx. Renewal is outside this stack: renew the files
and run `docker compose exec nginx nginx -s reload`. No self-signed fallback is
provided. During an outage, expiry, DNS resolution, and client certificate
validation can still prevent new connections.

The [Element Web v1.12.33 release metadata](https://api.github.com/repos/element-hq/element-web/releases/tags/v1.12.33)
publishes SHA-256 `04e180516430381d5f5e528ea345a435784bba26f76a84f106a623febd3fcd67`
for `element-v1.12.33.tar.gz`. Recheck the upstream digest before exporting:

```sh
ELEMENT_SHA256=04e180516430381d5f5e528ea345a435784bba26f76a84f106a623febd3fcd67 scripts/offline-export.sh
```

It pulls AMD64 images, verifies the Element archive hash, injects the local
Element config, exports the three images, and writes checksums for every bundle
file. Copy only the resulting `offline-bundle/`. On the target, verify the
bundle, load images, then extract `config-templates.tgz` into the deployment
directory alongside `compose.yaml` and `.env.example`:

```sh
cd offline-bundle && sha256sum -c SHA256SUMS
docker load -i images/runtime-images.tar
mkdir -p ../matrix-chat && cd ../matrix-chat
cp ../offline-bundle/compose.yaml ../offline-bundle/.env.example .
tar -xzf ../offline-bundle/config-templates.tgz
```

Create a protected `.env`, run `scripts/init.sh` with the loaded Synapse image,
then copy the static files with `cp -a ../offline-bundle/static/element/. data/element/`.
Restore protected TLS material separately before starting the stack. The bundle
excludes database data, `.env`, signing keys, secrets, and certificates. Run
`docker compose up -d --pull never`; no image
pull, package install, build, or external CDN is needed. Test this by blocking
international egress while retaining the domestic route.

## Operations

Start only after assets and TLS material exist: `docker compose up -d`.
Inspect consumption with `docker stats`; expect roughly 400–800 MiB combined
for a small group, plus PostgreSQL cache and media growth. The modest Postgres
settings reserve 128 MiB shared buffers and limit connections to 30; actual
usage varies with room history and concurrent syncs.

Create users locally with `scripts/users.sh create alice`; create the first
administrator with `scripts/users.sh admin admin`. The Synapse utility prompts
for passwords—never put them in arguments. `password`, `deactivate`, and
`list` use a token entered without echo and make a request only from inside the
Synapse container, so Admin API traffic is never publicly routed. Password reset
logs out devices; deactivation requires typing `DEACTIVATE` and removes access
tokens and devices. There is no reliable remote deletion of already-decrypted
content. Use `scripts/backup.sh`, encrypt its output before transfer, and read
`scripts/restore.sh` before an explicitly chosen recovery-environment restore.

## Manual media maintenance

Synapse stores local uploads and thumbnails under persistent
`data/synapse/media_store/`; PostgreSQL uses persistent `data/postgres/`.
Synapse and Nginx both cap each upload at 20 MiB, and all three containers
have bounded Docker log rotation. No automatic local media retention is enabled.
Synapse's [media retention setting](https://element-hq.github.io/synapse/v1.161/usage/configuration/config_documentation.html#media_retention)
can be configured later, but it purges by last access, not by whether a message
still references a file. Leave it unset unless that loss is acceptable.

Run from the deployment directory with Docker access:

```sh
scripts/media.sh usage
scripts/media.sh list-user '@alice:ct.koten.ir'
scripts/media.sh info 'mxc://ct.koten.ir/MEDIA_ID'
scripts/media.sh delete 'mxc://ct.koten.ir/MEDIA_ID'
scripts/media.sh delete 'mxc://ct.koten.ir/MEDIA_ID' --execute
scripts/media.sh purge-before 2025-01-01
scripts/media.sh purge-before 2025-01-01 --execute
```

`usage` reports media-store allocated KiB and host filesystem free space.
`list-user` shows the first 100 uploads and a `next_token` when more exist;
use the [Synapse user media API](https://element-hq.github.io/synapse/v1.161/admin_api/user_admin_api.html#list-media-uploaded-by-a-user)
for further pages. `info` and `delete` without `--execute` inspect one exact
local MXC. Destructive commands require `--execute` and typing the target or
cutoff. Bulk purge refuses cutoffs less than 90 days old, keeps profile media,
and has no exact dry-run candidate list. Review a backup and the affected users
before running it. The [Synapse media Admin API](https://element-hq.github.io/synapse/v1.161/admin_api/media_admin_api.html#delete-local-media)
removes media originals and thumbnails from local storage; check `usage` before
and after. Filesystem free-space changes may differ because PostgreSQL, Docker,
and filesystem metadata also consume blocks. Existing backup archives may
still contain copies of deleted media and occupy space independently.

Message redaction removes event content from the room view; it does not prove
that an uploaded media file was deleted. Deleting media through the Admin API
removes the stored file, so any surviving message link can break. Synapse cannot
reliably identify all unreferenced uploads: its room media listing covers only
unencrypted events, and encrypted attachment references are inside encrypted
events ([Matrix encrypted file format](https://spec.matrix.org/v1.16/client-server-api/#sending-encrypted-attachments)).
Never use an age-based purge as reference-safe cleanup. These media
commands do not touch the database files, signing key, Synapse configuration,
or encryption metadata.

## Privacy and client expectations

Element Web defaults to this homeserver and private room creation. Create
invite-only rooms and enable encryption in Element for private conversations;
Synapse cannot universally force E2EE with a simple setting. Users must verify
devices and save recovery keys. Encrypted message/media ciphertext is stored by
the server, but room membership, event timing, account identifiers, IP/connection
metadata, and unencrypted room content remain server-visible. Lost recovery
keys/devices can make encrypted history unrecoverable.

Synapse blocks non-admin invites, public-room-list searching, aliases, and the
edge proxy blocks directory-publication requests. Synapse has no built-in
administrator-only room-creation control; enforcing that would require a custom
third-party-rules module, which this minimal stack deliberately does not add.
Do not treat an Element UI choice as an access-control boundary.

Official Element-compatible iOS and Android clients use the same homeserver URL.
Foreground chat and sync work without external services. Background push is
Synapse → configured push gateway → APNs/FCM → operating system; no push gateway
is deployed here, and self-hosting one would not eliminate APNs/FCM. iOS cannot
reliably maintain an unrestricted background connection. Android alternatives
include compatible clients using a background connection or UnifiedPush.

Before deployment, manually verify on real devices and a browser: Element Web
login; Element X Android and iOS password login; device verification; encrypted
direct messages and group rooms; encrypted file upload and retrieval; recovery
key setup and recovery on a second device; foreground delivery; reconnect and
sync after network loss; and expected background notification limits without a
push gateway. Synapse 1.161 includes native simplified sliding sync and password
login for Element X, but API availability alone does not verify E2EE or mobile
behavior.

## Verification and acceptance

Run `docker compose config`, `docker compose exec nginx nginx -t`, and
`docker compose exec postgres pg_isready -U synapse -d synapse`. Check
`https://ct.koten.ir/_matrix/client/versions`, registration rejection, the
Admin API public 404, and persistence after restart. Manually test web/iOS/
Android login, private and encrypted DMs/group rooms, 20 MiB media, delivery,
reconnect sync, offline-egress behavior, push limitations, and a restore into a
separate recovery environment. This repository does not claim those live tests
have been performed.
