extends SceneTree
## Campaign control reuses recoverable storage without touching room proofs.
const Store = preload("res://services/relay_online_store.gd")
const Cleanup = preload("res://services/deleted_identity_cache_cleanup.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const PEER := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
var directory := "user://campaign-store-" + Crypto.new().generate_random_bytes(8).hex_encode()
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_boundaries()
	_recovery()
	_owner_cleanup()
	print("CAMPAIGN STORE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(label)

func _path(root_path: String, scope: String) -> String:
	return root_path.path_join(scope.sha256_text()+".json")

func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value))
	file.close()

func _boundaries() -> void:
	var location := directory.path_join("bounds")
	var storage := Store.new(location)
	var scope := "relay-campaign-v1:"+OWNER+":"+ROOM
	var pending := {"schema_version":1,"pending":{"operation":"continue","key":"a".repeat(64)},"selected_room":ROOM}
	_check(storage.save_scope(scope,pending).ok,"Campaign intent persists through the existing atomic generation adapter")
	_check(Canonical.same(Store.new(location).load_scope(scope).value,pending),"Cold process reloads the same pending Continue and room selection")
	var before := FileAccess.get_file_as_bytes(_path(location,scope))
	_check(not storage.save_scope(scope,{"proof":"x".repeat(Store.CAMPAIGN_VALUE_BYTES)}).ok,"Campaign control cannot grow to recording-proof size")
	_check(FileAccess.get_file_as_bytes(_path(location,scope)) == before,"Rejected oversized write preserves the recoverable intent")
	var legacy := "relay-room-v2:"+OWNER+":"+ROOM
	_check(storage.save_scope(legacy,{"retained_proof":"x".repeat(Store.CAMPAIGN_MAX_BYTES)}).ok,"Existing room proofs retain their larger storage budget")
	for invalid: String in ["relay-campaign-v2:"+OWNER+":"+ROOM,"relay-campaign-v1:../private:"+ROOM,"relay-campaign-v1:"+OWNER,"relay-campaign-lobby-v1:"+OWNER+":"+ROOM]:
		_check(not storage.load_scope(invalid).ok and not storage.save_scope(invalid,{}).ok,"Unknown or malformed campaign scopes never map to a file")
	_write(_path(location,scope)," ".repeat(Store.CAMPAIGN_MAX_BYTES+1))
	var large := FileAccess.get_file_as_bytes(_path(location,scope))
	_check(not Store.new(location).load_scope(scope).ok,"Oversized disk control is held before JSON parsing")
	_check(FileAccess.get_file_as_bytes(_path(location,scope)) == large,"Oversized disk data is not repaired or replaced")

func _recovery() -> void:
	var location := directory.path_join("recovery")
	var scope := "relay-campaign-lobby-v1:"+OWNER
	var storage := Store.new(location)
	_check(storage.save_scope(scope,{"pending":"first"}).ok and storage.save_scope(scope,{"pending":"second"}).ok,"Lobby writes retain a prior recoverable generation")
	var path := _path(location,scope)
	_write(path,"{interrupted")
	var recovered := Store.new(location).load_scope(scope)
	_check(recovered.ok and recovered.value == {"pending":"first"},"Interrupted lobby primary recovers its own valid backup")
	var future: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path+".backup"))
	future.version = 9
	_write(path,future)
	var before := FileAccess.get_file_as_bytes(path)
	var cold := Store.new(location)
	_check(not cold.load_scope(scope).ok and not cold.save_scope(scope,{}).ok,"A readable future generation cannot be downgraded using the old backup")
	_check(FileAccess.get_file_as_bytes(path) == before,"Future campaign control stays byte-identical")
	var foreign := future.duplicate(true)
	foreign.version = 1
	foreign.relay_online_scope = "relay-campaign-lobby-v1:"+PEER
	_write(path,foreign)
	_check(not Store.new(location).load_scope(scope).ok,"A mismatched owner envelope cannot bind to this lobby")

func _owner_cleanup() -> void:
	var cleanup := Cleanup.new()
	cleanup.relay_directory = directory.path_join("erase/relay")
	cleanup.shared_directory = directory.path_join("erase/shared")
	cleanup.safety_directory = directory.path_join("erase/safety")
	var storage := Store.new(cleanup.relay_directory)
	var own: Array[String] = []
	var others := {}
	for owner: String in [OWNER,PEER]:
		for scope: String in ["relay-campaign-lobby-v1:"+owner,"relay-campaign-v1:"+owner+":"+ROOM,"relay-room-v2:"+owner+":"+ROOM]:
			_check(storage.save_scope(scope,{"pending":"first"}).ok and storage.save_scope(scope,{"pending":"second"}).ok,"Owner-scoped campaign and room generations exist")
			for suffix: String in ["",".backup"]:
				var path := _path(cleanup.relay_directory,scope)+suffix
				if owner == OWNER: own.append(path)
				else: others[path] = FileAccess.get_file_as_bytes(path)
	# A fully truncated known lobby is still attributable by its exact hashed
	# owner scope. A room requires its remaining readable ownership envelope.
	_write(own[0],"{interrupted")
	_write(own[1],"{interrupted")
	_write(own[2],"{interrupted")
	_check(cleanup.erase_owner(OWNER).ok,"Confirmed owner cleanup includes campaign journals and their interrupted generations")
	for path: String in own: _check(not FileAccess.file_exists(path),"Every owned campaign generation is removed")
	for path: String in others: _check(FileAccess.get_file_as_bytes(path) == others[path],"Partner history remains byte-identical after owner cleanup")
	_check(cleanup.erase_owner(OWNER).ok,"Retrying confirmed cleanup remains safe")
	var unknown := cleanup.relay_directory.path_join("unknown".sha256_text()+".json")
	_write(unknown,"{interrupted")
	_check(not cleanup.erase_owner(PEER).ok,"An unattributable corrupt journal holds cleanup before any deletion")
	for path: String in others: _check(FileAccess.get_file_as_bytes(path) == others[path],"Held cleanup preserves the partner's full recoverable history")
