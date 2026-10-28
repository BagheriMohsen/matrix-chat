# Private Matrix stack

This is a deployment template for `ct.koten.ir`, not a deployment tool. It runs
exactly three persistent containers: Nginx, Synapse, and PostgreSQL. It has no
federation listener, federation is denied by Synapse, public registration and
guests are disabled, and the public proxy returns 404 for the Admin API.

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

Before leaving online connectivity, independently obtain the official release
hash for Element Web v1.12.33 and run:

```sh
ELEMENT_SHA256='<verified 64-hex SHA-256>' scripts/offline-export.sh
```

It pulls AMD64 images, verifies the Element archive hash, injects the local
Element config, exports the three images, and writes checksums. Copy only the
resulting `offline-bundle/`; copy `static/element/` to `data/element/` on the
target. It deliberately excludes database data, `.env`,
signing keys, secrets, and certificates. Offline restoration starts with
`sha256sum -c SHA256SUMS` and `docker load -i images/runtime-images.tar`.
Then copy protected secrets separately and run `docker compose up -d`; no image
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

## Verification and acceptance

Run `docker compose config`, `docker compose exec nginx nginx -t`, and
`docker compose exec postgres pg_isready -U synapse -d synapse`. Check
`https://ct.koten.ir/_matrix/client/versions`, registration rejection, the
Admin API public 404, and persistence after restart. Manually test web/iOS/
Android login, private and encrypted DMs/group rooms, 20 MiB media, delivery,
reconnect sync, offline-egress behavior, push limitations, and a restore into a
separate recovery environment. This repository does not claim those live tests
have been performed.
