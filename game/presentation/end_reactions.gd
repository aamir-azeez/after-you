extends HBoxContainer
## End-of-run reactions on an ending card. The row holds the split pill
## (design 4) that picks a face, and the bubbles that show a face: yours and
## your friend's. The pill's right half opens the faces card (design 1's 4 x 2
## grid of the spirit's own expressions, with the heart as an icon-only chip in
## its header). The faces and what this phone keeps of them are
## services/end_reaction_store.gd.
##
## Any card hosts it with one call, and gets null when there is nothing to show:
##   EndReactions.attach(card, {"run": recording_hash, "pick": true, ...})
## Context, every key optional:
##   run        the run's id, its recording hash: a pick is kept per run, so a
##              card that is rebuilt (Retry then Cancel) keeps it
##   pick       true: the player may pick, so the pill shows
##   locked     a face already sent, or waiting in a send: shown, not changeable
##   color      the player's spirit colour, "peach" or "mint"
##   friend     {face, color, name, sound}: the friend's face for this run; it
##              pops once, with its own sound (a Callable(face)), when first shown
##   compact    true: the friend's face small, still and quiet, without its
##              caption, for a list row or beside a name
##   note       the line under the faces (PlayerCopy.END_REACTIONS_*_NOTE)
##   settings   the player's settings: reduced_motion and left_handed are read
##   sound      Callable(face): plays the reaction's pop (soundscape.play_reaction)
##   on_pick    Callable(face): after each pick
##   store      the EndReactionStore to use (tests); a new one otherwise
## A free bubble over the world (a rewatched turn's end) is pop().
##
## Nothing runs per frame: faces are drawn once, a bubble's pop tween belongs to
## the bubble and ends with it, and the faces card is on its own canvas layer
## under the pill, closed when the pill leaves the tree. Under Reduce motion a
## bubble just appears and stays still.
const Store = preload("res://services/end_reaction_store.gd")
const Art = preload("res://presentation/empty_state_art.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SCRIPT_PATH := "res://presentation/end_reactions.gd"
## Every tap target is at least this tall and wide.
const TARGET := 56.0
const BUBBLE_SIZE := Vector2(68, 62)
## A compact bubble's size against BUBBLE_SIZE.
const COMPACT := 0.8
const CELL_SIZE := Vector2(98, 94)
const POP_SECONDS := 0.28
## Taps closer than this make one sound.
const SOUND_GUARD_MS := 250
const PAPER := Color("f6f1e1")
const CELL_FILL := Color("ece5cf")
const CELL_BORDER := Color("d6ceb4")
const PICKED_BORDER := Color("4f9d89")
const PICKED_FILL := Color("dcefe6")
const HEART_FILL := Color("fbe1dc")
const MUTED_INK := Color("4c6a63")
const HEART_COLOR := Color("ee8f86")
## The pill wears the card's secondary look (ControlTheme.secondary), so Save
## turn stays the one cream action on the card.
const PILL_FILL := Color("254b45")
const PILL_BORDER := Color("54766a")

signal picked(face: String)

var context: Dictionary = {}
var store: RefCounted
## This run's face: the pick, or the locked face.
var chosen := ""
var pill: PanelContainer
var quick: Button
var opener: Button
var own_slot: Control
var own_bubble: Control
var friend_bubble: Control
var faces_card: CanvasLayer
var _quick_icon: Control
var _last_sound := -SOUND_GUARD_MS
## Friend faces already popped with a sound, so a rebuilt card stays quiet.
static var _greeted: Dictionary = {}

## Adds the row to `container` and returns it, or returns null and adds
## nothing when there is no pick to offer, no face of yours and no friend face.
static func attach(container: Node, value: Dictionary) -> Control:
	if not is_instance_valid(container): return null
	var friend: Dictionary = value.get("friend", {}) if value.get("friend") is Dictionary else {}
	if not bool(value.get("pick", false)) and not Store.is_face(value.get("locked")) and not Store.is_face(friend.get("face")): return null
	var row: Control = load(SCRIPT_PATH).new()
	row.setup(value)
	container.add_child(row)
	return row

## A bubble on its own over `parent` at `at` (its tail's tip), popping in and
## fading away after `hold` seconds, then freed. For a rewatched turn's end.
## `follow`, when given, is Callable() -> Variant: the tip's point each frame
## while the bubble lives (a spirit the camera still moves past), or null to
## stay put. Only these short-lived bubbles do anything per frame.
static func pop(parent: Node, at: Vector2, face: String, color: String, settings: Dictionary = {}, hold: float = 1.6, follow: Callable = Callable()) -> Control:
	if not is_instance_valid(parent) or not Store.is_face(face): return null
	var bubble := Bubble.new(face, color)
	bubble.position = at - Vector2(BUBBLE_SIZE.x * 0.5, BUBBLE_SIZE.y)
	bubble.follow = follow
	bubble.set_process(follow.is_valid())
	parent.add_child(bubble)
	bubble.show_face(face, not bool(settings.get("reduced_motion", false)))
	var fade := bubble.create_tween()
	fade.tween_interval(hold)
	fade.tween_property(bubble, "modulate:a", 0.0, 0.3)
	fade.tween_callback(bubble.queue_free)
	return bubble

## A quiet pill for a list row (Replays): the face and who sent it, like the
## try count pills beside it. `accessible` is its screen reader name.
static func chip(face: String, color: String, label_text: String, accessible: String) -> Control:
	if not Store.is_face(face): return null
	var pill := PanelContainer.new()
	pill.name = "ReactionChip"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.accessibility_name = accessible
	pill.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(ControlTheme.CHOICE_PANEL, 15, ControlTheme.CHOICE_BORDER), 8.0, 2.0))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	pill.add_child(row)
	var icon := FaceIcon.new(face, color, 26.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", ControlTheme.CREAM)
	row.add_child(label)
	return pill

func setup(value: Dictionary) -> void:
	context = value
	name = "EndReactions"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	# Only the pill reads and writes the file; a row that only shows faces never does.
	if value.get("store") is RefCounted: store = value.get("store")
	elif can_pick(): store = Store.new()
	var run := str(value.get("run", ""))
	var locked := str(value.get("locked", ""))
	if Store.is_face(locked): chosen = locked
	elif can_pick() and not run.is_empty(): chosen = Store.picked(run)
	var friend := _friend_part()
	var own := _own_part()
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The pill sits on the player's hand side; the friend's face on the other.
	var parts: Array = [own, spacer, friend] if left_handed() else [friend, spacer, own]
	for part: Variant in parts:
		if part is Control: add_child(part)

func can_pick() -> bool:
	return bool(context.get("pick", false)) and not Store.is_face(context.get("locked"))

func left_handed() -> bool:
	return bool(_settings().get("left_handed", false))

func reduced_motion() -> bool:
	return bool(_settings().get("reduced_motion", false))

func _settings() -> Dictionary:
	return context.get("settings", {}) if context.get("settings") is Dictionary else {}

func _color() -> String:
	return str(context.get("color", "peach"))

## Picks `face` for this run: kept per run, shown in your bubble with its pop
## and sound, and handed to the host. Ignored once the face is locked.
func choose(face: String) -> void:
	if not can_pick() or not Store.is_face(face): return
	close_faces()
	var changed := face != chosen
	chosen = face
	store.choose(str(context.get("run", "")), face)
	_set_quick_face(face)
	if is_instance_valid(own_bubble):
		own_bubble.visible = true
		if changed: own_bubble.show_face(face, not reduced_motion())
		own_bubble.accessibility_name = PlayerCopy.END_REACTIONS_YOU_NAMED % face_name(face)
	if changed: _sound(face)
	var on_pick: Variant = context.get("on_pick")
	if on_pick is Callable and (on_pick as Callable).is_valid(): (on_pick as Callable).call(face)
	picked.emit(face)

func _sound(face: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_sound < SOUND_GUARD_MS: return
	_last_sound = now
	var sound: Variant = context.get("sound")
	if sound is Callable and (sound as Callable).is_valid(): (sound as Callable).call(face)

static func face_name(face: String) -> String:
	return FaceArt.face_name(face)

# --- The row's two sides --------------------------------------------------------

func _friend_part() -> Control:
	var friend: Dictionary = context.get("friend", {}) if context.get("friend") is Dictionary else {}
	var face := str(friend.get("face", ""))
	if not Store.is_face(face): return null
	var part := HBoxContainer.new()
	part.name = "FriendReaction"
	part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	part.add_theme_constant_override("separation", 10)
	friend_bubble = Bubble.new(face, str(friend.get("color", "mint")), COMPACT if bool(context.get("compact", false)) else 1.0)
	# The tail points at the caption beside it: inward from the row's edge.
	if not bool(context.get("compact", false)): friend_bubble.tail = Bubble.TAIL_LEFT if left_handed() else Bubble.TAIL_RIGHT
	var who := str(friend.get("name", ""))
	var shown := who if not who.is_empty() else PlayerCopy.ROOM_FRIEND
	friend_bubble.accessibility_name = PlayerCopy.END_REACTIONS_FRIEND_NAMED % [shown, face_name(face)]
	if bool(context.get("compact", false)):
		part.add_child(friend_bubble)
	else:
		# The face sits at the row's outer edge, its caption toward the middle.
		var label := _caption(PlayerCopy.END_REACTIONS_FRIEND % shown)
		for child: Control in [label, friend_bubble] if left_handed() else [friend_bubble, label]: part.add_child(child)
	# A friend face on a card pops once, with its own sound, the first time a
	# card shows it; a compact one in a list just shows.
	var key := "%s|%s|%s" % [str(context.get("run", "")), face, who]
	var fresh := not bool(context.get("compact", false)) and not _greeted.has(key)
	if fresh:
		_greeted[key] = true
		while _greeted.size() > 64: _greeted.erase(_greeted.keys()[0])
		var sound: Variant = friend.get("sound")
		if sound is Callable and (sound as Callable).is_valid(): (sound as Callable).call_deferred(face)
	friend_bubble.show_face.call_deferred(face, fresh and not reduced_motion())
	return part

func _own_part() -> Control:
	if not can_pick() and not Store.is_face(chosen): return null
	var part := HBoxContainer.new()
	part.name = "OwnReaction"
	part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	part.add_theme_constant_override("separation", 10)
	own_slot = Control.new()
	own_slot.name = "OwnBubbleSlot"
	own_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	own_slot.custom_minimum_size = BUBBLE_SIZE
	own_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	own_bubble = Bubble.new(chosen, _color())
	# The tail points at the pill (or "You reacted") beside it.
	own_bubble.tail = Bubble.TAIL_LEFT if left_handed() else Bubble.TAIL_RIGHT
	own_bubble.visible = Store.is_face(chosen)
	if own_bubble.visible:
		own_bubble.accessibility_name = PlayerCopy.END_REACTIONS_YOU_NAMED % face_name(chosen)
		own_bubble.show_face.call_deferred(chosen, false)
	own_slot.add_child(own_bubble)
	var side: Control
	if can_pick():
		side = _pill()
	else:
		side = _caption(PlayerCopy.END_REACTIONS_YOU)
	for child: Control in ([side, own_slot] if left_handed() else [own_slot, side]): part.add_child(child)
	return part

func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", ControlTheme.CREAM)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# --- The split pill -----------------------------------------------------------

func _pill() -> PanelContainer:
	pill = PanelContainer.new()
	pill.name = "ReactPill"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var look := ControlTheme.rounded(PILL_FILL, int(TARGET * 0.5), PILL_BORDER)
	look.content_margin_left = 4
	look.content_margin_right = 4
	pill.add_theme_stylebox_override("panel", look)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	pill.add_child(row)
	quick = _flat_button("QuickReact")
	quick.custom_minimum_size = Vector2(TARGET + 8.0, TARGET)
	_quick_icon = FaceIcon.new(store.last_face(), _color(), 40.0)
	# Centred however the button is sized: a centring box fills it.
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.add_child(_quick_icon)
	quick.add_child(centre)
	_set_quick_face(store.last_face() if not Store.is_face(chosen) else chosen)
	quick.pressed.connect(func(): choose(_quick_icon.face))
	var divider := ColorRect.new()
	divider.name = "PillDivider"
	divider.color = Color(ControlTheme.CREAM, 0.35)
	divider.custom_minimum_size = Vector2(2, 30)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opener = _flat_button("OpenReactions")
	opener.text = PlayerCopy.END_REACTIONS_REACT
	opener.accessibility_name = PlayerCopy.END_REACTIONS_CHOOSE
	opener.custom_minimum_size = Vector2(124, TARGET)
	opener.add_theme_font_size_override("font_size", 20)
	opener.alignment = HORIZONTAL_ALIGNMENT_LEFT
	opener.add_theme_constant_override("h_separation", 0)
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 14
	style.content_margin_right = 34
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]: opener.add_theme_stylebox_override(state, style)
	var chevron := Chevron.new()
	chevron.anchor_left = 1.0
	chevron.anchor_right = 1.0
	chevron.anchor_top = 0.5
	chevron.anchor_bottom = 0.5
	chevron.offset_left = -30.0
	chevron.offset_right = -16.0
	chevron.offset_top = -5.0
	chevron.offset_bottom = 5.0
	opener.add_child(chevron)
	opener.pressed.connect(open_faces)
	for child: Control in [quick, divider, opener]: row.add_child(child)
	return pill

func _flat_button(node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ControlTheme.CREAM)
	var plain := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]: button.add_theme_stylebox_override(state, plain)
	return button

