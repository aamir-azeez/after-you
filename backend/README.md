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

For an explicitly enabled v2 deployment, `node scripts/relay-smoke.mjs https://<worker>.<subdomain>.workers.dev` checks both Relay stages, role alternation, exact recordings/checkpoints, receipt reconciliation, membership isolation and checkpoint forks. It creates three disposable identities and performs bounded cleanup/reconciliation without logging their credentials or response bodies. To check a separate local Wrangler instance, use `node scripts/relay-smoke.mjs http://127.0.0.1:8794 --local`. The local service must explicitly enable `V2_ROOMS_ENABLED`; neither script changes deployment settings. This is HTTP fixture verification, not native two-install gameplay.

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

### Room-version compatibility

Stored Player room links and creation receipts may include a positive integer `api_version`; omission means version 1. Legacy JSON is not rewritten. `/v1/rooms` lists only version-1 links and never queries or prunes a newer/unknown version through the old room namespace. Legacy join, cleanup and creation retries also reject or preserve a conflicting room version rather than replacing its link. The existing 20-link limit includes all versions.

`src/room-links.ts` provides the internal deletion dispatcher. Version 1 uses `ROOMS`; version 2 uses the separate `ROOMS_V2` binding. The new class has an additive SQLite migration; the original namespace and tables are unchanged. V2 creation and gameplay mutations are **disabled by default**, independently of data deletion. With no configured v2 eraser, the dispatcher returns `503 room_service_unavailable`; an unknown link version returns `409 unsupported_room_version`. The Player checks every link synchronously before marking an active identity as deleting, so these failures preserve the active identity and every room. A deletion interrupted after an actual eraser failure retains the unresolved links and remains retryable with the deletion credential. Final identity removal refuses to proceed while any room link remains.

## V2 checkpoint coordination foundation

The `/v2` room envelope coordinates two consecutive A/B pairs through an exact authored chapter registry. **Relay Isles** retains its level/simulation/recording version 2 and original validator. **First Steps** is a separate level version 1 with simulation/recording/checkpoint version 4; its lift and activated-garden state is validated separately. Existing rooms and stored recordings are never converted. `V2_ROOMS_ENABLED` is `"false"` by default. Disabling it holds creation, joins, turns and forks while preserving authenticated reads, accepted-operation lookup and deletion. Recovery continues through the existing `/v1/identity/recover` protocol and retains both versions of room membership.

`FIRST_STEPS_ENABLED` defaults to `"false"`. It controls advertising and new First Steps creation only. Existing First Steps room reads, receipt reconciliation, joining and gameplay remain available subject to the shared v2 mutation flag. Capabilities retain the top-level v2 recording/simulation fields and the exact Relay descriptor for earlier clients; each chapter descriptor additionally names its own recording/simulation versions. Clients must select a trusted native engine by the entire `{level_id,level_version,definition_hash}` triple and hold unknown versions. Registry presence is not evidence of deployment or Android validation.

Room creation keys are bound to that complete descriptor before initialization. A changed chapter with the same key returns `409 idempotency_chapter_mismatch`. Raw v2 creation links have one explicit interpretation: the original Relay version 2 descriptor. New Relay creations retain that compatible shape. First Steps creation-intent records keep the ordinary room link separate from its chapter descriptor, allowing exact retries after a response loss without changing the room ID.

| Method and path | Body / result |
| --- | --- |
| `GET /v2/capabilities` | Authenticated version, exact supported chapter/hash, validation boundary and mutation availability |
| `POST /v2/rooms` | `{idempotency_key,level_id,level_version,definition_hash}`; rejects unknown catalog content before reserving a link |
| `GET /v2/rooms` | `{rooms:[RoomSnapshotV2]}`; lists only v2 links |
| `POST /v2/rooms/join` | `{invite_code}`; same two-member/invite-expiry behavior as v1 |
| `GET /v2/rooms/:id` | Current checkpoint, branch, stage, accepted A and role/player-slot assignment |
| `POST /v2/rooms/:id/turns` | `{base_revision,idempotency_key,branch,recording}` for A; B additionally requires `checkpoint` |
| `GET /v2/rooms/:id/operations/:key` | The caller's exact accepted receipt plus current snapshot; available even when mutations are disabled |
| `POST /v2/rooms/:id/fork` | `{base_revision,idempotency_key,branch,stage_index}`; restart a reached stage, retaining its earlier verified prefix |
| `GET /v2/rooms/:id/collection` | Small pair summaries plus the active branch's `active_pair_ids` |
| `GET /v2/rooms/:id/pairs/:pair_id` | One immutable A/B pair and its committed checkpoint for client replay |
| `DELETE /v2/rooms/:id` | Erases this shared room, all turns/pairs/receipts, and retains a deletion tombstone |

