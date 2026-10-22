extends RefCounted
## In-process stand-in for the After You Worker, for the online scenario
## harness. It keeps the live contract for every route Play with a friend uses
## (backend/src/index.ts, v2/routes.ts, v2/room.ts, room-leave.ts,
## room-inbox.ts, invitation-resolve.ts, v2/replay-transfer.ts): the same
## statuses, error codes, precedence and side effects, for relay-isles@2.
## Another chapter (see `chapters`) can be offered, hosted, joined and listed;
## turns are only played in relay-isles@2.
## What it does not do: physics (the real server is structural only too), photo
## delivery, Story/campaign, friend requests, presence, friend room events and
## push. Friends are linked directly by befriend(). Those answer as the
## live server does with their features off.
##
## Fidelity is pinned by backend/test/harness-contract.test.ts, which walks the
## same lifecycle on the real Worker.
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RELAY := "relay-isles@2"
## The room cap (backend room-limit.ts): only rooms still in play count toward
## MAX_ACTIVE_LINKS, and every link counts toward MAX_LINKS.
const MAX_ACTIVE_LINKS := 20
const MAX_LINKS := 60
const INVITE_DAYS := 7
## Header names a 0.6.0 phone never sent (rooms_api.gd at v0.6.0).
const POST_060_HEADERS := ["x-afteryou-room-level", "x-afteryou-friends", "x-afteryou-finished-room", "x-afteryou-friend-events", "x-afteryou-history", "x-afteryou-known-room", "x-afteryou-live"]
const HistoryStore = preload("res://services/history_store.gd")

var replay_transfer_enabled := true
## LIVE_CONNECTION_ENABLED on the live Worker (off unless "true"). On, the
## capability offers live_version 1 to a phone that asks, and live_socket (a
## phone's socket factory) opens that phone's live socket. The server then
## hints as live.ts does: the other member on a join, turn, fork or close, and
## each friend when a player shares a room.
var live_enabled := false
var live_sockets: Dictionary = {}
## Hints written to open sockets.
var live_hints := 0

## One phone's live socket: opens on its first poll when the handshake was
## accepted, answers "ping" with "pong", and holds the hints written to it.
class LiveSocket:
	extends RefCounted
	var state := WebSocketPeer.STATE_CONNECTING
	var accepted := false
	var inbound: Array[PackedByteArray] = []
	var close_code := -1
	func poll() -> void:
		if state == WebSocketPeer.STATE_CONNECTING: state = WebSocketPeer.STATE_OPEN if accepted else WebSocketPeer.STATE_CLOSED
	func get_ready_state() -> int: return state
	func get_available_packet_count() -> int: return inbound.size() if state == WebSocketPeer.STATE_OPEN else 0
	func get_packet() -> PackedByteArray: return inbound.pop_front()
	func send_text(text: String) -> int:
		if state == WebSocketPeer.STATE_OPEN and text == "ping": inbound.append("pong".to_utf8_buffer())
		return OK
	func close(code: int = 1000, _reason: String = "") -> void:
		close_code = code
		state = WebSocketPeer.STATE_CLOSED
	func get_close_code() -> int: return close_code
## False models a Worker from before the conditional room poll (v2/routes.ts
## knownRoom), which ignores X-AfterYou-Known-Room and always sends the full room.
var known_room_polls := true
## Room polls answered with the small unchanged reply.
var unchanged_replies := 0
## HISTORY_OFFLOAD_ENABLED on the live Worker (off unless "true").
var history_offload_enabled := false
## Chapters the server can create, as the live Worker's advertisedChapters
## (v2/chapters.ts). relay-isles@2 is always creatable there.
var chapters: Array[String] = [RELAY]
var mutations_enabled := true
## LEGACY_TRANSFERRED_ROOM_UNBLOCK on the live Worker (off unless "true").
var legacy_transferred_unblock := false
var players: Dictionary = {}
## Earlier-island (v1) invitation codes the resolver knows, code -> [status,
## error code] that their join answers. Only refusals are modelled.
var legacy_invites: Dictionary = {}
var rooms: Dictionary = {}
## Every request, in arrival order: {player, method, path, status, code}.
var requests: Array[Dictionary] = []
## Routes the fake does not implement, so a scenario can see what it missed.
var unknown: Array[String] = []
var now := 1791979200 # 2026-10-14T12:00:00Z
var _rng := RandomNumberGenerator.new()
var _level: Dictionary
var _ids: Dictionary = {}
var _definition_hash := ""

func _init() -> void:
	_level = Registry.definition(RELAY)
	_definition_hash = Canonical.digest(_level)
	_rng.seed = 1

func set_seed(value: int) -> void:
	_rng.seed = value

func _token(bytes: int) -> String:
	var raw := PackedByteArray()
	for i in bytes: raw.append(_rng.randi() & 255)
	return Marshalls.raw_to_base64(raw).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")

func _hex(count: int) -> String:
	var text := ""
	for i in count: text += "0123456789ABCDEF"[_rng.randi() % 16]
	return text

func _stamp(seconds: int = -1) -> String:
	return Time.get_datetime_string_from_unix_time(now if seconds < 0 else seconds) + ".000Z"

## A new identity, as POST /v1/identity creates one (index.ts:67-72).
func new_identity() -> Dictionary:
	var player := _token(16)
	var token := _token(32)
	players[player] = {"token": token, "links": [], "deleted": false, "keys": {}}
	_ids[player] = true
	return {"player_id": player, "device_token": token, "recovery_code": _token(32)}

## True for any room or player id this server issued (raw-id screen check).
func known_id(value: String) -> bool:
	return _ids.has(value)

static func legacy_headers(headers: PackedStringArray) -> PackedStringArray:
	var kept := PackedStringArray()
	for header: String in headers:
		if header.get_slice(":", 0).strip_edges().to_lower() not in POST_060_HEADERS: kept.append(header)
	return kept

static func _headers(list: PackedStringArray) -> Dictionary:
	var result := {}
	for header: String in list:
		result[header.get_slice(":", 0).strip_edges().to_lower()] = header.substr(header.find(":") + 1).strip_edges()
	return result

func _ok(body: Variant, status: int = 200) -> Dictionary:
	return {"status": status, "body": body, "headers": PackedStringArray()}

func _fail(status: int, code: String) -> Dictionary:
	var headers := PackedStringArray()
	if status == 429: headers.append("Retry-After: 60")
	if status == 503: headers.append("Retry-After: 15")
	return {"status": status, "body": {"error": {"code": code, "retryable": status in [429, 503]}}, "headers": headers}

