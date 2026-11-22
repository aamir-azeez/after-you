extends CanvasLayer
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Shared chapter controls. Puzzle progression and persistence stay with the owner.
signal pause_requested
## The redo chip beside the try pill was tapped (presentation/redo_flow.gd).
signal redo_chip_pressed
signal action_requested
signal finish_requested
## Skip to end, while the live spirit waits for its friend's memory.
signal skip_wait_requested

const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const Actions = preload("res://presentation/action_buttons.gd")
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const SeedTimerBar = preload("res://presentation/seed_timer_bar.gd")
const HoldButton = preload("res://presentation/hold_button.gd")
const MemoryWaitBar = preload("res://presentation/memory_wait_bar.gd")
const FastForwardBadge = preload("res://presentation/fast_forward_badge.gd")
const TryPill = preload("res://presentation/try_pill.gd")
const ButtonTicks = preload("res://presentation/button_ticks.gd")
const TurnDots = preload("res://presentation/kit/turn_dots.gd")
const PairChip = preload("res://presentation/kit/pair_chip.gd")
const Icons = preload("res://presentation/kit/icons.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const HomeSquare = preload("res://presentation/kit/home_square.gd")
## A card's Home square: as tall as the card's rows, so its touch target stays.
const CARD_HOME_SIDE := 54.0
const CREAM := Color("eceddb")
const MUTED := Color("afc7bd")
var settings: Dictionary = {}
## Solo play: the partner is the player's own memory, so a line with a solo
## wording reads that (PlayerCopy.from_canonical).
var solo := false
var ui: Control
var hud: Control
var overlay: Control
var stick: Control
var action_button: Button
## The action pop-up's pair letter (kit/pair_chip.gd), at the button's left end.
var pair_chip: PairChip
## Keeps room for the chip on the button's left (an icon that draws nothing).
var _chip_room := PlaceholderTexture2D.new()
var finish_button: Button
var pause_button: Button
var timer_label: Label
var chapter_label: Label
var hint_label: Label
var progress_label: Label
var objective_panel: PanelContainer
var turn_progress: SeedTimerBar
## Open turns (core/physical/open_turns.gd): the stage's turns as dots under the timer,
## and on the turn that must finish the stage the coral Last turn pill under them.
var turn_dots: TurnDots
var last_turn_pill: TryPill
var title_font: Font
var modal_shade: ColorRect
var modal_scroll: ScrollContainer
var modal_stack: VBoxContainer
var _card_title: Label
## Shown once the player has pinched or panned the chapter view, as on Home.
var reset_view_button: Button
## "Waiting for Sam" and the memory still to play, under the chapter title.
var wait_row: HBoxContainer
## "Try 3" under the chapter title from the turn's second try on.
var try_pill: TryPill
## "Sunshine ×2" under the try pill while the player's Sunshine has turns left (an online turn).
var sunshine_pill: TryPill
## Beside the try pill on a friend's second turn: "Ask for a redo", then what
## became of it (presentation/redo_flow.gd draws its words). Hidden otherwise.
var redo_chip: Button
var wait_label: Label
var wait_bar: MemoryWaitBar
## Hold to fast-forward and Skip to end take the action and finish places
## while the live spirit waits. Built once and only shown or hidden, so a
## finger on them never loses its press to a rebuild.
var fast_forward_button: HoldButton
var skip_wait_button: Button
## Over the world while the wait goes by faster (skipped or held).
var fast_forward_badge: FastForwardBadge
var _memory_wait := false
var _view_world: Node
## The room a control docked beside Finish takes (dock_beside_finish).
var _docked_width := 0.0
var _docked: Control
## A docked control keeps this far from the buttons.
const DOCK_GAP := 20.0
## The turn dots' row under the timer: its top and height, the width its dots
## take (the timer's track) unless a long stage needs DOTS_MIN_STEP a turn.
const DOTS_TOP := 94.0
const DOTS_HEIGHT := 30.0
const DOTS_WIDTH := 284.0
const DOTS_MIN_STEP := 18.0
## Reset view's top with no turn dots.
const RESET_VIEW_TOP := 92.0

func _ready() -> void:
	_build_ui()
	SafeArea.watch(self, _resize)
	_resize()

func show_play() -> void:
	overlay.visible = false
	hud.visible = true
	pause_button.visible = true
	Actions.apply(finish_button, "finish")

func show_moment(action_id: String) -> void:
	# The solved world stays visible until the player chooses to move on.
	show_play()
	hide_memory_wait()
	hide_watching()
	stick.release()
	stick.visible = false
	action_button.visible = false
	pause_button.visible = false
	finish_button.visible = true
	finish_button.disabled = false
	Actions.apply(finish_button, action_id)

func update_state(title: String, remaining: float, state: Dictionary, interactive: bool) -> void:
	chapter_label.text = title
	turn_progress.reduced_motion = bool(settings.get("reduced_motion", false))
	turn_progress.set_remaining(remaining, float(state.get("duration_ticks", 600)) / 30.0)
	hint_label.text = PlayerCopy.from_canonical(str(state.get("message", "")), solo)
	var objective: Dictionary = state.get("objective_display", {})
	objective_panel.show_objective(objective, str(state.get("progress_message", "")))
	var action: Dictionary = state.get("context_action", {})
	action_button.text = PlayerCopy.from_canonical(str(action.get("label", "Interact")))
	action_button.disabled = not bool(action.get("enabled", false))
	# Open turns (core/physical/open_turns.gd): a later turn may end at any time; it passes once its memory is over.
	finish_button.disabled = not (bool(state.get("can_commit", false)) or bool(state.get("can_pass", false)) or bool(state.get("can_end_early", false)))
	stick.visible = interactive or _watching
	action_button.visible = interactive and not action_button.text.is_empty() and not _memory_wait
	finish_button.visible = interactive and not _memory_wait
	fast_forward_button.visible = interactive and _memory_wait
	skip_wait_button.visible = interactive and _memory_wait
	_show_pair_chip(state, interactive)
	_show_replay_mark(state)

## Open turns: where the friend's replay ends in this turn (the snapshot's
## replay_ticks, M) as a notch on the timer in the friend's pip colour, filled
## once it has gone by, so a friend standing still still shows when their
## turn ended. Hidden with no replay (a first turn, a chapter without open turns).
func _show_replay_mark(state: Dictionary) -> void:
	var replay := int(state.get("replay_ticks", 0))
	var friend := _friend_slot(state)
	if replay <= 0 or friend.is_empty():
		turn_progress.clear_replay_mark()
		return
	var duration := maxf(1.0, float(state.get("duration_ticks", 600)))
	turn_progress.set_replay_mark(float(replay) / duration, SpiritLook.MINT if friend == "p1" else SpiritLook.PEACH, int(state.get("tick", 0)) >= replay)

## The slot of the friend's pip in `state` (the one marked ghost), "" for none.
static func _friend_slot(state: Dictionary) -> String:
	var players: Variant = state.get("players", {})
	if not players is Dictionary: return ""
	for key: Variant in players:
		if players[key] is Dictionary and bool(players[key].get("ghost", false)): return str(key)
	return ""

## The letter of the input the live pip is at, asked of the shown world's pair
## tags (kit/pair_tags.gd prompt()): inside the action button's left end, or
## alone in that spot at a pad, which has no button. None while the memory's
## wait holds that spot, or out of play.
func _show_pair_chip(state: Dictionary, interactive: bool) -> void:
	var chip: Dictionary = {}
	if interactive and not _memory_wait and is_instance_valid(_view_world) and "pair_tags" in _view_world: chip = _view_world.pair_tags.prompt(state)
	pair_chip.show_chip(chip)
	var room: Texture2D = _chip_room if pair_chip.visible and action_button.visible else null
	if action_button.icon != room: action_button.icon = room
	_fit_action_button()
	_place_pair_chip()

## The action button grows to hold its tag, gap, full label and the edge padding
## on one line, up to the room before the docked React button (its near edge
## less DOCK_GAP, read at layout time) or, with none docked, the safe area. A
## label wider than that wraps onto a second line at that width; the text is
## never shrunk and nothing touches the edges.
func _fit_action_button() -> void:
	if not is_instance_valid(action_button) or not is_instance_valid(ui): return
	var left_handed := bool(settings.get("left_handed", false))
	var edge := 28.0 if left_handed else 30.0
	var room := ui.size.x - edge * 2.0
	if is_instance_valid(_docked) and _docked.visible:
		room = (_docked.offset_right + DOCK_GAP - edge) if left_handed else (-edge - (_docked.offset_left - DOCK_GAP))
	var margin := action_button.get_theme_stylebox("normal").get_margin(SIDE_LEFT) + action_button.get_theme_stylebox("normal").get_margin(SIDE_RIGHT)
	var lead := _chip_room.size.x + float(action_button.get_theme_constant("h_separation")) if action_button.icon != null else 0.0
	var font := action_button.get_theme_font("font")
	var text_width := font.get_string_size(action_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, action_button.get_theme_font_size("font_size")).x
	var need := margin + lead + text_width
	var wrap := need > room
	var width := maxf(210.0, room if wrap else need)
	action_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	var height := 64.0
	if wrap:
		action_button.size = Vector2(width, 0.0)
		height = maxf(64.0, action_button.get_combined_minimum_size().y)
	action_button.offset_bottom = -114.0
	action_button.offset_top = -114.0 - height
	if left_handed:
		action_button.offset_left = 28.0
		action_button.offset_right = 28.0 + width
	else:
		action_button.offset_right = -edge
		action_button.offset_left = -edge - width

## Puts the chip in the room the button leaves at its left end, again
## whenever the button moves or grows (a long prompt grows it).
func _place_pair_chip() -> void:
	if not pair_chip.visible: return
	var left := action_button.get_theme_stylebox("normal").get_margin(SIDE_LEFT)
	pair_chip.position = action_button.position + Vector2(left, (action_button.size.y - pair_chip.size.y) * 0.5)

## The live spirit is waiting for its friend's memory: `text` names the friend
## and `ratio` is how much of the memory is left (1 to 0); `skipping` is true
## while Skip to end runs. Cheap to call every tick; nothing is rebuilt and
## unchanged values change nothing.
func show_memory_wait(text: String, ratio: float, skipping: bool = false) -> void:
	fast_forward_badge.reduced_motion = bool(settings.get("reduced_motion", false))
	fast_forward_badge.set_active(skipping or fast_forward_button.held())
	if wait_label.text != text: wait_label.text = text
	wait_bar.value = ratio
	if not wait_row.visible:
		wait_row.visible = true
		_place_wait_row.call_deferred()
	_memory_wait = true

## Carry-over turns: the friend's turn plays before this turn's hand-off. The
## wait row shows with Fast-forward and Skip as in a wait, and the stick's
## spot shows the watch (show_watching); the clock and the stick come at the
## hand-off (hide_memory_wait), with nothing said.
var _playback := false
func show_playback(text: String, ratio: float, skipping: bool = false) -> void:
	show_memory_wait(text, ratio, skipping)
	show_watching(1.0 - ratio)
	if _playback: return
	_playback = true
	turn_progress.visible = false

## Watching (a friend's turn before the hand-off, a stage's closing turn, a
## replay): the stick's spot shows the camera in a ring that fills toward the
## hand-off (`progress`, 0 to 1), and the stick takes no movement. Cheap to
## call every tick; nothing runs while not watching.
var _watching := false
func show_watching(progress: float) -> void:
	stick.watch(progress)
	if _watching: return
	_watching = true
	stick.visible = true

## The watch is over: the spot turns back into the stick with a short pop.
func hide_watching() -> void:
	if not _watching: return
	_watching = false
	stick.end_watch(bool(settings.get("reduced_motion", false)))

func watching() -> bool:
	return _watching

## True while the fast-forward mark shows (a skipped or fast-forwarded wait).
func fast_forwarding() -> bool:
	return fast_forward_badge.active()

## The wait is over (or there is none). Fast-forward lets go of its fingers.
func hide_memory_wait() -> void:
	fast_forward_badge.set_active(false)
	if _playback:
		_playback = false
		turn_progress.visible = true
		hide_watching()
	if not _memory_wait and not wait_row.visible: return
	_memory_wait = false
	wait_row.visible = false
	fast_forward_button.visible = false
	skip_wait_button.visible = false

func memory_wait_shown() -> bool:
	return _memory_wait

## The stick fades while Fast-forward plays the memory, since the live
## spirit stands still meanwhile.
func dim_stick(dim: bool) -> void:
	var alpha := 0.45 if dim else 1.0
	if not is_equal_approx(stick.modulate.a, alpha): stick.modulate.a = alpha

## True while a finger or the mouse holds Fast-forward.
func fast_forward_held() -> bool:
	return _memory_wait and fast_forward_button.held()

## Open turns: `view` (kit/turn_dots.gd view(), {} for none) under the timer,
## and the Last turn pill with the player's pip in `own_color` while `view` says
## this turn must finish the stage. Cheap to call every tick: an unchanged view
## changes nothing. Reset view moves below them.
func show_turns(view: Dictionary, own_color: Color) -> void:
	if not turn_dots.show_turns(view): return
	var bottom := RESET_VIEW_TOP
	last_turn_pill.visible = false
	if not view.is_empty():
		var cap := int(view.cap)
		turn_dots.max_step = clampf(DOTS_WIDTH / float(cap), DOTS_MIN_STEP, DOTS_WIDTH / 10.0)
		var width := turn_dots.natural_width()
		_anchor_rect(turn_dots, Control.PRESET_CENTER_TOP, Rect2(-width * 0.5, DOTS_TOP, width, DOTS_HEIGHT))
		bottom = DOTS_TOP + DOTS_HEIGHT + 8.0
		last_turn_pill.show_last_turn(bool(view.get("edge", false)), own_color)
		if last_turn_pill.visible:
			var pill := last_turn_pill.get_combined_minimum_size()
			# Under the dots' end, where the ringed dot is.
			_anchor_rect(last_turn_pill, Control.PRESET_CENTER_TOP, Rect2(width * 0.5 - pill.x, bottom - 2.0, pill.x, pill.y))
			bottom += pill.y + 6.0
	_anchor_rect(reset_view_button, Control.PRESET_CENTER_TOP, Rect2(-58, bottom, 116, 36))

## The turn's try count; the pill shows from the second try on.
## `text`: a hard run's line in place of the count (presentation/try_pill.gd).
func show_tries(tries: int, text: String = "") -> void:
	try_pill.show_try(tries, text)
	_place_wait_row.call_deferred()

## The redo chip: `text` with `icon` (null for none); a chip that only
## reports (Asked, kept) takes no tap. Empty `text` hides it.
func show_redo_chip(text: String, icon: Texture2D = null, tappable: bool = true) -> void:
	if not is_instance_valid(redo_chip): return
	redo_chip.visible = not text.is_empty()
	redo_chip.text = text
	redo_chip.icon = icon
	redo_chip.tooltip_text = text
	redo_chip.mouse_filter = Control.MOUSE_FILTER_STOP if tappable else Control.MOUSE_FILTER_IGNORE
	redo_chip.focus_mode = Control.FOCUS_ALL if tappable else Control.FOCUS_NONE
	_place_wait_row.call_deferred()

## The Sunshine pill under the try pill (presentation/try_pill.gd show_sunshine).
func show_sunshine(on: bool) -> void:
	if not is_instance_valid(sunshine_pill) or sunshine_pill.visible == on: return
	sunshine_pill.show_sunshine(on)
	_place_wait_row.call_deferred()

## The try pill and then the wait row sit just under the chapter title,
## however many lines it wraps to.
func _place_wait_row() -> void:
	if not is_instance_valid(wait_row) or not is_instance_valid(chapter_label): return
	var below := chapter_label.position.y + chapter_label.get_combined_minimum_size().y + 4.0
	if is_instance_valid(try_pill):
		try_pill.position = Vector2(chapter_label.position.x, below + 2.0)
		try_pill.size = try_pill.get_combined_minimum_size()
		# The redo chip shares the try pill's line, after it when it shows.
		if is_instance_valid(redo_chip) and redo_chip.visible:
			redo_chip.size = redo_chip.get_combined_minimum_size()
			var left := try_pill.position.x + (try_pill.size.x + 10.0 if try_pill.visible else 0.0)
			var line := maxf(try_pill.size.y if try_pill.visible else 0.0, redo_chip.size.y)
			redo_chip.position = Vector2(left, below + 2.0 + (line - redo_chip.size.y) * 0.5)
			if try_pill.visible: try_pill.position.y = below + 2.0 + (line - try_pill.size.y) * 0.5
			below += line + 8.0
		elif try_pill.visible: below += try_pill.size.y + 8.0
	if is_instance_valid(sunshine_pill):
		sunshine_pill.position = Vector2(chapter_label.position.x, below + 2.0)
		sunshine_pill.size = sunshine_pill.get_combined_minimum_size()
		if sunshine_pill.visible: below += sunshine_pill.size.y + 8.0
	wait_row.position = Vector2(chapter_label.position.x, below)

func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var theme := Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	theme.default_font = body
	var heading := FontVariation.new()
	heading.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	title_font = heading
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", CREAM)
	ControlTheme.install_buttons(theme)
	ui.theme = theme
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var brand := _label("AFTER YOU",22)
	brand.add_theme_font_override("font",title_font)
	_protect_world_label(brand)
	brand.position=Vector2(36,26)
	hud.add_child(brand)
	chapter_label = _label("THE SLEEPING LIGHTHOUSE",18)
	chapter_label.add_theme_color_override("font_color",MUTED)
	_protect_world_label(chapter_label)
	chapter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chapter_label.position = Vector2(36,61)
	hud.add_child(chapter_label)
	chapter_label.minimum_size_changed.connect(_fit_chapter_title.call_deferred)
	try_pill = TryPill.new(17)
	try_pill.visible = false
	hud.add_child(try_pill)
	redo_chip = Button.new()
	redo_chip.name = "RedoChip"
	redo_chip.visible = false
	redo_chip.custom_minimum_size.y = 46
	redo_chip.add_theme_font_size_override("font_size", 19)
	redo_chip.add_theme_constant_override("icon_max_width", 24)
	ControlTheme.secondary(redo_chip)
	redo_chip.pressed.connect(func() -> void: redo_chip_pressed.emit())
	hud.add_child(redo_chip)
	sunshine_pill = TryPill.new(17)
	sunshine_pill.name = "SunshinePill"
	sunshine_pill.visible = false
	hud.add_child(sunshine_pill)
	wait_row = HBoxContainer.new()
	wait_row.name = "MemoryWait"
	wait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wait_row.add_theme_constant_override("separation", 10)
	wait_row.visible = false
	hud.add_child(wait_row)
	wait_label = _label("", 16)
	_protect_world_label(wait_label)
	wait_row.add_child(wait_label)
	wait_bar = MemoryWaitBar.new()
	wait_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wait_row.add_child(wait_bar)
	# The shared seed timer owns the remaining-seconds number above its track.
	turn_progress = SeedTimerBar.new()
	turn_progress.reduced_motion = bool(settings.get("reduced_motion", false))
	hud.add_child(turn_progress)
	_anchor_rect(turn_progress, Control.PRESET_CENTER_TOP, Rect2(-160, 24, 320, SeedTimerBar.MIN_SIZE.y))
	timer_label = turn_progress.label
	turn_dots = TurnDots.new()
	turn_dots.centered = true
	turn_dots.visible = false
	hud.add_child(turn_dots)
	last_turn_pill = TryPill.new(16)
	last_turn_pill.name = "LastTurnPill"
	last_turn_pill.visible = false
	hud.add_child(last_turn_pill)
	objective_panel = ObjectivePanel.new()
	hud.add_child(objective_panel)
	_anchor_rect(objective_panel, Control.PRESET_TOP_RIGHT, Rect2(-248, 124, 224, 0))
	progress_label = objective_panel.label
	pause_button = button_for("pause", func(): pause_requested.emit())
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(-156, 20)
	pause_button.size = Vector2(132, 50)
	hud.add_child(pause_button)
	reset_view_button = Button.new()
	reset_view_button.name = "ChapterResetView"
	reset_view_button.text = "Reset view"
	reset_view_button.custom_minimum_size = Vector2(116, 36)
	reset_view_button.add_theme_font_size_override("font_size", 16)
	reset_view_button.pressed.connect(_reset_view)
	reset_view_button.visible = false
	reset_view_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	reset_view_button.position = Vector2(-58, RESET_VIEW_TOP)
	reset_view_button.size = Vector2(116, 36)
	hud.add_child(reset_view_button)
	hint_label = _label("", 21)
	_protect_world_label(hint_label)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-340, -94)
	hint_label.size = Vector2(680, 78)
	hud.add_child(hint_label)
	stick = Joystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(8, -218)
	stick.size = Vector2(Joystick.HIT_SIZE, Joystick.HIT_SIZE)
	hud.add_child(stick)
	action_button = button("Interact", func(): action_requested.emit())
	action_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	action_button.position = Vector2(-240, -178)
	action_button.size = Vector2(210, 64)
	# A long prompt with a pair chip grows the button toward the middle of the
	# screen, never past its edge.
	action_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# The controls a run is played with make its own cues: no tick over them.
	ButtonTicks.quiet(action_button)
	hud.add_child(action_button)
	# The room is the whole chip, so the chip sits at the button's own edge padding and the label keeps the button's usual icon gap.
	_chip_room.size = Vector2(PairChip.PairTags.CHIP, 1.0)
	action_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	action_button.add_theme_constant_override("h_separation", Actions.ICON_GAP)
	pair_chip = PairChip.new()
	hud.add_child(pair_chip)
	action_button.item_rect_changed.connect(_place_pair_chip)
	finish_button = button_for("finish", func(): finish_requested.emit())
	finish_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	finish_button.position = Vector2(-240, -100)
	finish_button.size = Vector2(210, 54)
	ButtonTicks.quiet(finish_button)
	hud.add_child(finish_button)
	fast_forward_button = HoldButton.new()
	fast_forward_button.name = "FastForward"
	fast_forward_button.custom_minimum_size.y = 50
	fast_forward_button.mouse_filter = Control.MOUSE_FILTER_STOP
	fast_forward_button.focus_mode = Control.FOCUS_NONE
	Actions.apply(fast_forward_button, "fast_forward")
	fast_forward_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fast_forward_button.position = Vector2(-240, -178)
	fast_forward_button.size = Vector2(210, 64)
	fast_forward_button.visible = false
	ButtonTicks.quiet(fast_forward_button)
	hud.add_child(fast_forward_button)
	# Skip acts on release, so the turn ends after the finger has lifted.
	skip_wait_button = button_for("skip_wait", func(): skip_wait_requested.emit())
	skip_wait_button.name = "SkipWait"
	skip_wait_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_wait_button.position = Vector2(-240, -100)
	skip_wait_button.size = Vector2(210, 54)
	skip_wait_button.visible = false
	hud.add_child(skip_wait_button)
	fast_forward_badge = FastForwardBadge.new()
	hud.add_child(fast_forward_badge)
	var badge := FastForwardBadge.SIZE
	_anchor_rect(fast_forward_badge, Control.PRESET_CENTER, Rect2(-badge * 0.5, -badge * 0.5 - 60.0, badge, badge))
	if settings.get("left_handed", false):
		_anchor_rect(stick, Control.PRESET_BOTTOM_RIGHT, Rect2(-200, -218, Joystick.HIT_SIZE, Joystick.HIT_SIZE))
		_anchor_rect(action_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -178, 210, 64))
		action_button.grow_horizontal = Control.GROW_DIRECTION_END
		_anchor_rect(finish_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -100, 210, 54))
		_anchor_rect(fast_forward_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -178, 210, 64))
		_anchor_rect(skip_wait_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -100, 210, 54))
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)