Host is always physical slot `p0`, guest `p1`. The pinned stage catalog assigns which slot plays A, alternating across the two stages. The host can save the first A before a friend joins; B has no active player until the guest arrives. The server derives the active player from membership and the catalog, not a submitted player identity. A B commit atomically stores its pair and moves to the next checkpoint; there is no separate `advance` request. Both registered v2 chapters are explicitly free. A future premium chapter needs a reviewed catalog and server-side host-entitlement integration; a client-supplied premium/unlock flag cannot add content or grant access. Existing v1 premium rules remain unchanged.

Mutation responses are `{receipt,room}`. The receipt includes `idempotency_key`, canonical `request_hash`, `operation`, `accepted_revision`, `branch`, `stage_index`, `stage_id`, `turn_id`, exact `recording_hash`, `pair_id` and resulting `checkpoint_hash`. **The receipt is immutable; the accompanying room is current.** Preserve the complete pending body before sending. After a lost response, retry it exactly or fetch its scoped operation receipt; clear the pending request only after matching its identifiers and hashes. A retry after another stage or fork returns the original accepted receipt rather than presenting later progress as the acceptance. Reusing the same key for changed content returns 409. Keys are scoped to the player; another member cannot fetch that player's receipt by guessing its key.

Direct room deletion returns 404 on a repeated request after erasure, rather than retaining a member-bearing deletion receipt. Reconcile an uncertain delete with authenticated absence/list refresh; listing removes that caller's now-absent v2 link. Identity deletion already treats missing linked rooms as erased and resumes remaining cleanup. A reserved creation is tombstoned if identity deletion wins before initialization. A join rechecks authorization after its room mutation and removes the newly joined shared room if the joining identity was deleted in flight.

Recordings retain their submitted JSON values with no default insertion or action normalization. The canonical SHA-256 algorithm matches the native fixtures, sorts object keys and encodes integral numbers consistently; wire indentation/order is not an archived byte format. B cites the full A recording hash, not just its endpoint. Its submitted checkpoint must contain the exact accepted previous checkpoint and A/B proof values, versioned catalog references, expected seed/latch state, bounded surface coordinates and a valid canonical checkpoint hash. Earlier prefix recordings and completed pairs remain immutable after forks. Do not pin real endpoints to fixture coordinates: players can finish at different valid positions.

**The server performs structural and dependency checks, not physics replay.** A self-consistent forged outcome or endpoint is not proof of successful play. Native clients must replay/verify the full recording and checkpoint proof chain before accepting it for gameplay. Every snapshot exposes `validation:"structural_client_replay_required"`. This foundation does not establish server-authoritative anti-cheat validation.

V2 request bodies are limited to 320 KiB, individual recordings to 48 KiB and checkpoints to 224 KiB. An iterative 16-depth/24,000-node JSON preflight bounds nested proof trees before recursive hashing. The authored recording contract remains 30 Hz, 1–600 ticks, at most 600 action runs and 21 integrity checks. Each room retains at most 32 branches, 128 turns, 64 pairs and 256 receipts. Capacity returns `room_history_full`; accepted records/receipts are not silently pruned. These are defensive bounds, not measured maximum-size CPU, storage or latency results. Collection returns summaries; fetch one pair's recordings at a time.