## Entry point for a byte body or reply (room attempts): {status, body, headers, bytes?}.
func handle_raw(method: int, path: String, header_list: PackedStringArray, body: PackedByteArray) -> Dictionary:
	now += 1
	var headers := _headers(header_list)
	var player := str(headers.get("x-player-id", ""))
	var record: Variant = players.get(player)
	var reply: Dictionary
	if not record is Dictionary or record.deleted or str(headers.get("authorization", "")) != "Bearer " + str(record.token): reply = _fail(401, "invalid_auth")
	else: reply = _history_route(player, method, path, headers, {}, body)
	var error: Variant = reply.body.get("error") if reply.body is Dictionary else null
	requests.append({"player": player, "method": method, "path": path, "status": reply.status, "code": str(error.get("code", "")) if error is Dictionary else ""})
	return reply

## Entry point: one HTTP request from one phone.
func handle(method: int, path: String, header_list: PackedStringArray, body: Dictionary) -> Dictionary:
	now += 1
	var headers := _headers(header_list)
	var player := str(headers.get("x-player-id", ""))
	var reply := _route(method, path, headers, body, player)
	var error: Variant = reply.body.get("error") if reply.body is Dictionary else null
	requests.append({"player": player, "method": method, "path": path, "status": reply.status, "code": str(error.get("code", "")) if error is Dictionary else ""})
	return reply

func _route(method: int, path: String, headers: Dictionary, body: Dictionary, player: String) -> Dictionary:
	if path == "/v1/identity" and method == HTTPClient.METHOD_POST:
		if not body.is_empty(): return _fail(400, "unexpected_field")
		return _ok(new_identity(), 201)
	# Authentication (index.ts:36-47): any failure, a deleted identity included.
	var record: Variant = players.get(player)
	if not record is Dictionary or record.deleted or str(headers.get("authorization", "")) != "Bearer " + str(record.token):
		return _fail(401, "invalid_auth")
	if path == "/v1/identity" and method == HTTPClient.METHOD_DELETE: return _erase_identity(player)
	if path == "/v2/capabilities": return _capabilities(headers)
	if path == "/v2/rooms" and method == HTTPClient.METHOD_GET: return _list(player)
	if path == "/v2/rooms" and method == HTTPClient.METHOD_POST: return _create(player, body)
	if path == "/v2/rooms/join": return _join(player, body)
	if path == "/v1/room-inbox": return _inbox(player, headers)
	if path == "/v1/invitations/resolve": return _resolve(body)
	if path == "/v1/rooms/join" and legacy_invites.has(normalize_invite(body.get("invite_code"))):
		var refusal: Array = legacy_invites[normalize_invite(body.get("invite_code"))]
		return _fail(int(refusal[0]), str(refusal[1]))
	if path == "/v1/friends" and method == HTTPClient.METHOD_GET:
		return _ok({"schema_version": 1, "friend_code": player, "refresh_after_seconds": 30, "shared_room": record.get("shared_room"), "friends": _friend_rows(player)})
	if path == "/v1/friends/share": return _share(player, body)
	var friend_join := RegEx.create_from_string("^/v1/friends/([A-Za-z0-9_-]{22})/join$").search(path)
	if friend_join != null and method == HTTPClient.METHOD_POST: return _friend_join(player, friend_join.get_string(1))
	if path == "/v1/social/inbox": return _ok({"schema_version": 1, "available": false, "events": [], "preferences": []})
	# queued counts the friends alerted (social-routes.ts), as the client checks.
	if path == "/v1/social/publication": return _fail(409, "friend_room_not_shared") if record.get("shared_room") == null else _ok({"schema_version": 1, "publication_epoch": 1, "queued": 0})
	if RegEx.create_from_string("^/v2/rooms/[A-Za-z0-9_-]{22}/history").search(path) != null: return _history_route(player, method, path, headers, body, PackedByteArray())
	var found := RegEx.create_from_string("^/v2/rooms/([A-Za-z0-9_-]{22})(?:/(turns|fork|redo|collection|operations|pairs|photos|leave|replay-transfer)(?:/(.*))?)?$").search(path)
	if found == null:
		unknown.append("%d %s" % [method, path])
		return _fail(404, "not_found")
	var room_id := found.get_string(1)
	var section := found.get_string(2)
	var item := found.get_string(3)
	if section == "leave": return _leave(player, room_id, method, item)
	if section.is_empty() and method == HTTPClient.METHOD_DELETE: return _close(player, room_id, headers)
	# requireInteraction (safety-routes.ts:14-17): live or archived membership.
	var room: Variant = rooms.get(room_id)
	if not room is Dictionary or room.deleted or player not in [room.host_id, room.guest_id]: return _fail(404, "room_not_found")
	if section == "replay-transfer":
		if _offloaded(room) > 0 and method == HTTPClient.METHOD_GET or _offloaded(room) > 0 and item in ["ack", "restore"]: return _fail(409, "history_offload_active")
		return _transfer(player, room, method, item, body)
	# Photo reads keep working on a transferred room (routes.ts:135-147, v2/photos.ts:32-38).
	if section == "photos": return _photo(player, room, method, item)
	if room.transferred:
		if section.is_empty() and legacy_transferred_unblock and not headers.has("x-afteryou-finished-room"): return _fail(409, "campaign_client_required")
		return _fail(410, "replay_transferred")
	match section:
		"":
			if method != HTTPClient.METHOD_GET: return _fail(405, "method_not_allowed")
			_note_history(room, player, headers)
			# v2/room.ts snapshotIfChanged: the member already holds this exact revision and branch.
			if known_room_polls and str(headers.get("x-afteryou-known-room", "")) == "%d.%d" % [int(room.revision), int(room.branch)]:
				unchanged_replies += 1
				return _ok({"schema_version": 1, "unchanged": true, "revision": room.revision, "branch": room.branch, "updated_at": room.updated_at})
			return _ok(_view(room, player))
		"fork":
			if method != HTTPClient.METHOD_POST or not item.is_empty(): return _fail(405, "method_not_allowed")
			if not mutations_enabled: return _fail(503, "v2_mutations_disabled")
			_note_history(room, player, headers)
			return _fork(player, room, body)
		"turns":
			if method != HTTPClient.METHOD_POST or not item.is_empty(): return _fail(405, "method_not_allowed")
			if not mutations_enabled: return _fail(503, "v2_mutations_disabled")
			_note_history(room, player, headers)
			return _turn(player, room, body)
		"operations":
			var receipt: Variant = room.receipts.get(player + ":" + item)
			if not receipt is Dictionary: return _fail(404, "operation_not_found")
			return _ok({"receipt": receipt.receipt.duplicate(true), "room": _view(room, player)})
		"pairs":
			var pair: Variant = room.pairs.get(item)
			if pair is Dictionary and room.stubbed.has(item): return _fail(410, "history_offloaded")
			return _ok(pair.duplicate(true)) if pair is Dictionary else _fail(404, "pair_not_found")
		"redo":
			if method != HTTPClient.METHOD_GET: return _fail(503, "v2_mutations_disabled") if not mutations_enabled else _fail(400, "invalid_redo_request")
			return _ok({"schema_version": 1, "source": _redo_source(room), "request": null})
		"collection":
			var rows: Array = []
			for pair: Dictionary in room.pairs.values():
				rows.append({"pair_id": pair.pair_id, "branch": pair.branch, "stage_index": pair.stage_index, "a_hash": pair.a.recording_hash, "b_hash": pair.b.recording_hash, "checkpoint_hash": pair.checkpoint.checkpoint_hash})
			return _ok({"pairs": rows, "active_pair_ids": room.completed_pair_ids.duplicate()})
	unknown.append("%d %s" % [method, path])
	return _fail(404, "not_found")

