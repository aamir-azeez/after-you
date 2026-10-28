extends Control
## The moment this player's run is confirmed in a chapter board's top 10
## (services/leaderboard_placings.gd): the pair, the chapter, the place and the
## time, held until View board or Back. Four tiers, each one row of TIERS:
##   top_ten  a card with the blue Top 10 rosette between the pips, about 1.0 s
##   third    a wider card, a bronze stage and place mark, about 1.6 s
##   second   an open mint arch with a silver place mark, about 2.1 s
##   first    gold curves round the pair, and gold spreading from base to tip
##            of both leaves, about 2.8 s
## pose() gives every moving value at a moment, so a tier's motion is data plus
## one pure function, and its last moment is the final pose.
##
## The pips are the real ones in their outfits: this player's own look
## (services/own_look.gd) beside their partner's as services/turn_looks.gd last
## heard it. Both stand in one small 3D view lit by kit/pip_stage.gd's studio.
## It draws every frame only while the pair moves, then holds its last frame
## and draws no more. The Top 10 rosette is the real ribbon's mesh
## (pip_wear/top_ten_ribbon.gd), and on first place each leaf turns to the
## Gold leaf cosmetic's own material and then wears the cosmetic itself
## (pip_wear/gold_leaf.gd). The stars, leaves, arch, curves and marks are drawn
## here with the canvas: no image assets.
##
## Under Reduce motion it fades in over REDUCED_FADE seconds straight into the
## final pose, the view drawn once. Everything is made once when it opens and
## freed with it; while it moves it asks the frame policy for full rate.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const Stage = preload("res://presentation/kit/pip_stage.gd")
const Preview = preload("res://presentation/kit/spirit_preview.gd")
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const PipOutfit = preload("res://presentation/pip_outfit.gd")
const GoldLeaf = preload("res://presentation/pip_wear/gold_leaf.gd")
const Ribbon = preload("res://presentation/pip_wear/top_ten_ribbon.gd")
const Look = preload("res://presentation/spirit_look.gd")
const OwnLook = preload("res://services/own_look.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const EmptyStateArt = preload("res://presentation/empty_state_art.gd")
const SPREAD_SHADER = preload("res://presentation/leaderboard_gold_spread.gdshader")

## The celebration's group: Home's cards wait while one is up.
const GROUP := &"leaderboard_celebration"
const NODE_NAME := "LeaderboardCelebration"
## Seconds of the fade in, with or without Reduce motion.
const REDUCED_FADE := 0.2
## The pair's world as the view shows it: metres of height the stage's height
## covers, where the camera looks, and how far above that it stands.
const FRAME_HEIGHT := 1.36
const LOOK_Y := 0.48
const CAMERA_LIFT := 0.1
## Each pip turns this far toward the other (radians).
const FACING := 0.32
const RIBBON_Y := 0.68
const RIBBON_SCALE := 1.6
const BACKDROP := Color("0f3433")
const CARD_FILL := Color("123936")
const CARD_EDGE := Color("466e63")
const BRONZE := Color("c27c4f")
const BRONZE_LIGHT := Color("e3a273")
const BRONZE_DARK := Color("8f5536")
const SILVER := Color("d3ded9")
const SILVER_RIM := Color("9fb5ad")
const STAR_COUNT := 26
## Seconds into first place when each leaf becomes the Gold leaf cosmetic: the
## glint's brightest moment (pose() glint).
const HANDOVER := 1.55
## The second place arch's height, in stage heights from the pair's floor.
const ARCH_RISE := 0.9

## The tiers. `seconds` of motion; `frame` the setting (card, arch, gold);
## `height` of the pair on screen and `aspect` of their view; `gap` metres
## from the middle to each pip; `width` of the stage; `card` width when framed;
## `leaves` the loose leaves as [x, y, turn] in stage heights from the pair's
## floor (x out from the middle, y up), and `drift` where they move to.
const TIERS := {
	Placings.TOP_TEN: {"seconds": 1.0, "frame": "card", "card": 576, "width": 500, "height": 210, "aspect": 1.9, "gap": 0.56, "mark": "ribbon", "leaves": [], "drift": Vector2.ZERO},
	Placings.THIRD: {"seconds": 1.6, "frame": "card", "card": 772, "width": 640, "height": 260, "aspect": 1.5, "gap": 0.4, "mark": "bronze", "leaves": [[-0.86, 0.12, -0.5], [-0.74, 0.03, -1.1], [0.74, 0.03, 1.1], [0.86, 0.12, 0.5]], "drift": Vector2(0.04, 0.22)},
	Placings.SECOND: {"seconds": 2.1, "frame": "arch", "width": 900, "height": 300, "aspect": 1.5, "gap": 0.4, "mark": "silver", "leaves": [[-0.66, 0.62, -0.9], [-0.86, 0.36, -1.3], [-0.6, 0.16, -1.8], [0.6, 0.16, 1.8], [0.86, 0.36, 1.3], [0.66, 0.62, 0.9]], "drift": Vector2(0.16, 0.04)},
	Placings.FIRST: {"seconds": 2.8, "frame": "gold", "width": 900, "height": 300, "aspect": 1.5, "gap": 0.4, "mark": "gold", "leaves": [[-0.94, 0.9, -0.7], [-1.04, 0.46, -1.2], [-0.84, 0.1, -1.7], [0.84, 0.1, 1.7], [1.04, 0.46, 1.2], [0.94, 0.9, 0.7]], "drift": Vector2(0.0, -0.06)},
}

## View board was pressed: the board to show.
signal view_board(board: String)
signal closed

## {entry_id, board, rank, ticks, names, gold_leaf, partner} (leaderboard_placings.gd).
var placing: Dictionary = {}
var tier := ""
var reduced := false
var _spec: Dictionary = {}
var _gold := false
var _time := 0.0
var _closing := false
var _done := false
var _content: Control
var _stage: Control
var _back: Control
var _front: Control
var _mark: Control
var _view: SubViewport
var _camera: Camera3D
var _pivots: Array[Node3D] = []
var _spirits: Array[Node3D] = []
var _ribbon: Node3D
var _spreads: Array[ShaderMaterial] = []
var _glints: Array[MeshInstance3D] = []
var _dressed: Array[RefCounted] = []
var _floor := Vector2.ZERO
var _ribbon_at := Vector2.ZERO
var _pose: Dictionary = {}

## Opens the oldest placing waiting for `owner` over `parent`, marking it shown
## at once so it never shows twice; null when none waits.
static func show_next(parent: Control, owner: String, reduced_motion: bool) -> Control:
	var waiting: Dictionary = Placings.shared().next(owner)
	if waiting.is_empty(): return null
	Placings.shared().mark_shown(owner, str(waiting.entry_id))
	return open(parent, waiting, reduced_motion)

## A celebration for `confirmed` over `parent`; null for a place outside the top 10.
static func open(parent: Control, confirmed: Dictionary, reduced_motion: bool) -> Control:
	var kind := Placings.tier(int(confirmed.get("rank", 0)))
	if kind.is_empty(): return null
	var made: Control = load("res://presentation/leaderboard_celebration.gd").new()
	made.placing = confirmed.duplicate(true)
	made.tier = kind
	made.reduced = reduced_motion
	parent.add_child(made)
	return made

## Whether a celebration is up under `parent`.
static func showing(parent: Node) -> bool:
	for child: Node in parent.get_children():
		if child.is_in_group(GROUP) and not child.is_queued_for_deletion(): return true
	return false

## Every moving value of `kind` at `seconds` from the start (0 to 1 unless
## said): lift (metres), roll toward the partner and bow (radians), ribbon,
## sparkles, leaves (their path), arch, mark, gold (the spread), glint, curves.
## Past the tier's length it is the final pose.
static func pose(kind: String, seconds: float) -> Dictionary:
	var t := clampf(seconds, 0.0, float(TIERS[kind].seconds))
	var result := {"lift": 0.0, "roll": 0.0, "bow": 0.0, "ribbon": 1.0, "sparkles": 1.0, "leaves": 1.0, "arch": 1.0, "mark": 1.0, "gold": 1.0, "glint": 0.0, "curves": 1.0}
	match kind:
		Placings.TOP_TEN:
			result.lift = 0.05 * _pulse(t, 0.0, 0.45)
			result.ribbon = _ease(t, 0.1, 0.7)
			result.sparkles = _ease(t, 0.65, 1.0)
		Placings.THIRD:
			result.roll = 0.1 * _ease(t, 0.0, 0.45) - 0.05 * _ease(t, 1.05, 1.6)
			result.bow = 0.16 * _pulse(t, 0.45, 1.05)
			result.leaves = _span(t, 0.3, 1.6)
			result.mark = _ease(t, 0.0, 0.6)
		Placings.SECOND:
			result.arch = _ease(t, 0.0, 1.3)
			result.roll = 0.12 * _pulse(t, 0.5, 1.8)
			result.leaves = _span(t, 0.7, 2.1)
			result.mark = _ease(t, 1.0, 1.5)
		Placings.FIRST:
			result.roll = 0.07 * _ease(t, 0.0, 0.6)
			result.gold = _span(t, 0.6, 1.4)
			result.glint = _pulse(t, 1.25, 1.85)
			result.curves = _ease(t, 1.0, 2.2)
			result.leaves = _ease(t, 1.8, 2.8)
	return result

## Seconds since it opened, and whether it has reached its final pose.
func elapsed() -> float:
	return _time

func settled() -> bool:
	return _done

## The tier's length in seconds.
func seconds() -> float:
	return float(_spec.get("seconds", 0.0))

## Back (Android Back, Escape, or the page beneath forwarding it): leaves it.
func go_back() -> void:
	close()

func close() -> void:
	if _closing: return
	_closing = true
	set_process(false)
	queue_free()
	closed.emit()

func _ready() -> void:
	name = NODE_NAME
	add_to_group(GROUP)
	_spec = TIERS[tier]
	_gold = tier == Placings.FIRST and bool(placing.get("gold_leaf", false))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = SettingsKit.font(600)
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", UiTokens.CREAM)
	ThemeRules.install_buttons(theme)
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	SafeArea.bleed(backdrop)
	var stars := Control.new()
	stars.name = "CelebrationStars"
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.draw.connect(func() -> void: _draw_stars(stars))
	add_child(stars)
	SafeArea.bleed(stars)
	_content = CenterContainer.new()
	_content.name = "CelebrationContent"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_content.add_child(_build_column())
	_build_pair()
	SafeArea.watch(self, _layout)
	_layout()
	modulate.a = 0.0
	_step(seconds() if reduced else 0.0)
	_draw_view()
	if not reduced:
		var frames: Node = get_tree().root.get_node_or_null("FramePolicy")
		if frames != null and frames.has_method("wake"): frames.wake(int((seconds() + REDUCED_FADE) * 1000.0))

func _layout() -> void:
	if not is_instance_valid(_content): return
	SafeArea.inset(_content, SafeArea.rect(get_viewport()))

func _input(event: InputEvent) -> void:
	if not _closing and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()

func _process(delta: float) -> void:
	if _closing: return
	_time += maxf(delta, 0.0)
	modulate.a = clampf(_time / REDUCED_FADE, 0.0, 1.0)
	if reduced:
		if _time >= REDUCED_FADE: set_process(false)
		return
	for spirit: Node3D in _spirits: spirit.advance_motion(Vector3.ZERO, maxf(delta, 0.001), false)
	_step(_time)
	_draw_view()
	if _done and _time >= REDUCED_FADE: set_process(false)

## Poses everything for `seconds` from the start.
func _step(seconds_in: float) -> void:
	_pose = pose(tier, seconds_in)
	_done = seconds_in >= seconds()
	var gap := float(_spec.gap)
	for index in range(_pivots.size()):
		var side := -1.0 if index == 0 else 1.0
		_pivots[index].position = Vector3(side * gap, float(_pose.lift), 0.0)
		_pivots[index].rotation = Vector3(float(_pose.bow), 0.0, side * float(_pose.roll))
	if is_instance_valid(_ribbon):
		var settle := float(_pose.ribbon)
		_ribbon.position = Vector3(0.0, RIBBON_Y + 0.2 * (1.0 - settle), 0.15)
		_ribbon.rotation.z = lerpf(0.5, 0.14, settle)
		_ribbon.scale = Vector3.ONE * RIBBON_SCALE * maxf(settle, 0.001)
	if _gold: _spread(float(_pose.gold), float(_pose.glint), seconds_in >= HANDOVER or _done)
	for layer: Control in [_back, _front, _mark]:
		if is_instance_valid(layer): layer.queue_redraw()

## The leaves' gold at `amount` of the spread: the spread material, and from
## `worn` (the glint at its brightest, so the cosmetic's own sparkles come in
## under it rather than popping) the Gold leaf cosmetic itself.
func _spread(amount: float, glint: float, worn: bool) -> void:
	for halo: MeshInstance3D in _glints:
		halo.visible = glint > 0.0
		(halo.material_override as StandardMaterial3D).albedo_color.a = GoldLeaf.GLOW_STRENGTH * 1.5 * glint
	if not worn:
		for material: ShaderMaterial in _spreads:
			material.set_shader_parameter("progress", amount)
			material.set_shader_parameter("glint", glint)
		return
	if not _dressed.is_empty(): return
	for spirit: Node3D in _spirits:
		var look: RefCounted = PipOutfit.dress(spirit, {})
		look.apply_art(GoldLeaf)
		_dressed.append(look)
	_spreads.clear()

func _draw_view() -> void:
	if is_instance_valid(_view): _view.render_target_update_mode = SubViewport.UPDATE_ONCE

# --- Building -------------------------------------------------------------

func _build_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "CelebrationColumn"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	var rank := int(placing.rank)
	var place := PlayerCopy.LEADERBOARD_PLACE_TITLE % ordinal(rank)
	if _spec.mark == "bronze":
		_mark = _medal_holder()
		column.add_child(_mark)
	var title := _text(PlayerCopy.LEADERBOARD_TOP_TEN_TITLE if tier == Placings.TOP_TEN else place, 56 if _spec.frame == "card" else 64, UiTokens.CREAM, true)
	title.name = "CelebrationTitle"
	column.add_child(title)
	var chapter_key := Runs.chapter_of(str(placing.board))
	if not chapter_key.is_empty():
		var chapter := _text(RoomChapterTitle.title(chapter_key, str(Registry.descriptor(chapter_key).get("title", ""))), 26, UiTokens.MUTED)
		chapter.name = "CelebrationChapter"
		column.add_child(chapter)
	if tier == Placings.TOP_TEN: column.add_child(_place_pill(place))
	_stage = Control.new()
	_stage.name = "CelebrationStage"
	_stage.custom_minimum_size = Vector2(float(_spec.width), float(_spec.height))
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_stage)
	var details: Control = column
	if _spec.frame == "gold":
		details = _details_panel()
		column.add_child(details.get_parent())
	var names: Variant = placing.get("names")
	var pair := _text(PlayerCopy.LEADERBOARD_NAMES % [names[0], names[1]] if names is Array else PlayerCopy.LEADERBOARD_A_PAIR, 26, UiTokens.CREAM)
	pair.name = "CelebrationPair"
	details.add_child(pair)
	var time := _text(Runs.time_text(int(placing.ticks)), 50, UiTokens.CREAM, true)
	time.name = "CelebrationTime"
	details.add_child(time)
	if _gold:
		var gold := _text(PlayerCopy.LEADERBOARD_GOLD_LEAVES, 20, UiTokens.MUTED)
		gold.name = "CelebrationGoldLeaves"
		details.add_child(gold)
	var view := Button.new()
	view.name = "CelebrationViewBoard"
	view.text = PlayerCopy.LEADERBOARD_VIEW_BOARD
	view.custom_minimum_size = Vector2(380, 60)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.add_theme_font_override("font", SettingsKit.font(700))
	view.add_theme_font_size_override("font_size", 24)
	view.pressed.connect(_view_board)
	column.add_child(view)
	if _spec.frame != "card": return column
	var card := PanelContainer.new()
	card.name = "CelebrationCard"
	card.custom_minimum_size.x = float(_spec.card)
	var style := ThemeRules.rounded(CARD_FILL, 24, UiTokens.MINT if tier == Placings.TOP_TEN else CARD_EDGE)
	style.set_border_width_all(2)
	ThemeRules.padded(style, 32.0, 22.0)
	card.add_theme_stylebox_override("panel", style)
	card.add_child(column)
	return card