`test/v2.test.ts` covers native fixture hashes and nested checkpoints, role changes, exact retry receipts after advancement/eviction, source mismatches, malformed/deep data, forks, membership, shared identity recovery/deletion and old-room isolation. Local runtime validation must pass before enabling the feature; an API fixture commit is not proof of native online gameplay. The optional photos section below describes separately enabled uploads and room-member-authenticated image reads; there is no public image route.

RoomV2 provides binding-only `exportSnapshot(sourceCommit)` and `restoreSnapshot(archive, expectedLogicalId)` methods. Objects without pair reactions keep database schema 3: Relay, empty and deleted objects export format 4; active First Steps objects use format 5. The first accepted preset reaction lazily adds database schema 4, whose complete archives use format 6 for either chapter. Restore accepts the previous formats 3/4/5 and current format 6; a First Steps object under format 3/4, or reaction tables under format 3/4/5, is rejected. The public HTTP router exposes neither method. Exports preserve exact stored JSON, positive 64-bit row IDs, both active and historical pairs, and immutable gameplay/photo/reaction receipts. Metadata must match the pinned schema; unexpected SQL objects, KV values or unowned alarms cause a refusal. Only the exact ephemeral notification tables and verified owned delivery alarm are excluded. A canonical SHA-256 envelope detects accidental alteration; it is not authentication or encryption, so use trusted, privately stored archives. This source contract does not establish deployment.

Restore validates record hashes, checkpoint lineage, actor/receipt references and the current branch cursor. It checks every destination table is empty again inside the transaction that inserts the preserved rows. It cannot overwrite an existing room, including a deletion tombstone. A lost restore response requires comparing a fresh export with the intended tables and logical identity, not retrying an overwrite. Native game replay verification remains required when clients open restored recordings.

RoomV2 archives are bounded to 24 MiB and individual raw JSON rows to 512 KiB; the existing room history row caps also apply. Oversized histories are refused without truncation. `test/v2-snapshot.test.ts` verifies complete/forked/pending rooms, raw bytes and full-width positive row IDs, old receipts, tombstones, modified archives, unknown storage, missing lineage, hidden pending turns, and concurrent initialization. These per-object primitives are not an automated whole-service backup. A complete inventory, coordinated pause of writes, independent deletion ledger, encrypted off-provider copies and a recovery drill remain operational requirements. Do not roll back to a release that lacks v2-aware room-link listing/deletion after v2 data exists.

Do not roll back to code that treats every link as version 1 after creating versioned rooms. That older code could prune valid newer links. This compatibility layer does not migrate existing recordings or make an unconfigured protocol accessible.

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

## Completed-pair preset reactions

First Steps and Relay share three presets: `love` (Beautiful!), `sparkles` (We did it!) and `again` (Again soon). Only room members can read or change a preset, and the referenced immutable A/B pair must already exist. This is separate from gameplay: it never modifies a room snapshot, revision, recording, checkpoint, photo or notification outbox. Historical completed pairs retain their own reactions after a fork. There is no arbitrary message text and no push event for reactions.

| Route | Contract |
| --- | --- |
| `GET /v2/rooms/:room_id/reactions/:pair_id` | Schema1, room/pair IDs, exact `a_hash`/`b_hash`, and up to two participant reaction rows |
| `POST /v2/rooms/:room_id/reactions/:pair_id` | Exact `{idempotency_key,a_hash,b_hash,expected_reaction_revision,reaction}`; returns immutable `receipt` plus current `state` |
| `GET /v2/rooms/:room_id/reaction-operations/:key` | Only the requesting member's exact accepted receipt and current pair reaction state |

Each member's initial reaction revision is0. An accepted write increments only that member's revision; a simultaneous partner write does not conflict. A stale own edit returns409. Reusing a key with different content returns409, while retrying the exact request returns its original receipt plus the latest state, even after a replacement or gameplay advance. Clients must retain the exact body/key across uncertain replies, validate the pair hashes and owner, and distinguish the accepted historical receipt from the current displayed preset. Timers should only GET; they must not resubmit an uncertain reaction automatically.