## The harness never uploads photos: every accepted turn reads as photo-less.
func _photo(player: String, room: Dictionary, method: int, item: String) -> Dictionary:
	var turn := item.get_slice("/", 0)
	var action := item.get_slice("/", 1) if item.contains("/") else ""
	if not room.turns.any(func(entry: Dictionary) -> bool: return entry.turn_id == turn): return _fail(404, "turn_not_found")
	if action == "delivery" and method == HTTPClient.METHOD_GET:
		return _ok({"schema_version": 1, "photo": null, "available": false, "removed_reason": null, "intended_player_ids": [room.host_id] + ([room.guest_id] if room.guest_id != null else []), "acked_player_ids": []})
	if action == "ack": return _fail(503, "photo_delivery_disabled")
	if action.is_empty() and method == HTTPClient.METHOD_GET: return _ok({"photo": null, "jpeg_base64": null})
	if action.is_empty(): return _fail(503, "photo_uploads_disabled")
	return _fail(405, "method_not_allowed")

## redoSource (v2/room.ts:160-167): set while a second turn is owed.
func _redo_source(room: Dictionary) -> Variant:
	if room.guest_id == null or room.a_turn_id == null or room.stage_index >= _stage_count(room): return null
	var first: Variant = _first(room)
	return {"room_id": room.room_id, "revision": room.revision, "branch": room.branch, "stage_index": room.stage_index,
		"a_hash": room.recording_a.recording_hash, "first_player_id": first, "second_player_id": room.guest_id if first == room.host_id else room.host_id}

func _capabilities(headers: Dictionary) -> Dictionary:
	var offered: Array = []
	for key: String in chapters:
		var level := Registry.definition(key)
		var chapter := {"level_id": "relay-isles", "level_version": 2, "definition_hash": _definition_hash, "premium": false, "recording_version": 2, "simulation_version": 2, "supported_simulation_versions": [2, 8]}
		if key != RELAY:
			chapter = {"level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "premium": level.premium,
				"recording_version": level.schema_version, "simulation_version": level.simulation_version, "supported_simulation_versions": Registry.supported_rules(key)}
		if headers.has("x-afteryou-room-level"): chapter["stage_count"] = level.stages.size()
		offered.append(chapter)
	var value := {"api_version": 2, "mutations_enabled": mutations_enabled, "recording_version": 2, "simulation_version": 2,
		"photo_uploads_enabled": false, "preset_reactions_enabled": false, "photo_delivery_enabled": false,
		"replay_transfer_version": 1 if replay_transfer_enabled else 0, "campaign_creation_enabled": false,
		"campaign_mutations_enabled": false, "campaign_definitions": [], "chapters": offered, "validation": "structural_client_replay_required"}
	if headers.get("x-afteryou-history") == "1": value.merge({"history_version": 1, "history_offload_enabled": history_offload_enabled})
	if headers.has("x-afteryou-room-level"):
		value.merge({"room_level": 2, "max_join_versions": 16, "max_stages": 8})
	if live_enabled and headers.get("x-afteryou-live") == "1": value["live_version"] = 1
	return _ok(value)

## The chapter definition a room was created in.
func _level_of(room: Dictionary) -> Dictionary:
	return _level if str(room.get("chapter", RELAY)) == RELAY else Registry.definition(str(room.chapter))

## A room's chapter key, "relay-isles@2" unless it was created in another one.
func room_chapter(room_id: String) -> String:
	return str(rooms[room_id].get("chapter", RELAY)) if rooms.has(room_id) else ""

# Room state ----------------------------------------------------------------

func _stage_count(room: Dictionary) -> int:
	return _level_of(room).stages.size()

func _first(room: Dictionary) -> Variant:
	if room.stage_index >= _stage_count(room): return null
	return room.host_id if _level_of(room).stages[room.stage_index].first_player_slot == "p0" else room.guest_id

func _active(room: Dictionary) -> Variant:
	if room.stage_index >= _stage_count(room): return null
	var first: Variant = _first(room)
	var second: Variant = room.guest_id if first == room.host_id else room.host_id
	return second if room.a_turn_id != null else first

func active_player(room_id: String) -> Variant:
	return _active(rooms[room_id]) if rooms.has(room_id) else null

func _state(room: Dictionary) -> Dictionary:
	var value := {}
	for key: String in ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint", "a_turn_id", "completed_pair_ids", "invite_expires_at", "created_at", "updated_at"]:
		value[key] = room[key].duplicate(true) if room[key] is Dictionary or room[key] is Array else room[key]
	if room.has("simulation_version"): value["simulation_version"] = room.simulation_version
	return value

## RoomSnapshotV2 for one member (room.ts:205-215).
func _view(room: Dictionary, player: String) -> Dictionary:
	var value := _state(room)
	var complete: bool = room.stage_index >= _stage_count(room)
	if player == room.host_id: value["invite_code"] = room.invite_code
	value["api_version"] = 2
	value["active_role"] = "complete" if complete else ("b" if room.a_turn_id != null else "a")
	value["first_player_id"] = _first(room)
	value["active_player_id"] = _active(room)
	value["player_slot"] = "p0" if player == room.host_id else "p1"
	value["stage_id"] = "" if complete else str(_level_of(room).stages[room.stage_index].id)
	value["recording_a"] = room.recording_a.duplicate(true) if room.recording_a is Dictionary else null
	value["validation"] = "structural_client_replay_required"
	return value

func _link(player: String, room_id: String, host: bool) -> void:
	var links: Array = players[player].links
	for link: Dictionary in links:
		if link.room_id == room_id: return
	links.push_front({"room_id": room_id, "host": host})

func _unlink(player: String, room_id: String) -> void:
	if not players.has(player): return
	players[player].links = players[player].links.filter(func(link: Dictionary) -> bool: return link.room_id != room_id)

func linked(player: String, room_id: String) -> bool:
	return players.has(player) and players[player].links.any(func(link: Dictionary) -> bool: return link.room_id == room_id)

func _bump(room: Dictionary, actor: String) -> void:
	room.updated_at = _stamp()
	for member: Variant in [room.host_id, room.guest_id]:
		if member is String and member != actor: room.activity[member] = int(room.activity.get(member, 0)) + 1
	_hint_room(room, actor)