func _view_board() -> void:
	if _closing: return
	var board := str(placing.get("board", ""))
	close()
	view_board.emit(board)

## The pair in one view: both pips, the rosette on Top 10, the leaves ready to
## turn gold on first place.
func _build_pair() -> void:
	var height := float(_spec.height)
	var pips := TextureRect.new()
	pips.name = "CelebrationPips"
	pips.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pips.stretch_mode = TextureRect.STRETCH_SCALE
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := height * float(_spec.aspect)
	pips.anchor_left = 0.5
	pips.anchor_right = 0.5
	pips.offset_left = -width * 0.5
	pips.offset_right = width * 0.5
	pips.anchor_bottom = 1.0
	_back = _layer("CelebrationBack", _draw_back)
	_stage.add_child(_back)
	_stage.add_child(pips)
	_front = _layer("CelebrationFront", _draw_front)
	_stage.add_child(_front)
	_view = SubViewport.new()
	_view.name = "CelebrationView"
	_view.size = Vector2i(Vector2(width, height) * Preview.RENDER_SCALE)
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	var pair := Node3D.new()
	pair.name = "Pair"
	_camera = Stage.build(_view, pair, {})
	var distance := FRAME_HEIGHT * 0.5 / tan(deg_to_rad(_camera.fov * 0.5))
	_camera.look_at_from_position(Vector3(0.0, LOOK_Y + CAMERA_LIFT, distance), Vector3(0.0, LOOK_Y, 0.0))
	var partner := str(placing.get("partner", ""))
	var looks: Array[Dictionary] = [OwnLook.outfit(), TurnLooks.shared().member(partner) if not partner.is_empty() else {}]
	var colours: Array[Color] = [OwnLook.color(), Look.MINT]
	for index in range(2):
		var outfit: Dictionary = looks[index].duplicate()
		# First place gilds each pip's own leaf: a leaf item comes off for it.
		if _gold: outfit.erase("leaf")
		var pivot := Node3D.new()
		pair.add_child(pivot)
		var spirit: Node3D = Stage.pip(colours[index], outfit)
		var yaw := FACING if index == 0 else -FACING
		spirit.facing_target = yaw
		spirit.facing.rotation.y = yaw
		pivot.add_child(spirit)
		spirit.advance_motion(Vector3.ZERO, 0.001, true)
		_pivots.append(pivot)
		_spirits.append(spirit)
		if _gold: _gild(spirit)
	if _spec.mark == "ribbon":
		_ribbon = Node3D.new()
		_ribbon.name = "Ribbon"
		var rosette := MeshInstance3D.new()
		rosette.mesh = Ribbon.rosette()
		rosette.material_override = Kit.vertex_material()
		_ribbon.add_child(rosette)
		pair.add_child(_ribbon)
	pips.texture = _view.get_texture()
	_floor = _on_stage(Vector3(0.0, 0.0, 0.08), width, height)
	_ribbon_at = _on_stage(Vector3(0.0, RIBBON_Y, 0.15), width, height)

