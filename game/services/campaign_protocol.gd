extends RefCounted
## Small campaign control references. Gameplay proofs stay in their own rooms.
## A valid hash is not admission: callers supply a locally bundled definition.
const Canonical = preload("res://core/v2/canonical.gd")
const Chapters = preload("res://services/chapter_registry.gd")
const MAX_CHAPTERS := 8
const MAX_CONTROL_BYTES := 16384
const MAX_REQUEST_BYTES := 4096
const MAX_NODES := 2048
const MAX_DEPTH := 12
const MAX_SAFE_INTEGER := 9007199254740991

static func definition_valid(value: Variant) -> bool:
	if not bounded(value) or not exact(value,["schema_version","campaign_id","campaign_version","chapters","story","definition_hash"]): return false
	if value.schema_version != 1 or not key_valid(key(value)) or not value.chapters is Array or value.chapters.size() < 2 or value.chapters.size() > MAX_CHAPTERS: return false
	if not exact(value.story,["story_id","story_version","content_hash"]) or not slug(value.story.story_id) or not integer(value.story.story_version,1) or not hash_valid(value.story.content_hash): return false
	for pin: Variant in value.chapters:
		if not pin_valid(pin): return false
	var body: Dictionary = value.duplicate(true)
	body.erase("definition_hash")
	return Canonical.digest(body) == value.definition_hash

static func key(definition: Dictionary) -> Dictionary:
	return {"campaign_id":definition.get("campaign_id"),"campaign_version":definition.get("campaign_version"),"definition_hash":definition.get("definition_hash")}

static func key_valid(value: Variant) -> bool:
	return exact(value,["campaign_id","campaign_version","definition_hash"]) and slug(value.campaign_id) and integer(value.campaign_version,1) and hash_valid(value.definition_hash)

static func pin_valid(value: Variant) -> bool:
	if not exact(value,["level_id","level_version","definition_hash","simulation_version","premium"]) or not value.premium is bool: return false
	var chapter := Chapters.resolve(value)
	if chapter.is_empty(): return false
	var descriptor := Chapters.descriptor(chapter)
	return value.simulation_version == descriptor.simulation_version and integer(value.simulation_version,1) and value.premium == descriptor.premium

static func source_valid(value: Variant) -> bool:
	return exact(value,["room_id","revision","branch","checkpoint_hash"]) and id_valid(value.room_id) and integer(value.revision) and integer(value.branch,0,31) and hash_valid(value.checkpoint_hash)

static func origin_valid(value: Variant, count: int) -> bool:
	return exact(value,["expected_revision","from_index","source"]) and integer(value.expected_revision) and integer(value.from_index,0,count-1) and source_valid(value.source)

static func origin(body: Dictionary) -> Dictionary:
	return {"expected_revision":body.get("expected_revision"),"from_index":body.get("from_index"),"source":body.get("source")}

static func continuation_key(anchor: String, owner: String, campaign_key: Dictionary, request_origin: Dictionary) -> String:
	return Canonical.digest({"operation":"campaign_continue","schema_version":1,"campaign_room_id":anchor,"campaign_key":campaign_key,"player_id":owner,"origin":request_origin})

static func request_hash(anchor: String, owner: String, body: Dictionary) -> String:
	return Canonical.digest({"operation":"campaign_continue","campaign_room_id":anchor,"player_id":owner,"body":body})

static func continue_body(anchor: String, owner: String, definition: Dictionary, request_origin: Dictionary) -> Dictionary:
	if not id_valid(anchor) or not id_valid(owner) or not definition_valid(definition) or not origin_valid(request_origin,definition.chapters.size()): return {}
	var result := request_origin.duplicate(true)
	result.merge({"schema_version":1,"campaign_key":key(definition),"idempotency_key":continuation_key(anchor,owner,key(definition),request_origin)})
	return result