Requests are bounded to4KiB, retained participant-pair rows to128, and immutable reaction operation receipts to256 per room. Full storage returns an explicit conflict rather than evicting history. No standalone removal operation is provided, matching existing preset behavior; identity/room deletion erases both tables. `PRESET_REACTIONS_ENABLED` defaults to false independently of gameplay. The capability `preset_reactions_enabled` requires both it and `V2_ROOMS_ENABLED` to be true. When either gate is off, POST is rejected before its body is parsed or any reaction schema migration occurs; reads and receipt reconciliation remain available. Existing clients tolerate the additive capability and receive unchanged gameplay snapshots.

The first valid reaction transaction creates only `pair_reactions` and `reaction_operations` and moves metadata from schema3 to4 atomically. Unused rooms retain their original schema/export format. Schema4 archives include both tables and validate participant ownership, immutable A/B hashes, contiguous per-member revisions, exact request hashes and receipt history. Deletion retains schema4 with an empty table set and tombstone. Restore into an already-schema4 empty target does not downgrade its metadata. Once any object uses schema4, rollback must retain a reaction-aware Worker; pre-reaction code refuses that schema. Disabling mutations does not revert it.

## Background turn notifications

`NOTIFICATIONS_ENABLED` defaults to `false`. The optional sender uses Firebase Cloud Messaging HTTP v1 and a server-only `FCM_SERVICE_ACCOUNT_JSON` Worker secret. Firebase's public Android configuration is separate. Do not include service credentials in the app, repository, API responses or logs. No Firebase Functions, Firestore or paid queue is required; FCM is a no-cost product and the existing SQLite Durable Objects remain subject to the Workers Free quotas.

After ordinary player authentication, `POST /v1/notifications/registration` accepts exactly `{schema_version:1,token,binding_epoch}` and returns `{registered:true,binding_epoch}`. The token is bounded printable ASCII; the binding epoch is a client-persisted random 22-character base64url value. Native binding must follow the matching server acknowledgement. `DELETE` at the same path accepts `{schema_version:1,binding_epoch}` and returns `{unregistered:true}`, including an already absent registration. Deletion is available while notifications are disabled. At most four registrations are retained per current credential; registration refresh and sending remove entries older than 30 days. Recovery and account deletion atomically revoke old registrations.

An accepted shared turn records a small hint for the **other member**, in the same SQLite transaction as gameplay and its idempotency receipt. Joining after an existing first contribution queues a catch-up hint; legacy advance can also notify the other member. Photos, reactions, reads and exact submission retries do not create alerts. The displayed text must be generic, such as “Your friend left a turn”: the sender may also own the next stage's first contribution.

An owned Durable Object alarm delivers the outbox through the recipient's Player object, which checks the current credential and registration again after OAuth work. A binding-only read also confirms room membership and the exact pending hint before sending; a stale local room link alone is insufficient. Provider failure cannot undo an accepted turn. Each room retains only its latest hint per recipient, at most two rows, with eight bounded attempts, exponential backoff, provider cooldown and a seven-day expiry. A provider acknowledgement is not a device receipt. A lost acknowledgement can resend the same event ID; native event/revision deduplication prevents repeat alerts. Permission denial, force-stop, offline devices and platform delivery restrictions remain best-effort limits. Foreground/manual refresh and a fresh authenticated room fetch remain authoritative.

Data-only messages contain exactly the string fields `schema_version`, `event_id`, `kind`, `room_id`, `room_family`, `revision`, `binding_epoch`. `kind` is `turn_ready`; `room_family=legacy` routes v1 and `relay` routes the v2 chapter API, including First Steps. No invitation code, player credential, recording, photo or URL is sent. Token rotation while the app is absent requires re-registration on the next foreground startup; a notification cannot authorize a room action. Already transmitted generic notifications cannot be recalled during recovery/deletion.

Notification registrations, outbox rows and owned-alarm metadata are explicitly **ephemeral operational data**, omitted from portable gameplay snapshots. Restore requires fresh authenticated device registration and schedules no historical alerts. Only these exact named schemas and Workerd's protected alarm metadata schema are recognized; unrelated tables, KV values and unowned alarms still fail closed. The exception does not weaken recording/checkpoint/photo validation or change existing archive formats. A backup coordinator, global write pause, deletion ledger and encrypted whole-service recovery procedure remain separate work.