## Docks `control` (`size` big) on the bottom row beside Finish, toward the
## middle of the screen: left of it, or right of it in the left-handed layout,
## DOCK_GAP away, so it never covers the action button, Finish or the wait's
## buttons in their places. The hint line keeps clear of it. One control at most.
func dock_beside_finish(control: Control, size: Vector2) -> void:
	_docked_width = size.x + DOCK_GAP
	_docked = control
	# A run's reactions pop their own sound.
	ButtonTicks.quiet(control)
	hud.add_child(control)
	if settings.get("left_handed", false): _anchor_rect(control, Control.PRESET_BOTTOM_LEFT, Rect2(28.0 + 210.0 + DOCK_GAP, -100, size.x, size.y))
	else: _anchor_rect(control, Control.PRESET_BOTTOM_RIGHT, Rect2(-240.0 - DOCK_GAP - size.x, -100, size.x, size.y))
	_resize()

## The chapter world whose pinch-and-pan view the Reset view chip restores.
func watch_view(world: Node) -> void:
	_view_world = world

func _process(_delta: float) -> void:
	if not is_instance_valid(reset_view_button): return
	var exploration: Node = _view_world.get("camera_exploration") if is_instance_valid(_view_world) else null
	var explored := is_instance_valid(exploration) and (not is_equal_approx(float(exploration.zoom_ratio), 1.0) or not Vector2(exploration.pan).is_zero_approx())
	if reset_view_button.visible != explored: reset_view_button.visible = explored

