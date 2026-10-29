extends Button
## Reactions during a run: the cream split React pill beside Finish (round two,
## design 4). Its left half is your last face: one tap sends it again. A thin
## divider parts it from React, which opens the shared faces card
## (presentation/end_reactions.gd FacesCard) up and inward, over the world: it
## never covers the action button or Finish, and the joystick, the action button
## and the camera keep working while it is open. The card's footer says the
## reactions go with the turn. A tap on a face sends it (`reacted`), closes the
## card and becomes the last face; while the cooldown runs a mint fill sweeps
## the pill, and it greys out once the turn's reactions are used up. The rules
## and the track are services/run_reaction_track.gd; the screen records and
## shows a reaction (presentation/run_reaction_player.gd).
##
## The last face is the end card's (services/end_reaction_store.gd), read from
## memory when the pill shows. A face used in play is noted in memory only and
## written once the pill hides (the turn ended or paused), so a tap in play
## writes no file.
##
## The chapter controls dock it (ChapterControls.dock_beside_finish). Nothing
## runs per frame: the screen calls show_cooldown() as its turn is stepped, and
## the pill only redraws when what it shows changes.
const EndReactions = preload("res://presentation/end_reactions.gd")
const Store = preload("res://services/end_reaction_store.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SIZE := Vector2(222, 54)
## The quick half's width; the divider sits just past it.
const QUICK_WIDTH := 68.0
const FACE_SIZE := 42.0
const FILL := Color("f6f1e1")
const BORDER := Color("d6ceb4")
## The cooldown's sweep, and the quick half's pressed tint.
const SWEEP := Color("d9f0e2")
const DIVIDER := Color(0.09, 0.235, 0.227, 0.16)
## React's ink while the cooldown runs.
const SOFT_INK := Color("4d6b66")
## Greyed once the turn's reactions are used up.
const RESTING_ALPHA := 0.55

signal reacted(face: String)

## What the faces card reads of its owner (FacesCard's header and footer).
var pill: Control
var opener: Control
var chosen := ""
var context := {"note": PlayerCopy.RUN_REACTIONS_NOTE}
## The player's settings (left_handed, reduced_motion) and spirit colour.
var settings: Dictionary = {}
var color := "peach":
	set(value):
		color = value
		_show_quick_face()
var faces_card: CanvasLayer
## The quick half and the face it sends.
var quick: Button
var quick_face := Store.DEFAULT_FACE
## The end reactions file the last face is shared with (tests use their own).
var store_path := Store.FILE_PATH
var _quick_icon: Control
var _backdrop: Control
## The cooldown still ahead (1 to 0) and whether the turn's reactions are used up.
var _cooldown := 0.0
var _spent := false

func _init() -> void:
	name = "RunReactions"
	pill = self
	text = PlayerCopy.END_REACTIONS_REACT
	accessibility_name = PlayerCopy.END_REACTIONS_CHOOSE
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_size_override("font_size", 22)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, ControlTheme.INK)
	add_theme_color_override("font_disabled_color", SOFT_INK)
	# The cream face is drawn behind the parts (Back), so the sweep sits under React.
	var plain := StyleBoxEmpty.new()
	plain.content_margin_left = QUICK_WIDTH + 46.0
	plain.content_margin_right = 34
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]: add_theme_stylebox_override(state, plain)
	_backdrop = Back.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop, false, Node.INTERNAL_MODE_FRONT)
	_build_quick()
	# Where the card's pointer aims: React's half.
	opener = Control.new()
	opener.name = "ReactHalf"
	opener.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opener.anchor_bottom = 1.0
	opener.anchor_right = 1.0
	opener.offset_left = QUICK_WIDTH
	add_child(opener, false, Node.INTERNAL_MODE_FRONT)
	pressed.connect(toggle_faces)
	visibility_changed.connect(_on_visibility)

func _build_quick() -> void:
	quick = Button.new()
	quick.name = "QuickReact"
	quick.flat = true
	quick.focus_mode = Control.FOCUS_NONE
	quick.mouse_filter = Control.MOUSE_FILTER_STOP
	quick.anchor_bottom = 1.0
	quick.offset_right = QUICK_WIDTH
	var plain := StyleBoxEmpty.new()
	var lit := ControlTheme.rounded(SWEEP, int(SIZE.y * 0.5))
	lit.corner_radius_top_right = 0
	lit.corner_radius_bottom_right = 0
	for state: String in ["normal", "hover", "disabled", "focus"]: quick.add_theme_stylebox_override(state, plain)
	for state: String in ["pressed", "hover_pressed"]: quick.add_theme_stylebox_override(state, lit)
	_quick_icon = EndReactions.FaceIcon.new(quick_face, color, FACE_SIZE)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.add_child(_quick_icon)
	quick.add_child(centre)
	quick.pressed.connect(func(): choose(quick_face))
	add_child(quick, false, Node.INTERNAL_MODE_FRONT)
	_show_quick_face()

