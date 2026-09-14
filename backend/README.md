# After You API

The Android game's asynchronous room service. It runs on Cloudflare Workers and SQLite Durable Objects, with one object per player and one per room. The service stores compact action recordings, not video. No external database or running game server is required.

## Run and verify

Use Node.js 22 or later. Install the exact dependency graph with `npm ci`, then run:

```sh
npm run types
npm run check
npm run dev
```

Development listens on `http://127.0.0.1:8791`. All bindings are local by default. `npm run check` type-checks source and tests, executes tests in the actual Workers runtime, and performs a deployment dry run. It does not deploy a service or create a Cloudflare account. The tests include recordings exported by the native Godot simulation in `../game/tests/fixtures`.

`npm run deploy` is a separate, explicit deployment action. Keep the Cloudflare account on its Free plan. No binding uses remote storage in local tests. Worker invocation logs and Wrangler usage metrics are disabled; the application never logs request bodies or credentials.

After a deployment, `node scripts/live-smoke.mjs https://<worker>.<subdomain>.workers.dev` creates two synthetic identities, submits the native A/B fixtures, checks retries/conflicts/fork/collection, and deletes its synthetic identity and room records in a `finally` block. It holds credentials only in memory and reports whether cleanup succeeded. These are server API checks, not a substitute for playing on two phones or making an actual RevenueCat purchase.

The pinned toolchain is in `package.json` and `package-lock.json`. Regenerate `worker-configuration.d.ts` with `npm run types` after changing bindings. The current official test integration is `@cloudflare/vitest-plugin`; its API differs from older `vitest-pool-workers` examples.

## Identity and request format

Requests use JSON with `Content-Type: application/json`. All responses use `Cache-Control: no-store`. Native clients do not require browser CORS; cross-origin browser access is not enabled. There are no query-string credentials.

`POST /v1/identity` with `{}` returns `player_id`, `device_token` and `recovery_code`. Store the device credential in Android Keystore-backed storage. Offer the recovery code to the player for private backup; do not include it in room invitations. Bootstrap returns these secrets once; the server stores only SHA-256 hashes. Recovery uses client-generated secrets as described below.

Authenticated requests include:

```text
X-Player-Id: <player_id>
Authorization: Bearer <device_token>
```

`POST /v1/identity/recover` accepts:

```text
{player_id, recovery_code, idempotency_key, next_device_token, next_recovery_code}
```

The client generates both proposed secrets using 32 cryptographically random bytes encoded as unpadded base64url (43 characters), and securely persists the **complete pending request before sending it**. The idempotency key is 16–80 URL-safe characters. Proposed secrets must differ from each other and from both existing credentials. An accepted request atomically rotates both credential hashes and returns only `{player_id, recovered:true}`. Both old secrets stop authorizing new operations immediately.

If the response is lost, retry the exact saved body. The server keeps one current receipt, containing only the previous recovery hash and a request fingerprint, so an identical retry succeeds without another rotation. A changed key or proposed secret using the consumed code returns `409 recovery_request_mismatch`; a later valid recovery supersedes the receipt and makes earlier attempts invalid. The client replaces its stored identity with the proposed values only after a matching acknowledgement, and clears the pending request only after the identity is securely stored. Startup must resume an unfinished request instead of generating a new one. Legacy or incomplete requests return `400 recovery_request_required` **before changing credentials**. Never log or store the pending body outside protected local storage.

`GET /v1/identity` checks the current device credential. `DELETE /v1/identity` removes the identity, its recovery receipt and all its shared rooms, including recordings held by its partner. Explain this effect before the user requests deletion. RevenueCat independently retains purchase records; deleting this service's identity does not cancel/refund a store purchase.

## Room routes

