extends RefCounted
## The keepsake card's words (the box under Home's islands): one line that
## says what the selected keepsake still needs, in plain words with its own
## piece names, and the count line. Read from the entries and states of
## services/home_keepsake_states.gd; every line any keepsake can show is listed
## by every_line(), so the box keeps one height in every state.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const TOGETHER_ICON = preload("res://assets/ui/social/users.svg")
const TOGETHER_LIT := UiTokens.TOGETHER
const GOLD := Color("efba73")
const DIM := Color(0.71, 0.84, 0.78, 0.38)
const EARLIER := "earlier"

## The line for one entry and its state. `together_hard`: the server hosts
## together Hard rooms (the gold top is only asked for then).
static func line(entry: Dictionary, item: Dictionary, together_hard: bool) -> String:
	var copy: Dictionary = entry.keepsake.copy
	var stages: Array = item.get("stages", [])
	if entry.id == EARLIER: return _lantern_line(entry, item, copy)
	match str(item.get("look", "none")):
		"next": return PlayerCopy.KEEPSAKE_NEXT % entry.title
		"started": return PlayerCopy.KEEPSAKE_STARTED % [_count(stages, ANY), stages.size(), entry.title]
		"none": return PlayerCopy.KEEPSAKE_NEXT % entry.title
	if entry.together and not item.together:
		var with_friend := _count(stages, FRIEND)
		if with_friend > 0 and with_friend < stages.size(): return PlayerCopy.KEEPSAKE_FRIEND_PART % [with_friend, stages.size()]
		return PlayerCopy.KEEPSAKE_WANTS_TOGETHER % copy.together
	if entry.hard and not item.hard:
		return (PlayerCopy.KEEPSAKE_WANTS_HARD_TOGETHER if item.together else PlayerCopy.KEEPSAKE_WANTS_HARD) % copy.hard
	if entry.hard and entry.together and together_hard and not item.top:
		return PlayerCopy.KEEPSAKE_WANTS_TOP % copy.top
	return PlayerCopy.KEEPSAKE_DONE % str(copy.action).to_lower()

static func _lantern_line(entry: Dictionary, item: Dictionary, copy: Dictionary) -> String:
	var count: int = entry.places.size()
	if not item.base: return PlayerCopy.KEEPSAKE_NEXT_EARLIER
	if not item.together: return PlayerCopy.KEEPSAKE_LANTERNS_WANT_TOGETHER % [item.lit, count, copy.together]
	if item.lit < count: return PlayerCopy.KEEPSAKE_LANTERNS_LIT % [item.lit, count, copy.together]
	return PlayerCopy.KEEPSAKE_LANTERNS_DONE % str(copy.action).to_lower()

## Stages done with a friend (FRIEND), or in either mode (ANY).
const ANY := -1
const FRIEND := 1
static func _count(stages: Array, mode: int) -> int:
	var done := 0
	for stage: Array in stages:
		if (stage[0] or stage[1]) if mode == ANY else stage[mode]: done += 1
	return done

## Every line the card can show for these entries, with the longest values
## filled in, so the box is measured once for all of them.
static func every_line(entries: Array) -> Array[String]:
	var lines: Array[String] = []
	for entry: Dictionary in entries:
		var copy: Dictionary = entry.keepsake.copy
		var count: int = entry.places.size()
		if entry.id == EARLIER:
			lines.append_array([PlayerCopy.KEEPSAKE_NEXT_EARLIER, PlayerCopy.KEEPSAKE_LANTERNS_WANT_TOGETHER % [count, count, copy.together],
				PlayerCopy.KEEPSAKE_LANTERNS_LIT % [count - 1, count, copy.together], PlayerCopy.KEEPSAKE_LANTERNS_DONE % str(copy.action).to_lower()])
			continue
		lines.append_array([PlayerCopy.KEEPSAKE_NEXT % entry.title, PlayerCopy.KEEPSAKE_STARTED % [maxi(1, count - 1), count, entry.title],
			PlayerCopy.KEEPSAKE_FRIEND_PART % [maxi(1, count - 1), count], PlayerCopy.KEEPSAKE_WANTS_TOGETHER % copy.together,
			PlayerCopy.KEEPSAKE_WANTS_HARD % copy.hard, PlayerCopy.KEEPSAKE_WANTS_HARD_TOGETHER % copy.hard,
			PlayerCopy.KEEPSAKE_WANTS_TOP % copy.top, PlayerCopy.KEEPSAKE_DONE % str(copy.action).to_lower()])
	return lines

