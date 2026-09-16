extends SceneTree
const Harness = preload("res://tests/test_safety_client.gd")
const Screen = preload("res://presentation/safety_screen.gd")
const Client = preload("res://services/safety_client.gd")
const Store = preload("res://services/safety_store.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func button(screen: Node, text: String) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		if node.text == text: return node
	return null
func frames() -> void:
	for _i in range(4): await process_frame

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var identity := Harness.Identity.new()
	var api := Harness.Server.new()
	root.add_child(api)
	var directory := "user://safety-ui-" + str(Time.get_ticks_usec())
	var service := Client.new(api, identity.current, Store.new(directory))
	var closed: Array = []
	var blocked: Array = []
	var screen := Screen.new(service, Harness.TARGET, func(): closed.append(true), func(): blocked.append(true))
	viewport.add_child(screen)
	await frames()
	check(button(screen, "Privacy policy") != null and button(screen, "Read community rules") != null, "public policy links visible")
	check(button(screen, "I accept the community rules") != null, "unaccepted account has explicit consent action")
	check(api.calls.all(func(value: Dictionary) -> bool: return value.method == HTTPClient.METHOD_GET), "opening controls never posts consent or report")
	var all_pass := true
	for item: Node in screen.find_children("*", "Button", true, false):
		all_pass = all_pass and item.mouse_filter == Control.MOUSE_FILTER_PASS and item.custom_minimum_size.y >= 48
	check(all_pass, "scrollable actions pass drag with usable minimum touch height")
	check(screen._content.size.x <= 960 and screen._margin.get_global_rect().size.x <= 960, "small landscape viewport preserves horizontal bounds")
	var old_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var scroll: ScrollContainer = screen._margin.get_child(0)
	var accept := button(screen, "I accept the community rules")
	scroll.ensure_control_visible(accept)
	await frames()
	var before := scroll.scroll_vertical
	await drag(viewport, accept.get_global_rect().get_center(), Vector2(0, -70))
	check(scroll.scroll_vertical > before and not service.terms_accepted, "actual drag over consent button scrolls without accepting")
	scroll.ensure_control_visible(accept)
	await frames()
	accept.mouse_filter = Control.MOUSE_FILTER_STOP
	before = scroll.scroll_vertical
	await drag(viewport, accept.get_global_rect().get_center(), Vector2(0, -70))
	check(scroll.scroll_vertical == before and not service.terms_accepted, "STOP negative control reproduces blocked button scrolling")
	accept.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.ensure_control_visible(accept)
	await frames()
	pointer(viewport, accept.get_global_rect().get_center(), true)
	pointer(viewport, accept.get_global_rect().get_center(), false)
	await frames()
	check(service.terms_accepted and button(screen, "I accept the community rules") == null, "explicit current acceptance updates UI")
	check(api.calls.filter(func(value: Dictionary) -> bool: return value.method == HTTPClient.METHOD_POST).size() == 1, "acceptance does not upload photo")
	button(screen, "Report this player").pressed.emit()
	await frames()
	check(button(screen, "Someone's private information") != null, "report offers specific reason choice")
	button(screen, "Someone's private information").pressed.emit()
	await frames()
	check(api.calls[-1].body.reason == "privacy" and api.calls[-1].body.photo == null, "user report sends selected reason without invented photo")
	check(service.pending_report().is_empty(), "only matching receipt clears pending")
	button(screen, "Block this player…").pressed.emit()
	await frames()
	check(button(screen, "Block player") != null and blocked.is_empty(), "block requires explicit confirmation")
	button(screen, "Block player").pressed.emit()
	await frames()
	check(blocked.size() == 1 and not is_instance_valid(screen), "confirmed block closes playback controls once")
	check(not Store.new(directory).partner_allowed(Harness.OWNER, "relay", Harness.ROOM, Harness.PEER), "block is persisted before caller exits")
	service = Client.new(api, identity.current, Store.new(directory))
	check(await service.unblock(Harness.PEER), "prepare independent delayed report scenario")
	screen = Screen.new(service, Harness.TARGET, func(): closed.append(true))
	viewport.add_child(screen)
	await frames()
	api.hold_path = "/v1/safety/report"
	button(screen, "Report this player").pressed.emit()
	await frames()
	button(screen, "Other inappropriate content").pressed.emit()
	await frames()
	check(api.waiting and screen._busy and button(screen, "Back") != null and not button(screen, "Back").disabled, "Back remains available during deferred report")
	var pending: Dictionary = Store.new(directory).read(Harness.OWNER).value.pending.duplicate(true)
	button(screen, "Back").pressed.emit()
	await frames()
	check(not is_instance_valid(screen) and closed.size() == 1, "Back closes screen while report request drains")
	api.release.emit()
	await frames()
	check(Store.Canonical.same(Store.new(directory).read(Harness.OWNER).value.pending, pending), "late accepted report does not overwrite cancelled view's durable request")
	api.hold_path = ""
	service = Client.new(api, identity.current, Store.new(directory))
	check(await service.check_report(), "later independent owner can reconcile cancelled report")
	screen = Screen.new(service, {}, func(): closed.append(true), Callable(), true)
	viewport.add_child(screen)
	await frames()
	check(button(screen, "Report this player") == null and button(screen, "Back to your photo") != null, "photo terms view has no implicit report/block action")
	identity.epoch += 1
	await frames()
	check(not is_instance_valid(screen) and closed.size() == 2, "identity epoch change closes old account UI")
	api.free()
	viewport.queue_free()
	Input.emulate_touch_from_mouse = old_touch
	await frames()
	print("Safety screen: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func pointer(viewport: SubViewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)

func drag(viewport: SubViewport, start: Vector2, delta: Vector2) -> void:
	pointer(viewport, start, true)
	for index in range(1, 9):
		var event := InputEventMouseMotion.new()
		event.position = start + delta * float(index) / 8.0
		event.global_position = event.position
		event.relative = delta / 8.0
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(event, true)
	pointer(viewport, start + delta, false)
	await frames()