| Method and path | JSON body / behavior |
| --- | --- |
| `POST /v1/rooms` | `{idempotency_key}`; creates or returns the same room for a retried key |
| `GET /v1/rooms` | Returns `{rooms: [RoomSnapshot]}` for the player |
| `POST /v1/rooms/join` | `{invite_code}`; joins the second slot |
| `GET /v1/rooms/:room_id` | Returns the current `RoomSnapshot` |
| `POST /v1/rooms/:room_id/turns` | `{base_revision, idempotency_key, recording}` |
| `POST /v1/rooms/:room_id/fork` | `{base_revision, idempotency_key}`; starts a new attempt with both turns cleared |
| `POST /v1/rooms/:room_id/advance` | `{base_revision, idempotency_key}`; advances a completed island |
| `GET /v1/rooms/:room_id/collection` | Returns `{islands: [RoomSnapshot]}` containing completed replays |
| `POST /v1/rooms/:room_id/reactions` | `{base_revision, idempotency_key, reaction}`; reaction is `love`, `sparkles` or `again` |
| `DELETE /v1/rooms/:room_id` | Erases the entire shared room and its replays, not just the caller's membership |
| `GET /v1/entitlement` | Returns server-verified `full_journey`, `status`, `environment`, `checked_at` |
| `GET /health` | Public, non-sensitive service and API version status |

Invitation codes contain 20 hexadecimal characters and expire after seven days for new joins. Spaces, hyphens and lowercase letters are accepted. Copy/share the whole code; existing room members can continue after invite expiry. Each identity can have 20 active room links. No search, public player directory or third participant is supported.

`RoomSnapshot` has `schema_version:1`, `room_id`, `revision`, `attempt`, `host_id`, nullable `guest_id`, `level_index` (zero-based), `level_id`, `first_player_id`, `active_role` (`a`, `b`, `complete`), `recordings:{a:null|TurnRecording,b:null|TurnRecording}`, `completed_islands`, timestamps and `reactions`. Only the host receives `invite_code`.

On even islands, the host is role A; on odd islands the guest is A. The host may save the first A turn before the guest joins. Joining increments `revision`, so a client must refresh before committing an old draft. Turns are accepted only for the active role and authenticated participant. Advancing requires a completed island and a partner. Islands from index 3 onward require the host's verified entitlement; the guest does not need to purchase.

All turn, fork, advance and reaction changes are stored atomically with their idempotency record. Repeating the same request key and content returns the **latest** snapshot without executing the change again. JSON object key order does not affect identity. Reusing a key for different content, or using an old revision for a new request, returns 409. Keep the same key and body when retrying an uncertain request. After a network failure, also fetch the room and compare the pending turn with its stored recording before clearing the local draft. Never silently rebase a pending turn onto a different level or attempt.

The most recent 256 mutation receipts and 128 room-creation receipts are retained. An older request with an obsolete revision is still rejected instead of replayed. Completed replay history is preserved; a room holds up to 64 completed archived attempts and then returns `room_history_full`. The last 24 incomplete attempts are retained. These storage bounds prevent unbounded growth; create another room rather than silently erasing completed memories.

## Recording version 1

The structural contract is defined in `src/protocol.ts`:

```text
schema_version, simulation_version, level_version: 1
level_id: one of the eight shipped IDs
role: a | b
tick_rate: 30
duration_ticks: 1..600
catch_assistance: boolean (omission defaults true)
actions: [{ticks:1..600, x:-100..100, z:-100..100, action:boolean}]
checkpoints: [{tick, state_hash:<64 lowercase hex characters>}]
final_state_hash: <64 lowercase hex characters>
completed: boolean
outcome: {threw_seed, caught_seed, planted_seed}
source_recording_hash: required for B, matching A.final_state_hash
```

Action durations must sum exactly to `duration_ticks`. Checkpoints must be strictly ordered and within the recording duration. Version mismatches, unknown fields and malformed values are rejected. A must report a thrown seed; B must report a caught and planted seed and completion. Request bodies are limited to 96 KiB while streaming, including requests without `Content-Length`.