Deploy this notification-aware version with the feature disabled first, preserving the existing v2/chapter/photo variables and secrets. Constructors add the empty operational tables even while disabled. If delivery needs to stop, keep a compatible notification-aware build and set `NOTIFICATIONS_ENABLED=false`; authenticated unregister/deletion and gameplay remain available. Do not delete live tables or roll back to a prior strict-schema exporter that rejects them. Feature disable does not recall notifications already accepted by FCM, and it is not global gameplay write quiescence.

## Failure handling and maintenance

Errors have `{error:{code,retryable}}`. 429 and 503 include `Retry-After`; keep the local draft and back off. A 409 requires fresh room state and explicit reconciliation, not blind retries. A 401 requires recovery or a new identity. `host_unlock_required` is 402; provider-unavailable errors are 503. Quota exhaustion may be a Cloudflare-generated response rather than this JSON envelope, so clients must tolerate non-JSON failures.

For deployments, preserve the SQLite migration history and simulation version contract. Back up encrypted provider credentials separately from source. Cloudflare SQLite Durable Objects support point-in-time recovery; verify provider availability and retention before relying on it. Per-player room listings and per-room collection endpoints export visible gameplay content, but omit identity hashes and operation receipts and are not restorable database snapshots.

The app configuration separately identifies its API origin. Live provider purchases, real-phone performance and independent-player testing require separate validation from the automated backend checks.

## Portable per-object snapshots

`Player` and `Room` expose two **binding-only RPC methods**. No HTTP route, public administration endpoint, scheduled exporter or new secret is added. A trusted same-account Worker with the appropriate Durable Object binding could call them; ordinary player credentials cannot. Only isolated local Worker tests exercise them so far.

| RPC method | Result |
| --- | --- |
| `exportSnapshot(sourceCommit)` | `Outcome<string>` containing canonical JSON; `sourceCommit` is the caller-supplied 40-character lowercase Git commit ID |
| `restoreSnapshot(archiveJson, expectedLogicalId)` | `Outcome<{restored:true,checksum}>`; requires the exact logical ID from the selected archive, or explicit `null` for erased/tombstoned state |

As elsewhere in the API, `Outcome<T>` is `{ok:true,value:T}` or `{ok:false,status,code}`. Invalid archives return a bounded 400 code, an occupied target returns `409 snapshot_target_not_empty`, and an unexpected storage failure returns `500 snapshot_storage_error`. No rows or hashes appear in error messages. An empty target means **every gameplay application table is empty**, not merely a missing identity/current-room row; verified ephemeral notification state is reset. A deleted-room tombstone is occupied and cannot be overwritten.

The archive contains:

- Format and database schema versions, object class, source physical Durable Object ID, caller-supplied source commit, UTC export time, and logical player/room ID where stored state still contains it.
- Current state (`active`, `deleting`, `deleted` or `empty`), room revision and attempt where applicable.
- All six class-specific gameplay tables: Player `identity`, `rooms`, `creations`; Room `room`, `operations`, `archive`. Table schemas, column lists, primary keys, raw JSON text and every SQLite `rowid` are preserved. Row IDs are signed decimal **strings**, avoiding JavaScript precision loss above 2^53. Recordings retain their level/simulation versions and original stored JSON bytes.
- A SHA-256 checksum of the canonical `payload`. Raw JSON data remains embedded as an unchanged string. The outer archive must remain canonical; reformatting it is rejected rather than silently changing its interpretation.

Legacy Player and Room exports remain **format version 1**. A Player export containing explicit `api_version` in any raw room link or creation receipt uses **format version 2**. A Player with chapter-bound creation-intent records uses **format version 3**. All preserve raw JSON and use database schema version 1 because no gameplay SQL tables or columns changed; notification tables are excluded operational state. Import accepts these three Player formats and only format 1 for the existing Room class; downgraded envelopes containing newer record shapes are rejected. Positive unknown link versions are retained for future dispatch rather than discarded, while unknown chapter creation descriptors are held as unsupported.