## Where a point of the pair's world lands on the stage.
func _on_stage(point: Vector3, width: float, height: float) -> Vector2:
	var seen := _camera.unproject_position(point) / Preview.RENDER_SCALE
	return Vector2(float(_spec.width) * 0.5 - width * 0.5 + seen.x, seen.y) if is_finite(seen.x) else Vector2(float(_spec.width) * 0.5, height * 0.94)

## Readies a pip's leaf to turn gold: the spread material over its own leaf
## (or, under Reduce motion, the Gold leaf at once) and a glint beside it.
func _gild(spirit: Node3D) -> void:
	var leaf: MeshInstance3D = spirit.sprout
	if reduced:
		var look: RefCounted = PipOutfit.dress(spirit, {})
		look.apply_art(GoldLeaf)
		_dressed.append(look)
		return
	var own: Material = leaf.material_override
	var gold := GoldLeaf.material()
	var shape := leaf.mesh.get_aabb() if leaf.mesh != null else AABB(Vector3.ZERO, Vector3(0.1, Look.LEAF_LENGTH, 0.1))
	var material := ShaderMaterial.new()
	material.shader = SPREAD_SHADER
	material.set_shader_parameter("leaf_color", own.albedo_color if own is StandardMaterial3D else Look.LEAF)
	material.set_shader_parameter("leaf_roughness", own.roughness if own is StandardMaterial3D else 0.9)
	material.set_shader_parameter("gold_color", gold.albedo_color)
	material.set_shader_parameter("gold_roughness", gold.roughness)
	material.set_shader_parameter("gold_glow", gold.emission)
	material.set_shader_parameter("gold_glow_energy", gold.emission_energy_multiplier)
	material.set_shader_parameter("base_y", shape.position.y)
	material.set_shader_parameter("tip_y", shape.end.y)
	leaf.material_override = material
	_spreads.append(material)
	var halo := Kit.halo(GoldLeaf.GLOW_SIZE, GoldLeaf.GLOW, 0.0)
	halo.name = "Glint"
	halo.position = Vector3(0.0, shape.end.y * 0.6, 0.03)
	halo.visible = false
	leaf.add_child(halo)
	_glints.append(halo)

