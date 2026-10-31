extends SceneTree
const Main = preload("res://main.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const RoomHubFlow = preload("res://presentation/room_hub_flow.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
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

class HostStub extends Node:
	var mode := RoomHubFlow.MODE_ROOMS

## A real redraw_locks wait; only the redraw itself is counted.
class RedrawProbe extends RoomHubFlow:
	var redraws := 0
	func redraw_chapters() -> void: redraws += 1

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
	await _check_hub_redraw()
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

## RoomHubFlow.redraw_locks keeps the screen a tap was made on: a tap the hub's
## gate holds keeps its label (and its chapter) until it runs or gives up, and a
## finger on Host as the check ends, whose release makes that tap, is waited for.
func _check_hub_redraw() -> void:
	var host := HostStub.new()
	root.add_child(host)
	# Out of the tree: the flow's own hub reads (_process) stay off.
	var flow := RedrawProbe.new(host)
	# A viewport of its own takes the pushed finger (as test_busy_tap_gate does).
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var screen := CanvasLayer.new()
	var button := Button.new()
	button.text = "Host a room"
	button.position = Vector2(20, 20)
	button.size = Vector2(120, 50)
	screen.add_child(button)
	viewport.add_child(screen)
	await process_frame
	flow.screen = screen
	flow._gate = BusyTapGate.new(screen)
	var state := {"ready": false, "ran": 0}
	var tap := func() -> void: flow._gate.tap(button, "Opening", func() -> bool: return state.ready, func() -> void: state.ran += 1)
	# A held tap, then the check ends.
	tap.call()
	flow.redraw_locks()
	await _frames(4)
	_check(flow.redraws == 0 and button.text == "Opening", "A tap the hub holds keeps its label while the check's redraw waits")
	state.ready = true
	await _frames(4)
	_check(state.ran == 1 and flow.redraws == 1 and button.text == "Host a room", "The locks are drawn once the held tap has run")
	# A held tap that gives up.
	state.ready = false
	flow._gate.wait_ms = 60
	tap.call()
	flow.redraw_locks()
	await _frames(2)
	_check(flow.redraws == 1, "The redraw waits while the tap may still run")
	await _until(func() -> bool: return flow.redraws == 2, 1000)
	_check(flow.redraws == 2 and state.ran == 1 and button.text == "Host a room", "A tap that gives up lets the locks be drawn")
	# A finger on Host as the check ends: its release makes the tap.
	flow._gate.wait_ms = BusyTapGate.WAIT_MS
	button.pressed.connect(tap)
	_mouse(viewport, button, true)
	await _frames(2)
	_check(button.is_pressed(), "The finger holds Host down")
	flow.redraw_locks()
	await _frames(3)
	_check(flow.redraws == 2, "The redraw waits for the finger on Host")
	_mouse(viewport, button, false)
	await _frames(4)
	_check(flow.redraws == 2 and button.text == "Opening", "The tap made as the finger lifts keeps its label")
	state.ready = true
	await _frames(4)
	_check(state.ran == 2 and flow.redraws == 3, "The locks are drawn once that tap has run")
	button.pressed.disconnect(tap)
	# The hub left while the redraw waits: nothing is drawn on the old screen.
	state.ready = false
	tap.call()
	flow.redraw_locks()
	await _frames(2)
	host.mode = "home"
	state.ready = true
	await _frames(4)
	_check(flow.redraws == 3, "A hub that was left draws nothing again")
	viewport.free()
	flow.free()
	host.free()

func _mouse(viewport: SubViewport, button: Control, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	viewport.push_input(event, true)

func _frames(count: int) -> void:
	for index in range(count): await process_frame

func _until(done: Callable, limit_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + limit_ms
	while not done.call() and Time.get_ticks_msec() < deadline: await process_frame

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
