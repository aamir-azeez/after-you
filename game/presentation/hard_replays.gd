extends RefCounted
## Hard runs in Replays (services/hard_mode.gd): a "Hard runs" section of
## their own at the end of a tab's list, solo runs on Solo and runs with a
## friend on Together. Rows come from HardMode.summaries(), so drawing them
## reads no recording; a run with nothing to watch is never kept. Watch opens
## the run's chapter at its slip; the part chips open it at an earlier stage.
## The rows use Replays' own row, chip and launch controls (`flow` is
## presentation/replays_flow.gd).
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const WhenLabel = preload("res://presentation/when_label.gd")
const CREAM := Color("eceddb")
const MUTED := Color("9dbeb4")

## The kept runs of `mode` (HardMode.SOLO or TOGETHER), newest first.
static func runs(mode: String) -> Array:
	return HardMode.summaries().filter(func(run: Dictionary) -> bool: return run.mode == mode and int(run.get("parts", 0)) > 0)

static func title(run: Dictionary) -> String:
	var chapter_title := str(ChapterRegistry.descriptor(str(run.chapter_key)).get("title", run.chapter_key))
	return (PlayerCopy.HARD_RUN_FAILED if run.kind == HardMode.FAILED else PlayerCopy.HARD_RUN_DONE) % chapter_title

## Who and when, then whose slip and where: "Solo · Today, 7:21 AM · You
## slipped on stage 1." A friend's own slip names them once.
static func caption(run: Dictionary) -> String:
	var parts: Array[String] = []
	var friend := str(run.get("friend", ""))
	var by_friend: bool = run.kind == HardMode.FAILED and str(run.get("by", "")) == "friend"
	if run.mode == HardMode.SOLO: parts.append(PlayerCopy.HARD_RUN_SOLO)
	elif not by_friend: parts.append(PlayerCopy.HARD_RUN_TOGETHER % (friend if not friend.is_empty() else PlayerCopy.HARD_FRIEND_FALLBACK))
	var when := WhenLabel.text(int(run.at))
	if not when.is_empty(): parts.append(when)
	if run.kind == HardMode.FAILED: parts.append(HardModeView.failure_line(run))
	return " · ".join(parts)

## The section: its heading, then one row per run. Nothing when there is none.
static func add_section(flow: Object, list: VBoxContainer, kept: Array) -> void:
	if kept.is_empty(): return
	var heading: Label = flow.host._label(PlayerCopy.HARD_REPLAYS_HEADING, 24, CREAM, true)
	heading.name = "HardRunsHeading"
	list.add_child(heading)
	list.add_child(flow.host._label(PlayerCopy.HARD_REPLAYS_SUBTITLE, 17, MUTED))
	for run: Dictionary in kept: list.add_child(_row(flow, run))

static func _row(flow: Object, run: Dictionary) -> Control:
	var parts := int(run.parts)
	var launch := func(part: int) -> void: await flow.launch_hard_run(run, part)
	var chips: Control = null
	if parts > 1:
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		for part in range(parts):
			var label := PlayerCopy.HARD_PART_SLIP if part == parts - 1 and run.kind == HardMode.FAILED else PlayerCopy.HARD_PART_STAGE % (part + 1)
			# Replays' launch: every Watch control waits while the chapter opens.
			var chip: Button = flow._part_chip(label, false, func() -> void: pass)
			chip.pressed.connect(flow._begin_replay_launch.bind(chip, launch.bind(part)))
			chip.set_meta("replay_launch", true)
			row.add_child(chip)
		chips = row
	# The whole row watches from the slip, as its Watch does.
	var shown: Array[Button] = []
	var tapped := func() -> void:
		if not shown.is_empty() and is_instance_valid(shown[0]): shown[0].pressed.emit()
	var card: Dictionary = flow._replay_row_card(str(run.chapter_key), title(run), caption(run), false, tapped, true, chips)
	var watch: Button = flow._replay_launch_button("Watch", launch.bind(parts - 1), false, true)
	shown.append(watch)
	watch.name = "HardRunWatch"
	watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.rowbox.add_child(watch)
	return card.panel