static func continue_valid(value: Variant, anchor: String, owner: String, definition: Dictionary) -> bool:
	if not bounded(value,MAX_REQUEST_BYTES) or not exact(value,["schema_version","idempotency_key","campaign_key","expected_revision","from_index","source"]): return false
	if not id_valid(anchor) or not id_valid(owner) or not definition_valid(definition) or value.schema_version != 1 or not Canonical.same(value.campaign_key,key(definition)) or not origin_valid(origin(value),definition.chapters.size()): return false
	return value.idempotency_key == continuation_key(anchor,owner,key(definition),origin(value))

static func view_valid(value: Variant, definition: Dictionary, owner: String) -> bool:
	if not bounded(value) or not definition_valid(definition) or not exact(value,["schema_version","api_version","campaign_room_id","campaign_key","revision","host_id","guest_id","player_slot","state","current_index","chapters","transition","activation","invite_code","invite_expires_at"]): return false
	if value.schema_version != 2 or value.api_version != 2 or not Canonical.same(value.campaign_key,key(definition)) or not id_valid(value.campaign_room_id) or not integer(value.revision): return false
	if not id_valid(owner) or not id_valid(value.host_id) or (value.guest_id != null and (not id_valid(value.guest_id) or value.guest_id == value.host_id)): return false
	if owner == value.host_id:
		if value.player_slot != "p0" or not matches(value.invite_code,"^[A-F0-9]{20}$") or not utc_valid(value.invite_expires_at): return false
		if ("v2:"+value.invite_code).sha256_text().substr(0,22) != value.campaign_room_id: return false
	elif owner == value.guest_id:
		if value.player_slot != "p1" or value.invite_code != null or value.invite_expires_at != null: return false
	else: return false
	if value.state not in ["waiting","active","continuing","complete","deleting"] or not integer(value.current_index,0,definition.chapters.size()-1): return false
	if not value.chapters is Array or value.chapters.size() != definition.chapters.size(): return false
	if value.guest_id == null and (value.state not in ["waiting","deleting"] or value.current_index != 0): return false
	if value.state == "waiting" and (value.guest_id != null or value.current_index != 0): return false
	if value.state == "complete" and value.current_index != definition.chapters.size()-1: return false
	var rooms := {}
	var transitions := {}
	var last_accepted := 0
	for index in range(value.chapters.size()):
		var entry: Variant = value.chapters[index]
		if not exact(entry,["chapter","room_id","completion"]) or not Canonical.same(entry.chapter,definition.chapters[index]): return false
		if index > value.current_index:
			if entry.room_id != null or entry.completion != null: return false
			continue
		if not id_valid(entry.room_id) or rooms.has(entry.room_id): return false
		rooms[entry.room_id] = true
		if index == 0 and entry.room_id != value.campaign_room_id: return false
		var terminal: bool = index == value.chapters.size()-1 and value.state in ["complete","deleting"] and entry.completion != null
		if index < value.current_index or terminal:
			if not completion_valid(entry.completion,value.revision) or entry.completion.from_campaign_revision < last_accepted or transitions.has(entry.completion.transition_id): return false
			last_accepted = int(entry.completion.accepted_campaign_revision)
			transitions[entry.completion.transition_id] = true
		elif entry.completion != null or value.state == "complete": return false
	if value.transition != null:
		if value.state not in ["continuing","deleting"] or value.guest_id == null or value.chapters[value.current_index].completion != null: return false
		var transition: Variant = value.transition
		if not exact(transition,["transition_id","phase","origin"]) or not hash_valid(transition.transition_id) or transitions.has(transition.transition_id) or transition.phase not in ["prepared","source_sealed","target_initialized"]: return false
		if transition.phase == "target_initialized" and value.current_index == definition.chapters.size()-1: return false
		if not origin_valid(transition.origin,definition.chapters.size()) or transition.origin.from_index != value.current_index or transition.origin.expected_revision >= value.revision or transition.origin.expected_revision < last_accepted: return false
		if transition.origin.source.room_id != value.chapters[value.current_index].room_id: return false
	elif value.state == "continuing": return false
	if value.activation != null:
		if not exact(value.activation,["transition_id"]) or not hash_valid(value.activation.transition_id): return false
		if value.state not in ["active","deleting"] or value.current_index == 0 or value.transition != null or value.chapters[value.current_index].completion != null: return false
		if value.activation.transition_id != value.chapters[value.current_index-1].completion.transition_id: return false
	return true