func _reset_view() -> void:
	if is_instance_valid(_view_world) and _view_world.has_method("reset_camera_exploration"): _view_world.reset_camera_exploration()
	reset_view_button.visible = false

func _anchor_rect(control: Control, preset: int, rect: Rect2) -> void:
	# Set offsets, not absolute positions, after the control has a parent.
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _resize() -> void:
	if not is_inside_tree() or not is_instance_valid(ui):
		return
	SafeArea.inset(ui, SafeArea.rect(get_viewport()))
	_fit_action_button()
	if is_instance_valid(hint_label):
		_anchor_rect(hint_label, Control.PRESET_BOTTOM_LEFT, ControlTheme.hint_bounds(ui.size.x, bool(settings.get("left_handed", false)), _docked_width))
	if is_instance_valid(chapter_label):
		# Long stage names wrap in the title column instead of covering the
		# timer and progress text in the centre of the display.
		chapter_label.size.x = maxf(240.0, ui.size.x * 0.5 - 244.0)
		_fit_chapter_title.call_deferred()
	_layout_card.call_deferred()


func _fit_chapter_title() -> void:
	# Wrapping recomputes its minimum height after the width/text changes.
	# Release any height retained from the earlier narrow layout so its real
	# rectangle does not invisibly cover the playfield or suppress photo bubbles.
	if is_instance_valid(chapter_label):
		chapter_label.size.y = 0.0
	_place_wait_row()


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = Color("54766a")
	return style