func _layer(node_name: String, painter: Callable) -> Control:
	var layer := Control.new()
	layer.name = node_name
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(func() -> void: painter.call(layer))
	return layer

func _details_panel() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "CelebrationDetails"
	panel.custom_minimum_size.x = 570
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := ThemeRules.rounded(Color(CARD_FILL, 0.9), 18, CARD_EDGE)
	ThemeRules.padded(style, 24.0, 10.0)
	panel.add_theme_stylebox_override("panel", style)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	panel.add_child(inner)
	return inner

func _place_pill(text: String) -> Control:
	var holder := CenterContainer.new()
	var pill := PanelContainer.new()
	pill.name = "CelebrationPlace"
	var style := ThemeRules.rounded(UiTokens.MINT, 18)
	ThemeRules.padded(style, 22.0, 4.0)
	pill.add_theme_stylebox_override("panel", style)
	pill.add_child(_text(text, 24, UiTokens.INK, false, 800))
	holder.add_child(pill)
	return holder

## The third place mark above the card's title: a bronze medal with leaves.
func _medal_holder() -> Control:
	var holder := Control.new()
	holder.name = "CelebrationMark"
	holder.custom_minimum_size = Vector2(0, 76)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.draw.connect(func() -> void:
		# It settles down into place as it appears, without turning.
		var shown := float(_pose.get("mark", 1.0))
		var middle := Vector2(holder.size.x * 0.5, 38.0 - 14.0 * (1.0 - shown))
		for side: float in [-1.0, 1.0]:
			for step in range(3):
				var ink: Color = BRONZE_LIGHT if step % 2 == 0 else UiTokens.CREAM
				_leaf(holder, middle + Vector2(side * (52.0 + step * 13.0), 6.0 - step * 15.0), 20.0, side * (0.9 + step * 0.35), Color(ink, shown))
		_medal(holder, middle, 33.0, Color(BRONZE, shown), Color(BRONZE_LIGHT, shown), "3"))
	return holder