static func resume_activation_body(definition: Dictionary, transition_id: String) -> Dictionary:
	if not definition_valid(definition) or not hash_valid(transition_id): return {}
	return {"schema_version":1,"campaign_key":key(definition),"transition_id":transition_id}

static func resume_activation_valid(value: Variant, definition: Dictionary) -> bool:
	return bounded(value,MAX_REQUEST_BYTES) and definition_valid(definition) and exact(value,["schema_version","campaign_key","transition_id"]) and value.schema_version == 1 and Canonical.same(value.campaign_key,key(definition)) and hash_valid(value.transition_id)

static func completion_valid(value: Variant, revision: int) -> bool:
	return exact(value,["source_revision","source_branch","checkpoint_hash","transition_id","from_campaign_revision","accepted_campaign_revision"]) and integer(value.source_revision) and integer(value.source_branch,0,31) and hash_valid(value.checkpoint_hash) and hash_valid(value.transition_id) and integer(value.from_campaign_revision) and integer(value.accepted_campaign_revision,1,revision) and value.accepted_campaign_revision > value.from_campaign_revision

static func result_valid(value: Variant, body: Dictionary, anchor: String, owner: String, definition: Dictionary) -> bool:
	if not bounded(value) or not continue_valid(body,anchor,owner,definition) or not value is Dictionary or value.get("schema_version") != 1 or value.get("operation") != "campaign_continue": return false
	if not view_valid(value.get("campaign"),definition,owner) or value.campaign.campaign_room_id != anchor: return false
	var campaign: Dictionary = value.campaign
	if value.get("status") == "pending":
		if not exact(value,["schema_version","operation","status","player_id","idempotency_key","request_hash","transition_id","campaign"]): return false
		return value.player_id == owner and value.idempotency_key == body.idempotency_key and value.request_hash == request_hash(anchor,owner,body) and campaign.transition != null and value.transition_id == campaign.transition.transition_id and Canonical.same(campaign.transition.origin,origin(body))
	if value.get("status") == "rejected":
		if campaign.guest_id == null: return false
		if not exact(value,["schema_version","operation","status","receipt","campaign"]): return false
		var rejected: Variant = value.receipt
		if not exact(rejected,["schema_version","operation","campaign_room_id","campaign_key","player_id","idempotency_key","request_hash","origin","reason","closed_before_branch"]): return false
		if rejected.schema_version != 1 or rejected.operation != "campaign_continue" or rejected.reason != "source_forked" or rejected.campaign_room_id != anchor or not Canonical.same(rejected.campaign_key,key(definition)) or rejected.player_id != owner or rejected.idempotency_key != body.idempotency_key or rejected.request_hash != request_hash(anchor,owner,body) or not Canonical.same(rejected.origin,origin(body)): return false
		if not integer(rejected.closed_before_branch,1,31) or rejected.closed_before_branch != body.source.branch+1 or campaign.revision < body.expected_revision or campaign.current_index < body.from_index: return false
		var rejected_entry: Dictionary = campaign.chapters[int(body.from_index)]
		if rejected_entry.room_id != body.source.room_id: return false
		if rejected_entry.completion != null and (rejected_entry.completion.source_branch < rejected.closed_before_branch or rejected_entry.completion.source_revision <= body.source.revision): return false
		if campaign.transition != null and campaign.transition.origin.from_index == body.from_index and (campaign.transition.origin.source.branch < rejected.closed_before_branch or campaign.transition.origin.source.revision <= body.source.revision): return false
		return true
	if value.get("status") != "accepted" or not exact(value,["schema_version","operation","status","receipt","campaign"]): return false
	var receipt: Variant = value.receipt
	if not exact(receipt,["schema_version","operation","campaign_room_id","campaign_key","player_id","idempotency_key","request_hash","transition_id","origin","accepted_revision","outcome","next_index","next_room_id"]): return false
	if receipt.schema_version != 1 or receipt.operation != "campaign_continue" or receipt.campaign_room_id != anchor or not Canonical.same(receipt.campaign_key,key(definition)) or receipt.player_id != owner or receipt.idempotency_key != body.idempotency_key or receipt.request_hash != request_hash(anchor,owner,body) or not Canonical.same(receipt.origin,origin(body)): return false
	var entry: Dictionary = campaign.chapters[int(body.from_index)]
	var completion: Variant = entry.completion
	if completion == null or entry.room_id != body.source.room_id or receipt.transition_id != completion.transition_id or receipt.accepted_revision != completion.accepted_campaign_revision or body.expected_revision != completion.from_campaign_revision: return false
	if body.source.revision != completion.source_revision or body.source.branch != completion.source_branch or body.source.checkpoint_hash != completion.checkpoint_hash: return false
	if receipt.outcome == "advanced":
		return integer(receipt.next_index,1,definition.chapters.size()-1) and receipt.next_index == body.from_index+1 and receipt.next_room_id == campaign.chapters[int(receipt.next_index)].room_id
	return receipt.outcome == "finished" and body.from_index == definition.chapters.size()-1 and receipt.next_index == null and receipt.next_room_id == null and campaign.state in ["complete","deleting"]