Do not roll back to pre-registry code after chapter-bound creation records or First Steps rooms exist. The old code does not understand the new creation rows or simulation-4 checkpoints, even though the SQL tables are unchanged. Disable new chapter creation to stop rollout, retain a registry-aware compatible build for reads/deletion, and use a reviewed forward fix. The flags do not provide global write quiescence or an automated backup coordinator.

The registry in `src/storage-schema.ts` is used both for construction and validation. Import never executes SQL from the archive: it uses fixed, parameter-bound inserts. Tables, columns, types, row counts, integer ranges, JSON shapes/duplicate keys, version metadata, identity consistency, recording structure, archive attempts and receipt revisions are checked before mutation. The existing gameplay simulation validation boundary still applies. A valid checksum detects corruption; it does **not** authenticate an archive or establish that its caller-supplied provenance is true.

Export reads all gameplay rows and metadata synchronously in one transaction, then hashes a detached copy. Restore completes validation and hashing first, then rechecks the target's current schema and emptiness in the same SQLite transaction as every insert and operational alarm reset. A failure rolls all inserts back. Unknown application tables, indices/views/triggers, nonempty KV storage and unowned alarms are rejected instead of omitted. Cloudflare's empty internal `_cf_KV` table and exact protected `_cf_METADATA` alarm schema are allowed. Only the explicitly classified notification state is excluded/reset; future gameplay persistence requires reviewed snapshot support.

Archives are bounded to **24 MiB UTF-8**, each raw JSON row to **256 KiB**, and tables to the application's existing retention limits. Oversized or unsupported objects fail without truncation. These are defensive bounds, not a production maximum-size latency, CPU or memory benchmark. `npm test` includes round trips into different local objects and after eviction, actual HTTP-created guest links, recovery retry receipts, current and archived replays, tombstones, malformed archives, unknown storage, concurrent-write boundaries and injected partial-insert failures.

### Operational boundaries

These primitives are not an owner-held production backup, a full-service restore tool or a tested provider migration. Before using them operationally, a coordinator must authenticate operators, inventory **all** namespace pages, preserve physical/logical target mappings, stop and drain writes across objects, encrypt owner-held archives and verify a complete manifest. The importer does not infer a target from an archive or rewrite references: the caller must route each restored object to the correct logical ID in the destination namespace. Room tombstones and fully erased identities no longer contain their old logical ID; their source physical ID is retained, while their manifest logical ID is explicitly `null`. An independent inventory/deletion ledger is still necessary.

An accepted restore whose response is lost must not be retried as an overwrite. It will return occupied-target conflict; reconcile a fresh export's exact table contents, summary and logical identity with the intended archive. Export time and source physical ID naturally differ, so whole-envelope checksums alone are insufficient for that comparison.

There is no global enumeration tool, cross-object write-quiescence gate, independent deletion ledger, scheduled encrypted backup, off-provider copy or PITR drill in this change. Restoring an old backup can reactivate revoked credential hashes or data deleted afterward; resolve the ledger and client pending requests before reopening writes. RevenueCat purchase records remain external and must be rechecked using the preserved logical player ID. Keep snapshot contents, including credential hashes and recovery receipts, out of logs, source control and public artifacts.