# Live socket ----------------------------------------------------------------

## The socket factory a phone's LiveConnection uses: the upgrade authenticates
## with the same headers as every request (index.ts auth, live.ts).
func live_socket(url: String, header_list: PackedStringArray) -> Object:
	now += 1
	var headers := _headers(header_list)
	var player := str(headers.get("x-player-id", ""))
	var record: Variant = players.get(player)
	var socket := LiveSocket.new()
	socket.accepted = live_enabled and url.ends_with("/v1/live") and record is Dictionary and not record.deleted and str(headers.get("authorization", "")) == "Bearer " + str(record.token)
	if socket.accepted:
		if not live_sockets.has(player): live_sockets[player] = []
		live_sockets[player].append(socket)
	requests.append({"player": player, "method": HTTPClient.METHOD_GET, "path": "/v1/live", "status": 101 if socket.accepted else 401, "code": ""})
	return socket

## Drops every open socket, as a server deploy does.
func drop_live_sockets() -> void:
	for list: Array in live_sockets.values():
		for socket: LiveSocket in list: socket.close(1001)
	live_sockets.clear()

func _hint(player: Variant, message: Dictionary) -> void:
	if not live_enabled or not player is String: return
	for socket: LiveSocket in live_sockets.get(player, []):
		if socket.state == WebSocketPeer.STATE_OPEN or socket.state == WebSocketPeer.STATE_CONNECTING:
			socket.inbound.append(JSON.stringify(message).to_utf8_buffer())
			live_hints += 1

func _hint_room(room: Dictionary, actor: String) -> void:
	for member: Variant in [room.host_id, room.guest_id]:
		if member != actor: _hint(member, {"type": "room_changed", "room": room.room_id, "seq": int(room.revision)})

# Routes ---------------------------------------------------------------------

func _list(player: String) -> Dictionary:
	var result: Array = []
	for link: Dictionary in players[player].links.duplicate():
		var room: Variant = rooms.get(link.room_id)
		if not room is Dictionary or room.deleted or player not in [room.host_id, room.guest_id]:
			# routes.ts:74: a 404 drops the caller's link silently.
			_unlink(player, link.room_id)
			continue
		if room.transferred:
			var entry := _state(room)
			entry.erase("checkpoint")
			entry.a_turn_id = null
			entry["replay_transfer_version"] = 1
			entry["checkpoint_hash"] = room.checkpoint.checkpoint_hash
			entry["api_version"] = 2
			entry["active_role"] = "complete"
			result.append(entry)
		else:
			result.append(_view(room, player))
	return _ok({"rooms": result})

func _create(player: String, body: Dictionary) -> Dictionary:
	if not mutations_enabled: return _fail(503, "v2_mutations_disabled")
	var keys := body.keys()
	keys.sort()
	if not (keys == ["definition_hash", "idempotency_key", "level_id", "level_version"] or keys == ["definition_hash", "idempotency_key", "level_id", "level_version", "simulation_version"]): return _fail(400, "unexpected_fields")
	var created := ""
	for offered: String in chapters:
		var level := Registry.definition(offered)
		if body.level_id == level.id and int(body.level_version) == int(level.version) and body.definition_hash == Canonical.digest(level): created = offered
	if created.is_empty(): return _fail(422, "unsupported_chapter")
	if body.has("simulation_version") and int(body.simulation_version) != 8: return _fail(422, "unsupported_simulation_version")
	var key := str(body.idempotency_key)
	if not RegEx.create_from_string("^[a-zA-Z0-9_-]{16,80}$").search(key): return _fail(400, "invalid_field")
	var known: Variant = players[player].keys.get(key)
	if known is String:
		var existing: Dictionary = rooms[known]
		if existing.transferred: return _fail(410, "replay_transferred")
		if existing.deleted: return _fail(410, "room_deleted")
		return _ok(_view(existing, player))
	if _room_limit_reached(player): return _fail(409, "room_limit_reached")
	var code := _hex(20)
	var room_id := ("v2:" + code).sha256_text().substr(0, 22)
	_ids[room_id] = true
	var room := {"schema_version": 2, "room_id": room_id, "revision": 0, "branch": 0, "stage_index": 0, "level_id": str(body.level_id), "level_version": int(body.level_version),
		"definition_hash": str(body.definition_hash), "host_id": player, "guest_id": null, "checkpoint": Registry.initial_checkpoint(created),
		"a_turn_id": null, "completed_pair_ids": [], "invite_expires_at": _stamp(now + INVITE_DAYS * 86400), "created_at": _stamp(), "updated_at": _stamp(),
		"invite_code": code, "recording_a": null, "receipts": {}, "turns": [], "pairs": {}, "deleted": false, "transferred": false,
		"activity": {}, "transfer": {}, "accepted_log": [], "chapter": created, "history": {"members": {}, "attempts": []}, "stubbed": {}}
	if body.has("simulation_version"): room["simulation_version"] = 8
	rooms[room_id] = room
	players[player].keys[key] = room_id
	_link(player, room_id, true)
	return _ok(_view(room, player))

static func normalize_invite(value: Variant) -> String:
	if not value is String or value.length() > 40: return ""
	var code: String = value.strip_edges().replace("-", "").replace(" ", "").to_upper()
	return code if RegEx.create_from_string("^[0-9A-F]{20}$").search(code) else ""

func _join(player: String, body: Dictionary) -> Dictionary:
	if not mutations_enabled: return _fail(503, "v2_mutations_disabled")
	for key: Variant in body:
		if key not in ["invite_code", "supported_simulation_versions"]: return _fail(400, "unexpected_fields")
	var code := normalize_invite(body.get("invite_code"))
	if code.is_empty(): return _fail(400, "invalid_invite")
	var room_id := ("v2:" + code).sha256_text().substr(0, 22)
	var room: Variant = rooms.get(room_id)
	var fresh := not linked(player, room_id)
	if fresh and _room_limit_reached(player): return _fail(409, "room_limit_reached")
	if not room is Dictionary or room.deleted: return _fail(404, "invite_not_found")
	if room.transferred: return _fail(410, "replay_transferred") if player in [room.host_id, room.guest_id] else _fail(404, "invite_not_found")
	if player in [room.host_id, room.guest_id]:
		_link(player, room_id, player == room.host_id)
		return _ok(_view(room, player))
	if Time.get_unix_time_from_datetime_string(str(room.invite_expires_at).left(19)) < now: return _fail(410, "invite_expired")
	if room.guest_id != null: return _fail(409, "room_full")
	room.guest_id = player
	room.revision += 1
	_bump(room, player)
	_link(player, room_id, false)
	return _ok(_view(room, player))

