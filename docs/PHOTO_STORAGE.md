# Photo delivery and device transfer

Photos are optional media. Uploading, receiving or deleting a photo never changes
an immutable game contribution or a replay checkpoint.

## On-device storage

Native camera captures live in Android app-private storage. Existing capture IDs
remain readable, and still-present legacy camera cache files are migrated before
expiry cleanup. Godot's owner-scoped photo library stores content-addressed JPEGs
and recoverable metadata records. Successful writes require flushing, replacing
the destination and verifying the saved bytes. The library never automatically
evicts a photo to make room for another.

Each reference includes the room, turn, recording hash, photo revision and author.
Local-only and removed versions cannot become a shared replay bubble merely by
being imported. A server removal tombstone suppresses older cached versions while
retaining the local archive pixels. Credentials and gameplay submission keys are
not included in portable photo entries.

## Shared delivery

The delivery endpoint returns metadata separately from JPEG bytes. A cached exact
version is used without downloading its JPEG again. If the service is unavailable,
the viewer can use verified cached pixels; an edit still needs a current server
revision. A newly downloaded version is acknowledged only after its JPEG and
reference metadata are durable. Failed writes never acknowledge delivery.

The room retains bytes until both intended participants acknowledge the current
version. An acknowledgement for an older revision cannot remove a replacement.
Delivery removal leaves metadata, distinct from an explicit author removal. A new
installation cannot fetch a delivered-and-removed photo unless the user prepared
a temporary transfer. Older clients that do not acknowledge delivery do not cause
server deletion.

## Photo transfer

The user explicitly prepares a transfer in Account & recovery. This can include
photos kept private on the source phone; it does not share those photos with a
partner. Only the authenticated account can receive its transfer.

- Up to the newest 1,000 photo references, with a 32 MiB temporary storage ceiling.
- New transfer sessions at most once every 24 hours; exact retries reuse the same
  session and operation keys.
- Temporary copies expire 14 days after acceptance. Retrying an operation does
  not extend their expiry.
- Bounded batches are imported and verified locally before exact revision/hash
  acknowledgements remove the corresponding server entries.
- A lost acknowledgement can be retried after checking the local files again.
  It never silently generates a different request.
- Global admission and per-account request limits return a retry or capacity
  response. Another account's photos are not evicted to admit a new transfer.
- Account deletion removes transfer data and the local owner's library/journals.

Transfers are not long-term storage. The original phone keeps its photos. Account
recovery rotates device credentials, so the destination should finish receiving
before its temporary copies expire. See the backend guide for protocol bounds and
compatible snapshot/rollback behavior.

## Release versions

New builds use `major.minor.patch` for both `application/config/version` and Android
`version/name`, with an increasing Android `version/code`. The build script checks
that the visible and package versions agree. Existing versioned releases and
their checksums remain immutable.