func _label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _protect_world_label(label: Label) -> void:
	# Scrolling rooms can put pale walls behind the HUD. Keep its lettering
	# readable without adding a panel across the visible route.
	label.add_theme_color_override("font_outline_color", Color("101f31"))
	label.add_theme_constant_override("outline_size", 4)
	# A soft dark halo behind the letters keeps the title readable over
	# bright grass, plaster and tile in every chapter.
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.09, 0.13, 0.62))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 12)


func button_for(action_id: String, callback: Callable) -> Button:
	return Actions.create(action_id, callback)


func button(text: String, callback: Callable, primary: bool=true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(callback)
	if not primary: ControlTheme.secondary(button)
	return button


func card(title: String, body: String) -> VBoxContainer:
	_open_overlay()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 610
	panel.add_theme_stylebox_override("panel", card_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.follow_focus = true
	margin.add_child(modal_scroll)
	modal_scroll.add_child(stack)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_stack = stack
	stack.minimum_size_changed.connect(func(): _layout_card.call_deferred())
	var heading_label := _label(title, 32)
	heading_label.add_theme_font_override("font", title_font)
	heading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading_label.custom_minimum_size.x = 550
	stack.add_child(heading_label)
	_card_title = heading_label
	var paragraph := _label(body, 20)
	paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paragraph.add_theme_color_override("font_color", MUTED)
	paragraph.custom_minimum_size.x = 550
	# A card with only its title (pause, save) leaves no empty line under it.
	paragraph.visible = not body.is_empty()
	stack.add_child(paragraph)
	_layout_card.call_deferred()
	return stack

## A whole-screen card of its own (a chapter's letter, presentation/letter/
## letter_view.gd) over the dimmed world, in place of the plain card.
func show_card_layer(layer: Control) -> void:
	_open_overlay()
	modal_scroll = null
	modal_stack = null
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(layer)

## The panel look every card shares.
func card_style() -> StyleBoxFlat:
	return _style(Color("163c36"))

## Clears the overlay for a card: the HUD hides and the world dims behind it.
func _open_overlay() -> void:
	stick.release()
	hud.visible = false
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = true
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.10, 0.10, 0.73)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Controls respect display cutouts; the dimming backdrop covers the whole
	# world, including those insets. Otherwise a bright side strip remains.
	SafeArea.bleed(modal_shade)
	overlay.add_child(modal_shade)

## Report or block on the current card: the shared flag button (kit/icons.gd)
## at the card's top right, beside its title. Returns the button.
func card_report(action: Callable) -> Button:
	var flag := Icons.report_button(action, PlayerCopy.REPORT_OR_BLOCK)
	flag.name = "CardReport"
	flag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_card_title_line().add_child(flag)
	return flag

## The current card's way home, in place of a Back row: the Home square
## (kit/home_square.gd) at its top left, beside its title. `action` is what
## Back did; Android Back and Escape still do it. Returns the button.
func card_home(action: Callable) -> Button:
	var square := HomeSquare.make(action, Vector2(CARD_HOME_SIDE, CARD_HOME_SIDE))
	square.name = "CardHome"
	square.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var line := _card_title_line()
	line.add_child(square)
	line.move_child(square, 0)
	return square

## The current card's top line: its title, with Home before it and Report after.
func _card_title_line() -> HBoxContainer:
	var line := modal_stack.get_node_or_null("CardTitleLine") as HBoxContainer
	if line != null: return line
	line = HBoxContainer.new()
	line.name = "CardTitleLine"
	line.add_theme_constant_override("separation", 12)
	modal_stack.add_child(line)
	modal_stack.move_child(line, 0)
	_card_title.reparent(line, false)
	_card_title.custom_minimum_size.x = 0
	_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return line

func _layout_card() -> void:
	if not is_instance_valid(modal_scroll) or not is_instance_valid(modal_stack): return
	# Long checkpoint lists scroll inside the card instead of pushing the
	# final button beyond the safe display area.
	var limit := maxf(120.0, ui.size.y - 84.0)
	var required := modal_stack.get_combined_minimum_size().y
	modal_scroll.custom_minimum_size = Vector2(566.0, minf(required, limit))