func _set_quick_face(face: String) -> void:
	if not is_instance_valid(_quick_icon): return
	_quick_icon.set_face(face, _color())
	quick.accessibility_name = PlayerCopy.END_REACTIONS_QUICK % face_name(face)

# --- The faces card -----------------------------------------------------------

func open_faces() -> void:
	if not can_pick() or not is_instance_valid(pill) or not pill.is_inside_tree(): return
	if is_instance_valid(faces_card):
		close_faces()
		return
	faces_card = FacesCard.new()
	faces_card.name = "ReactionFaces"
	var host := pill.get_canvas_layer_node()
	faces_card.layer = (host.layer if host != null else 0) + 1
	pill.add_child(faces_card, false, Node.INTERNAL_MODE_BACK)
	faces_card.build(self)

func close_faces() -> void:
	if is_instance_valid(faces_card): faces_card.close()
	faces_card = null

func faces_open() -> bool:
	return is_instance_valid(faces_card) and not faces_card.closing


## A face drawn flat with the game's own shapes: the spirit's head in its
## colour with the face's eyes, or the coral heart. Drawn once per face.
class FaceIcon extends Control:
	var face := ""
	var color := "peach"
	func _init(face_id: String, spirit_color: String, diameter: float) -> void:
		face = face_id
		color = spirit_color
		custom_minimum_size = Vector2.ONE * diameter
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_face(face_id: String, spirit_color: String) -> void:
		face = face_id
		color = spirit_color
		queue_redraw()
	func _draw() -> void:
		FaceArt.draw_face(self, Rect2(Vector2.ZERO, size), face, color)