func _turn(player: String, room: Dictionary, body: Dictionary) -> Dictionary:
	var recording: Variant = body.get("recording")
	if not recording is Dictionary: return _fail(400, "invalid_object")
	var expected := ["base_revision", "branch", "idempotency_key", "recording"]
	if recording.get("role") == "b": expected.append("checkpoint")
	var keys := body.keys()
	keys.sort()
	expected.sort()
	if keys != expected: return _fail(400, "unexpected_fields")
	var hash_input := body.duplicate(true)
	hash_input["operation"] = "turns"
	var request_hash := Canonical.digest(hash_input)
	var key := player + ":" + str(body.idempotency_key)
	if room.receipts.has(key):
		if room.receipts[key].request_hash != request_hash: return _fail(409, "idempotency_key_reused")
		return _ok({"receipt": room.receipts[key].receipt.duplicate(true), "room": _view(room, player)})
	if int(body.base_revision) != int(room.revision) or int(body.branch) != int(room.branch): return _fail(409, "stale_revision")
	if recording.role == "b" and room.a_turn_id == null: return _fail(409, "wrong_turn")
	if _active(room) != player or (recording.role == "a") != (room.a_turn_id == null): return _fail(409, "wrong_turn")
	if recording.get("stage_id") != _level_of(room).stages[room.stage_index].id or recording.get("checkpoint_hash") != room.checkpoint.checkpoint_hash: return _fail(409, "recording_context_mismatch")
	if recording.role == "b" and recording.get("source_recording_hash") != room.recording_a.recording_hash: return _fail(409, "source_recording_mismatch")
	var stage_index: int = room.stage_index
	room.revision += 1
	var turn_id := "t%d-%d-%s" % [room.branch, stage_index, recording.role]
	room.turns.append({"turn_id": turn_id, "player_id": player, "accepted_revision": room.revision, "recording": recording.duplicate(true)})
	room.accepted_log.append(str(recording.recording_hash))
	var pair_id: Variant = null
	if recording.role == "a":
		room.a_turn_id = turn_id
		room.recording_a = recording.duplicate(true)
	else:
		pair_id = "p%d-%d" % [room.branch, stage_index]
		room.pairs[pair_id] = {"pair_id": pair_id, "branch": room.branch, "stage_index": stage_index, "a": room.recording_a.duplicate(true), "b": recording.duplicate(true), "checkpoint": body.checkpoint.duplicate(true)}
		room.completed_pair_ids.append(pair_id)
		room.checkpoint = body.checkpoint.duplicate(true)
		room.stage_index += 1
		room.a_turn_id = null
		room.recording_a = null
	_bump(room, player)
	var receipt := {"schema_version": 2, "room_id": room.room_id, "idempotency_key": body.idempotency_key, "request_hash": request_hash, "operation": "turns",
		"accepted_revision": room.revision, "branch": room.branch, "stage_index": stage_index, "stage_id": recording.stage_id, "turn_id": turn_id,
		"recording_hash": recording.recording_hash, "pair_id": pair_id, "checkpoint_hash": room.checkpoint.checkpoint_hash}
	room.receipts[key] = {"receipt": receipt, "request_hash": request_hash}
	return _ok({"receipt": receipt.duplicate(true), "room": _view(room, player)})

## memberRoomState (room.ts:137-142): gone, finished or in_play.
func _member_state(room: Variant, player: String) -> String:
	if not room is Dictionary or room.deleted or player not in [room.host_id, room.guest_id]: return "gone"
	if room.transferred or room.stage_index >= _stage_count(room): return "finished"
	return "in_play"

## room-limit.ts roomLimitReached, with the settled rooms the router reads at the cap.
func _room_limit_reached(player: String) -> bool:
	var links: Array = players[player].links
	if links.size() >= MAX_LINKS: return true
	return links.filter(func(link: Dictionary) -> bool: return _member_state(rooms.get(link.room_id), player) == "in_play").size() >= MAX_ACTIVE_LINKS

## DELETE /v2/rooms/:id (room-leave.ts:7-9, room.ts:592-610).
func _close(player: String, room_id: String, headers: Dictionary) -> Dictionary:
	var room: Variant = rooms.get(room_id)
	if headers.get("x-afteryou-close-if") == "in-play" and _member_state(room, player) == "finished": return _fail(409, "room_finished")
	if not room is Dictionary or room.deleted or player not in [room.host_id, room.guest_id]: return _fail(404, "room_not_found")
	room.deleted = true
	room.receipts.clear()
	room.turns.clear()
	room.pairs.clear()
	room.activity.clear()
	room.transfer = {}
	room.history = {"members": {}, "attempts": []}
	room.stubbed = {}
	_unlink(player, room_id)
	_hint_room(room, player)
	return _ok({"deleted": true})

## POST /v2/rooms/:id/leave (room-leave.ts:11-31).
func _leave(player: String, room_id: String, method: int, item: String) -> Dictionary:
	if method != HTTPClient.METHOD_POST or not item.is_empty(): return _fail(405, "method_not_allowed")
	if not linked(player, room_id): return _ok({"schema_version": 1, "removed": true})
	if _member_state(rooms.get(room_id), player) != "gone": return _fail(409, "room_not_closed")
	_unlink(player, room_id)
	return _ok({"schema_version": 1, "removed": true})

## GET /v1/room-inbox (room-inbox.ts).
func _inbox(player: String, headers: Dictionary) -> Dictionary:
	var result: Array = []
	for link: Dictionary in players[player].links:
		var room: Variant = rooms.get(link.room_id)
		if not room is Dictionary or room.deleted or player not in [room.host_id, room.guest_id]:
			var closed: bool = room is Dictionary and room.deleted and headers.get("x-afteryou-room-inbox") == "2"
			result.append({"room_id": link.room_id, "family": "relay", "api_version": 2, "chapter": {"id": null, "version": null},
				"membership": {"host_id": null, "guest_id": null, "you_are_host": link.host}, "status": "closed" if closed else "unavailable",
				"revision": null, "remote_activity_sequence": 0, "activity_at": null})
			continue
		result.append({"room_id": room.room_id, "family": "relay", "api_version": 2, "chapter": {"id": room.level_id, "version": room.level_version},
			"membership": {"host_id": room.host_id, "guest_id": room.guest_id, "you_are_host": room.host_id == player},
			"status": _inbox_status(room, player), "revision": room.revision, "remote_activity_sequence": int(room.activity.get(player, 0)), "activity_at": room.updated_at})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.activity_at) > str(b.activity_at))
	return _ok({"schema_version": 1, "rooms": result})

func _inbox_status(room: Dictionary, player: String) -> String:
	if room.guest_id == null: return "waiting_for_friend"
	var active: Variant = _active(room)
	if active == null: return "completed"
	return "your_turn" if active == player else "waiting_for_their_turn"

## What the inbox reports per room for this player, room_id -> status.
func inbox_statuses(player: String) -> Dictionary:
	var result := {}
	for room: Dictionary in _inbox(player, {"x-afteryou-room-inbox": "2"}).body.rooms: result[room.room_id] = room.status
	return result

