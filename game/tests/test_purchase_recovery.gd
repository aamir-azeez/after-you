extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Purchases = preload("res://services/purchases.gd")
const OWNER := "PPPPPPPPPPPPPPPPPPPPPP"
const TOKEN := "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
var checks := 0
var failures := 0
var path := "user://purchase-recovery-%d.json" % Time.get_ticks_usec()

class Store extends Purchases:
	var configure_calls := 0
	var offer_calls := 0
	var refresh_calls := 0
	func _connect_native() -> bool: return true
	func configure_store(_key: String, _owner: String, _mode: String) -> String:
		configure_calls += 1
		return "setup-%d" % configure_calls
	func fetch_offerings() -> String:
		offer_calls += 1
		return "offer-%d" % offer_calls
	func refresh_customer_info() -> String:
		refresh_calls += 1
		return "refresh-%d" % refresh_calls

class Screen extends Main:
	var opened := ""
	func _tester_checks_enabled() -> bool: return false
	func _open_chapter_preview(scene: String) -> void: opened = scene

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var screen := Screen.new()
	screen.saves = Storage.new(path)
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	screen.world.set_process(false)
	screen.purchases.queue_free()
	var store := Store.new()
	screen.purchases = store
	screen.add_child(store)
	store.completed.connect(screen._purchase_completed)
	store.failed.connect(screen._purchase_failed)
	screen.config.revenuecat_public_key = "test_public_key"
	screen.config.purchase_mode = "test_store"
	screen.config.entitlement_id = "full_journey"
	store._configuration = {"purchase_mode":"test_store","entitlement_id":"full_journey"}
	screen.api.player_id = OWNER
	screen.api.device_token = TOKEN
	screen.identity_data = {"player_id":OWNER,"device_token":TOKEN}
	screen.identity_loading = false
	screen.identity_read_state = screen.IdentityReadState.LOADED
	store.customer_info = {"schema_version":1,"entitlements":{"full_journey":{"active":true}}}
	_check(store.has_entitlement(), "Fixture is an existing buyer with cached SDK information")
	screen._configure_purchases()
	var old_request: String = screen.store_configure_request
	store.failed.emit(old_request,"configure","network_error","Offline",false)
	_check(not screen.store_configured and screen.store_configure_request.is_empty(), "Failed offline setup settles without marking the store ready")
	screen._show_journey()
	screen._open_lighthouse_preview()
	_check(screen.mode == "paywall" and store.configure_calls == 2 and screen.opened.is_empty(), "Cached buyer can retry setup from Lighthouse without restarting or bypassing admission")
	await screen._resume_purchase_access()
	screen._load_store()
	_check(store.configure_calls == 2, "Foreground and repeated retry coalesce while configuration is pending")
	store.completed.emit(old_request,"configure",store.customer_info)
	_check(not screen.store_configured, "An expired earlier configure response cannot complete the new request")
	store.completed.emit(screen.store_configure_request,"configure",store.customer_info)
	_check(screen._store_identity_ready(), "Current-account configuration recovers after networking returns")
	screen._open_lighthouse_preview()
	_check(screen.opened == "res://lighthouse_preview.tscn", "Recovered buyer opens through the normal independently checked scene gate")
	# A reconnect without an entitlement must not become a paid unlock.
	screen.opened = ""
	screen.store_configured = false
	store.customer_info = {"schema_version":1,"entitlements":{}}
	screen._show_home()
	screen.application_backgrounded = true
	await screen._resume_purchase_access()
	_check(store.configure_calls == 2, "Backgrounded application does not restart purchase setup")
	screen.application_backgrounded = false
	await screen._resume_purchase_access()
	_check(store.configure_calls == 3, "Foreground retries idle incomplete initialization once")
	await screen._resume_purchase_access()
	_check(store.configure_calls == 3, "Paired foreground events do not issue duplicate setup")
	store.completed.emit(screen.store_configure_request,"configure",store.customer_info)
	screen._open_lighthouse_preview()
	_check(screen.opened.is_empty() and screen.mode == "paywall", "A recovered nonbuyer stays locked")
	# Recovery must not let an old identity's completion unlock the replacement.
	screen.store_configured = false
	screen._configure_purchases()
	var stale: String = screen.store_configure_request
	screen.api.player_id = "N".repeat(22)
	screen.identity_restart_required = true
	store.customer_info = {"schema_version":1,"entitlements":{"full_journey":{"active":true}}}
	store.completed.emit(stale,"configure",store.customer_info)
	await screen._resume_purchase_access()
	_check(not screen.store_configured and not screen._store_identity_ready() and store.configure_calls == 4, "Identity recovery rejects the previous account's completion and suppresses setup retries")
	screen._open_lighthouse_preview()
	_check(screen.opened.is_empty(), "Stale cached access never admits a recovered identity")
	# Keep the viewport available until deferred safe-area callbacks have drained.
	# queue_free disposes the tree after those calls; detaching first does not.
	screen.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("PURCHASE RECOVERY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
