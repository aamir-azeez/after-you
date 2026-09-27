extends SceneTree
const Main = preload("res://main.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
var checks := 0
var failures := 0

class LedgerProbe extends Keepsakes:
	var friend_passes := 0
	func reconcile_friend(_collection: RefCounted) -> bool:
		friend_passes += 1
		return true
	func backfill_pending() -> bool: return false
	func earned_descriptors() -> Array[Dictionary]: return []

class HomeProbe extends Main:
	var identity_state := {"ready": false, "player_id": OWNER, "epoch": 1}
	func _relay_identity() -> Dictionary: return identity_state.duplicate()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	# Do not add Main to the tree: this tests its real polling hook without
	# starting identity, network, UI or canonical gameplay save lifecycles.
	var app := HomeProbe.new()
	var ledger := LedgerProbe.new()
	app.home_keepsakes = ledger
	app.mode = "home"
	app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 0 and app.shared_replays == null, "Cold home defers friend work while identity is not ready")
	app.identity_state.ready = true
	app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 1 and app.shared_replays != null, "Identity becoming ready lazily creates collection and schedules a pass")
	for index in range(8): app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 1, "Repeated home polling does not reschedule the same owner and epoch")
	app.application_backgrounded = true
	app.identity_state.epoch += 1
	app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 1, "Backgrounded home does not start a new identity pass")
	app.application_backgrounded = false
	app.mode = "rehearse"
	app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 1, "Another screen does not start home backfill")
	app.mode = "home"
	app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 2, "Returning home schedules the newly ready epoch once")
	app._invalidate_relay_identity(false)
	_check(app._keepsake_identity.is_empty(), "Explicit account invalidation clears home reconciliation marker")
	app.identity_state.ready = false
	app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 2, "Invalidation does not schedule until identity becomes ready again")
	app.identity_state.ready = true
	app._service_home_keepsakes(0.15)
	_check(ledger.friend_passes == 3, "Ready identity restarts a pass after invalidation even when same account returns")
	app.free()
	print("HOME KEEPSAKE LIFECYCLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
