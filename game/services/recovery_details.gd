class_name RecoveryDetails
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Save = preload("res://services/local_save.gd")
## Parses the complete copied recovery block locally. Never log input or results.

const MAX_TEXT_LENGTH := 2048
const BLOCK_PATTERN := PlayerCopy.RECOVERY_DETAILS_CE7907464194
const ID_PATTERN := "^[A-Za-z0-9_-]{22}$"
const SECRET_PATTERN := "^[A-Za-z0-9_-]{43}$"
const KEY_PATTERN := "^[A-Za-z0-9_-]{16,80}$"


static func parse(text: String) -> Dictionary:
	if text.is_empty() or text.length() > MAX_TEXT_LENGTH:
		return {}
	# Anchoring the entire block rejects duplicate labels and extra content instead
	# of silently choosing which identity or recovery code the player intended.
	var expression := RegEx.new()
	if expression.compile(BLOCK_PATTERN) != OK:
		return {}
	var matched := expression.search(text)
	if matched == null:
		return {}
	return {"player_id": matched.get_string(1), "recovery_code": matched.get_string(2)}


## A new device token or recovery code, in the backend's 43-character format.
static func new_secret() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32)).replace("+","-").replace("/","_").trim_suffix("=")


static func field_matches(value: Variant, pattern: String) -> bool:
	return value is String and RegEx.create_from_string(pattern).search(value)!=null


## A secured rotation proposal in the exact field formats the backend accepts.
static func valid_pending(value: Variant) -> bool:
	if not value is Dictionary or not Save.equal(value.get("schema_version"), 1) or not value.get("request") is Dictionary:
		return false
	var request: Dictionary=value.request
	if request.size()!=5:
		return false
	return field_matches(request.get("player_id"),ID_PATTERN) and field_matches(request.get("recovery_code"),SECRET_PATTERN) and field_matches(request.get("idempotency_key"),KEY_PATTERN) and field_matches(request.get("next_device_token"),SECRET_PATTERN) and field_matches(request.get("next_recovery_code"),SECRET_PATTERN) and request.next_device_token!=request.next_recovery_code and request.next_device_token!=request.recovery_code and request.next_recovery_code!=request.recovery_code