func _text(value: String, font_size: int, ink: Color, heading: bool = false, weight: int = 600) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", SettingsKit.font(600 if heading else weight, heading))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## "8th".
static func ordinal(rank: int) -> String:
	return PlayerCopy.LEADERBOARD_ORDINALS[rank - 1] if rank >= 1 and rank <= PlayerCopy.LEADERBOARD_ORDINALS.size() else str(rank)

# --- Drawing --------------------------------------------------------------

## Behind the pair: the bronze stage, the arch and its mark, the gold curves.
func _draw_back(layer: Control) -> void:
	var unit := float(_spec.height)
	match _spec.frame:
		"card":
			if _spec.mark == "bronze":
				_ellipse(layer, _floor + Vector2(0, unit * 0.045), Vector2(unit * 1.02, unit * 0.1), BRONZE_DARK)
				_ellipse(layer, _floor, Vector2(unit * 1.0, unit * 0.085), BRONZE)
				_ellipse(layer, _floor + Vector2(0, -unit * 0.012), Vector2(unit * 0.9, unit * 0.055), BRONZE_LIGHT.lerp(BRONZE, 0.55))
		"arch":
			_ellipse(layer, _floor + Vector2(0, unit * 0.02), Vector2(float(_spec.width) * 0.5, unit * 0.09), Color(0, 0, 0, 0.14))
			var radii := Vector2(float(_spec.width) * 0.47, unit * ARCH_RISE)
			var reach := 90.0 * float(_pose.get("arch", 1.0))
			_arc(layer, _floor, radii, 180.0, 180.0 - reach, Color(UiTokens.MINT, 0.75), 4.0)
			_arc(layer, _floor, radii, 0.0, reach, Color(UiTokens.MINT, 0.75), 4.0)
		"gold":
			_ellipse(layer, _floor, Vector2(unit * 1.25, unit * 0.11), Color(UiTokens.MINT, 0.85))
			var grow := float(_pose.get("curves", 1.0))
			var radii := Vector2(unit * 1.12, unit * 0.62)
			var centre := _floor + Vector2(0, -unit * 0.45)
			for side: float in [-1.0, 1.0]:
				var start := 245.0 if side < 0 else -65.0
				var finish := 128.0 if side < 0 else 52.0
				var end := lerpf(start, finish, grow)
				_arc(layer, centre, radii, start, end, Color(GoldLeaf.GLOW, grow), 5.0)
				for share: float in [0.4, 0.66, 0.9]:
					if share > grow: continue
					var at := _on_arc(centre, radii, lerpf(start, finish, share))
					_leaf(layer, at + Vector2(side * unit * 0.05, 0), unit * 0.09, side * (0.8 + share), GoldLeaf.GOLD.lerp(GoldLeaf.GLOW, share))