## How a face is drawn and named, shared by the row and its inner parts.
class FaceArt:
	## Draws `face` to fit `box` on `ci`: the spirit's head in `color` with the
	## face's eyes, or the coral heart.
	static func draw_face(ci: CanvasItem, box: Rect2, face: String, color: String) -> void:
		if face == Store.HEART:
			draw_heart(ci, box.get_center() + Vector2(0, box.size.y * 0.04), minf(box.size.x, box.size.y) * 0.44, HEART_COLOR)
			return
		var expression := Store.expression(face)
		if expression == &"": return
		var scale := minf(box.size.x, box.size.y) * 0.5 / (Art.Look.HEAD_HALF.x * Art.UNIT * 1.12)
		var at := Transform2D(0.0, Vector2(scale, scale), 0.0, box.get_center() + Vector2(0, box.size.y * 0.06))
		Art.spirit(ci, at, {"color": color if Art.SPIRITS.has(color) else "peach", "eyes": str(expression)}, true)

	static func draw_heart(ci: CanvasItem, center: Vector2, radius: float, fill: Color) -> void:
		var points := PackedVector2Array()
		for step in range(40):
			var t := TAU * float(step) / 40.0
			var x := 16.0 * pow(sin(t), 3.0)
			var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
			points.append(center + Vector2(x, -y - 2.0) * radius / 17.0)
		ci.draw_colored_polygon(points, fill)
		points.append(points[0])
		ci.draw_polyline(points, fill.darkened(0.2), maxf(1.0, radius * 0.06), true)

	static func face_name(face: String) -> String:
		return str(PlayerCopy.END_REACTION_NAMES.get(face, ""))


