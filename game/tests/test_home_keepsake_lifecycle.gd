extends SceneTree
const Main = preload("res://main.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const RoomHubFlow = preload("res://presentation/room_hub_flow.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
var checks := 0
var failures := 0

class LedgerProbe extends Keepsakes:
	var friend_passes := 0
	var solo_passes := 0
	var advances := 0
	## A check in progress, and how many more advances it takes to end.
	var pending := false
	var advances_left := 0
	func reconcile_friend(_collection: RefCounted) -> bool:
		friend_passes += 1
		return true
	func reconcile_solo(_legacy_replays: Dictionary = {}) -> bool:
		solo_passes += 1
		return true
	func advance_backfill(_max_sources: int = 1) -> bool:
		advances += 1
		advances_left -= 1
		if advances_left <= 0: pending = false
		return true
	func backfill_pending() -> bool: return pending
	func earned_descriptors() -> Array[Dictionary]: return []

class HubProbe extends RoomHubFlow:
	var redraws := 0
	func is_open() -> bool: return true
	func redraw_locks() -> void: redraws += 1

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
	_check_hub(app, ledger)
	app.free()
	print("HOME KEEPSAKE LIFECYCLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The room hub (Main._service_hub_keepsakes) finishes a check Home started,
## starts none, and draws its chapter locks again once, when the check ends.
func _check_hub(app: Node, ledger: LedgerProbe) -> void:
	var hub := HubProbe.new()
	app.room_hub_flow.free()
	app.add_child(hub)
	app.room_hub_flow = hub
	app.mode = RoomHubFlow.MODE_ROOMS
	app._keepsakes_reconcile_frame = 0
	var solo := ledger.solo_passes
	var friend := ledger.friend_passes
	# A newly ready identity: Home would start its friend pass, the hub does not.
	app.identity_state.epoch += 1
	for index in range(4): app._service_home_keepsakes(0.15)
	_check(ledger.advances == 0 and ledger.solo_passes == solo and ledger.friend_passes == friend and hub.redraws == 0, "A hub with no check running starts none and draws nothing again")
	ledger.pending = true
	ledger.advances_left = 2
	app.application_backgrounded = true
	app._service_home_keepsakes(0.15)
	_check(ledger.advances == 0 and hub.redraws == 0, "A backgrounded hub leaves the check alone")
	app.application_backgrounded = false
	app._service_home_keepsakes(0.15)
	_check(ledger.advances == 1 and ledger.pending and hub.redraws == 0, "The hub advances a pending check and keeps its cards while it runs")
	_check(ledger.friend_passes == friend + 1, "An identity ready while the check runs joins its friend pass to it")
	_check(ledger.solo_passes == solo, "The hub never starts Home's solo check")
	app._service_home_keepsakes(0.15)
	_check(ledger.advances == 2 and not ledger.pending and hub.redraws == 1, "The hub draws its chapter locks again once the check ends")
	app.identity_state.epoch += 1
	for index in range(4): app._service_home_keepsakes(0.15)
	_check(ledger.advances == 2 and hub.redraws == 1 and ledger.friend_passes == friend + 1, "A settled hub stays settled: no new pass, no further redraw")

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