## In front of the pair: the sparkles, the loose leaves and the silver mark.
func _draw_front(layer: Control) -> void:
	var unit := float(_spec.height)
	if _spec.mark == "ribbon":
		var shine := float(_pose.get("sparkles", 1.0))
		for side: float in [-1.0, 1.0]:
			_sparkle(layer, _ribbon_at + Vector2(side * unit * 0.36, -unit * 0.1), unit * 0.045, Color(UiTokens.CREAM, shine))
	var path := float(_pose.get("leaves", 1.0))
	var settles: bool = _spec.frame == "gold"
	# Drifting leaves rise and fade; first place's settle and stay.
	var alpha := path if settles else sin(PI * path)
	if alpha > 0.01:
		var drift: Vector2 = _spec.drift
		for spot: Array in _spec.leaves:
			var side := signf(float(spot[0]))
			var move := Vector2(side * drift.x, -drift.y) * (path - 1.0 if settles else path)
			var at := _floor + Vector2(float(spot[0]), -float(spot[1])) * unit + move * unit
			var ink: Color = GoldLeaf.GOLD if settles else BRONZE_LIGHT if _spec.mark == "bronze" else UiTokens.MINT
			_leaf(layer, at, unit * 0.075, float(spot[2]), Color(ink.lerp(UiTokens.CREAM, 0.3 if int(absf(float(spot[1])) * 10.0) % 2 == 0 else 0.0), alpha))
	if _spec.mark == "silver":
		var shown := float(_pose.get("mark", 1.0))
		var radii := Vector2(float(_spec.width) * 0.47, unit * ARCH_RISE)
		var at := _on_arc(_floor, radii, 52.0) + Vector2(0, -14.0 * (1.0 - shown))
		for side: float in [-1.0, 1.0]:
			var tail := PackedVector2Array([at + Vector2(side * 6.0, 18.0), at + Vector2(side * 30.0, 18.0), at + Vector2(side * 26.0, 66.0), at + Vector2(side * 17.0, 56.0), at + Vector2(side * 8.0, 66.0)])
			layer.draw_colored_polygon(tail, Color(UiTokens.MINT.darkened(0.15), shown))
		_medal(layer, at, unit * 0.15, Color(SILVER, shown), Color(SILVER_RIM, shown), "2")