## A speech bubble with a face: the spirit's colour lightened toward cream, the
## kit's ink outline inside a thin cream rim (so it holds on the dark cards),
## and a tail: down at a spirit, or sideways at what it belongs to. Its pop is
## a short scale tween on the bubble itself; under Reduce motion it just appears.
class Bubble extends Control:
	const TAIL_DOWN := 0
	const TAIL_LEFT := 1
	const TAIL_RIGHT := 2
	var face := ""
	var color := "peach"
	var tail := TAIL_DOWN
	var follow: Callable
	func _ready() -> void:
		set_process(follow.is_valid())
	func _process(_delta: float) -> void:
		var at: Variant = follow.call() if follow.is_valid() else null
		if at is Vector2: position = (at as Vector2) - Vector2(size.x * 0.5, size.y)
	func _init(face_id: String, spirit_color: String, factor: float = 1.0) -> void:
		face = face_id
		color = spirit_color
		name = "ReactionBubble"
		custom_minimum_size = (BUBBLE_SIZE * factor).round()
		size = custom_minimum_size
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pivot_offset = Vector2(size.x * 0.5, size.y)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func show_face(face_id: String, animate: bool) -> void:
		face = face_id
		queue_redraw()
		if not animate or not is_inside_tree():
			scale = Vector2.ONE
			return
		scale = Vector2(0.4, 0.4)
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2.ONE, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	func _draw() -> void:
		if not Store.is_face(face): return
		var tint: Color = Art.SPIRITS.get(color, Art.PEACH).lerp(ControlTheme.CREAM, 0.6)
		var unit := size.y / BUBBLE_SIZE.y
		var reach := 10.0 * unit
		var body := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		var points: PackedVector2Array
		match tail:
			TAIL_LEFT:
				body = Rect2(Vector2(3.0 + reach, 3), size - Vector2(6.0 + reach, 6))
				var mid := body.get_center().y
				points = PackedVector2Array([Vector2(body.position.x + 1.0, mid - 7.0 * unit), Vector2(2, mid), Vector2(body.position.x + 1.0, mid + 7.0 * unit)])
			TAIL_RIGHT:
				body = Rect2(Vector2(3, 3), size - Vector2(6.0 + reach, 6))
				var mid := body.get_center().y
				points = PackedVector2Array([Vector2(body.end.x - 1.0, mid - 7.0 * unit), Vector2(size.x - 2.0, mid), Vector2(body.end.x - 1.0, mid + 7.0 * unit)])
			_:
				body = Rect2(Vector2(3, 3), Vector2(size.x - 6.0, size.y - 4.0 - reach))
				points = PackedVector2Array([Vector2(size.x * 0.5 - 8.0 * unit, body.end.y - 1.0), Vector2(size.x * 0.5, size.y - 2.0), Vector2(size.x * 0.5 + 8.0 * unit, body.end.y - 1.0)])
		var rim := ControlTheme.rounded(ControlTheme.CREAM, int(19.0 * unit))
		draw_style_box(rim, body.grow(2.0))
		draw_polyline(points, ControlTheme.CREAM, 6.0, true)
		var look := ControlTheme.rounded(tint, int(18.0 * unit), ControlTheme.INK)
		look.set_border_width_all(2)
		draw_style_box(look, body)
		draw_colored_polygon(points, tint)
		draw_polyline(points, ControlTheme.INK, 2.0, true)
		FaceArt.draw_face(self, body.grow(-6.0 * unit), face, color)


