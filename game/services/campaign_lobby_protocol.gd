extends RefCounted
## Lobby requests and bounded control lists share the immutable campaign pins.
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const MAX_LIST_BYTES := 327680
const MAX_LIST_NODES := 41000
const MAX_LIST_DEPTH := 14
const MAX_ROOMS := 20

static func create_body(definition: Dictionary, idempotency_key: String) -> Dictionary:
	if not Protocol.definition_valid(definition) or not Protocol.matches(idempotency_key,"^[A-Za-z0-9_-]{16,80}$"): return {}
	return {"schema_version":1,"idempotency_key":idempotency_key,"campaign_key":Protocol.key(definition)}

static func create_valid(value: Variant, definition: Dictionary) -> bool:
	if not Protocol.bounded(value,Protocol.MAX_REQUEST_BYTES) or not Protocol.exact(value,["schema_version","idempotency_key","campaign_key"]): return false
	return value.schema_version == 1 and Protocol.definition_valid(definition) and Protocol.matches(value.idempotency_key,"^[A-Za-z0-9_-]{16,80}$") and Canonical.same(value.campaign_key,Protocol.key(definition))

static func join_body(definition: Dictionary, invite_code: String) -> Dictionary:
	if not Protocol.definition_valid(definition): return {}
	var normalized := invite_code.strip_edges().replace(" ","").replace("-","").to_upper()
	if not Protocol.matches(normalized,"^[A-F0-9]{20}$"): return {}
	var versions: Array = []
	for chapter: Dictionary in definition.chapters:
		if int(chapter.simulation_version) not in versions: versions.append(int(chapter.simulation_version))
	versions.sort()
	return {"schema_version":1,"invite_code":normalized,"campaign_key":Protocol.key(definition),"supported_simulation_versions":versions}

static func join_valid(value: Variant, definition: Dictionary) -> bool:
	if not Protocol.bounded(value,Protocol.MAX_REQUEST_BYTES) or not Protocol.exact(value,["schema_version","invite_code","campaign_key","supported_simulation_versions"]): return false
	if value.schema_version != 1 or not Protocol.definition_valid(definition) or not Canonical.same(value.campaign_key,Protocol.key(definition)) or not Protocol.matches(value.invite_code,"^[A-F0-9]{20}$"): return false
	var versions: Variant = value.supported_simulation_versions
	if not versions is Array or versions.is_empty() or versions.size() > 8: return false
	var seen := {}
	for version: Variant in versions:
		if not Protocol.integer(version,1) or seen.has(int(version)): return false
		seen[int(version)] = true
	for chapter: Dictionary in definition.chapters:
		if not seen.has(int(chapter.simulation_version)): return false
	return true

static func envelope_valid(value: Variant, definition: Dictionary, owner: String, anchor: String = "") -> bool:
	return Protocol.bounded(value) and Protocol.exact(value,["campaign"]) and Protocol.view_valid(value.campaign,definition,owner) and (anchor.is_empty() or value.campaign.campaign_room_id == anchor)

static func list_valid(value: Variant, definitions: Array, owner: String) -> bool:
	if not Protocol.id_valid(owner) or not Protocol.bounded(value,MAX_LIST_BYTES,MAX_LIST_NODES,MAX_LIST_DEPTH) or not Protocol.exact(value,["campaigns"]) or not value.campaigns is Array or value.campaigns.size() > MAX_ROOMS: return false
	var catalog := _catalog(definitions)
	if catalog.is_empty() and not definitions.is_empty(): return false
	var anchors := {}
	for entry: Variant in value.campaigns:
		if not entry is Dictionary or not Protocol.key_valid(entry.get("campaign_key")): return false
		var definition: Dictionary = catalog.get(Canonical.digest(entry.campaign_key),{})
		if definition.is_empty() or not Protocol.view_valid(entry,definition,owner) or anchors.has(entry.campaign_room_id): return false
		anchors[entry.campaign_room_id] = true
	return true

static func definition_for(value: Variant, definitions: Array) -> Dictionary:
	if not Protocol.key_valid(value): return {}
	return _catalog(definitions).get(Canonical.digest(value),{}).duplicate(true)

static func request_hash(owner: String, path: String, body: Dictionary) -> String:
	if not Protocol.id_valid(owner) or path not in ["/v2/campaigns","/v2/campaigns/join"]: return ""
	return Canonical.digest({"owner_player_id":owner,"path":path,"body":body})

static func pending_valid(value: Variant, definitions: Array, owner: String) -> bool:
	if not Protocol.bounded(value,Protocol.MAX_REQUEST_BYTES) or not Protocol.exact(value,["path","body","request_hash"]) or not value.body is Dictionary: return false
	var definition := definition_for(value.body.get("campaign_key"),definitions)
	if definition.is_empty(): return false
	if value.path == "/v2/campaigns":
		if not create_valid(value.body,definition): return false
	elif value.path == "/v2/campaigns/join":
		if not join_valid(value.body,definition): return false
	else: return false
	return Protocol.hash_valid(value.request_hash) and value.request_hash == request_hash(owner,value.path,value.body)

static func _catalog(definitions: Array) -> Dictionary:
	var result := {}
	if definitions.size() > 128: return result
	for definition: Variant in definitions:
		if not Protocol.definition_valid(definition): return {}
		var pin := Canonical.digest(Protocol.key(definition))
		if result.has(pin): return {}
		result[pin] = definition
	return result