## "Keepsakes N / T", then "Upgrades u / U" once a keepsake is earned, then
## "Hard d / H" once a Hard play is open.
static func count_line(result: Dictionary) -> String:
	var parts: Array[String] = [PlayerCopy.KEEPSAKE_COUNT % result.keepsakes]
	if int(result.keepsakes[0]) > 0: parts.append(PlayerCopy.KEEPSAKE_UPGRADE_COUNT % result.upgrades)
	if int(result.hard[1]) > 0 and result.hard_open: parts.append(PlayerCopy.KEEPSAKE_HARD_COUNT % result.hard)
	return " · ".join(parts)

## The longest count line these entries can show, to measure the box with.
static func widest_count(entries: Array) -> String:
	var keepsakes := entries.size()
	var upgrades := 0
	var hard := 0
	for entry: Dictionary in entries:
		upgrades += int(entry.together) + int(entry.hard) * 2
		hard += int(entry.hard)
	return count_line({"keepsakes": [keepsakes, keepsakes], "upgrades": [upgrades, upgrades], "hard": [hard, hard], "hard_open": true})

## The card's three upgrade marks, side by side: the two people for Together,
## the Hard peak for Hard and a star for Together Hard; lit once earned, faint
## while still to earn, hidden where a keepsake has no such upgrade.
static func marks_row(side: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "KeepsakeUpgrades"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	var together := TextureRect.new()
	together.name = "KeepsakeTogether"
	together.texture = TOGETHER_ICON
	together.tooltip_text = PlayerCopy.KEEPSAKE_MARK_TOGETHER
	together.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	together.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	together.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	together.custom_minimum_size = Vector2(side, side)
	together.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(together)
	var hard := HardModeView.mark(HardMode.SOLO, HardMode.OPEN, side)
	hard.name = "KeepsakeHard"
	row.add_child(hard)
	var top := StarMark.new()
	top.name = "KeepsakeTop"
	top.custom_minimum_size = Vector2(side, side)
	top.tooltip_text = PlayerCopy.KEEPSAKE_MARK_TOP
	row.add_child(top)
	return row

## Shows the selected keepsake's upgrades (HomeKeepsakeLayer.selected_item()).
static func show_marks(row: Control, item: Dictionary) -> void:
	var together := row.get_node("KeepsakeTogether") as TextureRect
	together.visible = item.get("has_together", false)
	together.self_modulate = TOGETHER_LIT if item.get("together", false) else DIM
	var hard := row.get_node("KeepsakeHard") as HardModeView.Mark
	hard.visible = item.get("has_hard", false)
	hard.set_look(HardMode.DONE if item.get("hard", false) else HardMode.OPEN)
	hard.tooltip_text = PlayerCopy.KEEPSAKE_MARK_HARD
	var top := row.get_node("KeepsakeTop") as StarMark
	top.visible = item.get("top_offered", false)
	top.set_lit(item.get("top", false))

## A five-point star: gold once Together Hard is earned, a faint outline before.
class StarMark extends Control:
	var lit := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_lit(value: bool) -> void:
		if lit == value: return
		lit = value
		queue_redraw()

	func _draw() -> void:
		var middle := size * 0.5
		var outer := minf(size.x, size.y) * 0.46
		var points := PackedVector2Array()
		for i in range(10):
			var angle := -PI / 2.0 + i * PI / 5.0
			points.append(middle + Vector2(cos(angle), sin(angle)) * (outer if i % 2 == 0 else outer * 0.45))
		if lit:
			draw_colored_polygon(points, GOLD)
		else:
			points.append(points[0])
			draw_polyline(points, DIM, maxf(1.5, size.x * 0.07), true)