## The tiny up chevron on the pill's open half.
class Chevron extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(14, 10)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_polyline(PackedVector2Array([Vector2(1, 9), Vector2(7, 2), Vector2(13, 9)]), ControlTheme.CREAM, 2.5, true)


## The faces card: a cream card on its own canvas layer over the screen. It
## opens beside the pill on the player's hand side, out over the world beside
## the ending card, so the card's actions stay in view; where that does not fit
## (a narrow window) it opens above the pill, else below. A tap outside, Back,
## the close button or a pick closes it.
class FacesCard extends CanvasLayer:
	const EDGE := 12.0
	const POINTER := 9.0
	## From the pill's outer end past the ending card's own edge.
	const BESIDE := 30.0
	var row: Control
	var anchor: Control
	var shade: ColorRect
	var panel: PanelContainer
	var pointer: Polygon2D
	var cells: Dictionary = {}
	var closing := false

	func build(owner_row: Control) -> void:
		row = owner_row
		anchor = owner_row.pill
		shade = ColorRect.new()
		shade.name = "ReactionShade"
		# Barely dimmed: the pill it came from stays clear.
		shade.color = Color(0.02, 0.08, 0.08, 0.1)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		shade.gui_input.connect(_on_shade_input)
		add_child(shade)
		panel = PanelContainer.new()
		panel.name = "ReactionCard"
		var look := ControlTheme.rounded(PAPER, 22, Color(ControlTheme.INK, 0.18))
		look.content_margin_left = 16
		look.content_margin_right = 16
		look.content_margin_top = 10
		look.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", look)
		shade.add_child(panel)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 8)
		panel.add_child(stack)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 6)
		stack.add_child(header)
		var title := Label.new()
		title.text = PlayerCopy.END_REACTIONS_TITLE
		title.add_theme_font_size_override("font_size", 26)
		title.add_theme_color_override("font_color", ControlTheme.INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.add_child(title)
		var heart := _cell(Store.HEART, Vector2(TARGET, TARGET), false)
		heart.name = "Face_heart"
		header.add_child(heart)
		var close_button := Button.new()
		close_button.name = "CloseReactions"
		close_button.flat = true
		close_button.custom_minimum_size = Vector2(TARGET, TARGET)
		close_button.accessibility_name = PlayerCopy.END_REACTIONS_CLOSE
		close_button.add_child(Cross.new())
		close_button.pressed.connect(close)
		header.add_child(close_button)
		var grid := GridContainer.new()
		grid.name = "ReactionGrid"
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		stack.add_child(grid)
		for face: String in Store.FACES:
			if face == Store.HEART: continue
			grid.add_child(_cell(face, CELL_SIZE, true))
		var note := str(owner_row.context.get("note", ""))
		if not note.is_empty():
			var line := Label.new()
			line.name = "ReactionNote"
			line.text = note
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.add_theme_font_size_override("font_size", 16)
			line.add_theme_color_override("font_color", MUTED_INK)
			stack.add_child(line)
		pointer = Polygon2D.new()
		pointer.color = PAPER
		shade.add_child(pointer)
		place()
		get_viewport().size_changed.connect(place)
		anchor.tree_exiting.connect(close)
		anchor.visibility_changed.connect(_on_anchor_visibility)

	func _cell(face: String, cell_size: Vector2, named: bool) -> Button:
		var cell := Button.new()
		cell.name = "Face_" + face
		cell.custom_minimum_size = cell_size
		cell.focus_mode = Control.FOCUS_ALL
		cell.accessibility_name = FaceArt.face_name(face)
		var picked_now: bool = face == row.chosen
		var fill := HEART_FILL if face == Store.HEART else (PICKED_FILL if picked_now else CELL_FILL)
		var normal := ControlTheme.rounded(fill, 16, PICKED_BORDER if picked_now else CELL_BORDER)
		normal.set_border_width_all(3 if picked_now else 1)
		var lit := ControlTheme.rounded(PICKED_FILL, 16, PICKED_BORDER)
		lit.set_border_width_all(2)
		for state: String in ["normal", "disabled"]: cell.add_theme_stylebox_override(state, normal)
		for state: String in ["hover", "pressed", "hover_pressed", "focus"]: cell.add_theme_stylebox_override(state, lit)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_theme_constant_override("separation", 2)
		cell.add_child(box)
		var icon := FaceIcon.new(face, row._color(), 48.0 if named else 34.0)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		if named:
			var label := Label.new()
			label.text = FaceArt.face_name(face)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# A long name (Knocked out) a size smaller, so it keeps clear of the cell's edge.
			label.add_theme_font_size_override("font_size", 16 if label.text.length() <= 9 else 14)
			label.add_theme_color_override("font_color", ControlTheme.INK)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(label)
		cell.pressed.connect(func(): if not closing and is_instance_valid(row): row.choose(face))
		cells[face] = cell
		return cell

	## Beside the pill on the hand side when it fits there, its pointer on the
	## pill's end; else above the pill whenever it fits, else below, else the
	## roomier side kept inside, its edge lined up with the pill's on the hand side.
	func place() -> void:
		if closing or not is_instance_valid(anchor) or not anchor.is_inside_tree(): return
		var view := anchor.get_viewport().get_visible_rect()
		var transform := anchor.get_global_transform_with_canvas()
		var rect := Rect2(transform.origin, anchor.size * transform.get_scale())
		panel.reset_size()
		var card := panel.get_combined_minimum_size()
		var left: bool = row.left_handed()
		var side_x := rect.position.x - BESIDE - card.x if left else rect.end.x + BESIDE
		if side_x >= view.position.x + EDGE and side_x + card.x <= view.end.x - EDGE and card.y <= view.size.y - 2.0 * EDGE:
			var side_y := clampf(rect.get_center().y - card.y * 0.5, view.position.y + EDGE, view.end.y - EDGE - card.y)
			panel.position = Vector2(side_x, side_y)
			panel.size = card
			var edge_x := side_x + card.x if left else side_x
			var tip := rect.position.x - 4.0 if left else rect.end.x + 4.0
			var mid := clampf(rect.get_center().y, side_y + 24.0, side_y + card.y - 24.0)
			pointer.polygon = PackedVector2Array([Vector2(edge_x, mid - POINTER), Vector2(edge_x, mid + POINTER), Vector2(tip, rect.get_center().y)])
			return
		var x := rect.position.x if left else rect.end.x - card.x
		x = clampf(x, view.position.x + EDGE, maxf(view.position.x + EDGE, view.end.x - EDGE - card.x))
		var room_above := rect.position.y - POINTER - view.position.y - EDGE
		var room_below := view.end.y - EDGE - rect.end.y - POINTER
		var above := room_above >= card.y or room_above >= room_below
		var y := rect.position.y - POINTER - card.y if above else rect.end.y + POINTER
		y = clampf(y, view.position.y + EDGE, maxf(view.position.y + EDGE, view.end.y - EDGE - card.y))
		panel.position = Vector2(x, y)
		panel.size = card
		var tip_x := clampf(rect.get_center().x if not is_instance_valid(row.opener) else _opener_center(), x + 24.0, x + card.x - 24.0)
		var edge := y + card.y if above else y
		var toward := POINTER if above else -POINTER
		pointer.polygon = PackedVector2Array([Vector2(tip_x - POINTER, edge - signf(toward)), Vector2(tip_x + POINTER, edge - signf(toward)), Vector2(tip_x, edge + toward)])

	func _opener_center() -> float:
		var transform: Transform2D = row.opener.get_global_transform_with_canvas()
		return transform.origin.x + row.opener.size.x * transform.get_scale().x * 0.5

	## The card's rectangle on screen, for tests and captures.
	func panel_rect() -> Rect2:
		return Rect2(panel.position, panel.size)

	func close() -> void:
		if closing: return
		closing = true
		# Freed at the end of the frame, so the tap that closed it lands here
		# and never on whatever lies beneath.
		queue_free()

	func _input(event: InputEvent) -> void:
		if not closing and event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			close()

	func _on_shade_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			shade.accept_event()
			close()

	func _on_anchor_visibility() -> void:
		if not is_instance_valid(anchor) or not anchor.is_visible_in_tree(): close()


## The close button's cross.
class Cross extends Control:
	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		for sign_x: float in [-1.0, 1.0]:
			draw_line(c + Vector2(-9.0, -9.0 * sign_x), c + Vector2(9.0, 9.0 * sign_x), ControlTheme.INK, 3.0, true)
