extends SceneTree
## The field being typed in shows large above the on screen keyboard
## (presentation/kit/keyboard_lift.gd), with a simulated keyboard height:
## - no copy on desktop, and no tick while no field has focus;
## - it shows centred in the space above the keyboard, titled by the field;
## - the copy follows the field (typing, text set in code, caret, max length,
##   secret, placeholder) and the field stays the one source of truth;
## - Enter submits through the field; the keyboard closing, a press on the dim
##   and focus moving on all take it away; the tap that opened it does not;
## - a screen change or a rebuilt page while it shows leaves nothing stuck;
## - the display name prompt and the Friends code field, as built by the game.
const KeyboardLift = preload("res://presentation/kit/keyboard_lift.gd")
const Prompt = preload("res://presentation/display_name_prompt.gd")
const DisplayNames = preload("res://services/display_names.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Screen = preload("res://presentation/friends_screen.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const FullBleed = preload("res://presentation/full_bleed.gd")
const FriendRoster = preload("res://services/friend_roster.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const BASE := "https://example.test"
## About 55% of a 720 unit tall landscape screen.
const KEYBOARD := 396.0
const SIZE := Vector2i(1560, 720)

var checks := 0
var failures := 0
var viewport: SubViewport
var page: Control
var layer: CanvasLayer
var _paths: Array[String] = []

class Api extends Node:
	var base_url := "https://example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
	var device_token := "synthetic-token"
	var busy := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.gui_disable_input = false
	viewport.handle_input_locally = true
	root.add_child(viewport)
	page = _page()
	_units()
	await _desktop()
	await _first_layer()
	await _shows_centred()
	await _follows_field()
	await _submit_and_close()
	await _first_tap()
	await _screen_changes()
	await _name_prompt()
	await _friend_code()
	await _robust()
	KeyboardLift.simulate(-1.0)
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU KEYBOARD LIFT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# --- Helpers -------------------------------------------------------------------

func _page() -> Control:
	var made := Control.new()
	made.size = Vector2(SIZE)
	viewport.add_child(made)
	return made

func _field(title: String = "", parent: Control = null) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = title
	KeyboardLift.attach(field)
	field.position = Vector2(80, 600)
	field.size = Vector2(400, 48)
	(parent if parent != null else page).add_child(field)
	return field

func _copy() -> Control:
	return layer.find_child("KeyboardLiftField", true, false)

func _title() -> Label:
	return layer.find_child("KeyboardLiftTitle", true, false)

func _note() -> Label:
	return layer.find_child("KeyboardLiftNote", true, false)

func _timer_running() -> bool:
	return layer.ticking()

## How many of the layer's handlers listen to `field`.
func _listening(field: LineEdit) -> int:
	var count := 0
	for source: Signal in [field.text_changed, field.focus_exited, field.visibility_changed, field.tree_exiting]:
		for connection: Dictionary in source.get_connections():
			if (connection.callable as Callable).get_object() == layer: count += 1
	return count

func _mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)

func _type(text: String) -> void:
	for i in range(text.length()):
		var event := InputEventKey.new()
		event.pressed = true
		event.unicode = text.unicode_at(i)
		event.keycode = KEY_A
		viewport.push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		viewport.push_input(event, true)
	await _frames(1)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)
	await _frames(1)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _clear_page() -> void:
	for child: Node in page.get_children():
		page.remove_child(child)
		child.queue_free()
	await _frames(1)

# --- Cases ---------------------------------------------------------------------

func _units() -> void:
	_check(is_equal_approx(KeyboardLift.cover_units(1188.0, 2160.0, 720.0), 396.0), "Keyboard pixels become canvas units through the window height")
	_check(KeyboardLift.cover_units(0.0, 2160.0, 720.0) == 0.0 and KeyboardLift.cover_units(500.0, 0.0, 720.0) == 0.0, "No keyboard or no window is no cover")
	_check(KeyboardLift.cover_units(5000.0, 2160.0, 720.0) == 720.0, "The cover never passes the screen")