func _resolve(body: Dictionary) -> Dictionary:
	for key: Variant in body:
		if key != "invite_code": return _fail(400, "unexpected_field")
	var code := normalize_invite(body.get("invite_code"))
	if code.is_empty(): return _fail(400, "invalid_invite")
	var room: Variant = rooms.get(("v2:" + code).sha256_text().substr(0, 22))
	if room is Dictionary: return _ok({"schema_version": 1, "family": "relay", "api_version": 2})
	if legacy_invites.has(code): return _ok({"schema_version": 1, "family": "legacy", "api_version": 1})
	return _fail(404, "invite_not_found")

func _share(player: String, body: Dictionary) -> Dictionary:
	var target: Variant = body.get("room")
	if target == null:
		if players[player].get("shared_room") != null:
			for friend: String in players[player].get("friends", {}): _hint(friend, {"type": "friends_changed"})
		players[player].shared_room = null
		return _ok({"schema_version": 1, "shared_room": null})
	var room: Variant = rooms.get(str(target.get("room_id", "")))
	if not room is Dictionary or room.deleted or room.host_id != player: return _fail(404, "room_not_found")
	if room.transferred: return _fail(410, "replay_transferred")
	if room.guest_id == null and Time.get_unix_time_from_datetime_string(str(room.invite_expires_at).left(19)) < now: return _fail(410, "invite_expired")
	var changed: bool = players[player].get("shared_room") != {"api_version": 2, "room_id": room.room_id}
	players[player].shared_room = {"api_version": 2, "room_id": room.room_id}
	if changed:
		for friend: String in players[player].get("friends", {}): _hint(friend, {"type": "friends_changed"})
	return _ok({"schema_version": 1, "shared_room": players[player].shared_room})

## Accepted friends' rows (friends-routes.ts:58-90). No presence: every friend
## reads offline, and Join is offered while the friend shares an open room.
func _friend_rows(player: String) -> Array:
	var rows: Array = []
	for other: String in players[player].get("friends", {}):
		var record: Dictionary = players[other]
		if record.deleted: continue
		var shared: Variant = record.get("shared_room")
		var room: Variant = rooms.get(str(shared.room_id)) if shared is Dictionary else null
		var open: bool = room is Dictionary and not room.deleted and not room.transferred and room.host_id == other
		rows.append({"player_id": other, "request_id": players[player].friends[other], "status": "accepted", "online": false, "expires_after_seconds": 0, "join_available": open})
	return rows

## Two players who are already friends, as after a request and its acceptance.
func befriend(a: String, b: String) -> void:
	var request := _token(16)
	for pair: Array in [[a, b], [b, a]]:
		if not players[pair[0]].has("friends"): players[pair[0]]["friends"] = {}
		players[pair[0]].friends[pair[1]] = request

## POST /v1/friends/<id>/join (friends-routes.ts): a friend's shared open room
## hands over its invitation code, which the phone then joins with.
func _friend_join(player: String, other: String) -> Dictionary:
	if not players[player].get("friends", {}).has(other) or not players.has(other): return _fail(404, "friend_not_found")
	var shared: Variant = players[other].get("shared_room")
	var room: Variant = rooms.get(str(shared.room_id)) if shared is Dictionary else null
	if not room is Dictionary or room.deleted or room.transferred or room.host_id != other: return _fail(409, "friend_not_joinable")
	return _ok({"schema_version": 1, "api_version": 2, "room_id": room.room_id, "invite_code": room.invite_code})

## DELETE /v1/identity (room-links.ts:18-48): every room is erased for the partner.
func _erase_identity(player: String) -> Dictionary:
	for link: Dictionary in players[player].links.duplicate():
		var room: Variant = rooms.get(link.room_id)
		if room is Dictionary and not room.deleted:
			room.deleted = true
			room.transfer = {}
		_unlink(player, link.room_id)
	players[player].deleted = true
	return _ok({"deleted": true})

# Replay transfer (v2/replay-transfer.ts) ------------------------------------

func _manifest_room(room: Dictionary) -> Dictionary:
	var value := _state(room)
	value.erase("checkpoint")
	value["checkpoint_hash"] = room.checkpoint.checkpoint_hash
	return value

func _prepare_transfer(room: Dictionary) -> Dictionary:
	var archive_room := _state(room)
	var archive := {"schema_version": 1, "room": archive_room, "turns": room.turns.duplicate(true), "pairs": room.pairs.values().duplicate(true)}
	var archive_hash := Canonical.digest(archive)
	if not room.transfer.is_empty() and room.transfer.manifest.archive_hash == archive_hash: return room.transfer
	var turns: Array = []
	for turn: Dictionary in room.turns: turns.append({"turn_id": turn.turn_id, "player_id": turn.player_id, "accepted_revision": turn.accepted_revision, "recording_hash": turn.recording.recording_hash})
	var pairs: Array = []
	for pair: Dictionary in archive.pairs: pairs.append({"pair_id": pair.pair_id, "branch": pair.branch, "stage_index": pair.stage_index, "a_hash": pair.a.recording_hash, "b_hash": pair.b.recording_hash, "checkpoint_hash": pair.checkpoint.checkpoint_hash})
	var epoch := int(room.transfer.get("manifest", {}).get("epoch", 0)) + 1
	room.transfer = {"manifest": {"schema_version": 1, "epoch": epoch, "archive_hash": archive_hash, "room": _manifest_room(room), "turns": turns, "pairs": pairs}, "archive": archive, "acked": []}
	return room.transfer

func _transfer_view(room: Dictionary, with_archive: bool) -> Dictionary:
	var acked: Array = [room.host_id, room.guest_id].filter(func(id: Variant) -> bool: return id in room.transfer.acked)
	var value := {"schema_version": 1, "manifest": room.transfer.manifest.duplicate(true), "acked_player_ids": acked, "transferred": acked.size() == 2}
	if with_archive: value["archive"] = room.transfer.archive.duplicate(true) if not room.transferred else null
	return value