**Validation boundary:** the backend verifies structural integrity, membership, versions, sequencing and purchases. It does not run the Godot physics/puzzle simulation, so declared outcomes and hashes are not proof against a modified client. The native client replays and checks semantics before using partner recordings. There is no competitive leaderboard, prize allocation or financial reward based on reported completion.

## RevenueCat configuration

The app must configure RevenueCat with the authenticated `player_id` as its App User ID. The server checks that same user's active entitlements through RevenueCat's official API. Only the host is checked for premium rooms.

`REVENUECAT_ENTITLEMENT` is the public entitlement identifier, currently `full_journey`. The default verifier uses REST API V2 with the minimum `customer_information:customers:read` permission, through the dedicated active-entitlements endpoint. Configure three server bindings: `REVENUECAT_SECRET_KEY`, `REVENUECAT_PROJECT_ID` and `REVENUECAT_ENTITLEMENT_LOOKUP_ID` (the opaque `entl...` ID, not the public identifier).

`REVENUECAT_SECRET_KEY` is a **server-only** credential. Set it using the provider's secret manager (or an ignored local `.dev.vars` file for private integration testing); never put it in `wrangler.jsonc`, app resources, request payloads or git. Free rooms work without it; missing lookup configuration or provider errors fail closed for premium operations. The verifier fetches at most 100 active entitlements and does not follow provider-returned URLs with the credential. A project with more entitlements requires a reviewed pagination implementation.

The legacy V1 subscriber verifier remains covered by tests and can be selected explicitly with `REVENUECAT_API_VERSION=1` and a matching V1 credential. V1 and V2 keys are not interchangeable. V2 avoids retrieving the customer's full profile and uses read-only permission.

The current configuration is explicitly `test-store`. Tests mock provider responses; they do not prove a real purchase. Configure the actual project, offering, one-time product and entitlement in RevenueCat, then verify a real native Test Store purchase separately. Before an actual store launch, use separate RevenueCat app/project and Worker configuration so test entitlements cannot grant production access. No webhook or positive entitlement cache is used: premium operations verify the provider each time and fail closed on timeout/error.

## Failure handling and maintenance

Errors have `{error:{code,retryable}}`. 429 and 503 include `Retry-After`; keep the local draft and back off. A 409 requires fresh room state and explicit reconciliation, not blind retries. A 401 requires recovery or a new identity. `host_unlock_required` is 402; provider-unavailable errors are 503. Quota exhaustion may be a Cloudflare-generated response rather than this JSON envelope, so clients must tolerate non-JSON failures.

For deployments, preserve the SQLite migration history and simulation version contract. Back up encrypted provider credentials separately from source. Cloudflare SQLite Durable Objects support point-in-time recovery; verify provider availability and retention before relying on it. Per-player room listings and per-room collection endpoints export visible gameplay content, but omit identity hashes and operation receipts and are not restorable database snapshots.

This backend source contains no production account IDs or private operational handoff. The app configuration separately identifies its API origin. Live provider purchases, real-phone performance and independent-player testing require separate validation from the automated backend checks.

## Portable per-object snapshots

`Player` and `Room` expose two **binding-only RPC methods**. No HTTP route, public administration endpoint, scheduled exporter or new secret is added. A trusted same-account Worker with the appropriate Durable Object binding could call them; ordinary player credentials cannot. Only isolated local Worker tests exercise them so far.

| RPC method | Result |
| --- | --- |
| `exportSnapshot(sourceCommit)` | `Outcome<string>` containing canonical JSON; `sourceCommit` is the caller-supplied 40-character lowercase Git commit ID |
| `restoreSnapshot(archiveJson, expectedLogicalId)` | `Outcome<{restored:true,checksum}>`; requires the exact logical ID from the selected archive, or explicit `null` for erased/tombstoned state |

As elsewhere in the API, `Outcome<T>` is `{ok:true,value:T}` or `{ok:false,status,code}`. Invalid archives return a bounded 400 code, an occupied target returns `409 snapshot_target_not_empty`, and an unexpected storage failure returns `500 snapshot_storage_error`. No rows or hashes appear in error messages. An empty target means **every application table is empty**, not merely a missing identity/current-room row. A deleted-room tombstone is occupied and cannot be overwritten.