func _draw_stars(layer: Control) -> void:
	var noise := RandomNumberGenerator.new()
	noise.seed = 7
	var area := layer.size
	for index in range(STAR_COUNT):
		var at := Vector2(noise.randf() * area.x, noise.randf() * area.y)
		var size := noise.randf_range(1.6, 3.2)
		if index % 4 == 0: _sparkle(layer, at, size * 2.2, Color(UiTokens.CREAM, 0.75))
		else: layer.draw_circle(at, size * 0.6, Color(UiTokens.CREAM, 0.6))

static func _medal(canvas: CanvasItem, at: Vector2, radius: float, fill: Color, rim: Color, number: String) -> void:
	canvas.draw_circle(at, radius, rim)
	canvas.draw_circle(at, radius * 0.82, fill)
	canvas.draw_arc(at, radius * 0.82, 0.0, TAU, 40, Color(rim, fill.a * 0.6), 2.0, true)
	var font := SettingsKit.font(600, true)
	var size := int(radius * 1.15)
	var width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	canvas.draw_string(font, at + Vector2(-width * 0.5, size * 0.36), number, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(UiTokens.INK, fill.a))

## A leaf: a pointed oval with a lighter middle line, `length` long, turned by `turn`.
static func _leaf(canvas: CanvasItem, at: Vector2, length: float, turn: float, ink: Color) -> void:
	var points := PackedVector2Array()
	for index in range(13):
		var a := PI * float(index) / 12.0
		points.append(Vector2(-cos(a) * length * 0.5, sin(a) * length * 0.22))
	for index in range(1, 12):
		var a := PI * float(index) / 12.0
		points.append(Vector2(cos(a) * length * 0.5, -sin(a) * length * 0.22))
	var place := Transform2D(turn, at)
	canvas.draw_colored_polygon(place * points, ink)
	canvas.draw_line(place * Vector2(-length * 0.42, 0), place * Vector2(length * 0.42, 0), Color(ink.lightened(0.35), ink.a * 0.7), maxf(1.0, length * 0.04), true)

