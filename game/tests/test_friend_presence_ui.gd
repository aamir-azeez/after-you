extends "res://tests/test_chapter_exit.gd"
const Presence = preload("res://services/friend_presence.gd")
const PresenceTests = preload("res://tests/test_friend_presence.gd")

func _run() -> void:
	for key: String in Registry.keys():
		_load_chapter(key)
		await _room_ui(key)
	await _singleton_ownership()
	for path: String in cleanup_paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	await create_timer(0.15).timeout
	print("FRIEND PRESENCE UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _room_ui(key: String) -> void:
	var scene := await _open_case(key)
	var app: Node = scene.app
	app._leave_online_relay()
	await process_frame
	var service := Presence.new()
	var presence_api := PresenceTests.Api.new()
	var clock := PresenceTests.Clock.new()
	service.api = presence_api
	service.clock_ms = clock.read
	root.add_child(service)
	service.set_process(false)
	app.friend_presence = service
	app.api.base_url = "https://presence.invalid"
	app._enter_online_relay()
	var preview: Node = app.relay_child
	preview.set_process(false)
	preview.set_physics_process(false)
	await process_frame
	var badge: Label = preview.overlay.find_child("FriendPresence", true, false)
	_check(badge != null and badge.text.contains("Checking friend status"), "Actual chapter ready card shows a text status before network reply: " + key)
	var saved_before := Canonical.digest(scene.store.values)
	var requests_before: int = scene.api.calls.size()
	# A busy gameplay connection cannot hold the independent presence transport.
	scene.api.busy = true
	await service.service()
	await service.service()
	scene.api.busy = false
	_check(badge != null and badge.text == "● Friend online", "A fresh partner result updates the actual chapter card: " + key)
	_check(presence_api != scene.api and scene.api.calls.size() == requests_before and Canonical.digest(scene.store.values) == saved_before, "Presence never uses gameplay HTTP or changes a room journal: " + key)
	preview._begin()
	await process_frame
	var badge_rect: Rect2 = preview.presence_hud.get_global_rect()
	_check(preview.controls.ui.get_global_rect().encloses(badge_rect), "The room status stays inside the gameplay safe area: " + key)
	for control: Control in [preview.controls.pause_button, preview.controls.progress_label, preview.controls.turn_progress, preview.chapter_label, preview.stick, preview.action_button, preview.finish_button]:
		_check(not badge_rect.intersects(control.get_global_rect()), "The room status leaves gameplay controls and progress unobstructed: " + key)
	preview.advance_input({"move_x": 0, "move_z": 0, "interact": false})
	var tick: int = preview.sim.tick
	var hash_before: String = preview.sim.state_hash()
	var draft_before: Dictionary = preview.journey.draft()
	clock.now += 30000
	presence_api.response = {"ok": false, "status": 503}
	await service.service()
	await service.service()
	_check(preview.presence_hud.text.contains("status unavailable") and preview.running and preview.sim.tick == tick and preview.sim.state_hash() == hash_before and Canonical.same(preview.journey.draft(), draft_before), "A status failure only changes HUD text, never the live turn: " + key)
	preview._pause()
	preview._leave()
	_check(service._room.is_empty(), "Returning from a chapter clears its room lookup immediately: " + key)
	await process_frame
	app.active_room = {"schema_version": 1, "room_id": "L".repeat(22), "revision": 1, "level_index": 0, "level_id": "first-light", "host_id": HOST, "guest_id": GUEST, "first_player_id": HOST, "active_role": "a", "attempt": 0, "recordings": {"a": null, "b": null}, "completed_islands": [], "reactions": {}}
	app._show_room_detail()
	presence_api.response = {"ok": true, "data": {"schema_version": 1, "partner_joined": false, "partner_online": false, "expires_after_seconds": 0}}
	await service.service()
	badge = app.overlay.find_child("FriendPresence", true, false)
	_check(badge != null and badge.text == "○ Waiting for friend" and presence_api.calls.back().path.begins_with("/v1/rooms/"), "Earlier-island room UI uses the legacy presence route and waiting label: " + key)
	app._show_settings()
	var toggle: CheckButton
	for candidate: Node in app.overlay.find_children("*", "CheckButton", true, false):
		if candidate.text == "Share online status": toggle = candidate
	_check(toggle != null and toggle.button_pressed, "Existing/default settings expose sharing as enabled: " + key)
	if toggle != null: toggle.button_pressed = false
	var reloaded := Save.new(app.saves.path)
	reloaded.load_data()
	_check(not service.enabled and reloaded.data.settings.share_online_status == false, "Opt-out updates the service and survives a fresh save read: " + key)
	var before_offline := presence_api.calls.size()
	await service.service()
	_check(presence_api.calls.size() == before_offline + 1 and not presence_api.calls.back().body.online, "Settings opt-out sends only its lease's offline request: " + key)
	app._invalidate_relay_identity()
	_check(service._identity_key.is_empty() and service.view("v1", "L".repeat(22)).state == "checking", "Real identity invalidation clears cached presence immediately: " + key)
	app.identity_loading = true
	app._sync_presence()
	var before_missing := presence_api.calls.size()
	clock.now += 120000
	await service.service()
	_check(presence_api.calls.size() == before_missing, "An unreadable/loading identity cannot republish a cached credential: " + key)
	app.identity_loading = false
	app.api.player_id = "N".repeat(22)
	app.api.device_token = "new-synthetic-credential"
	app._sync_presence()
	_check(service._identity.player_id == "N".repeat(22) and not service.enabled, "A loaded replacement identity keeps the persisted opt-out: " + key)
	scene.viewport.queue_free()
	await process_frame
	_check(is_instance_valid(service) and service.is_inside_tree() and service._room.is_empty(), "Leaving the scene retains global presence but clears room selection: " + key)
	var weak_api: WeakRef = weakref(presence_api)
	service.queue_free()
	await process_frame
	_check(weak_api.get_ref() == null, "Explicit fixture shutdown frees the separate transport: " + key)

func _singleton_ownership() -> void:
	var first := Presence.shared(self)
	var second := Presence.shared(self)
	_check(first == second, "Two callers before deferred attachment still share one root owner")
	await process_frame
	_check(first.get_parent() == root and first.api != null and first._identity.is_empty(), "Singleton owns its transport and begins without another fixture's credentials")
	first.queue_free()
	await process_frame
	_check(not root.has_meta(Presence.SINGLETON_NAME) and root.get_node_or_null(Presence.SINGLETON_NAME) == null, "Shutdown removes root ownership metadata as well as the node")
