extends RefCounted
## Typed share codes ("<type>-<id>") and invite links. Server IDs and API bodies are
## unchanged: format() adds the prefix for display/copy/share, parse() accepts prefixed,
## legacy unprefixed and link input and returns the bare ID for API calls.
## Adding a type: add its constant to TYPES, an _id() branch and a wrong_type_message().
const PlayerCopy = preload("res://presentation/player_copy.gd")
const FRIEND := "friend"
const ROOM := "room"
## Detection order for unprefixed legacy input after the expected type.
const TYPES: Array[String] = [FRIEND, ROOM]
## Only these types are ever shared as invite links.
const LINK_TYPES: Array[String] = [FRIEND]
const LINK_BASE := "https://aamirazeez.com/after-you/link"
## Upper bound for any typed or linked input; also the input fields' max_length.
const MAX_INPUT := 256
const INVALID := "invalid"
const WRONG_TYPE := "wrong_type"
# The code sits in the fragment (or the ?c= fallback); the bare /after-you path never matches.
const LINK_PATTERN := "\\A(?i:https)://(?i:aamirazeez\\.com)/after-you/link/?(?:#|\\?c=)(?<type>[a-z]+)-(?<id>[A-Za-z0-9_-]{1,64})\\z"

## Canonical bare ID for a type, or "" when raw is not a valid ID of that type.
static func _id(type: String, raw: String) -> String:
	match type:
		FRIEND:
			return raw if _matches(raw, "\\A[A-Za-z0-9_-]{22}\\z") else ""
		ROOM:
			# Legacy invitation input tolerates spaces/hyphens and lower case.
			var code := raw.replace(" ", "").replace("-", "").to_upper()
			return code if _matches(code, "\\A[A-F0-9]{20}\\z") else ""
	return ""

## "<type>-<id>" for a canonical ID, else "".
static func format(type: String, id: Variant) -> String:
	if not id is String or id.is_empty() or type not in TYPES or _id(type, id) != id: return ""
	return type + "-" + id

## Display form: the typed code when the ID is canonical, otherwise the value unchanged.
static func display(type: String, id: Variant) -> String:
	var typed := format(type, id)
	return typed if not typed.is_empty() else str(id)

static func link(type: String, id: Variant) -> String:
	var typed := format(type, id)
	return LINK_BASE + "#" + typed if type in LINK_TYPES and not typed.is_empty() else ""

## {"ok":true,"type":t,"id":bare} or {"ok":false,"error":INVALID|WRONG_TYPE,"type":detected}.
static func parse(text: Variant, expected: String) -> Dictionary:
	if not text is String or expected not in TYPES: return _fail(INVALID, "")
	var value: String = text.strip_edges()
	if value.is_empty() or value.length() > MAX_INPUT: return _fail(INVALID, "")
	if value.contains("://"):
		var linked := parse_link(value)
		if not linked.ok: return linked
		return linked if linked.type == expected else _fail(WRONG_TYPE, linked.type)
	var lower := value.to_lower()
	var prefixed := ""
	for type: String in TYPES:
		if lower.begins_with(type + "-"):
			prefixed = type
			var id := _id(type, value.substr(type.length() + 1))
			if not id.is_empty(): return _ok(type, id) if type == expected else _fail(WRONG_TYPE, type)
			break
	# Legacy unprefixed input: the expected type first, then any other known type.
	var legacy := _id(expected, value)
	if not legacy.is_empty(): return _ok(expected, legacy)
	for type: String in TYPES:
		if type != expected and not _id(type, value).is_empty(): return _fail(WRONG_TYPE, type)
	return _fail(INVALID, prefixed)

## Strict invite-link parser for the native bridge and pasted input.
static func parse_link(text: Variant) -> Dictionary:
	if not text is String or text.is_empty() or text.length() > MAX_INPUT: return _fail(INVALID, "")
	var found := RegEx.create_from_string(LINK_PATTERN).search(text)
	if found == null: return _fail(INVALID, "")
	var type := found.get_string("type")
	var id := found.get_string("id")
	if type not in LINK_TYPES or _id(type, id) != id: return _fail(INVALID, type)
	return _ok(type, id)

static func wrong_type_message(found: String) -> String:
	match found:
		FRIEND: return PlayerCopy.SHARE_CODE_FRIEND_NOT_ROOM
		ROOM: return PlayerCopy.SHARE_CODE_ROOM_NOT_FRIEND
	return ""

## Player-facing error for a failed parse, or invalid_message when no type-specific text applies.
static func error_message(result: Dictionary, invalid_message: String) -> String:
	if result.get("error") == WRONG_TYPE:
		var text := wrong_type_message(str(result.get("type", "")))
		if not text.is_empty(): return text
	return invalid_message

static func _ok(type: String, id: String) -> Dictionary:
	return {"ok": true, "type": type, "id": id}

static func _fail(error: String, type: String) -> Dictionary:
	return {"ok": false, "error": error, "type": type}

static func _matches(value: String, pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(value) != null
