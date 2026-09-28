extends SceneTree
const Lobby = preload("res://services/campaign_lobby_protocol.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
var fixture: Dictionary
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v2.json"))
	_requests()
	_envelopes()
	_lists()
	_pending()
	print("Campaign lobby protocol: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _requests() -> void:
	var body := Lobby.create_body(fixture.definition,"saved-create-key-1")
	_check(Lobby.create_valid(body,fixture.definition),"Creation sends an exact immutable campaign pin and a retained key")
	for key: String in ["short","a".repeat(81),"with.invalid.key"]:
		_check(Lobby.create_body(fixture.definition,key).is_empty(),"Invalid idempotency keys never form a request")
	for mode: String in ["extra","schema","pin","type"]:
		var altered := body.duplicate(true)
		match mode:
			"extra": altered["unexpected"] = true
			"schema": altered.schema_version = 2
			"pin": altered.campaign_key.definition_hash = "f".repeat(64)
			"type": altered.idempotency_key = 22
		_check(not Lobby.create_valid(altered,fixture.definition),"Creation rejects "+mode+" drift")
	var join := Lobby.join_body(fixture.definition," ab-ab-ab-ab-ab-ab-ab-ab-ab-ab ","saved-join-key-0001")
	_check(Lobby.join_valid(join,fixture.definition) and join.invite_code == "AB".repeat(10),"Join normalizes the explicit invitation and carries its exact story pin")
	_check(join.supported_simulation_versions == [6],"Join derives distinct bundled simulation support from the selected story")
	_check(join.schema_version == 2 and join.idempotency_key == "saved-join-key-0001","Join2 preserves its explicit attempt identity")
	for mode: String in ["legacy","missing_key","changed_key","extra"]:
		var altered := join.duplicate(true)
		match mode:
			"legacy":
				altered.schema_version = 1
				altered.erase("idempotency_key")
			"missing_key": altered.erase("idempotency_key")
			"changed_key": altered.idempotency_key = "short"
			"extra": altered["unexpected"] = true
		_check(not Lobby.join_valid(altered,fixture.definition),"Join rejects "+mode+" without synthesizing identity")
	for key: String in ["short","a".repeat(81),"with.invalid.key"]:
		_check(Lobby.join_body(fixture.definition,"AB".repeat(10),key).is_empty(),"Invalid Join attempt keys never form a request")
	var descriptor := Registry.descriptor(Registry.CONSERVATORY)
	var pin := {}
	for field: String in ["level_id","level_version","definition_hash","simulation_version","premium"]: pin[field] = descriptor[field]
	# Historical pins remain explicit when the registry's preferred rules change.
	for journey_rules: int in [7,8]:
		var mixed: Dictionary = fixture.definition.duplicate(true)
		var selected_pin: Dictionary = pin.duplicate(true)
		selected_pin.simulation_version = journey_rules
		mixed.chapters.append(selected_pin)
		mixed.erase("definition_hash")
		mixed["definition_hash"] = Canonical.digest(mixed)
		var mixed_join := Lobby.join_body(mixed,"AB".repeat(10),"saved-join-key-0001")
		_check(Lobby.join_valid(mixed_join,mixed) and mixed_join.supported_simulation_versions == [6,journey_rules],"Mixed stories advertise their exact retained or current Journey rules")
	var current: Dictionary = fixture.definition.duplicate(true)
	current.chapters.append(pin.duplicate(true))
	for chapter: Dictionary in current.chapters: chapter.simulation_version = 8
	current.erase("definition_hash")
	current["definition_hash"] = Canonical.digest(current)
	var current_join := Lobby.join_body(current,"AB".repeat(10),"saved-join-key-0001")
	_check(Lobby.join_valid(current_join,current) and current_join.supported_simulation_versions == [8],"Current physical and Journey chapters negotiate one shared rules8 version")
	for versions: Array in [[],[6,6],[7],[0,6],[6.5],[1,2,3,4,5,6,7,8,9]]:
		var altered := join.duplicate(true)
		altered.supported_simulation_versions = versions
		_check(not Lobby.join_valid(altered,fixture.definition),"Unsupported or malformed simulation negotiation is rejected")
	_check(Lobby.join_body(fixture.definition,"invalid-invite","saved-join-key-0001").is_empty(),"Unknown invitation text never becomes a network request")
	var copied := Lobby.definition_for(Protocol.key(fixture.definition),[fixture.definition])
	copied.chapters.clear()
	_check(fixture.definition.chapters.size() == 2,"Resolved definitions are detached from the bundled catalog")

func _envelopes() -> void:
	var value := {"campaign":fixture.active_view.duplicate(true)}
	_check(Lobby.envelope_valid(value,fixture.definition,HOST,fixture.active_view.campaign_room_id),"Host response is exact and bound to the selected anchor")
	_check(not Lobby.envelope_valid(value,fixture.definition,HOST,"Z".repeat(22)),"A different anchor cannot satisfy a join or resume response")
	_check(not Lobby.envelope_valid(value,fixture.definition,GUEST),"Host-only invitation fields cannot be used as a guest projection")
	value.campaign.player_slot = "p1"
	value.campaign.invite_code = null
	value.campaign.invite_expires_at = null
	_check(Lobby.envelope_valid(value,fixture.definition,GUEST),"Guest responses need no purchase proof or host invitation secret")
	value["rooms"] = []
	_check(not Lobby.envelope_valid(value,fixture.definition,GUEST),"Unknown envelope extensions fail closed")

func _lists() -> void:
	var value := {"campaigns":[fixture.active_view.duplicate(true)]}
	var before := Canonical.digest(value)
	_check(Lobby.list_valid(value,[fixture.definition],HOST) and Canonical.digest(value) == before,"List validation leaves server bytes unchanged")
	_check(Lobby.list_valid({"campaigns":[]},[],HOST),"An empty bundled catalog can read an empty list")
	var full := {"campaigns":[]}
	for index in range(Lobby.MAX_ROOMS):
		var entry: Dictionary = fixture.active_view.duplicate(true)
		entry.invite_code = "%020d" % index
		entry.campaign_room_id = ("v2:"+entry.invite_code).sha256_text().substr(0,22)
		entry.chapters[0].room_id = entry.campaign_room_id
		full.campaigns.append(entry)
	_check(Lobby.list_valid(full,[fixture.definition],HOST),"All twenty distinct authenticated anchors fit the agreed bounded list")
	_check(not Lobby.list_valid(value,[],HOST),"An unknown immutable story cannot silently become a supported row")
	_check(not Lobby.list_valid(value,[fixture.definition,fixture.definition],HOST),"Duplicate catalog definitions are ambiguous and rejected")
	value.campaigns.append(fixture.active_view.duplicate(true))
	_check(not Lobby.list_valid(value,[fixture.definition],HOST),"Duplicate anchor rows cannot consume two lobby slots")
	value.campaigns = []
	for index in range(21): value.campaigns.append(fixture.active_view.duplicate(true))
	_check(not Lobby.list_valid(value,[fixture.definition],HOST),"Server lobby capacity remains twenty campaigns")
	_check(not Lobby.list_valid({"campaigns":[],"padding":"x".repeat(Lobby.MAX_LIST_BYTES)},[fixture.definition],HOST),"Oversized control data is rejected before ordinary row processing")
	var unsupported: Dictionary = fixture.active_view.duplicate(true)
	unsupported.schema_version = 1
	unsupported.erase("activation")
	_check(not Lobby.list_valid({"campaigns":[unsupported]},[fixture.definition],HOST),"Legacy missing activation data is never inferred as a safe new row")

func _pending() -> void:
	for path: String in ["/v2/campaigns","/v2/campaigns/join"]:
		var body := Lobby.create_body(fixture.definition,"retained-create-key") if path == "/v2/campaigns" else Lobby.join_body(fixture.definition,"AB".repeat(10),"saved-join-key-0001")
		var pending := {"path":path,"body":body,"request_hash":Lobby.request_hash(HOST,path,body)}
		_check(Lobby.pending_valid(pending,[fixture.definition],HOST),"A durable exact lobby request can be replayed under its original owner")
		_check(not Lobby.pending_valid(pending,[fixture.definition],GUEST),"A restored request cannot transfer to another identity")
		var tampered := pending.duplicate(true)
		tampered.body.campaign_key.campaign_version += 1
		_check(not Lobby.pending_valid(tampered,[fixture.definition],HOST),"A request pin change invalidates the saved intent")
		pending.path = "/v2/rooms"
		_check(not Lobby.pending_valid(pending,[fixture.definition],HOST),"Story recovery cannot call the ordinary room endpoint")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