func _transfer(player: String, room: Dictionary, method: int, item: String, body: Dictionary) -> Dictionary:
	if method == HTTPClient.METHOD_GET and item in ["", "manifest"]:
		if room.transferred: return _ok(_transfer_view(room, true)) if not room.transfer.is_empty() else _fail(410, "replay_transferred")
		if room.guest_id == null or room.stage_index < _stage_count(room) or room.a_turn_id != null: return _fail(409, "replay_not_complete")
		if not replay_transfer_enabled and room.transfer.is_empty(): return _fail(503, "replay_transfer_disabled")
		_prepare_transfer(room)
		var view := _transfer_view(room, true)
		if item == "manifest": view.archive = null
		return _ok(view)
	if method == HTTPClient.METHOD_POST and item == "ack":
		if not replay_transfer_enabled: return _fail(503, "replay_transfer_disabled")
		if room.transfer.is_empty() or int(body.get("epoch", -1)) != int(room.transfer.manifest.epoch) or body.get("archive_hash") != room.transfer.manifest.archive_hash: return _fail(409, "stale_replay_ack")
		if player not in room.transfer.acked: room.transfer.acked.append(player)
		if room.transfer.acked.size() == 2 and not room.transferred:
			room.transferred = true
		return _ok(_transfer_view(room, false))
	if method == HTTPClient.METHOD_POST and item == "restore":
		if room.transfer.is_empty() or int(body.get("epoch", -1)) != int(room.transfer.manifest.epoch) or body.get("archive_hash") != room.transfer.manifest.archive_hash: return _fail(409, "stale_replay_restore")
		room.transferred = false
		var next := int(room.transfer.manifest.epoch) + 1
		room.transfer.manifest.epoch = next
		room.transfer.acked = []
		return _ok({"restored": true, "transfer": _transfer_view(room, false)})
	if method == HTTPClient.METHOD_GET and item.begins_with("operations/"):
		return _fail(404, "operation_not_found")
	return _fail(405, "method_not_allowed")

# Room history (v2/history.ts, history-room.ts, history-blob.ts) -------------
# The fake keeps every row in full and only marks what the Worker would have
# stubbed: its replies match the Worker's, which tests/backend pin.

## A member room request says what the phone supports, while offload is on.
func _note_history(room: Dictionary, player: String, headers: Dictionary) -> void:
	if not history_offload_enabled: return
	var version := 1 if headers.get("x-afteryou-history") == "1" else 0
	if version == 0 and room.history.members.is_empty(): return
	room.history.members[player] = version

func _offloaded(room: Dictionary) -> int:
	return room.history.attempts.filter(func(record: Dictionary) -> bool: return record.state == "offloaded").size()

func _v1_transferred(room: Dictionary) -> bool:
	return room.transferred and not room.get("history_tombstone", false)

func _finished(room: Dictionary) -> int:
	return int(room.branch) + (1 if room.transferred or room.stage_index >= _stage_count(room) else 0)

func _attempt_blob(room: Dictionary, branch: int) -> Dictionary:
	var pairs: Array = room.pairs.values().filter(func(pair: Dictionary) -> bool: return int(pair.branch) == branch)
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.stage_index) < int(b.stage_index))
	var turns: Array = room.turns.filter(func(turn: Dictionary) -> bool: return str(turn.turn_id).begins_with("t%d-" % branch))
	var paired := {}
	for pair: Dictionary in pairs:
		paired["t%d-%d-a" % [branch, pair.stage_index]] = true
		paired["t%d-%d-b" % [branch, pair.stage_index]] = true
	var open: Variant = null
	for turn: Dictionary in turns:
		if not paired.has(turn.turn_id): open = turn.recording.duplicate(true)
	return {"format": "after-you.attempt", "format_version": 1, "room_id": room.room_id, "level_id": room.level_id, "level_version": room.level_version, "definition_hash": room.definition_hash,
		"position": branch, "branch": branch, "checkpoint": pairs.back().checkpoint.duplicate(true) if not pairs.is_empty() else null, "open_turn": open,
		"rows": {"turns": turns.map(func(turn: Dictionary) -> Dictionary: return {"turn_id": turn.turn_id, "player_id": turn.player_id, "accepted_revision": turn.accepted_revision, "recording_hash": turn.recording.recording_hash}),
			"pairs": pairs.map(func(pair: Dictionary) -> Dictionary: return {"pair_id": pair.pair_id, "branch": pair.branch, "stage_index": pair.stage_index, "a_hash": pair.a.recording_hash, "b_hash": pair.b.recording_hash, "checkpoint_hash": pair.checkpoint.checkpoint_hash})}}

static func _blob_bytes(blob: Dictionary) -> PackedByteArray:
	return JSON.stringify(Canonical.normalized(blob), "", true).to_utf8_buffer()

## Finished attempts in order; newly finished ones are recorded as the Worker does lazily.
func _history_chain(room: Dictionary) -> Array:
	var records: Array = room.history.attempts
	while records.size() < _finished(room):
		var position := records.size()
		var blob := _attempt_blob(room, position)
		var bytes := _blob_bytes(blob)
		var digest := HistoryStore.digest(bytes)
		var last_stage := int(blob.checkpoint.stage_index) if blob.checkpoint is Dictionary else (int(str(blob.rows.turns[0].turn_id).get_slice("-", 1)) if blob.open_turn != null else 0)
		records.append({"position": position, "branch": position, "digest": digest, "link": HistoryStore.link(room, position, records.back().link if position > 0 else HistoryStore.ZERO_LINK, digest, bytes.size()),
			"byte_length": bytes.size(), "last_stage": last_stage, "state": "held", "acked": [], "wanted": [], "pair_ids": blob.rows.pairs.map(func(pair: Dictionary) -> String: return pair.pair_id)})
	return records

func _history_view(room: Dictionary, player: String) -> Dictionary:
	var partner: Variant = room.guest_id if player == room.host_id else room.host_id
	var facts := {"room_id": room.room_id, "level_id": room.level_id, "level_version": room.level_version, "definition_hash": room.definition_hash, "host_id": room.host_id, "guest_id": room.guest_id}
	var partner_supports: bool = partner != null and room.history.members.get(partner) == 1
	if _v1_transferred(room): return {"schema_version": 1, "mode": "v1_transferred", "head": HistoryStore.ZERO_LINK, "room": facts, "partner_supports": partner_supports, "attempts": []}
	var records := _history_chain(room)
	return {"schema_version": 1, "mode": "attempts", "head": records.back().link if not records.is_empty() else HistoryStore.ZERO_LINK, "room": facts, "partner_supports": partner_supports,
		"attempts": records.map(func(record: Dictionary) -> Dictionary: return {"position": record.position, "branch": record.branch, "digest": record.digest, "link": record.link,
			"byte_length": record.byte_length, "last_stage": record.last_stage, "state": record.state, "acked_by_you": player in record.acked, "partner_acked": partner in record.acked,
			"wanted_by_partner": partner in record.wanted, "pair_ids": record.pair_ids.duplicate()})}

