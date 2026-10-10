extends RefCounted
## Device-local phone consent, separate from gameplay settings and journals.
## Scope includes server, identity and credential hash; values bind consent to friendship tokens.
const PATH := "user://hosting_notification_preferences.cfg"
var path := PATH
var _preferences: Dictionary = {}

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	var config := ConfigFile.new()
	if config.load(path) == OK and config.get_value("hosting","schema_version",-1) == 1:
		var value: Variant = config.get_value("hosting","preferences",{})
		if valid(value): _preferences = value.duplicate(true)

func read() -> Dictionary:
	return _preferences.duplicate(true)

func save(value: Dictionary) -> bool:
	if not valid(value): return false
	var config := ConfigFile.new()
	config.set_value("hosting","schema_version",1)
	config.set_value("hosting","preferences",value)
	# Write replacement first so a failed write leaves the old consent file intact.
	var temporary := path + ".tmp"
	if config.save(temporary) != OK: return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path)) != OK: return false
	_preferences = value.duplicate(true)
	return true

func clear_owner(owner: String, server: String = "") -> bool:
	var next := read()
	for scope: String in next:
		var suffix := ":" + owner + ":"
		if suffix in scope and (server.is_empty() or scope.begins_with(server.trim_suffix("/") + suffix)): next.erase(scope)
	return save(next)

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 32: return false
	for scope: Variant in value:
		if not scope is String or scope.length() > 2048 or not value[scope] is Dictionary or value[scope].size() > 20: return false
		for peer: Variant in value[scope]:
			if not peer is String or RegEx.create_from_string("^[A-Za-z0-9_-]{22}$").search(peer) == null: return false
			var request: Variant = value[scope][peer]
			if not request is String or RegEx.create_from_string("^[A-Za-z0-9_-]{22}$").search(request) == null: return false
	return true
