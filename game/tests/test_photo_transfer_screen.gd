extends SceneTree
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Screen = preload("res://presentation/photo_transfer_screen.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
var checks := 0
var failures := 0

class Identity extends RefCounted:
	var epoch := 1
	func current() -> Dictionary: return {"ready": true, "player_id": OWNER, "epoch": epoch}

class Client extends RefCounted:
	signal progress(message: String)
	var busy := false
	var message := "A saved transfer can be continued or its local plan cleared."
	var pending := true
	var cleared := 0
	var invalidated := 0
	func local_entries() -> Dictionary: return {"ok": true, "entries": []}
	func has_pending_upload() -> bool: return pending
	func has_pending_work() -> bool: return pending
	func refresh() -> bool: return true
	func abandon_local_plan() -> bool:
		cleared += 1
		pending = false
		return true
	func invalidate() -> void: invalidated += 1; busy = false

class PhotoClient extends Client:
	var entries: Array = []
	func local_entries() -> Dictionary: return {"ok": true, "entries": entries}

## Reads one stored photo per call, as the real library does from disk.
class Library extends RefCounted:
	var reads: Dictionary = {}
	var jpegs: Dictionary = {}
	func export_entry(_owner: String, entry_id: String) -> Dictionary:
		reads[entry_id] = int(reads.get(entry_id, 0)) + 1
		return {"ok": true, "entry": {"jpeg_base64": Marshalls.raw_to_base64(jpegs[entry_id])}}

func _init() -> void: _run.call_deferred()

## Fourteen photos: a redraw shows the same twelve without reading or decoding
## them again, a changed photo (new hash) is read afresh, paging keeps only the
## page on show, and closing drops them.
func _thumbnails_decode_once() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var client := PhotoClient.new()
	client.pending = false
	var library := Library.new()
	var noise := Image.create(960, 720, false, Image.FORMAT_RGB8)
	var bytes := PackedByteArray()
	bytes.resize(960 * 720 * 3)
	var random := RandomNumberGenerator.new()
	random.seed = 7
	for i in range(0, bytes.size(), 97): bytes[i] = random.randi() % 256
	noise.set_data(960, 720, false, Image.FORMAT_RGB8, bytes)
	var jpeg := noise.save_jpg_to_buffer(0.85)
	for i in range(14):
		var id := "%064x" % i
		library.jpegs[id] = jpeg
		client.entries.append({"entry_id": id, "photo": {"sha256": "%064x" % (1000 + i)}})
	var identity := Identity.new()
	var screen := Screen.new(null, identity.current, Callable())
	screen.client_override = client
	viewport.add_child(screen)
	screen._library = library
	library.reads.clear()
	var started := Time.get_ticks_usec()
	screen._render()
	var first := Time.get_ticks_usec() - started
	check(library.reads.size() == 12 and screen._thumbnails.size() == 12 and _photos_shown(screen) == 12, "the first page reads and shows twelve photos")
	started = Time.get_ticks_usec()
	for i in range(3): screen._render()
	var again := (Time.get_ticks_usec() - started) / 3
	print("Photo page draw: %.2f ms first, %.2f ms per redraw" % [first / 1000.0, again / 1000.0])
	check(library.reads.values().all(func(count: int) -> bool: return count == 1), "redraws reuse the decoded photos without reading them again")
	check(_photos_shown(screen) == 12, "a redraw still shows all twelve")
	client.entries[0].photo = {"sha256": "%064x" % 5000}
	screen._render()
	check(library.reads[client.entries[0].entry_id] == 2 and library.reads[client.entries[1].entry_id] == 1, "a photo with a new hash is read afresh, the rest are reused")
	screen._local_page = 1
	screen._render()
	check(screen._thumbnails.size() == 2 and library.reads[client.entries[12].entry_id] == 1, "the next page keeps only its own two photos")
	screen._close()
	check(screen._thumbnails.is_empty(), "closing the screen drops the decoded photos")
	viewport.queue_free()
	await _settle()
func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var identity := Identity.new()
	var client := Client.new()
	var closed := [0]
	var screen := Screen.new(null, identity.current, func(): closed[0] += 1)
	screen.client_override = client
	viewport.add_child(screen)
	await _settle()
	var scroll: ScrollContainer = screen._margin.get_child(0)
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(scroll.get_global_rect()), "transfer scrolling stays inside a small landscape viewport")
	check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "actual transfer content overflows and must scroll")
	var target := _button(screen, "Clear unfinished plan…")
	check(target != null and target.mouse_filter == Control.MOUSE_FILTER_PASS, "clear-plan action participates in real card scrolling")
	check(screen._back.mouse_filter == Control.MOUSE_FILTER_PASS, "Back does not create a dead scroll strip")
	var old := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	check(DisplayServer.is_touchscreen_available(), "real touch-emulated viewport path is available")
	scroll.ensure_control_visible(target)
	await _settle()
	var position := target.get_global_rect().get_center()
	var before := scroll.scroll_vertical
	await _drag(viewport, position, Vector2(0, -70))
	check(scroll.scroll_vertical > before and not screen._confirm_clear and client.cleared == 0, "drag over clear-plan scrolls without activating it")
	scroll.ensure_control_visible(target)
	await _settle()
	target.mouse_filter = Control.MOUSE_FILTER_STOP
	before = scroll.scroll_vertical
	await _drag(viewport, target.get_global_rect().get_center(), Vector2(0, -70))
	check(scroll.scroll_vertical == before and not screen._confirm_clear, "STOP negative control reproduces blocked button drag")
	target.mouse_filter = Control.MOUSE_FILTER_PASS
	await _tap_visible(viewport, scroll, target)
	check(screen._confirm_clear and client.cleared == 0, "first tap opens clear-plan confirmation without clearing")
	await _tap_visible(viewport, scroll, _button(screen, "Keep the plan"))
	check(not screen._confirm_clear and client.pending, "Keep the plan leaves pending transfer intact")
	await _tap_visible(viewport, scroll, _button(screen, "Clear unfinished plan…"))
	await _tap_visible(viewport, scroll, _button(screen, "Clear unfinished plan"))
	check(client.cleared == 1 and not client.pending, "explicit confirmation clears only once")
	screen._set_migration_result({"ok": true, "missing": 1})
	check(screen._migration_message == PlayerCopy.PHOTO_TRANSFER_SCREEN_5A0341379E73 and screen._migration_message.contains("app data") and not screen._migration_message.contains("no longer"), "retryable migration reads are not described as proven missing files")
	client.busy = true
	screen._progress("Preparing photos…")
	check(screen._back.text == "Pause & return" and not screen._back.disabled, "Back remains usable during transfer work")
	identity.epoch += 1
	await _settle()
	check(closed[0] == 1 and client.invalidated > 0 and screen._closing, "identity change invalidates media work and returns exactly once")
	Input.emulate_touch_from_mouse = old
	viewport.remove_child(screen)
	screen.queue_free()
	root.remove_child(viewport)
	viewport.queue_free()
	await _settle()
	await _thumbnails_decode_once()
	print("Photo transfer screen: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child: Node in node.get_children():
		var result := _button(child, text)
		if result != null: return result
	return null

func _tap_visible(viewport: SubViewport, scroll: ScrollContainer, button: Button) -> void:
	scroll.ensure_control_visible(button)
	await _settle()
	var point := button.get_global_rect().get_center()
	_pointer(viewport, point, true)
	_pointer(viewport, point, false)
	await _settle()

func _pointer(viewport: SubViewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)

func _drag(viewport: SubViewport, start: Vector2, delta: Vector2) -> void:
	_pointer(viewport, start, true)
	for index in range(1, 9):
		var event := InputEventMouseMotion.new()
		event.position = start + delta * float(index) / 8.0
		event.global_position = event.position
		event.relative = delta / 8.0
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(event, true)
	_pointer(viewport, start + delta, false)
	await _settle()

func _photos_shown(screen: Node) -> int:
	var grids := screen.find_children("*", "GridContainer", true, false)
	return grids[0].get_child_count() if grids.size() == 1 else -1

func _settle() -> void:
	await process_frame
	await process_frame

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
