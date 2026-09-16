extends SceneTree
const Client = preload("res://services/safety_client.gd")
const Store = preload("res://services/safety_store.gd")
const Save = preload("res://services/local_save.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const PEER := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const TARGET := {"room_family": "relay", "room_id": ROOM, "peer_id": PEER}

class Identity:
	extends RefCounted
	var player := OWNER
	var ready := true
	var epoch := 1
	func current() -> Dictionary: return {"ready": ready, "player_id": player, "epoch": epoch}

class Server:
	extends Node
	signal release
	var player_id := OWNER
	var device_token := "synthetic-device-token"
	var base_url := "https://example.invalid"
	var busy := false
	var accepted := false
	var blocked: Array = []
	var receipts: Dictionary = {}
	var calls: Array = []
	var drop := false
	var corrupt := false
	var wrong_peer := false
	var hold_path := ""
	var waiting := false
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if busy: return {"ok": false, "code": "request_busy"}
		busy = true
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		var data: Dictionary = {}
		if path == "/v1/safety/config":
			data = {"schema_version": 2 if corrupt else 1, "enforced": true, "terms_version": Client.TERMS_VERSION, "privacy_path": "/privacy", "deletion_path": "/account-deletion", "rules_path": "/community-rules"}
		elif path == "/v1/safety/terms":
			if method == HTTPClient.METHOD_POST: accepted = true
			data = {"schema_version": 1, "terms_version": Client.TERMS_VERSION, "accepted": accepted, "accepted_at": "2026-09-16T00:00:00.000Z" if accepted else null}
		elif path == "/v1/safety/blocks": data = {"schema_version": 1, "blocked_players": blocked.duplicate()}
		elif path == "/v1/safety/block":
			if PEER not in blocked: blocked.append(PEER)
			data = {"schema_version": 1, "blocked": true, "player_id": ROOM if wrong_peer else PEER}
		elif path.begins_with("/v1/safety/blocks/") and method == HTTPClient.METHOD_DELETE:
			var player := path.get_file()
			blocked.erase(player)
			data = {"schema_version": 1, "blocked": false, "player_id": player}
		elif path == "/v1/safety/report":
			var material := body.duplicate(true)
			material.merge({"operation": "safety_report", "reporter_id": player_id})
			data = {"schema_version": 1, "received": true, "report_id": (player_id + ":" + str(body.idempotency_key)).sha256_text(), "request_hash": Canonical.digest(material)}
			if receipts.has(body.idempotency_key) and not Canonical.same(receipts[body.idempotency_key], data):
				busy = false
				return {"ok": false, "status": 409, "code": "idempotency_key_reused"}
			receipts[body.idempotency_key] = data.duplicate(true)
		elif path.begins_with("/v1/safety/reports/"):
			data = receipts.get(path.get_file(), {}).duplicate(true)
		if corrupt and path.begins_with("/v1/safety/reports/"): data.report_id = "wrong".sha256_text()
		if path == hold_path:
			waiting = true
			await release
			waiting = false
		busy = false
		if drop and method == HTTPClient.METHOD_POST and path == "/v1/safety/report": return {"ok": false, "status": 0, "code": "connection_interrupted"}
		return {"ok": true, "status": 200, "data": data} if not data.is_empty() else {"ok": false, "status": 404, "code": "not_found"}

var checks := 0
var failures := 0
var _directory := ""

func _initialize() -> void: _run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(text)

func _run() -> void:
	_directory = "user://safety-tests-" + str(Time.get_ticks_usec())
	var identity := Identity.new()
	var server := Server.new()
	root.add_child(server)
	var store := Store.new(_directory)
	var client := Client.new(server, identity.current, store)
	check(await client.check_terms() and not client.terms_accepted, "fresh terms read cannot imply consent")
	check(server.calls.size() == 2 and server.calls.all(func(call: Dictionary) -> bool: return call.method == HTTPClient.METHOD_GET), "initial discovery only GETs")
	check(await client.accept_rules() and client.terms_accepted, "explicit acceptance acknowledged")
	check(server.calls[-1].body == {"schema_version": 1, "terms_version": Client.TERMS_VERSION}, "acceptance body has exact version only")
	check(await client.check_terms() and client.terms_accepted, "subsequent read uses server acceptance")
	server.corrupt = true
	check(not await client.check_terms() and not client.terms_accepted and client.config.is_empty(), "future config revokes in-memory eligibility")
	var before := server.calls.size()
	check(not await client.accept_rules() and server.calls.size() == before, "unsupported config cannot POST acceptance")
	server.corrupt = false
	check(client.public_url("/privacy") == "https://example.invalid/privacy" and client.public_url("https://untrusted.invalid").is_empty(), "public links limited to fixed paths")
	server.wrong_peer = true
	check(not await client.block(TARGET), "wrong derived block peer rejected")
	check(store.partner_allowed(OWNER, "relay", ROOM, PEER), "mismatched response cannot hide unrelated peer")
	server.wrong_peer = false
	check(await client.block(TARGET), "authenticated exact peer block accepted")
	check(not store.partner_allowed(OWNER, "relay", ROOM, PEER), "confirmed block hides cached room partner")
	check(not Store.new(_directory).partner_allowed(OWNER, "relay", OWNER, PEER), "cold store also suppresses same blocked peer in another room")
	check(Store.new(_directory).partner_allowed(PEER, "relay", ROOM, OWNER), "local block state is owner scoped")
	check(await client.unblock(PEER), "explicit own unblock acknowledged")
	check(store.partner_allowed(OWNER, "relay", ROOM, PEER), "successful unblock clears process and disk suppression")
	var photo := {"turn_id": "t0-1-b", "photo_revision": 2, "sha256": "photo".sha256_text()}
	server.drop = true
	check(not await client.report(TARGET, "privacy", photo), "lost report reply remains unresolved")
	var pending: Dictionary = client.pending_report()
	check(Store.valid_report(pending) and Canonical.same(pending.photo, photo), "exact photo version and reason persisted before POST")
	var later_revision: Dictionary = pending.duplicate(true)
	later_revision.photo.photo_revision = 1000000
	check(Store.valid_report(later_revision), "report accepts the full photo revision range understood by the native client")
	later_revision.photo.photo_revision = 1.5
	check(not Store.valid_report(later_revision), "fractional photo revision cannot be reported")
	var posts := server.calls.filter(func(call: Dictionary) -> bool: return call.method == HTTPClient.METHOD_POST and call.path == "/v1/safety/report").size()
	client = Client.new(server, identity.current, Store.new(_directory))
	check(Canonical.same(client.pending_report(), pending), "cold reopen retains original report body and key")
	server.drop = false
	server.corrupt = true
	check(not await client.check_report() and Canonical.same(client.pending_report(), pending), "wrong report ID cannot clear pending")
	server.corrupt = false
	check(await client.check_report() and client.pending_report().is_empty(), "exact GET receipt settles lost acknowledgement")
	check(server.calls.filter(func(call: Dictionary) -> bool: return call.method == HTTPClient.METHOD_POST and call.path == "/v1/safety/report").size() == posts, "receipt check does not repeat report POST")
	server.drop = true
	check(not await client.report(TARGET, "harassment"), "user report supports photo null")
	pending = client.pending_report()
	check(pending.photo == null, "no fake photo attached to user report")
	server.drop = false
	check(await client.retry_report(), "explicit same report retry resolves")
	check(Canonical.same(server.calls[-1].body, pending), "retry preserves exact key and body")
	var invalid := photo.duplicate(true)
	invalid.extra = true
	before = server.calls.size()
	check(not await client.report(TARGET, "privacy", invalid) and server.calls.size() == before, "extra photo fields rejected before transport")
	var legacy := TARGET.duplicate(true)
	legacy.room_family = "legacy"
	check(not await client.report(legacy, "privacy", photo), "legacy report cannot attach nonexistent chapter photo")
	server.hold_path = "/v1/safety/report"
	var delayed := {"done": false, "ok": false}
	_delayed_report(client, delayed)
	for _index in range(20):
		if server.waiting: break
		await process_frame
	check(server.waiting and client.busy, "real deferred report owns request")
	var preserved: Dictionary = store.read(OWNER).value.pending.duplicate(true)
	identity.epoch += 1
	server.release.emit()
	await process_frame
	check(delayed.done and not delayed.ok, "old epoch report result rejected")
	check(Canonical.same(store.read(OWNER).value.pending, preserved), "old identity callback cannot clear durable pending")
	server.hold_path = ""
	client.invalidate()
	check(await client.check_report(), "current owner can independently reconcile old pending request")
	check(not Store.valid_report({"schema_version": 1, "idempotency_key": "a".repeat(20), "room_family": "relay", "room_id": ROOM, "reason": "other", "invented": null}), "missing explicit photo field rejected")
	check(await client.block(TARGET), "second block accepted")
	server.blocked.clear()
	check(await client.refresh_blocks() and store.partner_allowed(OWNER, "relay", ROOM, PEER), "fresh own block list removes outdated process suppression")
	var path := _directory.path_join(OWNER.sha256_text() + ".json")
	var save := Save.new(path)
	save.load_data()
	var future: Dictionary = store.read(OWNER).value.duplicate(true)
	future.schema_version = 2
	check(save.update_values({"safety": future}), "future-state negative fixture written")
	var bytes := FileAccess.get_file_as_bytes(path)
	before = server.calls.size()
	client.invalidate()
	check(not await client.check_terms() and server.calls.size() == before, "understandable future safety state held without network")
	check(FileAccess.get_file_as_bytes(path) == bytes, "future state bytes not migrated or overwritten")
	check(not store.partner_allowed(OWNER, "relay", ROOM, PEER), "unreadable safety state does not expose cached partner photos")
	check(store.erase(OWNER) and not FileAccess.file_exists(path), "explicit account cleanup removes only owner's safety generations")
	server.free()
	print("Safety client: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _delayed_report(client: RefCounted, result: Dictionary) -> void:
	result.ok = await client.report(TARGET, "other")
	result.done = true
