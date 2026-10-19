extends SceneTree
## The Play with your friend icon: two happy spirits at rest; squeezed eyes,
## a squish and a heart pop while the button is hovered by a mouse, held, or
## has keyboard focus; happy again on release or exit. Input goes through the
## viewport as real events: mouse motion and buttons, and a finger's touch with
## the mouse the engine emulates from it. The icon never takes the tap, draws
## nothing on idle frames, and under reduced motion only swaps the eyes.

const FriendPlayIcon = preload("res://presentation/friend_play_icon.gd")
const Art = preload("res://presentation/empty_state_art.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_poses()
	await _rest_and_idle()
	await _mouse_hover()
	await _mouse_hold()
	await _finger_tap()
	await _pan_ends_on_button()
	await _disabled_while_held()
	await _engine_touch()
	await _keyboard_focus()
	await _reduced_motion()
	await _label_follows_text()
	await _home()
	print("AFTER YOU FRIEND PLAY ICON: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The scene state reaches the drawing: the squishing spirits take the state's
## eyes, slide together, tip in and squash about the chin, the heart pops and
## lifts; rows of the other scenes come back exactly as written.
func _poses() -> void:
	var rows: Array = Art.SCENES.friends_squeeze
	var rest := {"eyes": Look.HAPPY, "squish": 0.0}
	var held := {"eyes": Look.SQUEEZE, "squish": 1.0}
	for row: Array in rows:
		if row[0] != "face": continue
		var toward: float = row[2].squish
		var calm := Art.pose(row, rest)
		var close := Art.pose(row, held)
		_check(calm.options.eyes == Look.HAPPY and close.options.eyes == Look.SQUEEZE, "%s: happy at rest, squeezed when held" % row[2].color)
		_check(calm.place.origin.is_equal_approx(row[1]), "%s rests where the scene puts it" % row[2].color)
		_check(is_equal_approx(close.place.origin.x - calm.place.origin.x, toward * Art.SQUISH_SHIFT), "%s slides %.1f toward the other" % [row[2].color, Art.SQUISH_SHIFT])
		_check(is_equal_approx(close.options.tilt - calm.options.tilt, toward * Art.SQUISH_TIP), "%s tips further in" % row[2].color)
		_check(close.place.get_scale().x < calm.place.get_scale().x and close.place.get_scale().y > calm.place.get_scale().y, "%s squashes narrower and taller" % row[2].color)
		# A face's place is centred on its head; the chin is half a head below.
		var chin := Vector2(0, Look.HEAD_HALF.y * Art.UNIT)
		_check(absf((close.place * chin).y - (calm.place * chin).y) < 0.01, "%s keeps its chin level as it squashes" % row[2].color)
		_check(row[2].eyes == "happy" and not row[2].has("edge"), "The scene row itself is left untouched")
	var heart: Array = rows[2]
	var calm_heart := Art.pose(heart, rest)
	var popped := Art.pose(heart, held)
	_check(is_equal_approx(popped.size, calm_heart.size * 1.28) and popped.pos.y < calm_heart.pos.y, "The heart pops 28%% bigger and lifts: %.2f to %.2f" % [calm_heart.size, popped.size])
	for scene_id: String in ["invite", "finished", "friend", "friend_next", "polaroid"]:
		for row: Array in Art.SCENES[scene_id]:
			if row[0] in ["spirit", "face"]:
				var posed := Art.pose(row, held)
				_check(is_same(posed.options, row[2]) and posed.place == Art._place(row[1], row[2]), "%s: its spirits ignore the squish state" % scene_id)
			elif row[0] == "heart":
				var posed := Art.pose(row, held)
				_check(posed.pos == row[1] and posed.size == row[2], "%s: its heart ignores the squish state" % scene_id)

## A 1280x720 viewport with a Home-sized button in a column, the icon leading
## its label. Returns [viewport, button, icon, presses].
func _stage(reduced := false) -> Array:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	# A full-screen backdrop that takes touches and drags, as Home's world does.
	var backdrop := Control.new()
	backdrop.size = Vector2(1280, 720)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport.add_child(backdrop)
	var column := VBoxContainer.new()
	column.position = Vector2(64, 300)
	column.size = Vector2(385, 54)
	viewport.add_child(column)
	var button := Button.new()
	button.text = "Play with your friend"
	button.custom_minimum_size = Vector2(385, 54)
	button.focus_mode = Control.FOCUS_ALL
	column.add_child(button)
	var icon := FriendPlayIcon.new()
	icon.reduced_motion = reduced
	icon.lead_label(button)
	var presses := [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	await _frames(3)
	return [viewport, button, icon, presses]

func _close(made: Array) -> void:
	(made[0] as Node).queue_free()
	await _frames(2)

func _rest_and_idle() -> void:
	var made := await _stage()
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	_check(icon.get_parent() == button and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE and icon.focus_mode == Control.FOCUS_NONE, "The icon sits in the button and never takes the mouse or focus")
	_check(not icon.squeezed and icon.squish == 0.0 and not icon.is_processing(), "At rest both spirits are happy and nothing runs")
	_check(icon.draw_count >= 1, "The icon draws once when shown")
	var drawn: int = icon.draw_count
	await _frames(30)
	_check(icon.draw_count == drawn and not icon.is_processing(), "Idle frames draw nothing: %d then %d" % [drawn, icon.draw_count])
	var rect := Rect2(icon.position, icon.size)
	_check(Rect2(Vector2.ZERO, button.size).encloses(rect), "The icon fits inside the button: %s in %s" % [rect, button.size])
	_check(absf(rect.get_center().y - button.size.y * 0.5) <= 1.0, "The icon is centred down the button")
	var font := button.get_theme_font("font")
	var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
	var style := button.get_theme_stylebox("normal")
	var text_left := (style.get_margin(SIDE_LEFT) + button.size.x - style.get_margin(SIDE_RIGHT) - text_width) * 0.5
	_check(rect.end.x <= text_left - 4.0 and rect.end.x >= text_left - 14.0, "The icon leads the centred label, just left of it: icon ends %.1f, label starts %.1f" % [rect.end.x, text_left])
	await _close(made)

func _mouse_hover() -> void:
	var made := await _stage()
	var viewport: SubViewport = made[0]
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	var inside := button.get_global_rect().get_center()
	_motion(viewport, inside - Vector2(0, 120))
	await _frames(2)
	_motion(viewport, inside)
	await _frames(1)
	_check(icon.squeezed, "A mouse over the button squeezes the eyes at once")
	_check(icon.is_processing(), "The squish starts easing in")
	await create_timer(FriendPlayIcon.SQUISH_TIME * 1.5).timeout
	await _frames(2)
	_check(icon.squish > 0.9, "The squish is near full by about 0.12 s: %.2f" % icon.squish)
	await create_timer(0.2).timeout
	_check(icon.squish == 1.0 and not icon.is_processing(), "The squish settles and stops")
	var drawn: int = icon.draw_count
	await _frames(20)
	_check(icon.draw_count == drawn, "A hovered, settled icon draws nothing more")
	_motion(viewport, inside + Vector2(0, 120))
	await _frames(1)
	_check(not icon.squeezed, "Moving off the button brings the happy eyes back at once")
	await create_timer(0.35).timeout
	_check(icon.squish == 0.0 and not icon.is_processing(), "And the spirits ease apart, then stop")
	await _close(made)

func _mouse_hold() -> void:
	var made := await _stage()
	var viewport: SubViewport = made[0]
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	var presses: Array = made[3]
	var inside := button.get_global_rect().get_center()
	_motion(viewport, inside)
	_click(viewport, inside, true)
	await _frames(1)
	_check(icon.squeezed, "Pressing the mouse squeezes")
	await create_timer(0.3).timeout
	_check(icon.squeezed and icon.squish == 1.0, "Holding keeps them squeezed together")
	_check(presses[0] == 0, "Nothing is pressed until the release")
	_click(viewport, inside, false)
	await _frames(1)
	_check(presses[0] == 1, "The release presses the button once: %d" % presses[0])
	_check(icon.squeezed, "The mouse still over it keeps the squeeze, as hover")
	_motion(viewport, inside + Vector2(0, 120))
	await _frames(1)
	_check(not icon.squeezed and not button.has_focus(true), "Leaving after a click is happy again: the click's focus is hidden")
	await _close(made)

## A finger on Android: the engine sends the emulated mouse (its emulation
## device), then the touch. The emulated pointer never leaves the button, but
## the lift ends the squeeze.
func _finger_tap() -> void:
	var made := await _stage()
	var viewport: SubViewport = made[0]
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	var presses: Array = made[3]
	var at := button.get_global_rect().get_center()
	_finger(viewport, at, true)
	await _frames(1)
	_check(icon.squeezed, "A finger down squeezes at once")
	_check(presses[0] == 0, "Touching down presses nothing yet")
	for step: Vector2 in [Vector2(1, 1), Vector2(2, -1)]:
		at += step
		_drag(viewport, at, step)
	await create_timer(0.25).timeout
	_check(icon.squeezed and icon.squish == 1.0, "Holding a finger on it keeps them squeezed together")
	_finger(viewport, at, false)
	await _frames(1)
	_check(presses[0] == 1, "The first tap registers once, through the icon: %d" % presses[0])
	_check(not icon.squeezed, "Lifting the finger is happy again at once")
	await create_timer(0.35).timeout
	_check(icon.squish == 0.0 and not icon.is_processing(), "And they ease apart, then stop")
	# A second tap squeezes and releases the same way.
	_finger(viewport, at, true)
	await _frames(1)
	_check(icon.squeezed, "A second finger down squeezes again")
	_finger(viewport, at, false)
	await _frames(1)
	_check(presses[0] == 2 and not icon.squeezed, "A second tap presses once more and lets go")
	await _close(made)

## A pan over Home's world that ends with the finger lifting over the button:
## the touch belongs to the world, yet the emulated pointer ends on the button.
func _pan_ends_on_button() -> void:
	var made := await _stage()
	var viewport: SubViewport = made[0]
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	var presses: Array = made[3]
	var at := button.get_global_rect().get_center() + Vector2(0, -160)
	_finger(viewport, at, true)
	await _frames(1)
	for step: int in range(8):
		at += Vector2(0, 20)
		_drag(viewport, at, Vector2(0, 20))
		await _frames(1)
	_check(icon.squeezed, "The emulated pointer reaches the button during the pan, so the lift below is the stuck case")
	_finger(viewport, at, false)
	await _frames(1)
	_check(presses[0] == 0, "A pan that ends on the button presses nothing")
	_check(not icon.squeezed, "A pan that lifts over the button leaves it happy")
	await create_timer(0.35).timeout
	_check(icon.squish == 0.0 and not icon.is_processing(), "And nothing keeps running after the pan")
	await _close(made)

## Disabling a held button drops its press with no button_up.
func _disabled_while_held() -> void:
	var made := await _stage()
	var viewport: SubViewport = made[0]
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	var at := button.get_global_rect().get_center()
	_finger(viewport, at, true)
	await _frames(1)
	_check(icon.squeezed, "Held before disabling")
	button.disabled = true
	await _frames(2)
	_check(not icon.squeezed, "Disabling the held button is happy again")
	_finger(viewport, at, false)
	await _frames(1)
	button.disabled = false
	await _frames(2)
	_check(not icon.squeezed, "Enabling it again, untouched, stays happy")
	await _close(made)

## The same finger through the engine's own input path: Input turns the touch
## into its emulated mouse before the root viewport sees either.
func _engine_touch() -> void:
	# Touch emulation on makes this headless display report a touchscreen, as a phone.
	root.size = Vector2i(1280, 720)
	var original_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var column := VBoxContainer.new()
	column.position = Vector2(64, 300)
	root.add_child(column)
	var button := Button.new()
	button.text = "Play with your friend"
	button.custom_minimum_size = Vector2(385, 54)
	column.add_child(button)
	var icon := FriendPlayIcon.new()
	icon.lead_label(button)
	var presses := [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	await _frames(3)
	var at := button.get_global_rect().get_center()
	_input_touch(at, true)
	await _frames(1)
	_check(icon.squeezed, "Engine touch: a finger down squeezes")
	_input_touch(at, false)
	await _frames(1)
	_check(presses[0] == 1, "Engine touch: one tap, one press: %d" % presses[0])
	_check(not icon.squeezed, "Engine touch: the lift is happy again")
	Input.emulate_touch_from_mouse = original_touch
	column.queue_free()
	await _frames(2)

func _keyboard_focus() -> void:
	var made := await _stage()
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	button.grab_focus()
	await _frames(1)
	_check(icon.squeezed, "Keyboard focus on the button squeezes, as hover does")
	button.release_focus()
	await _frames(1)
	_check(not icon.squeezed, "Focus moving on is happy again")
	button.disabled = true
	button.grab_focus()
	await _frames(1)
	_check(not icon.squeezed, "A disabled button's icon stays happy")
	await _close(made)

func _reduced_motion() -> void:
	var made := await _stage(true)
	var viewport: SubViewport = made[0]
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	var presses: Array = made[3]
	var drawn: int = icon.draw_count
	var at := button.get_global_rect().get_center()
	_finger(viewport, at, true)
	await _frames(1)
	_check(icon.squeezed and icon.squish == 0.0 and not icon.is_processing(), "Reduced motion: the eyes squeeze with no squish")
	await _frames(10)
	_check(icon.draw_count == drawn + 1, "Reduced motion: one redraw for the eyes, nothing per frame: %d" % (icon.draw_count - drawn))
	_finger(viewport, at, false)
	await _frames(1)
	_check(not icon.squeezed and icon.squish == 0.0 and not icon.is_processing() and presses[0] == 1, "Reduced motion: release is happy at once and the tap lands")
	await _close(made)

## The label can change under the icon (Opening… while a save runs); the icon
## moves to lead the new label.
func _label_follows_text() -> void:
	var made := await _stage()
	var button: Button = made[1]
	var icon: FriendPlayIcon = made[2]
	var before: float = icon.position.x
	button.text = "Opening…"
	await _frames(3)
	_check(icon.position.x > before + 20.0, "A shorter label pulls the icon in: %.1f to %.1f" % [before, icon.position.x])
	button.text = "Play with your friend"
	await _frames(3)
	_check(is_equal_approx(icon.position.x, before), "The usual label puts it back")
	await _close(made)

## Today's Home: the cream Play with your friend button carries the icon.
func _home() -> void:
	var path := "user://friend-icon-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = storage
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.identity_loading = false
	await _frames(2)
	app._show_home()
	await _frames(3)
	var play: Button = null
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == "Play with your friend": play = button
	_check(play != null, "Home shows Play with your friend")
	if play != null:
		var icons := play.find_children("*", "Control", true, false).filter(func(child: Node) -> bool: return child.get_script() == FriendPlayIcon)
		_check(icons.size() == 1, "Home's Play with your friend carries one friend icon")
		_check(play.icon == null, "The drawing is a child, not a tinted Button icon")
		if icons.size() == 1:
			var icon: FriendPlayIcon = icons[0]
			_check(not icon.squeezed and play.get_global_rect().encloses(icon.get_global_rect()), "On Home it rests happy, inside the button")
			_motion(viewport, play.get_global_rect().get_center())
			await _frames(1)
			_check(icon.squeezed, "Hovering Home's button squeezes")
			_motion(viewport, play.get_global_rect().get_center() + Vector2(0, -200))
			await _frames(1)
			_check(not icon.squeezed, "Leaving it is happy again")
	viewport.queue_free()
	await _frames(2)
	await create_timer(0.1).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _motion(viewport: Viewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)

func _click(viewport: Viewport, at: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.position = at
	click.global_position = at
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.pressed = pressed
	viewport.push_input(click, true)

## The engine's order for a finger: its emulated mouse, then the touch.
func _finger(viewport: Viewport, at: Vector2, pressed: bool) -> void:
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = at
	mouse.global_position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse.pressed = pressed
	viewport.push_input(mouse, true)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = pressed
	viewport.push_input(touch, true)

func _drag(viewport: Viewport, at: Vector2, relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.position = at
	motion.global_position = at
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(motion, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = at
	drag.relative = relative
	viewport.push_input(drag, true)

func _input_touch(at: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = pressed
	Input.parse_input_event(touch)
	Input.flush_buffered_events()

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + description)