static func exact(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for field: Variant in value:
		if field not in fields: return false
	return true

static func integer(value: Variant, minimum: int = 0, maximum: int = MAX_SAFE_INTEGER) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func matches(value: Variant, expression: String) -> bool:
	if not value is String: return false
	var pattern := RegEx.new()
	pattern.compile(expression)
	return pattern.search(value) != null

static func id_valid(value: Variant) -> bool: return matches(value,"^[A-Za-z0-9_-]{22}$")
static func hash_valid(value: Variant) -> bool: return matches(value,"^[a-f0-9]{64}$")
static func slug(value: Variant) -> bool: return matches(value,"^[a-z][a-z0-9-]{0,47}$")

static func utc_valid(value: Variant) -> bool:
	if not matches(value,"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"): return false
	var year := int(value.substr(0,4))
	var month := int(value.substr(5,2))
	var day := int(value.substr(8,2))
	if month < 1 or month > 12 or day < 1: return false
	var days := [31,29 if year%400 == 0 or (year%4 == 0 and year%100 != 0) else 28,31,30,31,30,31,31,30,31,30,31]
	return day <= days[month-1] and int(value.substr(11,2)) < 24 and int(value.substr(14,2)) < 60 and int(value.substr(17,2)) < 60

static func bounded(value: Variant, max_bytes: int = MAX_CONTROL_BYTES, max_nodes: int = MAX_NODES, max_depth: int = MAX_DEPTH) -> bool:
	var pending: Array = [{"value":value,"depth":0}]
	var nodes := 0
	while not pending.is_empty():
		var item: Dictionary = pending.pop_back()
		nodes += 1
		if nodes > max_nodes or item.depth > max_depth: return false
		var current: Variant = item.value
		if current is Dictionary:
			if nodes+pending.size()+current.size()*2 > max_nodes: return false
			for field: Variant in current:
				if not field is String: return false
				pending.append({"value":field,"depth":item.depth+1})
				pending.append({"value":current[field],"depth":item.depth+1})
		elif current is Array:
			if nodes+pending.size()+current.size() > max_nodes: return false
			for child: Variant in current: pending.append({"value":child,"depth":item.depth+1})
		elif current is String:
			if current.to_utf8_buffer().size() > max_bytes: return false
		elif current is int or current is float:
			if not integer(current,-MAX_SAFE_INTEGER): return false
		elif current != null and not current is bool: return false
	return JSON.stringify(value).to_utf8_buffer().size() <= max_bytes