Relevant platform references: [SQLite storage and transactions](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/), [Durable Object bindings/RPC](https://developers.cloudflare.com/durable-objects/api/stub/), [RPC visibility and security](https://developers.cloudflare.com/workers/runtime-apis/rpc/visibility/).

## Optional Relay turn photos

The source includes separate optional photo operations for an **already accepted** Relay v2 turn. Photo upload does not commit, modify, complete, or advance a turn. A client keeps gameplay receipts independently, and a failed upload must leave the accepted turn usable. Deployment and native-client integration are separate steps; this section describes the source contract.

All routes use the existing player credential headers and rate limiter. Room members can read a photo; only the owner of its immutable accepted turn can upload, replace, or delete it. Historical accepted turns retained after a fork keep their own distinct photo. The turn's exact `recording_hash` is required for every change.

New uploads require both `V2_ROOMS_ENABLED=true` and the separate `RELAY_PHOTOS_ENABLED=true`; the photo flag defaults to false. `/v2/capabilities` reports `photo_uploads_enabled`. Pausing only photos leaves gameplay available and returns retryable `503 photo_uploads_disabled` before reading an upload body. Reads, receipt reconciliation and deletions remain available when either mutation flag is off. Keep the client photo UI disabled until the server upload gate and native sharing flow have been verified together.

| Route | Result |
| --- | --- |
| `GET /v2/rooms/:room/photos/:turn` | `{photo:<metadata or null>,jpeg_base64:<string or null>}` |
| `POST /v2/rooms/:room/photos/:turn` | Upload or replace; `{receipt,photo:<current metadata>}` |
| `DELETE /v2/rooms/:room/photos/:turn` | Erase bytes, retain deletion revision and receipt; same response shape |
| `GET /v2/rooms/:room/photo-operations/:key` | This caller's immutable receipt plus current photo metadata |

Upload JSON has exactly `idempotency_key`, `recording_hash`, `expected_photo_revision`, `expected_photo_hash`, `jpeg_base64`, and `sha256`. Delete JSON has the same first four fields. Initial absence uses revision `0` and hash `null`; after deletion use the returned tombstone revision and hash `null`. Both revision and hash must match, preventing an old deletion from erasing a later replacement even if its image bytes match an earlier version. Missing, unsupported or extra fields are rejected.

Keep the exact body and key when an acknowledgement is uncertain. An accepted retry returns its original receipt without applying the image again; accompanying metadata may describe a newer image. The receipt binds `room_id`, `turn_id`, `recording_hash`, operation, canonical request hash, photo revision and accepted photo hash. Do not confuse it with the gameplay room revision, which photo changes leave unchanged. An old receipt cannot authorize a new upload body. All responses use `Cache-Control: no-store`; images have no public URL.

The narrow image profile accepts canonical base64 for a complete baseline JPEG, at most **160 KiB**, each edge at most **960 pixels**, one grayscale or RGB scan. SHA-256 and dimensions are derived from the bytes. APP/EXIF/XMP/comment segments are rejected, except one fixed JFIF APP0 frame without a thumbnail. `jpeg-js` additionally decodes with strict settings, a one-megapixel ceiling and a 32 MiB internal allocation limit to reject malformed compressed image data. This is a synchronous CPU workload; local workerd measurements do not prove production CPU usage. Keep decoding in the Durable Object, after cheap membership/accepted-turn checks, with an atomic authority recheck after asynchronous validation. See [backend dependency notices](THIRD_PARTY_NOTICES.md).

There are at most **32 active images** and **256 immutable photo-operation receipts** per room. Upload admission reserves one future deletion receipt for each active image, so full upload history cannot strand images that their owners want to remove. Full capacity returns `photo_room_full` or `photo_history_full` without silently discarding memories. Deletion removes image bytes but preserves a small version tombstone; deleting the entire room or an associated identity erases all photo rows and receipts. Photo deletion remains available while new v2 gameplay/uploads are disabled. The stream-limited upload body is 224 KiB; deletion is 4 KiB. Invalid images return bounded 400 errors, ownership/absence 404, stale versions or reused keys 409, and unexpected storage failure 500 `photo_storage_error`. Partial writes roll back.

### Relay snapshot extension

RoomV2 now stores the original four tables plus `photos` and `photo_operations` under database schema **3**, and exports archive format **4**. Constructor migration from schema 2 only adds empty photo tables and updates metadata atomically. Restore also accepts existing format-3/schema-2 archives and leaves the new tables empty. Legacy Player and Room archive formats are unchanged.

The archive retains exact base64 strings, raw JSON, numeric SQLite row order, per-turn deletion revisions and immutable photo receipts. Validation checks accepted-turn ownership, exact recording bindings, contiguous photo revisions, byte checksums and full JPEG validity before the empty-target transaction. Limits are 24 MiB per RoomV2 archive and 512 KiB per raw row; these are bounds, not production maximum-size CPU/memory certification. Existing no-public-admin-route, inventory, encryption, deletion-ledger and write-quiescence limitations still apply. Native decoder compatibility, deployment, and real photo sharing require their own release evidence.
