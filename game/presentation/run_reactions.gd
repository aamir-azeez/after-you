extends Button
## Reactions during a run: the cream React pill beside Finish (concept A). A tap
## opens the shared faces card (presentation/end_reactions.gd FacesCard) up and
## inward, over the world: it never covers the action button or Finish, and the
## joystick, the action button and the camera keep working while it is open. A
## tap on a face sends it (`reacted`) and closes the card; the pill then shows
## the cooldown as a thin bar, and greys out once the turn's reactions are used
## up. The rules and the track are services/run_reaction_track.gd; the screen
## records and shows a reaction (presentation/run_reaction_player.gd).
##
## The chapter controls dock it (ChapterControls.dock_beside_finish). Nothing
## runs per frame: the screen calls show_cooldown() as its turn is stepped, and
## the pill only redraws when what it shows changes.
const EndReactions = preload("res://presentation/end_reactions.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SIZE := Vector2(168, 54)
const FILL := Color("f6f1e1")
const BORDER := Color("d6ceb4")
const BAR := Color("4f9d89")
## Greyed while it cannot send.
const RESTING_ALPHA := 0.55

signal reacted(face: String)

## What the faces card reads of its owner (FacesCard's header).
var pill: Control
var opener: Control
var chosen := ""
var context := {}
## The player's settings (left_handed, reduced_motion) and spirit colour.
var settings: Dictionary = {}
var color := "peach"
var faces_card: CanvasLayer
## The cooldown still ahead (1 to 0) and whether the turn's reactions are used up.
var _cooldown := 0.0
var _spent := false

func _init() -> void:
	name = "RunReactions"
	pill = self
	opener = self
	text = PlayerCopy.END_REACTIONS_REACT
	accessibility_name = PlayerCopy.END_REACTIONS_CHOOSE
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_size_override("font_size", 22)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, ControlTheme.INK)
	var look := ControlTheme.rounded(FILL, int(SIZE.y * 0.5), BORDER)
	look.content_margin_left = 54
	look.content_margin_right = 34
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]: add_theme_stylebox_override(state, look)
	pressed.connect(toggle_faces)
	visibility_changed.connect(func(): if not is_visible_in_tree(): close_faces())

func left_handed() -> bool:
	return bool(settings.get("left_handed", false))

func _color() -> String:
	return color

## The card's pick: the face goes to the screen, which records and shows it.
func choose(face: String) -> void:
	close_faces()
	if can_send(): reacted.emit(face)

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
	modulate.a = 1.0 if can_send() else RESTING_ALPHA
	if not can_send(): close_faces()
	queue_redraw()

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

func close_faces() -> void:
	if is_instance_valid(faces_card): faces_card.close()
	faces_card = null

func faces_open() -> bool:
	return is_instance_valid(faces_card) and not faces_card.closing

## The speech bubble before the label, the up chevron after it, and the
## cooldown's bar along the bottom while it runs.
func _draw() -> void:
	var mid := size.y * 0.5
	var bubble := Rect2(Vector2(22, mid - 11), Vector2(24, 18))
	draw_style_box(_outline(int(bubble.size.y * 0.5)), bubble)
	draw_colored_polygon(PackedVector2Array([bubble.position + Vector2(5, 16), bubble.position + Vector2(4, 23), bubble.position + Vector2(11, 17)]), ControlTheme.INK)
	var chevron := Vector2(size.x - 26, mid)
	draw_polyline(PackedVector2Array([chevron + Vector2(-6, 3), chevron + Vector2(0, -3), chevron + Vector2(6, 3)]), ControlTheme.INK, 2.5, true)
	if _cooldown > 0.0 and not _spent:
		var track := Rect2(Vector2(22, size.y - 9), Vector2(size.x - 44, 4))
		draw_rect(track, Color(BAR, 0.25))
		draw_rect(Rect2(track.position, Vector2(track.size.x * (1.0 - _cooldown), track.size.y)), BAR)

static func _outline(radius: int) -> StyleBoxFlat:
	var look := ControlTheme.rounded(Color(0, 0, 0, 0), radius, ControlTheme.INK)
	look.set_border_width_all(2)
	look.draw_center = false
	return look
