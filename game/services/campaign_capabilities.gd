extends RefCounted
const Protocol = preload("res://services/campaign_protocol.gd")
const Lobby = preload("res://services/campaign_lobby_protocol.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")

static func read(value: Variant, definitions: Array) -> Dictionary:
	var held := {"valid":false,"creation":false,"mutations":false,"lobby_retry":false,"definitions":[]}
	if not Protocol.bounded(value,65536,8192,14) or not Registry.supported_capabilities(value).valid: return held
	if value.get("campaign_control_version") != 2 or not value.get("campaign_creation_enabled") is bool or not value.get("campaign_mutations_enabled") is bool or not value.get("campaign_definitions") is Array or value.campaign_definitions.size() > 1: return held
	var admitted: Array = []
	for definition: Variant in value.campaign_definitions:
		if not Protocol.definition_valid(definition): return held
		var local := Lobby.definition_for(Protocol.key(definition),definitions)
		if local.is_empty() or not Canonical.same(local,definition): return held
		admitted.append(local)
	return {"valid":true,"creation":value.mutations_enabled and value.campaign_creation_enabled,"mutations":value.mutations_enabled and value.campaign_mutations_enabled,"lobby_retry":value.mutations_enabled,"definitions":admitted}

static func supports_redo(value: Variant, definitions: Array) -> bool:
	return read(value,definitions).valid and Protocol.integer(value.get("campaign_redo_version"),1,1)