The version-1 archive contains:

- Format and database schema versions, object class, source physical Durable Object ID, caller-supplied source commit, UTC export time, and logical player/room ID where stored state still contains it.
- Current state (`active`, `deleting`, `deleted` or `empty`), room revision and attempt where applicable.
- All six class-specific application tables: Player `identity`, `rooms`, `creations`; Room `room`, `operations`, `archive`. Table schemas, column lists, primary keys, raw JSON text and every SQLite `rowid` are preserved. Row IDs are signed decimal **strings**, avoiding JavaScript precision loss above 2^53. Recordings retain their level/simulation versions and original stored JSON bytes.
- A SHA-256 checksum of the canonical `payload`. Raw JSON data remains embedded as an unchanged string. The outer archive must remain canonical; reformatting it is rejected rather than silently changing its interpretation.

The registry in `src/storage-schema.ts` is used both for construction and validation. Import never executes SQL from the archive: it uses fixed, parameter-bound inserts. Tables, columns, types, row counts, integer ranges, JSON shapes/duplicate keys, version metadata, identity consistency, recording structure, archive attempts and receipt revisions are checked before mutation. The existing gameplay simulation validation boundary still applies. A valid checksum detects corruption; it does **not** authenticate an archive or establish that its caller-supplied provenance is true.

Export reads all rows and metadata synchronously in one transaction, then hashes a detached copy. Restore completes validation and hashing first, then rechecks the target's current schema and emptiness inside the same synchronous transaction as every insert. A failure rolls all inserts back. Unknown application tables, indices/views/triggers, nonempty KV storage and alarms are rejected instead of omitted. Cloudflare's empty internal `_cf_KV` table is allowed. Any future persistence feature requires a reviewed snapshot version.

Archives are bounded to **24 MiB UTF-8**, each raw JSON row to **256 KiB**, and tables to the application's existing retention limits. Oversized or unsupported objects fail without truncation. These are defensive bounds, not a production maximum-size latency, CPU or memory benchmark. `npm test` includes round trips into different local objects and after eviction, actual HTTP-created guest links, recovery retry receipts, current and archived replays, tombstones, malformed archives, unknown storage, concurrent-write boundaries and injected partial-insert failures.

### Operational boundaries

These primitives are not an owner-held production backup, a full-service restore tool or a tested provider migration. Before using them operationally, a coordinator must authenticate operators, inventory **all** namespace pages, preserve physical/logical target mappings, stop and drain writes across objects, encrypt owner-held archives and verify a complete manifest. The importer does not infer a target from an archive or rewrite references: the caller must route each restored object to the correct logical ID in the destination namespace. Room tombstones and fully erased identities no longer contain their old logical ID; their source physical ID is retained, while their manifest logical ID is explicitly `null`. An independent inventory/deletion ledger is still necessary.

An accepted restore whose response is lost must not be retried as an overwrite. It will return occupied-target conflict; reconcile a fresh export's exact table contents, summary and logical identity with the intended archive. Export time and source physical ID naturally differ, so whole-envelope checksums alone are insufficient for that comparison.

There is no global enumeration tool, cross-object write-quiescence gate, independent deletion ledger, scheduled encrypted backup, off-provider copy or PITR drill in this change. Restoring an old backup can reactivate revoked credential hashes or data deleted afterward; resolve the ledger and client pending requests before reopening writes. RevenueCat purchase records remain external and must be rechecked using the preserved logical player ID. Keep snapshot contents, including credential hashes and recovery receipts, out of logs, source control and public artifacts.

Relevant platform references: [SQLite storage and transactions](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/), [Durable Object bindings/RPC](https://developers.cloudflare.com/durable-objects/api/stub/), [RPC visibility and security](https://developers.cloudflare.com/workers/runtime-apis/rpc/visibility/).
