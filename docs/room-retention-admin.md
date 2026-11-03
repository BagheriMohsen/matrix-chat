# Room-retention administration

The bundled administration application is Ketesa v1.5.1, the maintained
successor to synapse-admin. Its room view exposes raw state but does not provide
a retention editor. This project adds the smallest isolated extension to the
already-authenticated Analytics service, linked from Ketesa as **Room
retention**. It adds no service, database table, migration, dependency, or
Synapse module.

## Operations

After server-admin login, the page searches Synapse's room-list Admin API by
room name, alias, or identifier. Selecting a room reads `m.room.retention`
through the read-only Admin API and shows its override. It offers 24 hours, 7
days, 30 days, custom whole hours, update/enable, and disable after an explicit
history-deletion warning. Values are validated against the managed Synapse
bounds of 1 through 90 days; Synapse remains the final authority.

There is no Client-Server API operation to delete a state event. **Disable**
writes an empty `m.room.retention` content object; it is not “remove a room
override”. A future Synapse `retention.default_policy` applies only to rooms
lacking that state event. The current configuration deliberately has no global
default policy, so existing rooms do not expire unless explicitly configured.

## Authorization

Synapse's room-state Admin API is read-only. A server administrator is not
automatically permitted to send `m.room.retention` in arbitrary rooms. The UI
calculates the logged-in account's membership and current/required room power
levels, then sends the standard authenticated Client-Server state event only as
that account. Synapse enforces authorization again server-side.

If access is missing, the UI never impersonates a member. A separately
confirmed **Request room-admin access** action uses Synapse's documented
`make_room_admin` Admin API for the logged-in account. It can add/invite that
real account and works only if an eligible local room admin exists. Otherwise,
an existing room admin must grant access through normal Matrix room management.

## Effects and activation

Enabling or shortening a policy can hide existing expired messages and purge
them asynchronously. It does not promise to delete cached messages, downloaded
attachments, media files, backups, or copies held elsewhere.

No Synapse configuration change is required: existing `retention.enabled: true`
enables room-level policy enforcement, while the absence of `default_policy`
keeps global automatic expiration off. After approval, render the Ketesa menu
and recreate only Analytics to load its mounted code:

```sh
python3 scripts/render-config.py
docker compose -f compose.yaml up -d --no-deps --force-recreate analytics
```

No Synapse, Nginx, PostgreSQL, Element, MatrixRTC/LiveKit, ntfy, push, TLS, or
network change is required. Verify with a test room: inspect its policy, reject
an out-of-range duration, reject an unauthorised room write, then set a 24-hour
policy. Confirm normal encrypted messaging and UnifiedPush before production
use.

Rollback only removes the UI when Analytics is reverted/stopped. It cannot undo
an already-sent room policy or restore purged history.
