extends RefCounted
## Called after local cleanup, before forgetting the old device credential.
const Photos = preload("res://services/deleted_identity_photo_cleanup.gd")
const KEY := "deleted_identity_server_ack"

static func valid_marker(value: Variant, owner: String) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("schema_version") == 1 and value.get("owner") == owner and Photos.valid_owner(owner) and value.get("acknowledged") is bool

static func permitted(save: RefCounted, owner: String) -> bool:
	return Photos.valid_owner(owner) and (not save.data.has(KEY) or valid_marker(save.data[KEY], owner))

static func finish(api: Node, save: RefCounted, owner: String) -> Dictionary:
	if not permitted(save, owner) or Photos.marker_owner(save.data.get(Photos.MARKER_KEY)) != owner:
		return {"ok": false, "error": "invalid_cleanup_marker"}
	if save.data.has(KEY) and save.data[KEY].acknowledged: return {"ok": true}
	if api == null or api.player_id != owner or api.device_token.is_empty() or api.busy:
		return {"ok": false, "error": "cleanup_auth_unavailable"}
	# This durable marker means local erasure completed, not server ACK. A lost
	# reply retries only the harmless authenticated ACK, never identity creation.
	if not save.update_values({KEY: {"schema_version": 1, "owner": owner, "acknowledged": false}}):
		return {"ok": false, "error": "cleanup_marker_unwritable"}
	var credential_hash: String = api.device_token.sha256_text()
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST, "/v1/identity/deletion-ack", {"schema_version": 1})
	var data: Variant = response.get("data")
	if api.player_id != owner or api.device_token.sha256_text() != credential_hash or not response.get("ok", false) or not data is Dictionary or data.size() != 2 or data.get("schema_version") != 1 or not data.get("acknowledged") is bool or not data.acknowledged:
		return {"ok": false, "error": "cleanup_ack_unconfirmed"}
	if not permitted(save, owner) or Photos.marker_owner(save.data.get(Photos.MARKER_KEY)) != owner or not save.update_values({KEY: {"schema_version": 1, "owner": owner, "acknowledged": true}}):
		return {"ok": false, "error": "cleanup_ack_unwritable"}
	return {"ok": true}