## A four point star.
static func _sparkle(canvas: CanvasItem, at: Vector2, radius: float, ink: Color) -> void:
	if ink.a <= 0.01: return
	var points := PackedVector2Array()
	for index in range(8):
		var a := TAU * float(index) / 8.0
		points.append(at + Vector2(cos(a), sin(a)) * (radius if index % 2 == 0 else radius * 0.28))
	canvas.draw_colored_polygon(points, ink)

static func _ellipse(canvas: CanvasItem, at: Vector2, radii: Vector2, ink: Color) -> void:
	canvas.draw_colored_polygon(EmptyStateArt.ellipse(at, radii), ink)

## Part of an ellipse from `from` to `to` degrees (0 right, 90 up).
static func _arc(canvas: CanvasItem, at: Vector2, radii: Vector2, from: float, to: float, ink: Color, width: float) -> void:
	if is_equal_approx(from, to) or ink.a <= 0.01: return
	var points := PackedVector2Array()
	var steps := maxi(2, int(absf(to - from) / 4.0))
	for index in range(steps + 1):
		points.append(_on_arc(at, radii, lerpf(from, to, float(index) / float(steps))))
	canvas.draw_polyline(points, ink, width, true)

static func _on_arc(at: Vector2, radii: Vector2, degrees: float) -> Vector2:
	var a := deg_to_rad(degrees)
	return at + Vector2(cos(a) * radii.x, -sin(a) * radii.y)

# --- Timing ---------------------------------------------------------------

## 0 before `from`, 1 after `to`, eased in and out between.
static func _ease(t: float, from: float, to: float) -> float:
	return smoothstep(from, to, t)

## 0 to 1 at an even pace between `from` and `to`.
static func _span(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)

## One soft rise and fall between `from` and `to`, 0 outside.
static func _pulse(t: float, from: float, to: float) -> float:
	return sin(PI * _span(t, from, to))