func _ready() -> void:
	# Read once while the screen is built, never in play.
	if Store.last_known(store_path).is_empty(): Store.new(store_path)
	_take_last()

func left_handed() -> bool:
	return bool(settings.get("left_handed", false))

func _color() -> String:
	return color

## The card's pick or the quick half: the face goes to the screen, which
## records and shows it, and becomes the quick face.
func choose(face: String) -> void:
	close_faces()
	if not can_send() or not Store.is_face(face): return
	quick_face = face
	_show_quick_face()
	Store.use_last(face, store_path)
	reacted.emit(face)

func can_send() -> bool:
	return not _spent and _cooldown <= 0.0

## The turn's cooldown still ahead (1 to 0), and whether its reactions are used
## up. Cheap to call every tick: unchanged values change nothing.
func show_cooldown(ratio: float, spent: bool) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(ratio, _cooldown) and spent == _spent: return
	_cooldown = ratio
	_spent = spent
	disabled = not can_send()
	quick.disabled = disabled
	modulate.a = RESTING_ALPHA if _spent else 1.0
	if not can_send(): close_faces()
	queue_redraw()
	_backdrop.queue_redraw()

func toggle_faces() -> void:
	if faces_open():
		close_faces()
		return
	if not can_send() or not is_inside_tree(): return
	faces_card = EndReactions.FacesCard.new()
	faces_card.name = "RunReactionFaces"
	var host := get_canvas_layer_node()
	faces_card.layer = (host.layer if host != null else 0) + 1
	add_child(faces_card, false, Node.INTERNAL_MODE_BACK)
	faces_card.build(self, {"modal": false, "away": true})
	# The chevron turns back down whichever way the card closes.
	faces_card.tree_exited.connect(queue_redraw)
	queue_redraw()

func close_faces() -> void:
	if is_instance_valid(faces_card): faces_card.close()
	faces_card = null
	queue_redraw()

func faces_open() -> bool:
	return is_instance_valid(faces_card) and not faces_card.closing

## Shown: the last face, from memory. Hidden (the turn ended or paused): the
## card closes and a face used in play is written.
func _on_visibility() -> void:
	if is_visible_in_tree():
		_take_last()
		return
	close_faces()
	if Store.has_unsaved(store_path): Store.new(store_path).save_last()

func _take_last() -> void:
	var known := Store.last_known(store_path)
	if not known.is_empty() and known != quick_face:
		quick_face = known
		_show_quick_face()

func _show_quick_face() -> void:
	if not is_instance_valid(_quick_icon): return
	_quick_icon.set_face(quick_face, color)
	quick.accessibility_name = PlayerCopy.END_REACTIONS_QUICK % EndReactions.face_name(quick_face)

## The divider, the speech bubble before React and the chevron after it: down
## while the card is shut, up while it is open (design 4).
func _draw() -> void:
	var mid := size.y * 0.5
	draw_line(Vector2(QUICK_WIDTH + 1.0, 12.0), Vector2(QUICK_WIDTH + 1.0, size.y - 12.0), DIVIDER, 1.5, true)
	var ink := SOFT_INK if disabled and not _spent else ControlTheme.INK
	var bubble := Rect2(Vector2(QUICK_WIDTH + 14.0, mid - 10.0), Vector2(24, 18))
	draw_style_box(ControlTheme.rounded(ink, int(bubble.size.y * 0.5)), bubble)
	draw_colored_polygon(PackedVector2Array([bubble.position + Vector2(4, 14), bubble.position + Vector2(3, 22), bubble.position + Vector2(11, 16)]), ink)
	for dot in range(3): draw_circle(bubble.get_center() + Vector2(-6.0 + 6.0 * dot, 0), 1.7, FILL)
	var chevron := Vector2(size.x - 24, mid)
	var tip := -3.0 if faces_open() else 3.0
	draw_polyline(PackedVector2Array([chevron + Vector2(-6, -tip), chevron + Vector2(0, tip), chevron + Vector2(6, -tip)]), ink, 2.5, true)


## The pill's cream face with its edge, and the cooldown's mint sweep over it,
## drawn behind React's label and the quick face.
class Back extends Control:
	func _init() -> void:
		name = "PillBack"
		show_behind_parent = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var owner_pill := get_parent()
		var radius := int(size.y * 0.5)
		draw_style_box(ControlTheme.rounded(FILL, radius, BORDER), Rect2(Vector2.ZERO, size))
		var ratio: float = owner_pill._cooldown
		if ratio <= 0.0 or owner_pill._spent: return
		var width := size.x * (1.0 - ratio)
		if width < 1.0: return
		var sweep := ControlTheme.rounded(SWEEP, radius)
		# A straight leading edge until the sweep reaches the far end's curve.
		if width < size.x - radius:
			sweep.corner_radius_top_right = 0
			sweep.corner_radius_bottom_right = 0
		var inset := Rect2(Vector2(1, 1), Vector2(minf(width, size.x - 2.0), size.y - 2.0))
		if inset.size.x >= radius: draw_style_box(sweep, inset)