func _history_route(player: String, method: int, path: String, headers: Dictionary, body: Dictionary, raw: PackedByteArray) -> Dictionary:
	var found := RegEx.create_from_string("^/v2/rooms/([A-Za-z0-9_-]{22})/history(?:/([0-9]{1,2})(?:/(ack|want))?)?$").search(path)
	if found == null:
		unknown.append("%d %s" % [method, path])
		return _fail(404, "not_found")
	var room: Variant = rooms.get(found.get_string(1))
	if not room is Dictionary or room.deleted or player not in [room.host_id, room.guest_id]: return _fail(404, "room_not_found")
	_note_history(room, player, headers)
	var item := found.get_string(2)
	var action := found.get_string(3)
	if item.is_empty():
		return _ok(_history_view(room, player)) if method == HTTPClient.METHOD_GET else _fail(405, "method_not_allowed")
	var position := int(item)
	if position > 31: return _fail(400, "invalid_field")
	if method == HTTPClient.METHOD_POST and action == "ack" and not history_offload_enabled: return _fail(503, "history_offload_disabled")
	if _v1_transferred(room): return _fail(409, "history_v1_transferred")
	var records := _history_chain(room)
	if position >= records.size(): return _fail(404, "history_not_found")
	var record: Dictionary = records[position]
	if method == HTTPClient.METHOD_GET and action.is_empty():
		if record.state == "offloaded": return _fail(410, "history_offloaded")
		var tagged := PackedByteArray([HistoryStore.ENCODING_DEFLATE])
		tagged.append_array(_blob_bytes(_attempt_blob(room, position)).compress(FileAccess.COMPRESSION_DEFLATE))
		return {"status": 200, "body": {}, "headers": PackedStringArray(), "bytes": tagged}
	if method != HTTPClient.METHOD_POST: return _fail(405, "method_not_allowed")
	if action == "ack":
		if body.keys().size() != 2 or body.get("schema_version") != 1.0: return _fail(422, "invalid_history_request")
		if body.get("link") != record.link: return _fail(409, "history_mismatch")
		if record.state == "held":
			if player not in record.acked: record.acked.append(player)
			var members: Dictionary = room.history.members
			if record.acked.size() == 2 and room.guest_id != null and members.get(room.host_id) == 1 and members.get(room.guest_id) == 1 and position < _finished(room): _offload(room, record)
		return _ok(_history_view(room, player))
	if action == "want":
		if record.state == "offloaded" and player not in record.wanted: record.wanted.append(player)
		return _ok(_history_view(room, player))
	var bytes := HistoryStore.decode(raw, int(record.byte_length))
	if bytes.is_empty() or HistoryStore.digest(bytes) != record.digest: return _fail(422, "history_mismatch")
	if record.state == "offloaded":
		record.state = "held"
		record.acked = [player]
		record.wanted = []
		if room.get("history_tombstone", false) and position == int(room.branch):
			room.transferred = false
			room.history_tombstone = false
			for pair_id: String in room.completed_pair_ids: room.stubbed.erase(pair_id)
		for pair_id: String in record.pair_ids: room.stubbed.erase(pair_id)
	return _ok(_history_view(room, player))

func _offload(room: Dictionary, record: Dictionary) -> void:
	record.state = "offloaded"
	record.acked = []
	record.wanted = []
	if not room.transferred and room.stage_index >= _stage_count(room) and int(record.position) == int(room.branch):
		room.transferred = true
		room.history_tombstone = true
	_stub_released(room)

## Every pair of an offloaded attempt that the live lineage no longer reads answers 410.
func _stub_released(room: Dictionary) -> void:
	var live := {}
	if not room.transferred:
		for pair_id: String in room.completed_pair_ids: live[pair_id] = true
	for record: Dictionary in room.history.attempts:
		if record.state != "offloaded": continue
		for pair_id: String in record.pair_ids:
			if not live.has(pair_id): room.stubbed[pair_id] = true

## POST /v2/rooms/:id/fork (room.ts forkInternal): back to a stage, a new branch.
func _fork(player: String, room: Dictionary, body: Dictionary) -> Dictionary:
	var keys := body.keys()
	keys.sort()
	if keys != ["base_revision", "branch", "idempotency_key", "stage_index"]: return _fail(400, "unexpected_fields")
	var hash_input := body.duplicate(true)
	hash_input["operation"] = "fork"
	var request_hash := Canonical.digest(hash_input)
	var key := player + ":" + str(body.idempotency_key)
	if room.receipts.has(key):
		if room.receipts[key].request_hash != request_hash: return _fail(409, "idempotency_key_reused")
		return _ok({"receipt": room.receipts[key].receipt.duplicate(true), "room": _view(room, player)})
	if int(body.base_revision) != int(room.revision) or int(body.branch) != int(room.branch): return _fail(409, "stale_revision")
	var stage := int(body.stage_index)
	if stage > int(room.stage_index) or (stage == int(room.stage_index) and room.a_turn_id == null): return _fail(409, "nothing_to_fork")
	if int(room.branch) + 1 >= 32 or int(room.branch) + 2 - _offloaded(room) > 32: return _fail(409, "room_history_full")
	room.checkpoint = Registry.initial_checkpoint(str(room.get("chapter", RELAY))) if stage == 0 else room.pairs[room.completed_pair_ids[stage - 1]].checkpoint.duplicate(true)
	room.completed_pair_ids = room.completed_pair_ids.slice(0, stage)
	room.a_turn_id = null
	room.recording_a = null
	room.stage_index = stage
	room.branch += 1
	room.revision += 1
	_bump(room, player)
	var receipt := {"schema_version": 2, "room_id": room.room_id, "idempotency_key": body.idempotency_key, "request_hash": request_hash, "operation": "fork",
		"accepted_revision": room.revision, "branch": room.branch, "stage_index": stage, "stage_id": _level_of(room).stages[stage].id, "turn_id": null,
		"recording_hash": null, "pair_id": null, "checkpoint_hash": room.checkpoint.checkpoint_hash}
	room.receipts[key] = {"receipt": receipt, "request_hash": request_hash}
	_stub_released(room)
	return _ok({"receipt": receipt.duplicate(true), "room": _view(room, player)})

# Scenario helpers -----------------------------------------------------------

func advance_days(days: int) -> void:
	now += days * 86400

func room_of(player: String) -> Array[String]:
	var result: Array[String] = []
	for room_id: String in rooms:
		var room: Dictionary = rooms[room_id]
		if player in [room.host_id, room.guest_id]: result.append(room_id)
	return result

## Every recording hash this room ever accepted, closing it included.
func ever_accepted(room_id: String) -> Array:
	return rooms[room_id].accepted_log if rooms.has(room_id) else []

## Accepted turns' recording hashes in one room, in order.
func accepted(room_id: String) -> Array:
	return rooms[room_id].turns.map(func(turn: Dictionary) -> String: return turn.recording.recording_hash) if rooms.has(room_id) else []

## Attempt states on the server, in order: "held" or "offloaded".
func attempt_states(room_id: String) -> Array:
	return rooms[room_id].history.attempts.map(func(record: Dictionary) -> String: return record.state) if rooms.has(room_id) else []

## "in_play", "complete", "closed" or "transferred".
func room_state(room_id: String) -> String:
	var room: Variant = rooms.get(room_id)
	if not room is Dictionary or room.deleted: return "closed"
	if room.transferred: return "transferred"
	return "complete" if room.stage_index >= _stage_count(room) else "in_play"