func _desktop() -> void:
	KeyboardLift.simulate(-1.0)
	_check(not KeyboardLift.watching(), "A desktop build does not watch for an on screen keyboard")
	var field := _field("Invitation code")
	_check(KeyboardLift.attached(field) and KeyboardLift.attach(field) == field, "attach returns the field, and a second call is harmless")
	field.grab_focus()
	await _frames(3)
	_check(field.has_focus() and KeyboardLift.layer_of(viewport) == null, "On desktop an attached field takes focus and nothing is made at all")
	field.release_focus()
	await _clear_page()

## The layer is made when the first attached field takes focus with a keyboard.
func _first_layer() -> void:
	KeyboardLift.simulate(KEYBOARD)
	var plain := LineEdit.new()
	page.add_child(plain)
	plain.grab_focus()
	await _frames(2)
	_check(KeyboardLift.layer_of(viewport) == null, "A field that is not attached makes nothing")
	var field := _field("Invitation code")
	field.grab_focus()
	await _frames(2)
	layer = KeyboardLift.layer_of(viewport)
	_check(layer != null and layer.is_inside_tree() and layer.get_parent() == viewport and layer.layer == KeyboardLift.LAYER, "The first attached field makes one layer in its viewport, above the screens")
	if layer == null:
		push_error("No layer; stopping")
		quit(1)
		return
	_check(layer.showing() and layer.target() == field, "and it shows as soon as it arrives")
	var shade: ColorRect = layer.find_child("KeyboardLiftShade", true, false)
	_check(shade != null and shade.get_node_or_null(NodePath(FullBleed.NAME)) != null and shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Its dim reaches every screen edge (SafeArea.bleed) and only draws")
	field.release_focus()
	await _clear_page()
	var other := _field("Tester code")
	other.grab_focus()
	await _frames(2)
	_check(KeyboardLift.layer_of(viewport) == layer and layer.showing(), "The next field uses the same layer")
	other.release_focus()
	await _clear_page()

func _shows_centred() -> void:
	KeyboardLift.simulate(KEYBOARD)
	var field := _field("Invitation code")
	_check(not _timer_running(), "With a keyboard simulated, no tick runs until a field has focus")
	field.grab_focus()
	await _frames(3)
	_check(layer.showing() and layer.target() == field, "A field taking focus with the keyboard up shows large")
	_check(_timer_running(), "and a light tick follows it while it has focus")
	var panel: Control = layer.find_child("KeyboardLiftPanel", true, false)
	var box := panel.get_global_rect()
	var free := Rect2(0, 0, SIZE.x, SIZE.y - KEYBOARD)
	_check(free.encloses(box), "The card fits above the keyboard: %s in %s" % [box, free])
	_check(absf(box.get_center().x - SIZE.x * 0.5) < 2.0 and absf(box.get_center().y - free.get_center().y) < 2.0, "and sits centred in that space: %s" % box.get_center())
	_check(box.size.x >= 600.0, "It is wide: %s" % box.size.x)
	_check(_title().visible and _title().text == "Invitation code", "Its title is the field's own label: " + _title().text)
	_check(_copy().font_size >= 40 and _copy().font_size > field.get_theme_font_size("font_size") * 1.5, "Its words are large: %d" % _copy().font_size)
	_check(_copy().placeholder.is_empty(), "A placeholder used as the title is not said twice")
	_check(not _note().visible, "No note unless the field names one")
	field.release_focus()
	await _frames(1)
	_check(not layer.poll() and not _timer_running(), "With focus gone the tick stops")
	await _clear_page()

func _follows_field() -> void:
	var field := _field()
	KeyboardLift.attach(field, "Nickname")
	field.placeholder_text = "Pip"
	field.max_length = 6
	field.grab_focus()
	await _frames(2)
	_check(layer.showing() and _title().text == "Nickname", "A field may name its title")
	_check(_copy().shown_text.is_empty() and _copy().placeholder == "Pip", "An empty field shows its placeholder")
	await _type("Robin")
	_check(field.text == "Robin" and _copy().shown_text == "Robin" and _copy().caret == 5, "Typing goes into the field and the copy follows: " + _copy().shown_text)
	await _type("Kite")
	_check(field.text == "RobinK" and _copy().shown_text == "RobinK", "The field's max length holds: " + field.text)
	await _key(KEY_BACKSPACE)
	_check(_copy().shown_text == "Robin", "Erasing follows too")
	field.text = "Sky"
	field.caret_column = 1
	_check(layer.poll() and _copy().shown_text == "Sky" and _copy().caret == 1, "Text and caret set in code reach the copy on the next tick")
	await _type("u")
	_check(field.text == "Suky" and _copy().shown_text == "Suky" and _copy().caret == 2, "Typing lands at the field's caret: " + field.text)
	field.select(0, 2)
	layer.poll()
	_check(_copy().selection == Vector2i(0, 2), "A selection shows in the copy")
	field.deselect()
	field.secret = true
	layer.poll()
	_check(_copy().shown_text == "••••" and field.text == "Suky", "A secret field shows dots only")
	var note := Label.new()
	note.text = "4 / 6"
	page.add_child(note)
	KeyboardLift.attach(field, "Nickname", note)
	layer.poll()
	_check(_note().visible and _note().text == "4 / 6", "A named note shows under the field")
	note.text = "Too long"
	note.add_theme_color_override("font_color", Color.RED)
	layer.poll()
	_check(_note().text == "Too long" and _note().get_theme_color("font_color") == Color.RED, "and follows its words and colour")
	note.queue_free()
	await _frames(1)
	_check(layer.poll() and not _note().visible, "A note that goes away leaves nothing behind")
	field.release_focus()
	await _clear_page()

func _submit_and_close() -> void:
	var field := _field("Tester code")
	var submitted: Array = []
	field.text_submitted.connect(func(text: String) -> void: submitted.append(text))
	field.grab_focus()
	await _frames(2)
	await _type("abc")
	await _key(KEY_ENTER)
	_check(submitted == ["abc"], "Enter submits through the field once: %s" % [submitted])
	# The keyboard closes on Enter or Back; the field may keep focus.
	KeyboardLift.simulate(0.0)
	await _frames(1)
	_check(not layer.poll() and not layer.showing(), "The keyboard closing takes the copy away")
	_check(_timer_running() == field.has_focus(), "The tick keeps watching only while the field keeps focus")
	if not field.has_focus(): field.grab_focus()
	KeyboardLift.simulate(KEYBOARD)
	_check(layer.poll() and layer.showing(), "Tapping the field again (the keyboard back up) shows it again")
	# A press on the dim closes the keyboard.
	_mouse(Vector2(20, 20), true)
	await _frames(1)
	_check(not layer.showing() and not field.has_focus(), "A press on the dim takes it away and the field lets go")
	_mouse(Vector2(20, 20), false)
	await _frames(1)
	_check(field.text == "abc" and not layer.poll() and not _timer_running(), "The text stays and the tick stops")
	# A button showing through the dim (a lifted card's Save) works on the first tap.
	var button := Button.new()
	button.position = Vector2(600, 40)
	button.size = Vector2(120, 48)
	var pressed := [0]
	button.pressed.connect(func() -> void: pressed[0] += 1)
	page.add_child(button)
	field.grab_focus()
	await _frames(1)
	_check(layer.showing(), "Back in the field it shows")
	var spot := button.get_global_rect().get_center()
	_mouse(spot, true)
	await _frames(1)
	_check(not layer.showing() and not field.has_focus(), "A press on a button under the dim closes the keyboard")
	_mouse(spot, false)
	await _frames(1)
	_check(pressed[0] == 1, "and the same tap presses it: %d" % pressed[0])
	# A tap on the large copy moves the field's caret.
	field.grab_focus()
	field.caret_column = 3
	await _frames(1)
	_check(layer.showing() and _copy().caret == 3, "The copy shows the caret at the end")
	var copy_rect := _copy().get_global_rect()
	_mouse(Vector2(copy_rect.position.x + 1.0, copy_rect.get_center().y), true)
	_mouse(Vector2(copy_rect.position.x + 1.0, copy_rect.get_center().y), false)
	await _frames(1)
	_check(layer.showing() and field.has_focus() and field.caret_column == 0 and _copy().caret == 0, "A tap at the copy's start puts the caret there: %d" % field.caret_column)
	# Focus moving to a button takes it away.
	button.grab_focus()
	await _frames(1)
	_check(not layer.showing() and not _timer_running(), "Focus on a button takes it away")
	# A read only field never shows.
	field.editable = false
	field.grab_focus()
	await _frames(1)
	_check(not layer.showing(), "A read only field does not show")
	await _clear_page()

func _first_tap() -> void:
	var field := _field("Identity")
	var at := field.get_global_rect().get_center()
	_mouse(at, true)
	await _frames(1)
	_check(field.has_focus() and layer.showing(), "The tap on a field gives it focus and the copy shows")
	_mouse(at, false)
	await _frames(1)
	_check(layer.showing() and field.has_focus(), "The release of that same tap does not close it")
	await _type("x")
	_check(field.text == "x" and _copy().shown_text == "x", "Typing right after works")
	field.release_focus()
	await _clear_page()

func _screen_changes() -> void:
	# A screen swapped out while the copy shows.
	var screen := Control.new()
	page.add_child(screen)
	var field := _field("Recovery code", screen)
	field.grab_focus()
	await _frames(1)
	_check(layer.showing(), "Showing before the screen changes")
	screen.queue_free()
	await _frames(2)
	_check(not layer.showing() and layer.target() == null, "A screen freed under it leaves no copy behind")
	_check(not layer.poll() and not _timer_running(), "and no tick")
	# A page rebuilt in place, its field taking focus again in the same frame.
	var first := _field("Friend code")
	first.text = "friend-ab"
	first.grab_focus()
	await _frames(1)
	page.remove_child(first)
	first.queue_free()
	var second := _field("Friend code")
	second.text = "friend-abc"
	second.grab_focus()
	_check(layer.showing() and layer.target() == second and _copy().shown_text == "friend-abc", "A rebuilt field takes the copy over at once")
	await _frames(2)
	_check(layer.showing() and layer.target() == second, "and it stays")
	# The keyboard closing in the middle of a change.
	KeyboardLift.simulate(0.0)
	second.queue_free()
	await _frames(2)
	KeyboardLift.simulate(KEYBOARD)
	_check(not layer.poll() and not layer.showing(), "Nothing is stuck after the keyboard and the page go together")
	await _clear_page()

func _path(label: String) -> String:
	var path := "user://test-keyboard-focus-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _name_prompt() -> void:
	var saved: Array = []
	var modal: Control = Prompt.open(page, {"own": DisplayNames.new(_path("own")).own(BASE, ME), "anonymous": "Kite 41", "platform": "",
		"save": func(choice: String, name: String) -> Dictionary: saved.append([choice, name]); return {"closed": true}})
	await _frames(3)
	var prompt: Node = modal.find_child("DisplayNamePrompt", true, false)
	_check(prompt.field.has_focus() and layer.showing() and layer.target() == prompt.field, "The name prompt's field shows large as the card opens")
	_check(_title().text == PlayerCopy.DISPLAY_NAME_ASK, "under the card's question: " + _title().text)
	_check(_copy().placeholder == PlayerCopy.DISPLAY_NAME_FIELD, "with the field's placeholder")
	await _type("Robin")
	_check(_copy().shown_text == "Robin" and prompt.tag.text == "Robin", "Typing reaches the prompt as before")
	_check(_note().visible and _note().text == prompt._counter.text and _note().text == "5 / 18", "and its counter shows under the copy: " + _note().text)
	await _key(KEY_ENTER)
	await _frames(3)
	_check(saved == [["typed", "Robin"]], "Enter saves the name as before: %s" % [saved])
	_check(not layer.showing(), "The card closing takes the copy away")
	await _clear_page()

func _friend_code() -> void:
	DisplayNames.use_shared(DisplayNames.new(_path("names")))
	FriendRoster.use_shared(FriendRoster.new(_path("roster")))
	var api := Api.new()
	viewport.add_child(api)
	var page_data := {"schema_version": 1, "friend_code": ME, "refresh_after_seconds": 30, "shared_room": null, "friends": []}
	var client: RefCounted = FriendsClient.new(api, func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1},
		func(_m: int, _p: String, _b: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify({"ok": true, "data": page_data})))
	await client.refresh()
	var screen: CanvasLayer = Screen.new()
	screen.client = client
	screen.nickname_store = FriendNicknames.new(_path("nicknames"))
	viewport.add_child(screen)
	await _frames(8)
	screen._render()
	await _frames(3)
	var field: LineEdit = screen.find_child("FriendCode", true, false)
	_check(field != null, "The Friends page has its code field")
	if field == null:
		DisplayNames.use_shared(null)
		FriendRoster.use_shared(null)
		return
	var own: LineEdit = screen.find_child("OwnFriendCode", true, false)
	_check(own != null and not KeyboardLift.eligible(own), "The player's own code (read only) never shows large")
	field.grab_focus()
	await _frames(2)
	_check(layer.showing() and _title().text == "Friend code", "The friend code field shows large under its own label: " + _title().text)
	await _type("friend-maya")
	_check(_copy().shown_text == "friend-maya" and screen._code == "friend-maya", "Typing reaches the screen")
	# A poll rebuilds the page while the player types.
	screen._render()
	await _frames(1)
	var rebuilt: LineEdit = screen.find_child("FriendCode", true, false)
	_check(rebuilt != field and rebuilt.has_focus() and layer.showing() and layer.target() == rebuilt, "A rebuilt Friends page keeps the copy on its new field")
	_check(_copy().shown_text == "friend-maya", "with the same words")
	screen.queue_free()
	api.queue_free()
	await _frames(2)
	_check(not layer.showing() and not layer.poll(), "Leaving Friends leaves no copy")
	DisplayNames.use_shared(null)
	FriendRoster.use_shared(null)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _robust() -> void:
	KeyboardLift.simulate(KEYBOARD)
	var a := _field("Identity")
	var b := _field("Recovery code")
	b.position.y = 660
	# Focus given twice listens once.
	a.grab_focus()
	a.grab_focus()
	await _frames(1)
	_check(layer.showing() and _listening(a) == 4, "Focus given twice listens once: %d" % _listening(a))
	# Quick switching between two fields.
	b.grab_focus()
	a.grab_focus()
	b.grab_focus()
	_check(layer.showing() and layer.target() == b and _title().text == "Recovery code", "Quick switching ends on the last field at once")
	_check(_listening(a) == 0 and _listening(b) == 4, "and only it is listened to: %d / %d" % [_listening(a), _listening(b)])
	var focus_links := 0
	for connection: Dictionary in viewport.gui_focus_changed.get_connections():
		if (connection.callable as Callable).get_object() == layer: focus_links += 1
	_check(focus_links == 1, "The layer listens to the viewport's focus once")
	# Focus let go in code: gone at once, not at the next tick.
	b.release_focus()
	_check(not layer.showing() and layer.target() == null and _listening(b) == 0, "Focus let go takes the copy away at once")
	_check(not layer.poll() and not layer.ticking(), "and stops the tick")
	# A field hidden while it shows.
	a.grab_focus()
	await _frames(1)
	_check(layer.showing(), "Shows again")
	a.visible = false
	_check(not layer.showing(), "A field hidden while it shows takes the copy away at once")
	a.visible = true
	# The app paused and resumed with the field still focused.
	a.grab_focus()
	await _frames(1)
	_check(layer.showing(), "Shows before the pause")
	layer.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(not layer.showing() and not layer.poll(), "Pausing the app takes it away and it stays away")
	layer.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(layer.showing(), "Resuming with the field and keyboard still there brings it back")
	layer.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not layer.showing(), "The app losing focus takes it away")
	KeyboardLift.simulate(0.0)
	layer.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not layer.showing(), "Coming back with the keyboard gone leaves it away")
	KeyboardLift.simulate(KEYBOARD)
	_check(layer.poll(), "and the keyboard coming back up shows it")
	# The system Back button closes the keyboard; the field keeps focus.
	KeyboardLift.simulate(0.0)
	_check(not layer.poll() and not layer.showing() and a.has_focus() and layer.ticking(), "Back closing the keyboard takes it away while the field keeps focus")
	KeyboardLift.simulate(KEYBOARD)
	_check(layer.poll(), "and the keyboard back up shows it again")
	# A field freed outright while it shows.
	a.free()
	_check(not layer.showing() and layer.target() == null, "A field freed outright takes the copy with it")
	await _frames(1)
	_check(not layer.poll() and not layer.ticking(), "and nothing keeps ticking")
	await _clear_page()
