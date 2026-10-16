extends RefCounted
## Explicit, cache-backed reads for the authenticated room inbox.
## Refresh is caller-controlled; this service never starts a timer or polls.
const Presence = preload("res://services/friend_presence.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const Typed = preload("res://services/typed_values.gd")
const CACHE_PATH := "user://room-inbox-cache.cfg"
const UNAVAILABLE_TITLE := "Unavailable room"
## A room taken off the list for good (closed or left), not just hidden: its
## entry in the hidden map never comes back, and it is not a hidden room.
const FORGOTTEN := 1 << 40
var busy := false
var last_error := ""
var _api: Node
var _identity: Callable
var _transport: Callable
## Optional provider of rooms kept in local history (hosted and joined rooms
## from existing endpoints). Lets the hub work before the inbox ships.
var local: Callable
## Optional provider of finished rooms whose replay is saved on this device, in
## the same room shape. It only names a listed room the server can no longer
## read (its replay moved to the phones); it never adds a room to the list.
var finished: Callable
var _binding: Dictionary = {}
var _rooms: Array[Dictionary] = []
var _seen: Dictionary = {}
## Rooms this player removed from the list, by room key, with the activity
## sequence seen then. New activity in such a room shows it again.
var _hidden: Dictionary = {}
var stale := true

func _init(api: Node, identity: Callable, transport: Callable = Callable()) -> void:
	_api = api
	_identity = identity
	_transport = transport
	_bind(true)

func context() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	if not value is Dictionary or value.get("ready") != true or not Presence.valid_id(value.get("player_id")): return {}
	if not is_instance_valid(_api) or _api.player_id != value.player_id or _api.device_token.is_empty(): return {}
	var server := str(_api.base_url).trim_suffix("/")
	if server.is_empty(): return {}
	return {"player_id":value.player_id,"epoch":value.get("epoch",0),"server":server,"credential_hash":str(_api.device_token).sha256_text()}

func view() -> Dictionary:
	if not _bind():
		var cold := _local_rooms()
		if cold.is_empty(): return {"rooms":[],"stale":true,"error":"Rooms unavailable"}
		return {"rooms":ordered(cold,_seen,""),"stale":true,"error":""}
	var history := _local_rooms()
	var combined := _resolved(_merge(_rooms,history),history).filter(_shown)
	return {"rooms":ordered(combined,_seen,_binding.player_id),"stale":stale,"error":last_error}

## A listed room without a known chapter takes its name, members and state from
## this device's own record of it, or else reads as an unavailable room.
func _resolved(rooms: Array[Dictionary], history: Array[Dictionary]) -> Array[Dictionary]:
	var known := {}
	var replays := {}
	var saved: Variant = finished.call() if finished.is_valid() else []
	var sources: Array = [saved if saved is Array else [], history]
	for index in sources.size():
		for item: Variant in sources[index]:
			if not valid_room(item) or unresolved(item): continue
			var item_key := room_key(int(item.api_version),str(item.room_id))
			if index == 0: replays[item_key] = true
			known[item_key] = item
	var result: Array[Dictionary] = []
	for room: Dictionary in rooms:
		if not unresolved(room):
			result.append(room)
			continue
		var key := room_key(int(room.get("api_version",0)),str(room.get("room_id","")))
		var shown: Dictionary = (known[key] as Dictionary).duplicate(true) if known.has(key) else room.duplicate(true)
		if known.has(key):
			shown.remote_activity_sequence = maxi(int(shown.get("remote_activity_sequence",0)),int(room.get("remote_activity_sequence",0)))
			# Local history only names the room. A room the other player closed
			# stays closed; one whose replay this phone saved still opens it.
			if room.get("status") == "closed" and not replays.has(key): shown.status = "closed"
		else:
			shown.chapter_key = "unknown"
			shown.chapter_title = UNAVAILABLE_TITLE
		result.append(shown)
	return result

## True for a room row with no chapter: the server's placeholder for a room it
## cannot read, including rows a 0.6.0 cache saved as "<null>".
static func unresolved(room: Dictionary) -> bool:
	var key := str(room.get("chapter_key",""))
	return key.is_empty() or key == "unknown" or key.begins_with("<")

func _shown(room: Dictionary) -> bool:
	var key := room_key(int(room.get("api_version",0)),str(room.get("room_id","")))
	return not _hidden.has(key) or int(room.get("remote_activity_sequence",0)) > int(_hidden[key])

## Rooms carried from local history (existing endpoints) that the inbox summary
## has not already provided. Each local room begins at a read baseline so a room
## we have never seen a server sequence for cannot raise a false unread dot.
func _local_rooms() -> Array[Dictionary]:
	if not local.is_valid(): return []
	var value: Variant = local.call()
	var result: Array[Dictionary] = []
	if not value is Array: return result
	for item: Variant in value:
		if not valid_room(item): continue
		var room: Dictionary = (item as Dictionary).duplicate(true)
		var key := room_key(int(room.api_version),str(room.room_id))
		result.append(room)
		if not _seen.has(key): _seen[key] = int(room.remote_activity_sequence)
	return result

func _merge(primary: Array, secondary: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys := {}
	for value: Variant in primary:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
			keys[room_key(int(value.get("api_version",0)),str(value.get("room_id","")))] = true
	for value: Variant in secondary:
		if not value is Dictionary: continue
		var key := room_key(int(value.get("api_version",0)),str(value.get("room_id","")))
		if keys.has(key): continue
		keys[key] = true
		result.append((value as Dictionary).duplicate(true))
	return result

func refresh() -> bool:
	if not _bind() or busy:
		if busy or not _rooms.is_empty(): stale = true
		return false
	busy = true
	last_error = ""
	var binding := _binding.duplicate(true)
	var response: Variant = await _transport.call(HTTPClient.METHOD_GET,"/v1/room-inbox",{}) if _transport.is_valid() else await _api.request_json(HTTPClient.METHOD_GET,"/v1/room-inbox",{},func() -> bool: return context() == binding)
	if context() != binding:
		busy = false
		_bind(true)
		return false
	busy = false
	if not response is Dictionary or not response.get("ok",false):
		last_error = "Rooms unavailable"
		stale = true
		return false
	var data: Variant = response.get("data")
	if not valid_page(data):
		last_error = "Rooms unavailable"
		stale = true
		return false
	_rooms.clear()
	for room: Dictionary in data.rooms:
		_rooms.append(_normalize_room(room))
		var key := room_key(RoomsApi.json_int(room.api_version),str(room.room_id))
		# Existing rooms begin at a read baseline. Only later remote activity is
		# marked unread, avoiding a false alert for the whole prior room history.
		if not _seen.has(key): _seen[key] = int(room.remote_activity_sequence)
	stale = false
	_save()
	return true

## Call only after the destination room has loaded and rendered successfully.
func confirm_room_rendered(api_version: int, room_id: String) -> bool:
	if not _bind() or api_version not in [1,2] or not Presence.valid_id(room_id): return false
	var identity := room_key(api_version,room_id)
	var found := false
	for row: Dictionary in _rooms:
		if row.api_version == api_version and row.room_id == room_id:
			_seen[identity] = int(row.remote_activity_sequence)
			found = true
	if found: _save()
	return found

func unread(room: Dictionary) -> bool:
	return is_unread(room,_seen)

## True when the latest successful server read listed this room, so its status
## is current enough to close or remove it.
func confirmed(room: Dictionary) -> bool:
	if stale or not _bind(): return false
	for row: Dictionary in _rooms:
		if int(row.api_version) == int(room.get("api_version",0)) and str(row.room_id) == str(room.get("room_id","")): return true
	return false

## Takes a room off this player's list on this device. A finished room stays
## linked on the server (so identity deletion still erases it); new activity in
## it, such as the friend replaying, brings it back.
func hide(room: Dictionary) -> void:
	if not _bind(): return
	_hidden[room_key(int(room.get("api_version",0)),str(room.get("room_id","")))] = maxi(0,int(room.get("remote_activity_sequence",0)))
	_save()

## Drops a room the server has closed or no longer links to this player.
func forget(api_version: int, room_id: String) -> void:
	if not _bind(): return
	var key := room_key(api_version,room_id)
	var kept: Array[Dictionary] = []
	for row: Dictionary in _rooms:
		if room_key(int(row.api_version),str(row.room_id)) != key: kept.append(row)
	_rooms = kept
	_seen.erase(key)
	# Local history may still carry the room; keep it off the list there too.
	_hidden[key] = FORGOTTEN
	_save()

## Finished rooms this player hid on this device that are still hidden, in the
## list's order. A forgotten room is not one of them.
func hidden_rooms() -> Array[Dictionary]:
	if not _bind(): return []
	var history := _local_rooms()
	var hidden := _resolved(_merge(_rooms,history),history).filter(func(room: Dictionary) -> bool:
		var key := room_key(int(room.get("api_version",0)),str(room.get("room_id","")))
		return room.get("status") == "completed" and _hidden.has(key) and int(_hidden[key]) < FORGOTTEN and not _shown(room))
	return ordered(hidden,_seen,_binding.player_id)

## Puts a hidden room back on the list.
func show_again(room: Dictionary) -> void:
	if not _bind(): return
	var key := room_key(int(room.get("api_version",0)),str(room.get("room_id","")))
	if not _hidden.has(key) or int(_hidden[key]) >= FORGOTTEN: return
	_hidden.erase(key)
	_save()

func _bind(force: bool = false) -> bool:
	var current := context()
	if current.is_empty():
		_binding = {}
		_rooms.clear()
		_seen.clear()
		_hidden.clear()
		stale = true
		return false
	if force or current != _binding:
		_binding = current
		_rooms.clear()
		_seen.clear()
		_hidden.clear()
		stale = true
		_load()
	return true

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CACHE_PATH) != OK: return
	var key := _cache_section()
	var value: Variant = config.get_value(key,"rooms",[])
	if value is Array and valid_page({"schema_version":1,"rooms":value}):
		for room: Dictionary in value: _rooms.append(room.duplicate(true))
	var seen: Variant = config.get_value(key,"seen",{})
	if seen is Dictionary:
		for identity: Variant in seen:
			var sequence: Variant = seen[identity]
			if identity is String and (sequence is int or sequence is float) and is_finite(sequence) and sequence >= 0 and sequence == floor(sequence): _seen[identity] = int(sequence)
	var hidden: Variant = config.get_value(key,"hidden",{})
	if hidden is Dictionary and hidden.size() <= 256:
		for identity: Variant in hidden:
			var sequence: Variant = hidden[identity]
			if identity is String and identity.length() <= 40 and (sequence is int or sequence is float) and is_finite(sequence) and sequence >= 0: _hidden[identity] = int(sequence)

func _save() -> void:
	var config := ConfigFile.new()
	config.load(CACHE_PATH)
	var key := _cache_section()
	config.set_value(key,"rooms",_rooms)
	config.set_value(key,"seen",_seen)
	# Bounded, newest kept: the oldest entries hide rooms long gone from the list.
	while _hidden.size() > 256: _hidden.erase(_hidden.keys()[0])
	config.set_value(key,"hidden",_hidden)
	config.save(CACHE_PATH)

func _cache_section() -> String:
	return "inbox_" + (_binding.server + "|" + _binding.player_id).sha256_text()

func _normalize_room(value: Dictionary) -> Dictionary:
	# The server keeps a nested, versioned metadata contract. Convert it into a
	# compact view model only after validating that contract.
	if value.has("chapter_key"):
		return value.duplicate(true)
	var chapter: Dictionary = value.get("chapter",{})
	var membership: Dictionary = value.get("membership",{})
	# A room the server cannot read sends a null chapter id.
	var id: Variant = chapter.get("id")
	var chapter_key: String = id if id is String else ""
	if value.get("family") == "legacy" and not chapter_key.is_empty():
		# Earlier islands use their level id; the thumbnail catalog keys them as legacy-<id>.
		chapter_key = RoomChapterTitle.LEGACY_PREFIX + chapter_key
	elif not chapter_key.contains("@") and not RoomChapterTitle.key(chapter_key, chapter.get("version")).is_empty():
		# Registry keys are "<id>@<version>"; the server sends them separately.
		chapter_key = RoomChapterTitle.key(chapter_key, chapter.get("version"))
	# A chapter this build does not know keeps a name made from its id.
	var unknown := chapter_key.trim_prefix(RoomChapterTitle.LEGACY_PREFIX).get_slice("@",0).replace("-"," ").capitalize() if not chapter_key.is_empty() else UNAVAILABLE_TITLE
	var title := RoomChapterTitle.title(chapter_key, unknown)
	var members: Array[String] = []
	for key: String in ["host_id","guest_id"]:
		var member: Variant = membership.get(key)
		if member is String and not member.is_empty(): members.append(member)
	var timestamp := 0
	var activity: Variant = value.get("activity_at")
	if activity is String and not activity.is_empty():
		timestamp = int(Time.get_unix_time_from_datetime_string(activity))
	return {
		"api_version":int(value.get("api_version",0)),
		"room_id":str(value.get("room_id","")),
		"chapter_key":chapter_key if not chapter_key.is_empty() else "unknown",
		"chapter_title":title,
		"member_ids":members,
		"status":str(value.get("status","unavailable")),
		"revision":int(value.get("revision",0)) if value.get("revision") != null else 0,
		"remote_activity_sequence":int(value.get("remote_activity_sequence",0)),
		"activity_at":timestamp,
		"family":str(value.get("family","unknown")),
	}.merged({"partner_left":true} if value.get("partner_left") == true else {})

static func room_key(api_version: int, room_id: String) -> String:
	return str(api_version) + ":" + room_id

static func is_unread(room: Dictionary, seen: Dictionary) -> bool:
	var key := room_key(int(room.get("api_version",0)),str(room.get("room_id","")))
	return int(room.get("remote_activity_sequence",0)) > int(seen.get(key,room.get("remote_activity_sequence",0)))

static func ordered(rooms: Array, seen: Dictionary, current_player: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in rooms:
		if value is Dictionary: result.append(value.duplicate(true))
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var au := is_unread(a,seen)
		var bu := is_unread(b,seen)
		if au != bu: return au
		var at := int(a.get("activity_at",0))
		var bt := int(b.get("activity_at",0))
		if at != bt: return at > bt
		return str(a.get("room_id","")) < str(b.get("room_id","")))
	return result

static func valid_page(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not Typed.equal(value.get("schema_version"), 1) or not value.get("rooms") is Array or value.rooms.size() > 100: return false
	var keys := {}
	for item: Variant in value.rooms:
		if not valid_server_room(item) and not valid_room(item): return false
		var key := room_key(int(item.api_version),str(item.room_id))
		if keys.has(key): return false
		keys[key] = true
	return true

static func valid_server_room(value: Variant) -> bool:
	# partner_left (true only) comes only to clients that send X-AfterYou-Room-Leave.
	if not value is Dictionary or value.size() != (10 if value.has("partner_left") else 9) or value.get("partner_left",true) != true: return false
	if not value.get("room_id") is String or not Presence.valid_id(value.room_id): return false
	if value.get("family") not in ["legacy","relay","story","unknown"]: return false
	var version: Variant = value.get("api_version")
	if not (version is int or version is float) or version < 0 or version > 4: return false
	if not value.get("chapter") is Dictionary or value.chapter.size() != 2: return false
	if value.chapter.get("id") != null and (not value.chapter.id is String or value.chapter.id.length() > 80): return false
	if value.chapter.get("version") != null and (not _nonnegative_integer(value.chapter.version)): return false
	if not value.get("membership") is Dictionary or value.membership.size() != 3: return false
	var membership: Dictionary = value.membership
	for field: String in ["host_id","guest_id"]:
		if membership.get(field) != null and (not membership[field] is String or not Presence.valid_id(membership[field])): return false
	if not membership.get("you_are_host") is bool: return false
	if membership.host_id == null and membership.guest_id == null and value.status not in ["unavailable","closed"]: return false
	if value.get("status") not in ["waiting_for_friend","your_turn","waiting_for_their_turn","completed","unavailable","closed"]: return false
	if value.get("revision") != null and not _nonnegative_integer(value.revision): return false
	if not _nonnegative_integer(value.get("remote_activity_sequence")): return false
	if value.get("activity_at") != null and (not value.activity_at is String or value.activity_at.length() > 40): return false
	return true

static func _nonnegative_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value == floor(value)

static func valid_room(value: Variant) -> bool:
	if not value is Dictionary or value.size() not in ([10,11] if value.has("partner_left") else [9,10]) or value.get("partner_left",true) != true: return false
	if not value.get("api_version") is int and not value.get("api_version") is float: return false
	if value.api_version not in [1,2] or not Presence.valid_id(value.get("room_id")): return false
	if not value.get("chapter_key") is String or value.chapter_key.is_empty() or value.chapter_key.length() > 80: return false
	if not value.get("chapter_title") is String or value.chapter_title.length() > 100: return false
	if not value.get("member_ids") is Array or value.member_ids.size() > 2: return false
	var members := {}
	for member: Variant in value.member_ids:
		if not Presence.valid_id(member) or members.has(member): return false
		members[member] = true
	if value.get("status") not in ["waiting_for_friend","your_turn","waiting_for_their_turn","completed","unavailable","closed"]: return false
	for field: String in ["revision","remote_activity_sequence","activity_at"]:
		var number: Variant = value.get(field)
		if not (number is int or number is float) or not is_finite(number) or number < 0 or number != floor(number): return false
	if value.has("family") and value.family not in ["legacy","relay","story","unknown"]: return false
	return true
