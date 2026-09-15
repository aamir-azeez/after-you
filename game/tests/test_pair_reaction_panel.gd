extends SceneTree
const Spec = preload("res://tests/test_pair_reaction_controller.gd")
const ReactionPanel = preload("res://presentation/pair_reaction_panel.gd")
const Preview = preload("res://relay_preview.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const Canonical = preload("res://core/v2/canonical.gd")

class FakeSession:
	extends RefCounted
	var harness := Spec.Harness.new()
	var controller: RefCounted
	var other_busy := false
	func create_pair_reaction_controller() -> RefCounted:
		controller = harness.create()
		return controller
	func photo_identity() -> Dictionary: return harness.identity()
	func photo_request_busy() -> bool: return other_busy or (controller != null and controller.busy())
	func preset_reactions_enabled() -> bool: return harness.enabled
	func busy() -> bool: return photo_request_busy()
	func pair_reaction_request_busy() -> bool: return controller != null and controller.busy()

var checks := 0
var failures := 0
var canvas: Control

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	canvas = Control.new()
	root.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _render_refresh_and_controls()
	await _back_during_optional_request()
	await _rebuild_during_optional_request()
	canvas.queue_free()
	await process_frame
	print("After You pair reaction panel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _button(text: String, callback: Callable, _primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(130, 44)
	button.pressed.connect(callback)
	return button

func _panel(session: RefCounted) -> Control:
	var panel := ReactionPanel.new()
	canvas.add_child(panel)
	panel.size = Vector2(600, 400)
	panel.configure(session, session.harness.target_fixture(), _button)
	return panel

func _render_refresh_and_controls() -> void:
	var session := FakeSession.new()
	var panel := _panel(session)
	var h: RefCounted = session.harness
	h.set_row(h.row(Spec.GUEST, "love", 1))
	await process_frame
	panel.service(Time.get_ticks_msec() + 1, false)
	_check(h.calls.is_empty(), "hidden/background/unsafe eligibility issues no metadata requests")
	panel.service(Time.get_ticks_msec() + 2, true)
	await process_frame
	_check(panel.get_node("PairReactionSummary").text == "Your friend reacted: Beautiful!", "existing partner preset uses legacy label")
	_check(panel.get_node("PairReactionNotice").text.is_empty(), "first read does not announce old reactions as new")
	var button: Button = panel._choices[1]
	var instance := button.get_instance_id()
	button.grab_focus()
	h.set_row(h.row(Spec.GUEST, "sparkles", 2))
	panel.request_refresh()
	panel.service(Time.get_ticks_msec() + 3, true)
	await process_frame
	_check(panel.get_node("PairReactionNotice").text == "Your friend reacted: We did it!", "fresh partner revision gives a small scoped notice")
	_check(button.get_instance_id() == instance and button.has_focus(), "metadata refresh preserves controls and focus")
	_check(h.calls.all(func(call: Dictionary) -> bool: return call.method == HTTPClient.METHOD_GET), "foreground service is GET-only")
	button.pressed.emit()
	await process_frame
	_check(h.calls[-1].method == HTTPClient.METHOD_POST and h.calls[-1].body.reaction == "sparkles", "actual preset button invokes one explicit matching selection")
	_check(panel.get_node("PairReactionSummary").text.contains("Your reaction: We did it!"), "acknowledged own reaction renders")
	var count: int = h.calls.size()
	panel.hide()
	panel.request_refresh()
	panel.service(Time.get_ticks_msec() + 10000, true)
	_check(h.calls.size() == count, "hidden replay/gameplay overlay does not poll")
	panel.show()
	session.other_busy = true
	panel.service(Time.get_ticks_msec() + 10001, true)
	_check(h.calls.size() == count, "shared API busy prevents concurrent request")
	panel.queue_free()
	await process_frame

func _back_during_optional_request() -> void:
	var session := FakeSession.new()
	var panel := _panel(session)
	var h: RefCounted = session.harness
	panel.service(Time.get_ticks_msec(), true)
	await process_frame
	h.hold = true
	panel._choices[0].pressed.emit()
	_check(session.busy() and not session.controller.pending().is_empty(), "delayed explicit POST retains its pending request")
	var saved := Canonical.digest(h.values)
	var screen := Preview.new()
	screen.online_session = session
	screen.pair_reaction_panel = panel
	var closed := [false]
	screen.closed.connect(func(): closed[0] = true)
	screen._leave()
	_check(closed[0], "Back closes without waiting for optional transport")
	h.release.emit()
	await process_frame
	_check(Canonical.digest(h.values) == saved, "late accepted result cannot redraw or discard pending after leave")
	_check(session.controller.state().is_empty(), "leaving invalidates controller result context")
	var reopened: RefCounted = h.create()
	_check(await reopened.check_pending() and reopened.pending().is_empty(), "later receipt check recovers pending accepted after Back")
	screen.free()
	panel.queue_free()
	await process_frame

func _rebuild_during_optional_request() -> void:
	var session := FakeSession.new()
	var screen := Preview.new()
	screen.online_session = session
	screen.controls = Controls.new()
	root.add_child(screen.controls)
	var first: VBoxContainer = screen._card("First card", "Synthetic completed stage")
	var old := ReactionPanel.new()
	first.add_child(old)
	old.configure(session, session.harness.target_fixture(), _button)
	screen.pair_reaction_panel = old
	old.service(Time.get_ticks_msec(), true)
	await process_frame
	session.harness.hold = true
	old._choices[0].pressed.emit()
	var saved := Canonical.digest(session.harness.values)
	var next: VBoxContainer = screen._card("Replacement card", "Same verified stage")
	_check(not old._alive, "actual card replacement invalidates old panel synchronously")
	var fresh := ReactionPanel.new()
	next.add_child(fresh)
	fresh.configure(session, session.harness.target_fixture(), _button)
	screen.pair_reaction_panel = fresh
	_check(not fresh.controller.pending().is_empty(), "replacement panel restores original pending request")
	session.harness.release.emit()
	await process_frame
	_check(Canonical.digest(session.harness.values) == saved, "late replaced-panel response cannot overwrite new same-scope state")
	fresh.service(Time.get_ticks_msec(), true)
	await process_frame
	_check(fresh.controller.pending().is_empty() and fresh.controller.last_receipt().reaction == "love", "replacement panel resolves the exact accepted key by GET")
	screen.controls.queue_free()
	screen.free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
