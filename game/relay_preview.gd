extends Node3D
const ChapterIndex = preload("res://content/chapters/index.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## The same chapter presentation can use local practice or a retained online owner.
signal closed

const Registry = preload("res://services/chapter_registry.gd")
const SlotLooks = preload("res://presentation/slot_looks.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Journey = preload("res://services/relay_journey.gd")
const World = preload("res://presentation/relay_world.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const Joystick = preload("res://presentation/joystick.gd")
const LegacySave = preload("res://services/local_save.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Frames = preload("res://services/frame_policy.gd")
const Soundscape = preload("res://services/soundscape.gd")
const ChapterSoundMap = preload("res://services/chapter_sound_map.gd")
const LighthouseHud = preload("res://presentation/lighthouse_hud.gd")
const JournalLoader = preload("res://services/lighthouse_loader.gd")
const WorldPrewarm = preload("res://services/world_prewarm.gd")
const LighthouseMigration = preload("res://services/lighthouse_migration.gd")
const ReactionPhotos = preload("res://presentation/reaction_photo_flow.gd")
const ReactionStrip = preload("res://presentation/reaction_photo_strip.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const RedoClient = preload("res://services/redo_client.gd")
const RedoScreen = preload("res://presentation/redo_screen.gd")
const RedoRequestNotice = preload("res://presentation/redo_request_notice.gd")
const SoloRedoOffer = preload("res://presentation/solo_redo_offer.gd")
const PresenceBadge = preload("res://presentation/friend_presence_badge.gd")
const RoomReadyPanel = preload("res://presentation/room_ready_panel.gd")
const RoomActions = preload("res://presentation/room_actions.gd")
const RoomFriendStrip = preload("res://presentation/room_friend_strip.gd")
const RoomOptionsSheet = preload("res://presentation/room_options_sheet.gd")
const RoomPageBuilder = preload("res://presentation/room_page_builder.gd")
const WaitFraming = preload("res://presentation/wait_framing.gd")
## Seconds the room panel's camera takes to ease into a new framing.
const FRAMING_EASE := 0.6
const ControlTheme = preload("res://presentation/control_theme.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const PartnerFriends = preload("res://services/partner_friends.gd")
const MemoryWait = preload("res://presentation/memory_wait.gd")
const WaitHints = preload("res://presentation/wait_hints.gd")
const TurnEndings = preload("res://presentation/turn_endings.gd")
const EndingBadge = preload("res://presentation/ending_badge.gd")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("afc7bd")
const COMPLETION_DURATION := 3.0
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const EndReactionScreen = preload("res://presentation/end_reaction_screen.gd")
const RunReactions = preload("res://presentation/run_reactions.gd")
const RunReactionPlayer = preload("res://presentation/run_reaction_player.gd")
const RunReactionStore = preload("res://services/run_reaction_store.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardRunFlow = preload("res://presentation/hard_run_flow.gd")
const RoomRefreshFlow = preload("res://presentation/room_refresh_flow.gd")
# Short status labels for the shared waiting panel (concept 06).
const WAITING_FOR_FRIEND := "Waiting for friend"
const ROOM_CLOSED := "Room closed"
const WAITING_TURN_SAVED := "Your turn is saved"
const FRIEND_JOINED := "Friend joined"
# Names whose turn is pending once a partner is in the room (concept 06). %s is
# the local nickname, or the partner's short friend code when none is saved.
const WAITING_FOR_PARTNER_TURN := "Waiting for %s's turn"
const CHIP_FILL := Color("1d4b44")

@export var chapter_key := Registry.RELAY
var chapter: Dictionary = {}
var _simulation: Script = Simulation
var journey: RefCounted = Journey.new()
var online_session: RefCounted
var friend_presence: Node
## The phone's live socket (services/live_connection.gd), or null. A hint for
## this room asks the poll for one read now, and while the socket is healthy
## the poll slows to the socket's safety interval.
var live_connection: Node:
	set(value):
		live_connection = value
		if is_instance_valid(value):
			value.room_changed.connect(refresh_flow.on_live_room_changed)
			value.missed_hints.connect(refresh_flow.live_caught_up)
var presence_hud: Label
var _safety_screen: CanvasLayer
var _redo_screen: CanvasLayer
var _safety_photos: Array = []
var online_refresh_queued := false
var online_request_generation := 0
var reaction_photos_enabled := ReactionPhotos.FEATURE_ENABLED
var reaction_photos: Node
var reaction_strip: Control
var clipboard_copy: Callable = _copy_with_display_server
var definition: Dictionary = Catalog.relay_isles()
var sim: RefCounted = Simulation.new()
var world: Node3D
var soundscape: Node
var controls: CanvasLayer
## The wait for the friend's memory at the end of a second turn.
var memory_wait := MemoryWait.new()
## Reactions during a run: the React pill and what records and shows them.
var run_reactions: Button
var run_player := RunReactionPlayer.new()
## The finished turn's own reactions, kept with it when it is saved or sent.
var _review_track: Array = []
var ui: Control
var refresh_schedule := RefreshClock.new()
var online_sync_status: Label
var online_last_checked_ms := -1
var hud: Control
var overlay: Control
var stick: Control
var action_button: Button
var finish_button: Button
var timer_label: Label
var chapter_label: Label
var hint_label: Label
var review: Dictionary = {}
var replay_frames: Array = []
var replay_cursor := 0
var _replay_context: Dictionary = {}
var _continue_replay_context := false
var replay_pair_index := -1
var _replay_collection: Array = []
var _solo_replay_only := false
var redo_notice := RedoRequestNotice.new()
## Every start of a turn counts a try; the pill shows the live turn's count.
var turn_tries := TurnTries.new()
## The turn a replay plays and its memory, for their reactions at its end.
var _replay_runs: Array = []
var _replay_hold := 0
## This screen's hard run (services/hard_run.gd), or null outside hard mode,
## and how the screen shows it (presentation/hard_run_flow.gd).
var hard: RefCounted = null
var hard_flow: RefCounted = HardRunFlow.new(self)
var refresh_flow: RefCounted = RoomRefreshFlow.new(self)
var _live_tries := 0
## A start whose try is still to be counted, at its first tick (see _begin).
var _try_due := false
var _try_slot := ""
## Whether the turn waits on its opening glance at its goal (_glance_at_goal).
var _glancing := false
var _shown_pill := ""
var _solo_replay_context_error := false
var running := false
var mode := "ready"
var action_pressed := false
var stage: Dictionary = {}
var checkpoint: Dictionary = {}
var prior: Dictionary = {}
var role := "a"
var settings: Dictionary = {}
var save_photo_prompt_preference: Callable
var turn_notification_status: Callable
var enable_turn_notifications: Callable
var share_current_room: Callable
## Main's view of this room's sharing: {"shared": bool, "busy": bool}.
var room_share_state: Callable
## func(snapshot, chapter_key) -> Control or null: the leaderboard line on a
## finished together run's card (presentation/board_feedback_flow.gd). Main sets it.
var board_line: Callable
## services/partner_friends.gd: whether this room offers to add its partner as
## a friend, and the request. Main sets it; without it nothing is offered.
var partner_friends: RefCounted
var _sharing_room := false
var _room_ready_panel: Control
## Notes from outside the room (a friend's room is ready, a tapped notification
## that waits), newest last. Each card of this room visit shows them.
var _deferred_notes: PackedStringArray = []
const DEFERRED_NOTES := 3
var _room_camera: Dictionary = {}
var _camera_tween: Tween
## The room panel's framing is on screen; a redraw in the same frame keeps
## easing from what was shown (_shown_framing) instead of starting over.
var _room_framed := false
var _shown_framing: Dictionary = {}
## Begin and Resume on the ready card, by action, for the busy-tap gate.
var _ready_turn_buttons: Dictionary = {}
var notification_hint: Label
var notification_offer: Button
var _waiting_notify_section := false
var _waiting_notify_offered := false
var _room_options_modal: Control
## The room action table state drawn now ("" for any other card), and the mode
## it was drawn in. Room options act only while both still hold.
var _room_state := ""
var _room_state_mode := ""
var completion_remaining := 0.0
var _completion_is_replay := false
var backgrounded := false
var _retry_cancel: Callable
## Solo work that will hold the screen for a noticeable time waits behind a
## card that is drawn first (see _after_visible_wait).
const VISIBLE_WAIT_USEC := 150000
## How long a drowned spirit is seen going under before the review card.
const DROWN_BEAT_FRAMES := 45
var _drown_frames := 0
## The turn ending being shown (turn_endings.gd), or {}.
var _ending: Dictionary = {}
var _wait_then: Callable
var _wait_frames := 0
## The solo live simulation the ready card set up, as it was then. Start turn
## plays it instead of setting up the same turn twice.
var _fresh_live: Dictionary = {}
const Reaper = preload("res://services/worker_reaper.gd")
const ScreenSwitch = preload("res://services/screen_switch.gd")
const OpeningCard = preload("res://presentation/chapter_loading_card.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Typed = preload("res://services/typed_values.gd")
const PollenResultLine = preload("res://presentation/pollen_result_line.gd")
## The turn after a solo first turn, set up on a worker while its review card
## is up, so Save turn need not replay that turn again on this thread. Joined
## in _process once it ends, before use; leaving hands it to the reaper.
var _prefetch_thread: Thread
## The check of the turn just finished, running on its worker (_start_turn_check).
var _check_thread: Thread
var _check_job: Dictionary = {}
## A reopened finished chapter's final scene, set up on its worker
## (_start_final_scene), and what it built.
var _scene_thread: Thread
var _scene_built: Dictionary = {}
var _prefetch_job: Dictionary = {}
var _prefetch_built: Dictionary = {}
var _leaving := false
## A long chapter's solo journal loads on a worker (it replays every saved
## stage the proof cache does not already know); nothing reads it until joined.
var _journal_loader: RefCounted
var _leave_after_load := false
## A staged world build, asked for by Main's chapter open behind its card
## (request_staged_build): the world builds over several frames, a few
## milliseconds each, while this screen waits in "loading" and the card keeps
## moving. Any other way of making this screen builds the world at once.
## Every chapter stages (island_world.build_staged), straight to the stage the
## screen opens on, a slice of each frame sized to the device
## (island_world.frame_budget_usec). Tests set staged_build_usec to stage a
## build however fast the machine is; 0 leaves the slice to the world.
static var staged_build_usec := 0
static var _staged_request := ""
var _world_building := false
var _leave_after_build := false

## Main asks for one staged build of the scene it is about to open.
static func request_staged_build(scene: String) -> void:
	_staged_request = scene

## True while the world is still being built (the chapter card waits for it).
func building() -> bool:
	return _world_building
var _loading_label: Label
## The bridges at the previous tick, for cues that name the bridge that opened.
var _sound_seen: Dictionary = {}
## The Lighthouse's last stage ends on its lit beacon, held until the player moves on.
var _moment_replay := false
var title_font: Font
var modal_shade: ColorRect
## A replay whose room changed under it locks this screen with an error.
var _room_context_lost := false


func _ready() -> void:
	if settings.is_empty():
		var old_save := LegacySave.new()
		old_save.load_data()
		settings = old_save.data.settings.duplicate(true)
	if online_session != null:
		journey = online_session.coordinator
		chapter_key = journey.chapter_key()
	chapter = Registry.descriptor(chapter_key)
	if chapter.is_empty():
		_build_ui()
		_show_error(PlayerCopy.RELAY_PREVIEW_7D6EECC5B2C3)
		return
	definition = Registry.definition(chapter_key)
	_simulation = Registry.simulation_script(chapter_key)
	sim = _simulation.new()
	# Only an open Main made as a solo replay reads the context; never online.
	var injected := SoloReplayLaunch.consume(solo_replay_rules(chapter_key, definition, _simulation)) if SoloReplayLaunch.claim(online_session != null) else {"status": "none"}
	if injected.get("status") == "error":
		_solo_replay_context_error = true
	elif injected.get("status") == "consumed":
		_solo_replay_only = true
		_replay_collection = injected.context.accepted_pairs.duplicate(true)
		replay_pair_index = int(injected.context.get("start_stage_index", injected.context.selected_stage_index))
	_claim_hard()
	var staged: bool = not scene_file_path.is_empty() and _staged_request == scene_file_path and online_session == null
	_staged_request = ""
	if online_session == null and not _solo_replay_only and not _solo_replay_context_error:
		if _hard_on():
			journey = Journey.new(HardMode.journal_path(chapter_key), null, chapter_key)
		elif journey == null or journey.chapter_key() != chapter_key:
			journey = Journey.new("", null, chapter_key)
		# A staged open loads every journal on the worker, behind the card: its
		# read, parse and check held the scene-change frame (tens of ms here).
		if _loads_threaded() or staged:
			_journal_loader = JournalLoader.new()
			if _journal_loader.start(journey, _journal_preparation()) != OK: _journal_loader = null
		if _journal_loader == null: journey.load_data()
	soundscape = Soundscape.new()
	soundscape.configure(settings)
	add_child(soundscape)
	world = Registry.world_script(chapter_key).new()
	world.fold_over_frames = true
	add_child(world)
	GraphicsPolicy.apply(world, settings)
	world.footstep.connect(func(spirit: String):
		if running and mode in ["play", "replay"]: soundscape.play_footstep(spirit))
	world.reunion.connect(func():
		if running and mode in ["play", "replay"]: soundscape.play_reunion())
	soundscape.listen_to(world)
	world.reduced_motion = bool(settings.get("reduced_motion", false))
	if staged and OpeningCard.covering():
		# Main's opening card covers this screen: its controls and loading
		# card are made at the start of the next frame (before any step of
		# the build resumes), not in the frame of the scene change; that frame
		# shows the empty stage under the card. Anything of this screen that
		# runs earlier (input, its own frame) makes them first
		# (_finish_ready_due). An open quick enough to show no card makes
		# them at once, so its own loading card is drawn in this frame.
		mode = "loading"
		running = false
		_controls_due = true
		get_tree().process_frame.connect(_finish_ready_due, CONNECT_ONE_SHOT)
		_build_world_staged()
		return
	if staged: _build_world_staged()
	else: world.load_level(definition)
	_finish_ready()

## A staged open's controls are still to be made (see _ready).
var _controls_due := false

## Makes a staged open's controls and loading card now, if still due.
func _finish_ready_due() -> void:
	if not _controls_due or not is_inside_tree(): return
	_controls_due = false
	_finish_ready()

## The rest of _ready: the controls, then the first view or the loading card.
func _finish_ready() -> void:
	_build_ui()
	world.configure_camera_exploration(_camera_exploration_active, _camera_exploration_allowed)
	world.camera_exploration.frame_applied.connect(_position_replay_photos)
	if online_session != null and reaction_photos_enabled:
		reaction_photos = ReactionPhotos.new()
		reaction_photos.configure(self, online_session)
		reaction_photos.prompts_enabled = _photo_prompts_enabled
		reaction_photos.save_prompt_preference = _save_photo_prompts
		reaction_photos.reduced_motion = func() -> bool: return bool(settings.get("reduced_motion", false))
		add_child(reaction_photos)
		reaction_strip = ReactionStrip.new()
		reaction_strip.configure(online_session)
		reaction_strip.report_requested.connect(_report_partner_photo)
		reaction_strip.edit_requested.connect(_edit_replay_photo)
		hud.add_child(reaction_strip)
		reaction_strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_resize)
	_resize()
	get_tree().auto_accept_quit = false
	if _world_building: _show_journal_loading()
	else: _show_first_view()


func _show_first_view() -> void:
	if _solo_replay_context_error:
		_show_error(PlayerCopy.RELAY_PREVIEW_3DB2A54BEB93)
	elif _solo_replay_only:
		_play_collection_pair()
	else:
		_show_ready()
		_resume_photo()


## A turn of this room may still wait for its photo: After You closed while the camera was
## open. Its photo card opens again with that photo (reaction_photo_flow.gd).
func _resume_photo() -> void:
	if online_session == null or not is_instance_valid(reaction_photos) or mode not in ["ready", "online_waiting"]: return
	var room_id := str(journey.snapshot().get("room_id", ""))
	if room_id.is_empty(): return
	reaction_photos.resume_for_room(room_id, _show_ready, func() -> bool: return mode in ["ready", "online_waiting"] and not running and not _leaving and not backgrounded)


## Builds the world a few milliseconds a frame (see staged_build_usec). The
## world does not run until it is whole, and is not drawn either: drawing the
## half-built world under the card took a growing share of every build frame.
## Once whole it shows over a few frames (island_world.reveal_staged), still
## behind the card. Back waits for the build and the reveal to finish.
## It builds the stage the screen opens on. The journal, loading on its
## worker, names that stage only once joined, so the build waits for it
## behind the card, then builds that stage once.
func _build_world_staged() -> void:
	_world_building = true
	var held := world.process_mode
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var shown := world.visible
	world.visible = false
	while _journal_loader != null and not _leaving:
		await get_tree().process_frame
		_finish_ready_due()
		# Joined here as soon as it ends, not a frame later from _process.
		if mode == "loading": _poll_journal_load()
	if not _leaving and not _leave_after_build:
		# The ready card's fresh turn is set up on a worker meanwhile (it
		# replays the partner's turn): the same setup the card would run.
		_start_opening_turn()
		await world.build_staged(definition, staged_build_usec, _opening_stage_id())
		# A Home warm-up of this stage would only build it again (world_prewarm.gd).
		var built: Variant = world.get("_built_stage_id")
		if built is String and not _leaving and not _leave_after_build: WorldPrewarm.note_built(chapter_key, built)
		if shown: await world.reveal_staged()
		# The ready card is built in a frame of its own, not on the build's last.
		await get_tree().process_frame
		while _prefetch_thread != null and _prefetch_thread.is_alive() and not _leaving:
			await get_tree().process_frame
	world.process_mode = held
	world.visible = shown
	_world_building = false
	if _leaving: return
	if _leave_after_build:
		_leave()
	elif mode == "loading" and _journal_loader == null:
		_show_first_view()

## A ready card whose turn replays its partner's turn to set up (First Steps
## and Relay; the other rules take the journey's proof) sets it up on a
## worker during the build, as Save turn's prefetch does (_prefetch_turn).
func _start_opening_turn() -> void:
	if online_session != null or _solo_replay_only or _solo_replay_context_error or journey == null or _journal_loader != null: return
	if journey.read_only or not journey.has_method("next_turn_job") or journey.chapter_complete(): return
	var job: Dictionary = journey.next_turn_job({}, true)
	if not job.is_empty() and Proofs.setup_replays(job): _prefetch_turn(job)

## The stage the first view shows, as far as this screen knows before its
## world is built: the solo journal's current stage, or its last for a
## finished chapter, or a collection replay's stage. "" (the first stage)
## for anything else.
func _opening_stage_id() -> String:
	if _solo_replay_only:
		# A replay from the collection plays its chosen stage.
		if replay_pair_index < 0 or replay_pair_index >= _replay_collection.size() or not _replay_collection[replay_pair_index] is Dictionary: return ""
		var pair: Dictionary = _replay_collection[replay_pair_index]
		return str(pair.b.get("stage_id", "")) if pair.get("b") is Dictionary else ""
	if online_session != null or _solo_replay_context_error or journey == null or _journal_loader != null: return ""
	if journey.read_only or not journey.has_method("stage_id"): return ""
	if journey.chapter_complete():
		var stages: Array = definition.get("stages", [])
		return str(stages[-1].get("id", "")) if not stages.is_empty() and stages[-1] is Dictionary else ""
	return str(journey.stage_id())


## Chapters with more than two stages: up to a dozen saved turns to replay.
func _loads_threaded() -> bool:
	return int(chapter.get("stage_count", 2)) > 2

func _show_journal_loading() -> void:
	mode = "loading"
	running = false
	var card := _card("Opening your chapter", PlayerCopy.LIGHTHOUSE_PREVIEW_E52C132C24BE)
	_loading_label = _label(PlayerCopy.LIGHTHOUSE_PREVIEW_DA74C3A728FC, 18)
	card.add_child(_loading_label)
	card.add_child(_action_button("back", _leave))

## Work the journal worker does first: the Lighthouse carries an unconverted
## solo @1 journey into @2 the first time @2 opens (lighthouse_migration.gd),
## never into a hard run's own journal.
func _journal_preparation() -> Callable:
	if Registry.is_lighthouse(chapter_key) and not _hard_on() and LighthouseMigration.plan() == "migrate": return Callable(LighthouseMigration, "convert_v1")
	return Callable()

## Joins the journal worker once it ends; the journal is used only after that.
func _poll_journal_load() -> void:
	if _journal_loader == null or not _journal_loader.ready(): return
	var loaded: RefCounted = _journal_loader.take_result()
	var prepared: Variant = _journal_loader.prepared
	_journal_loader = null
	if _leave_after_load:
		_leave()
		return
	if loaded == null:
		_show_error(PlayerCopy.LIGHTHOUSE_PREVIEW_E51024E31751)
		return
	journey = loaded
	if prepared is Dictionary and not _adopt_migration(prepared): return
	_show_ready()

## False when this screen hands over to the solo @1 screen instead, or shows
## that the carried-over journey could not be saved.
func _adopt_migration(converted: Dictionary) -> bool:
	match str(converted.get("status", "")):
		"converted":
			match LighthouseMigration.carry(journey, converted):
				"adopted": return true
				"unsaved":
					# Nothing is remembered: the next open converts it again.
					_show_error(journey.last_error)
					return false
			LighthouseMigration.remember("fallback" if not converted.get("complete", false) else "fresh")
		"fallback":
			LighthouseMigration.remember("fallback" if not converted.get("complete", false) else "fresh")
		_:
			return true
	if converted.get("complete", false): return true
	# Keep playing the unfinished @1 journey in its own screen.
	_leaving = true
	mode = "leaving"
	ScreenSwitch.to_file(get_tree(), LighthouseMigration.V1_SCENE)
	return false


## What a solo replay hand-off must hold for this chapter (services/solo_replay_launch.gd):
## every accepted pair rebuilds its stage's checkpoint from the chapter's start.
static func solo_replay_rules(chapter: String, level: Dictionary, simulation_script: Script) -> Dictionary:
	var stage_ids: Array = []
	for stage: Variant in level.get("stages", []):
		stage_ids.append(str(stage.get("id", stage.get("stage_id", ""))) if stage is Dictionary else "")
	return {"chapter_key": chapter, "stage_ids": stage_ids, "pairs_valid": func(pairs: Array) -> bool:
		var checkpoint: Dictionary = Registry.initial_checkpoint(chapter)
		if checkpoint.is_empty(): return false
		for pair: Dictionary in pairs:
			var derived: Dictionary = simulation_script.derive_checkpoint(level, checkpoint, pair.a, pair.b)
			if not derived.get("valid", false) or not derived.get("checkpoint") is Dictionary: return false
			checkpoint = derived.checkpoint
		return true}


func _build_ui() -> void:
	controls=Controls.new()
	controls.settings=settings.duplicate(true)
	add_child(controls)
	ui=controls.ui
	hud=controls.hud
	overlay=controls.overlay
	stick=controls.stick
	action_button=controls.action_button
	finish_button=controls.finish_button
	timer_label=controls.timer_label
	chapter_label=controls.chapter_label
	hint_label=controls.hint_label
	title_font=controls.title_font
	controls.pause_requested.connect(_pause)
	controls.watch_view(world)
	controls.action_requested.connect(_request_action)
	controls.finish_requested.connect(_finish)
	controls.skip_wait_requested.connect(_skip_memory_wait)
	run_reactions = RunReactions.new()
	run_reactions.settings = settings
	run_reactions.visible = false
	controls.dock_beside_finish(run_reactions, RunReactions.SIZE)
	run_reactions.reacted.connect(_react_in_run)
	if is_instance_valid(friend_presence) and online_session != null:
		presence_hud = _presence_badge()
		hud.add_child(presence_hud)
		presence_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		presence_hud.offset_left = -270
		presence_hud.offset_right = -36
		presence_hud.offset_top = 88
		presence_hud.offset_bottom = 112
		presence_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _photo_prompts_enabled() -> bool:
	return bool(settings.get("photo_prompts", true))

func _save_photo_prompts(enabled: bool) -> bool:
	if not save_photo_prompt_preference.is_valid() or save_photo_prompt_preference.call(enabled) != true:
		return false
	settings.photo_prompts = enabled
	return true


func _anchor_rect(control: Control, preset: int, rect: Rect2) -> void:
	# Set offsets, not absolute positions, after the control has a parent.
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _resize() -> void:
	if not is_inside_tree(): return
	if is_instance_valid(controls): controls._resize()
	if is_instance_valid(_room_ready_panel) and mode in ["ready", "online_waiting"]:
		if ui.size.x < 880 or _room_ready_panel.short_layout != (ui.size.y < 640): _show_ready.call_deferred()
		else: _frame_ready_world.call_deferred()


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


func _action_button(action_id: String, callback: Callable) -> Button:
	var button: Button = controls.button_for(action_id, callback)
	# A hard run never offers a way to play a turn again (services/hard_mode.gd).
	if not hard_flow.offers(action_id):
		button.visible = false
		button.disabled = true
	return button


func _button(text: String, callback: Callable, primary: bool=true) -> Button:
	return controls.button(text,callback,primary)


func _card(title: String, body: String) -> VBoxContainer:
	var card := _plain_card(title, body)
	if _presence_available(): card.add_child(_presence_badge())
	return card

## The optional photo card's place: the room's dimmed overlay, cleared for the polaroid card
## that reaction_photo_flow.gd builds.
func _photo_overlay() -> Control:
	_plain_card("", "")
	controls.modal_scroll = null
	controls.modal_stack = null
	for child: Node in overlay.get_children():
		if child == controls.modal_shade: continue
		overlay.remove_child(child)
		child.queue_free()
	return overlay

func _plain_card(title: String, body: String) -> VBoxContainer:
	_end_glance()
	if is_instance_valid(world) and world.has_method("set_goal_beacon_live"): world.set_goal_beacon_live(false)
	_restore_ready_world()
	_close_room_options()
	_room_ready_panel = null
	_set_room_state("")
	_ready_turn_buttons.clear()
	if is_instance_valid(reaction_strip) and mode == "replay": _safety_photos = reaction_strip.report_targets()
	running=false
	action_pressed=false
	var card: VBoxContainer=controls.card(title,body)
	modal_shade=controls.modal_shade
	_show_deferred_notes.call_deferred()
	return card

func _presence_available() -> bool:
	return is_instance_valid(friend_presence) and online_session != null

func _presence_badge() -> Label:
	var badge := PresenceBadge.new()
	badge.configure(friend_presence, "v2", str(journey.snapshot().get("room_id", "")))
	return badge


func _show_ready() -> void:
	refresh_flow.forget_owed_redraw()
	if _journal_loader != null or _world_building:
		_show_journal_loading()
		return
	_restore_ready_world()
	if _room_context_lost:
		_show_error(PlayerCopy.RELAY_PREVIEW_17179ABFBE5C)
		return
	_clear_reaction_view()
	_replay_collection = []
	mode = "ready"
	replay_pair_index = -1
	if journey.read_only:
		_show_error(journey.last_error)
		return
	if _room_gone():
		_show_room_gone()
		return
	# A turn refused after a hard room started again belongs to the old run.
	hard_flow.settle_held()
	if online_session != null and not journey.pending().is_empty():
		_show_online_waiting()
		return
	if _ordinary_redo_available():
		var redo: RefCounted = online_session.redo_client()
		if not redo.busy: redo.bind_room("relay",journey.snapshot())
		if redo.pending().get("action") == "accept":
			_show_online_waiting()
			return
	if hard_flow.holds(): return
	if journey.chapter_complete():
		_show_completed()
		return
	if online_session != null and not journey.my_turn():
		_show_online_waiting()
		return
	checkpoint = journey.checkpoint()
	prior = journey.prior_recording()
	role = journey.role()
	for item: Dictionary in definition.stages:
		if str(item.id) == journey.stage_id():
			stage = item
	if not _reset_live():
		return
	world.present(sim.snapshot(), true)
	var body := _chapter_body(int(checkpoint.stage_index), role, stage)
	body += hard_flow.ready_note()
	var invited: bool = online_session != null and not online_session.invitation_code().is_empty()
	var joined: bool = online_session != null and journey.snapshot().get("guest_id") != null
	if invited and not joined:
		body += "\n\nInvitation: " + ShareCodes.display(ShareCodes.ROOM, online_session.invitation_code())
	var title: String = hard_flow.heading(_turn_title(int(checkpoint.stage_index), role))
	var compact: bool = online_session != null and _room_panel_fits()
	var facts := _room_facts()
	if compact:
		var hint := PlayerCopy.from_canonical(str(Registry.stage_presentation(chapter_key,stage)["hint_"+role]), online_session == null)
		var panel := _ordinary_room_card(title,hint)
		_set_room_state(RoomActions.panel_state("ready", facts))
		_add_friend_strip(panel, joined)
		_add_room_panel_actions(panel, facts)
	else:
		var card := _plain_card(title,body)
		# Before a friend joins, the invitation heading already states that status.
		if _presence_available() and (joined or not invited): card.add_child(_presence_badge())
		_set_room_state("ready_card")
		if invited: _add_friend_status(card, joined)
		_add_room_actions(card, "ready_card", "invite", facts)
		_add_room_actions(card, "ready_card", "turn", facts)
	# A tap still waiting keeps its label on the redrawn button.
	if _turn_gate != null and _ready_turn_buttons.has(_turn_gate_action): _turn_gate.follow(_ready_turn_buttons[_turn_gate_action])

func _set_room_state(state: String) -> void:
	_room_state = state
	_room_state_mode = mode if not state.is_empty() else ""

func _room_state_current() -> bool:
	return not _room_state.is_empty() and mode == _room_state_mode

## One draw's facts for the room action table: each is read at most once, in
## the order the rows ask for them.
func _room_facts() -> Callable:
	return _room_fact.bind({})

func _room_fact(name: String, state: String, known: Dictionary) -> bool:
	# Only "options" depends on the state it is read for. It reads false while
	# it is being read, so no row can make it read itself.
	var key := name + ":" + state if name == "options" else name
	if not known.has(key):
		known[key] = false
		known[key] = _read_room_fact(name, state, known)
	return known[key]

func _read_room_fact(name: String, state: String, known: Dictionary) -> bool:
	match name:
		"online": return online_session != null
		"solo": return online_session == null
		"hard": return _hard_on()
		# A hard run with a saved draft goes on only from it.
		"resume_only": return _hard_on() and _room_fact("draft", state, known)
		"invited": return online_session != null and not online_session.invitation_code().is_empty()
		"joined": return journey.snapshot().get("guest_id") != null
		"share": return _share_available()
		# A solo draft is checked only on Resume, behind the wait card.
		"draft": return journey.has_draft() if journey.has_method("has_draft") else not journey.draft().is_empty()
		"pending": return online_session != null and not journey.pending().is_empty()
		"held": return online_session != null and bool(journey.pending().get("held", false))
		# Turn alerts can be offered and are still off.
		"notifications": return _notifications_available() and not turn_notification_status.call().get("registered", false)
		"alerts": return _notifications_available()
		# A finished chapter always has its replays; otherwise finished pairs
		# online, or archived attempts solo.
		"watchable": return mode == "complete" or (not _pairs().is_empty() if online_session != null else not journey.archived_attempts().is_empty())
		"restart": return _local_restart_available()
		"redo": return _redo_offered()
		"redo_accept": return online_session.redo_client().can_accept()
		"my_turn": return journey.my_turn()
		"solo_redo": return not _solo_redo_plan().is_empty()
		"photo": return not _recent_photo_receipt().is_empty()
		"about": return not _waiting_details_stage().is_empty()
		"safety": return _safety_available()
		"partner_addable": return _partner_friend_state() == PartnerFriends.ADDABLE
		"partner_requested": return _partner_friend_state() == PartnerFriends.REQUESTED
		"options": return not RoomActions.shown(state, "options", _room_fact.bind(known)).is_empty()
	push_error("Unknown room action fact: " + name)
	return false

## Each RoomActions row's hooks on this screen, by id:
##   run: a plain row's handler; the row's bind and with_receipt give its
##   arguments.
##   widget: builds and wires a widget row. It takes (parent, id, facts, look)
##   and returns the row's button, if any.
##   option: wires a widget row's Room options row, taking the row and the id;
##   without one a row runs its run hook once the sheet closes.
##   drawn: told about the row's button once it is drawn.
## Method references, not names, so renaming or moving a handler is a parse
## error. They still call by name, so a subclass's override answers.
var _room_hooks: Dictionary = {}
func _room_action_hooks() -> Dictionary:
	if not _room_hooks.is_empty(): return _room_hooks
	_room_hooks = {
		"copy_code": {"widget": _add_invitation_code_row, "option": _wire_copy_code_option},
		"copy_code_button": {"widget": _add_copy_code_button},
		"share": {"widget": _add_share_row, "option": _wire_share_option},
		"check_saved": {"run": _online_refresh},
		"keep_held": {"run": _keep_held_turn},
		"alerts": {"widget": _add_alerts_status},
		"notify": {"run": _enable_turn_notifications, "drawn": _track_notify_offer},
		"resume": {"run": _turn_tap, "drawn": _track_turn_button},
		"record": {"run": _turn_tap, "drawn": _track_turn_button},
		"refresh": {"run": _online_refresh},
		"replays": {"run": _play_replays},
		"local_replays": {"run": _show_local_replays},
		"redo_answer": {"run": _open_redo, "drawn": _announce_pending_redo},
		"redo": {"run": _open_redo},
		"solo_redo": {"run": _confirm_solo_redo},
		"photo": {"run": _offer_recent_photo},
		"checkpoints": {"run": _choose_local_checkpoint},
		"hard_again": {"run": _hard_again},
		"new_room": {"run": _create_another_room, "drawn": _track_new_room_button},
		"restart": {"run": _confirm_restart_chapter},
		"add_friend": {"run": _add_partner_friend},
		"friend_requested": {"run": _partner_friend_requested},
		"about": {"run": _show_waiting_details},
		"safety": {"run": _open_safety},
		"room_options": {"widget": _add_room_options_button},
		"your_rooms": {"run": _leave},
		"back": {"run": _leave},
	}
	return _room_hooks

## A plain table row's handler, with its bound arguments and, for a
## with_receipt row, the receipt it was drawn for.
func _room_action_handler(id: String) -> Callable:
	var row: Dictionary = RoomActions.ACTIONS[id]
	var run: Callable = _room_action_hooks()[id].run.bindv(row.get("bind", []))
	return run.bind(_recent_photo_receipt()) if row.get("with_receipt", false) else run

## A plain table row as the shared action button or a plain card button.
func _room_action_button(id: String, facts: Callable, cream: bool = false) -> Button:
	var row: Dictionary = RoomActions.ACTIONS[id]
	var run := _room_action_handler(id)
	if row.has("button"): return _action_button(str(row.button), run)
	return _button(RoomActions.label(id, facts), run, cream or row.get("primary", false))

## One slot of a room state, in the table's order and its slot's look.
func _add_room_actions(parent: Container, state: String, slot: String, facts: Callable) -> void:
	var look := RoomActions.look(state, slot, is_instance_valid(_room_ready_panel) and _room_ready_panel.short_layout)
	for id: String in RoomActions.shown(state, slot, facts): _add_room_action(parent, id, facts, look)

## A wide panel's actions under its status: the invitation, a divider, the
## cream rows, the outlined rows, then the last line's rows side by side.
func _add_room_panel_actions(card: VBoxContainer, facts: Callable) -> void:
	var state := _room_state
	if not RoomActions.shown(state, "invite", facts).is_empty(): _add_room_actions(RoomPageBuilder.group(card, 8), state, "invite", facts)
	# The divider sets the turn's actions apart; an invitation that leads the
	# panel's actions (a cream Share) stays one block with the code above it.
	var primary := RoomActions.shown(state, "primary", facts)
	if primary.is_empty() or RoomActions.ACTIONS[primary[0]].get("section", "") != "invite": card.add_child(HSeparator.new())
	_add_room_actions(card, state, "primary", facts)
	_add_room_actions(card, state, "turn", facts)
	var line := HBoxContainer.new()
	line.name = "RoomPanelLastLine"
	line.add_theme_constant_override("separation", 10)
	card.add_child(line)
	_add_room_actions(line, state, "pair", facts)
	_add_room_actions(_room_ready_panel.header, state, "header", facts)

## Adds one table row when it applies, drawn in `look` (RoomActions.look), and
## returns its button. A plain row is one button; a widget row is built by its
## widget hook (_room_action_hooks).
func _add_room_action(parent: Container, id: String, facts: Callable = Callable(), look: Dictionary = {}) -> Button:
	if not facts.is_valid(): facts = _room_facts()
	if not RoomActions.applies(id, facts, _room_state): return null
	var row: Dictionary = RoomActions.ACTIONS[id]
	var hooks: Dictionary = _room_action_hooks()[id]
	if look.get("heading", false) and row.get("heading", false):
		var divider := HSeparator.new()
		divider.name = "RoomRowDivider"
		parent.add_child(divider)
		var heading := _label(RoomActions.label(id), 17)
		heading.name = "RoomRowHeading"
		heading.add_theme_color_override("font_color", CREAM)
		parent.add_child(heading)
	var button: Button
	if hooks.has("widget"):
		button = hooks.widget.call(parent, id, facts, look)
	else:
		button = _room_action_button(id, facts, look.get("cream", false))
		parent.add_child(button)
	if button == null: return null
	if look.get("icon_only", false): RoomPageBuilder.icon_button(button, row.icon, button.text, true)
	elif look.get("icon", false): RoomPageBuilder.panel_row_look(button, RoomActions.icon(id), look.get("cream", false) or row.get("primary", false))
	if look.get("icon", false) and row.get("alert", false): RoomPageBuilder.alert_outline(button)
	if look.has("height"): button.custom_minimum_size.y = look.height
	if look.get("fill", false): button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if hooks.has("drawn"): hooks.drawn.call(button)
	return button

## Widget rows (widget hooks): each takes (parent, id, facts, look).

## The narrow card's Copy invitation code button and its result line.
func _add_copy_code_button(parent: Container, id: String, _facts: Callable, _look: Dictionary) -> Button:
	var status := RoomPageBuilder.feedback_label("RelayCopyStatus")
	var button := RoomPageBuilder.panel_button(RoomActions.label(id), false)
	button.name = "CopyInvitationCode"
	button.pressed.connect(_copy_invitation.bind(status))
	parent.add_child(button)
	parent.add_child(status)
	return button

## Share and its result line, which shows the row's line where the look has lines.
func _add_share_row(parent: Container, id: String, _facts: Callable, look: Dictionary) -> Button:
	var share := RoomPageBuilder.panel_button(RoomActions.label(id), look.get("cream", false))
	parent.add_child(share)
	var lined: bool = look.get("line", false)
	var status := _label(str(RoomActions.ACTIONS[id].line) if lined else "", 17)
	status.visible = lined
	parent.add_child(status)
	_wire_share(share, status)
	return share

func _add_room_options_button(parent: Container, id: String, _facts: Callable, _look: Dictionary) -> Button:
	var button := RoomPageBuilder.panel_button(RoomActions.label(id), false)
	button.name = "RoomOptions"
	button.pressed.connect(_open_room_options.bind(button))
	parent.add_child(button)
	return button

## Turn alerts' status line ("Turn notifications are on", or a problem). It
## shows only when it has something to say; Notify is its own row.
func _add_alerts_status(parent: Container, _id: String, _facts: Callable, _look: Dictionary) -> Button:
	notification_hint = _label("", 16)
	notification_hint.name = "WaitingNotificationHint"
	notification_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(notification_hint)
	# A change in registration redraws the panel (see update_notification_offer).
	_waiting_notify_section = true
	_waiting_notify_offered = not turn_notification_status.call().get("registered", false)
	update_notification_offer()
	return null

## Drawn hooks: each takes the row's button.

## A tap still waiting keeps its label on the redrawn Record or Resume.
func _track_turn_button(button: Button) -> void:
	_ready_turn_buttons[str(button.get_meta("action_id"))] = button

func _track_notify_offer(button: Button) -> void:
	notification_offer = button
	update_notification_offer()

## The online replays row: the finished pairs from the first.
func _play_replays() -> void:
	replay_pair_index = 0
	_play_collection_pair()

## The held turn's row: archive it and read the room again.
func _keep_held_turn() -> void:
	if journey.archive_held_submission():
		_online_refresh()
	else:
		_show_online_waiting()

func _enable_turn_notifications() -> void:
	enable_turn_notifications.call()
	update_notification_offer()

func _chapter_body(stage_index: int, for_role: String, stage_item: Dictionary) -> String:
	return Registry.turn_intro(chapter_key, stage_index) + PlayerCopy.from_canonical(str(Registry.stage_presentation(chapter_key,stage_item)["hint_" + for_role]), online_session == null) + (PlayerCopy.RELAY_PREVIEW_441E8D9C7D61 if online_session != null else PlayerCopy.RELAY_PREVIEW_DC436BB6F967)

func _turn_title(stage_index: int, for_role: String) -> String:
	return "%d / %d  ·  %s" % [stage_index + 1, definition.stages.size(), "Leave a path" if for_role == "a" else "Follow the recording"]

func _room_panel_fits() -> bool:
	# Wide screens use the side panel; narrow ones keep the centred card.
	return ui.size.x >= 880

func _ordinary_room_card(title: String, hint: String) -> VBoxContainer:
	_plain_card("", "")
	# The ordinary card's deferred width constraints must not own this layout.
	controls.modal_scroll = null
	controls.modal_stack = null
	for child: Node in overlay.get_children():
		if child == controls.modal_shade: continue
		overlay.remove_child(child)
		child.queue_free()
	controls.modal_shade.color = Color(0.025,0.10,0.10,0.26)
	_room_ready_panel = RoomReadyPanel.new()
	overlay.add_child(_room_ready_panel)
	var card: VBoxContainer = _room_ready_panel.build(str(chapter.title),title,hint,title_font,_leave)
	_room_ready_panel.scene_space.resized.connect(_frame_ready_world.call_deferred)
	var camera: Camera3D = world.camera
	_room_camera = {"transform":camera.transform,"size":camera.size,"keep_aspect":camera.keep_aspect,"h_offset":camera.h_offset,"v_offset":camera.v_offset}
	world.set_process(false)
	_frame_ready_world.call_deferred()
	return card

## Frames the scene beside the room panel: the whole chapter, then eased in
## closer on the spirits (WaitFraming) while waiting or before recording.
func _frame_ready_world() -> void:
	if _room_camera.is_empty() or not is_instance_valid(_room_ready_panel) or mode not in ["ready", "online_waiting"]: return
	var target: Rect2 = _room_ready_panel.scene_space.get_global_rect()
	if target.size.x < 80 or target.size.y < 60: return
	var camera: Camera3D = world.camera
	var shown: Dictionary = WaitFraming.of(camera) if _room_framed else _shown_framing.get("framing", {}) if _shown_framing.get("frame", -1) == Engine.get_process_frames() else {}
	_shown_framing = {}
	camera.transform = _room_camera.transform
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.h_offset = _room_camera.h_offset
	camera.v_offset = _room_camera.v_offset
	var viewport := get_viewport().get_visible_rect()
	var whole := WaitFraming.whole(camera, float(_room_camera.size), target, viewport)
	WaitFraming.apply(camera, whole)
	var goal := WaitFraming.closer(camera, _framing_points(), target, viewport)
	_room_framed = true
	_ease_camera(camera, shown if not shown.is_empty() else whole, whole if goal.is_empty() else goal)

## The spirits on the scene, and on this player's turn the goal pieces too.
func _framing_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for actor: Variant in world.actors.values():
		if is_instance_valid(actor) and actor.is_visible_in_tree(): points.append(actor.global_position)
	if mode == "ready" and world.has_method("_doze_anchors"):
		for anchor: Node3D in world._doze_anchors():
			if is_instance_valid(anchor) and anchor.is_inside_tree(): points.append(anchor.global_position)
	return points

func _ease_camera(camera: Camera3D, from: Dictionary, to: Dictionary) -> void:
	_stop_camera_ease()
	if bool(settings.get("reduced_motion", false)) or WaitFraming.same(from, to):
		WaitFraming.apply(camera, to)
		return
	WaitFraming.apply(camera, from)
	_camera_tween = create_tween()
	_camera_tween.tween_method(func(weight: float): if is_instance_valid(camera): WaitFraming.apply(camera, WaitFraming.blend(from, to, weight)), 0.0, 1.0, FRAMING_EASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_camera_ease() -> void:
	if is_instance_valid(_camera_tween): _camera_tween.kill()
	_camera_tween = null

func _restore_ready_world() -> void:
	if _room_camera.is_empty(): return
	_stop_camera_ease()
	if is_instance_valid(world) and is_instance_valid(world.camera):
		var camera: Camera3D = world.camera
		# A redraw that frames again this frame eases on from here.
		if _room_framed: _shown_framing = {"frame": Engine.get_process_frames(), "framing": WaitFraming.of(camera)}
		camera.transform = _room_camera.transform
		camera.size = _room_camera.size
		camera.keep_aspect = _room_camera.keep_aspect
		camera.h_offset = _room_camera.h_offset
		camera.v_offset = _room_camera.v_offset
	_room_framed = false
	_room_camera.clear()

func _add_room_status_chip(card: VBoxContainer, fixed_text: String = "") -> PanelContainer:
	# One pill for the room's status: fixed text when the room snapshot already
	# knows it, otherwise the live presence label.
	var text: Label
	if not fixed_text.is_empty():
		text = _label(fixed_text, 16)
		text.add_theme_color_override("font_color", MINT)
	elif _presence_available():
		text = _presence_badge()
	else:
		return null
	var chip := PanelContainer.new()
	chip.name = "RoomStatusChip"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CHIP_FILL, 14), 14.0, 6.0))
	chip.add_child(text)
	card.add_child(chip)
	return chip


## The friend-nickname store; tests pass one with its own file. Left empty, the
## device's saved nicknames are read when the waiting card is drawn.
var nickname_store: RefCounted = null
func _waiting_partner_name(room: Dictionary) -> String:
	# The viewer's slot is p0 when they host and p1 when they joined, so the
	# partner is the other player id. Use the local nickname when one is saved,
	# otherwise "a friend" (as the room hub does). Never the raw id.
	var id := _partner_id(room)
	if id.is_empty(): return ""
	var scope: Dictionary = online_session.nickname_scope() if online_session != null and online_session.has_method("nickname_scope") else {}
	if scope.is_empty(): return FriendNicknames.FALLBACK
	var names: RefCounted = nickname_store if nickname_store != null else FriendNicknames.new()
	return names.display_name(str(scope.server), str(scope.owner), id)


## The Pollen the viewer's latest turn in this room earned, once the server
## confirmed it, on the screen drawn after that turn (`mode` names it). Each
## credit shows once (presentation/pollen_result_line.gd once). A turn still
## being sent has no credit yet, and the last receipt is then an earlier turn's.
var _pollen_seen: Dictionary = {}
func _add_pollen_line(parent: Container) -> void:
	if online_session == null or not online_session.has_method("nickname_scope") or not journey.pending().is_empty(): return
	var line := PollenResultLine.once(_pollen_seen, mode, online_session.nickname_scope(), journey.last_receipt(), _waiting_partner_name(journey.snapshot()), MUTED)
	if line != null: parent.add_child(line)


## Each slot's pip in its own player's look (presentation/slot_looks.gd). A live
## turn and the waiting view dress the viewer in their own look and the partner
## in theirs, with `recordings` that play in the turn in their own turn's look; a
## replay (`replay`) dresses each slot in its recording's look only. Solo play
## has no room, so its pips keep the default look.
func _dress(recordings: Array, replay: bool = false) -> void:
	if not is_instance_valid(world) or not world.has_method("wear_slots"): return
	var room: Dictionary = journey.snapshot() if online_session != null and journey != null and journey.has_method("snapshot") else {}
	world.wear_slots(SlotLooks.replay(recordings) if replay else SlotLooks.live(room, recordings))


## The other player's id: the viewer's slot is p0 when they host, p1 when they joined.
func _partner_id(room: Dictionary) -> String:
	var partner: Variant = room.get("guest_id") if room.get("player_slot") == "p0" else room.get("host_id")
	return str(partner) if partner != null else ""


## A replay names each spirit from this player's side: "You", and the friend
## by the nickname given to them. Live turns keep their usual badges. The room
## and nickname are read once per room view, not every tick.
var _replay_label: Dictionary = {}
func _replay_badges(state: Dictionary) -> Dictionary:
	if _replay_label.is_empty():
		var room: Dictionary = journey.snapshot() if journey != null and journey.has_method("snapshot") else {}
		var slot := str(room.get("player_slot", ""))
		var partner: Variant = room.get("guest_id") if slot == "p0" else room.get("host_id")
		var scope: Dictionary = online_session.nickname_scope() if partner is String and online_session != null and online_session.has_method("nickname_scope") else {}
		_replay_label = {"slot": slot, "name": "" if scope.is_empty() else FriendNicknames.new().nickname(str(scope.server), str(scope.owner), str(partner))}
	return preload("res://presentation/kit/badges.gd").viewer_labels(state, _replay_label.slot, _replay_label.name)


func _viewer_is_first(room: Dictionary) -> bool:
	var viewer: Variant = room.get("host_id") if room.get("player_slot") == "p0" else room.get("guest_id")
	return viewer != null and room.get("first_player_id") == viewer


func _viewer_saved_turn(room: Dictionary) -> bool:
	# The viewer recorded this stage's first turn and the partner follows it.
	return not room.is_empty() and str(room.get("active_role", "")) == "b" and _viewer_is_first(room)


func _waiting_details_stage() -> Dictionary:
	var room: Dictionary = journey.snapshot()
	if room.is_empty() or int(room.get("stage_index", definition.stages.size())) >= definition.stages.size(): return {}
	return _simulation.stage_by_id(definition, str(room.get("stage_id", "")))


func _show_waiting_details() -> void:
	var item := _waiting_details_stage()
	if item.is_empty(): return
	var room: Dictionary = journey.snapshot()
	mode = "room_details"
	var details := _card(str(chapter.title), _chapter_body(int(room.stage_index), "a" if _viewer_is_first(room) else "b", item))
	details.add_child(_action_button("back", _show_ready))


func _share_available() -> bool:
	return online_session != null and not online_session.invitation_code().is_empty() and share_current_room.is_valid()


func _notifications_available() -> bool:
	return turn_notification_status.is_valid() and enable_turn_notifications.is_valid()


## The other player closed this room (or it is otherwise gone for good).
func _room_gone() -> bool:
	return online_session != null and journey.has_method("room_gone") and journey.room_gone()

## A gone room has nothing left to wait for or retry: say so once and offer
## the way back. Polling stops here (this mode is not polled).
func _show_room_gone() -> void:
	mode = "room_gone"
	var card := _card(ROOM_CLOSED, PlayerCopy.ROOMS_API_A7ACF38988EE)
	var rooms := _button(RoomActions.label("your_rooms"), _leave)
	rooms.name = "YourRooms"
	card.add_child(rooms)

func _show_online_waiting() -> void:
	if _room_gone():
		_show_room_gone()
		return
	if hard_flow.holds(): return
	mode = "online_waiting"
	var room: Dictionary = journey.snapshot()
	var pending: Dictionary = journey.pending()
	if not room.is_empty() and room.stage_index < definition.stages.size():
		var display_sim: RefCounted = _simulation.new()
		var first: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
		if display_sim.reset(definition,room.stage_id,room.checkpoint,first,room.active_role):
			_dress([first])
			_present_stage_history(_simulation.stage_by_id(definition,room.stage_id),room.checkpoint)
			var display: Dictionary = display_sim.snapshot()
			# The verified room identifies the viewer; the simulation still owns
			# the active player. This hint belongs only to this waiting preview.
			if room.get("player_slot") in ["p0", "p1"]: display["viewer_slot"] = room.player_slot
			world.present(display,true)
	var notices: PackedStringArray = []
	if not pending.is_empty():
		notices.append(PlayerCopy.SHARED_TURN_HELD_HINT if pending.get("held", false) else PlayerCopy.RELAY_PREVIEW_53416F9C53E3)
	elif room.is_empty():
		notices.append(PlayerCopy.RELAY_PREVIEW_17179ABFBE5C)
	if not journey.last_error.is_empty(): notices.append(journey.last_error)
	if not online_session.mutations_enabled(): notices.append(PlayerCopy.RELAY_PREVIEW_F8EBEB9FEF49.strip_edges())
	# Concept 06: what happened, whose turn is next, then the one thing to do.
	var joined: bool = not room.is_empty() and room.get("guest_id") != null
	var partner_present: bool = joined or not pending.is_empty()
	var saved: bool = not pending.is_empty() or _viewer_saved_turn(room)
	var partner := _waiting_partner_name(room)
	var whose := WAITING_FOR_PARTNER_TURN % (partner if not partner.is_empty() else "your friend")
	var heading := WAITING_TURN_SAVED if saved else whose if partner_present else WAITING_FOR_FRIEND
	var subline := whose if saved and partner_present else "" if room.is_empty() else PlayerCopy.RELAY_PREVIEW_06FE980C1040
	notification_hint = null
	notification_offer = null
	_waiting_notify_section = false
	_waiting_notify_offered = false
	if _room_panel_fits():
		_show_waiting_panel(room, heading, subline, whose, partner_present, saved, notices)
		return
	# The narrow card: the chip carries the room status the heading does not state.
	var chip_text := ""
	if not joined: chip_text = WAITING_FOR_FRIEND if heading != WAITING_FOR_FRIEND else ""
	elif not _presence_available(): chip_text = FRIEND_JOINED
	var card := _plain_card(heading, "")
	card.get_child(1).visible = false
	if heading == whose: card.get_child(0).name = "WaitingPartnerLine"
	var chip: PanelContainer = _add_room_status_chip(card, chip_text) if joined or not chip_text.is_empty() else null
	if chip != null: card.move_child(chip, 0)
	RoomPageBuilder.waiting_lines(card, subline, whose, notices)
	if saved: _add_pollen_line(card)
	_set_room_state("waiting_card")
	var facts := _room_facts()
	_add_room_actions(card, "waiting_card", "invite", facts)
	_add_room_actions(card, "waiting_card", "turn", facts)
	refresh_flow.add_sync_status(card)
	_add_room_actions(card, "waiting_card", "more", facts)

## Concept 04 and 05: the friend strip, then what happened and whose turn is
## next, then the panel's actions.
func _show_waiting_panel(room: Dictionary, heading: String, subline: String, whose: String, partner_present: bool, saved: bool, notices: PackedStringArray) -> void:
	var card := _ordinary_room_card(_room_stage_title(), "")
	var facts := _room_facts()
	_set_room_state(RoomActions.panel_state("waiting", facts))
	var top := RoomPageBuilder.group(card, 4)
	# Before a friend arrives the strip says so, and carries the saved turn.
	_add_friend_strip(top, room.get("guest_id") != null, WAITING_TURN_SAVED if saved and not partner_present else "")
	if partner_present:
		var gap := Control.new()
		gap.custom_minimum_size.y = 8
		top.add_child(gap)
		var title := _label(heading, 30)
		title.add_theme_font_override("font", title_font)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if heading == whose: title.name = "WaitingPartnerLine"
		top.add_child(title)
	RoomPageBuilder.waiting_lines(top, subline if partner_present or not saved else "", whose, notices)
	if saved: _add_pollen_line(top)
	_add_room_actions(top, _room_state, "status", facts)
	_add_room_panel_actions(card, facts)
	refresh_flow.add_sync_status(card, true)
	online_sync_status.add_theme_color_override("font_color", MUTED)
	online_sync_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_sync_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

## Share sends the room to all friends; its result replaces the status text,
## which otherwise reads `status`'s idle text.
func _wire_share(share: Button, status: Label) -> void:
	share.name = "ShareCurrentRoom"
	share.accessibility_name = RoomActions.SHARE
	status.name = "RoomShareStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.set_meta("idle_text", status.text)
	share.set_meta("status", status)
	share.pressed.connect(_share_room_from_card.bind(share, status))
	_style_share(share)


func _share_target() -> Dictionary:
	return {"api_version": 2, "room_id": str(journey.snapshot().get("room_id", ""))}


func _room_shared() -> bool:
	return room_share_state.is_valid() and room_share_state.call(_share_target()).get("shared", false)


## Restyles the Share controls in place after this room's sharing changes.
func update_share_controls(message: String = "") -> void:
	# Room options sits beside the overlay, under the same UI root.
	if not is_instance_valid(ui): return
	for share: Button in ui.find_children("ShareCurrentRoom", "Button", true, false): _style_share(share, message)


func _style_share(share: Button, message: String = "") -> void:
	# A shared room offers Stop sharing; otherwise the original Share text.
	var state: Dictionary = room_share_state.call(_share_target()) if room_share_state.is_valid() else {}
	var shared: bool = state.get("shared", false)
	var text: String = RoomActions.STOP_SHARING if shared else RoomActions.SHARE
	# A Room options row shows its label in its own title.
	if share.has_meta("title"): (share.get_meta("title") as Label).text = text
	else: share.text = text
	share.accessibility_name = text
	share.tooltip_text = text if share.icon != null else ""
	share.disabled = _sharing_room or state.get("busy", false) or online_session.busy()
	var status: Variant = share.get_meta("status", null)
	if status is Label and is_instance_valid(status):
		RoomPageBuilder.set_feedback(status, message if not message.is_empty() else RoomActions.SHARED if shared else str(status.get_meta("idle_text", "")))


func _open_room_options(opener: Control = null) -> void:
	if is_instance_valid(_room_options_modal) or not _room_state_current() or running or _leaving: return
	var facts := _room_facts()
	var columns := RoomActions.option_columns(_room_state, facts)
	if columns.all(func(column: Array): return column.is_empty()): return
	_room_options_modal = InGameModal.open(ui, "RoomOptionsModal", RoomActions.label("room_options"), str(chapter.title), opener)
	_room_options_modal.closed.connect(func(): _room_options_modal = null)
	_room_options_modal.widen(880)
	var content: VBoxContainer = _room_options_modal.content
	content.add_theme_constant_override("separation", 14)
	content.add_child(RoomFriendStrip.card(_friend_strip(journey.snapshot().get("guest_id") != null, "", 52.0), _room_stage_title()))
	# The modal's heading, card and padding take about 280 of the screen's height.
	var sheet := RoomOptionsSheet.new(content, ui.size.y - 280.0)
	for side in range(columns.size()):
		for group: Dictionary in columns[side]:
			var section: Dictionary = RoomActions.SECTIONS[group.section]
			sheet.heading(side, section.title)
			for id: String in group.ids:
				_wire_room_option(sheet.row(side, RoomActions.icon(id), RoomActions.label(id, facts), section.get("danger", false)), id)

## A Room options row runs its action once the sheet closes, unless the row
## has an option hook that wires it.
func _wire_room_option(row: Button, id: String) -> void:
	var hooks: Dictionary = _room_action_hooks()[id]
	if hooks.has("option"):
		hooks.option.call(row, id)
		return
	assert(not hooks.has("widget"), "A widget room action needs its own Room options row: " + id)
	row.pressed.connect(_room_option.bind(_room_action_handler(id)))

## Option rows (option hooks): each takes the sheet row and the id, and
## answers in place on the row's second line.

func _wire_copy_code_option(row: Button, _id: String) -> void:
	row.pressed.connect(_copy_invitation.bind(row.get_meta("subtitle")))

func _wire_share_option(row: Button, id: String) -> void:
	var status: Label = row.get_meta("subtitle")
	status.text = str(RoomActions.ACTIONS[id].line)
	status.visible = true
	_wire_share(row, status)


func _room_option(action: Callable) -> void:
	_close_room_options()
	if not _room_state_current() or running or _leaving: return
	action.call()


func _close_room_options() -> void:
	if is_instance_valid(_room_options_modal): _room_options_modal.close(false)
	_room_options_modal = null


func _refresh_waiting_panel() -> void:
	# Turn-notification registration moves the panel's primary action.
	if mode != "online_waiting" or running or _leaving or not _waiting_notify_section or not turn_notification_status.is_valid(): return
	if (not turn_notification_status.call().get("registered", false)) != _waiting_notify_offered: _show_ready()


## The photo row: a receipt-backed way back to an unfinished optional photo even
## before the partner completes this stage and its combined replay is available.
func _offer_recent_photo(receipt: Dictionary) -> void:
	reaction_photos.offer(receipt, _show_ready)

func _recent_photo_receipt() -> Dictionary:
	if not is_instance_valid(reaction_photos) or not journey.pending().is_empty(): return {}
	var receipt: Dictionary = journey.last_receipt()
	return receipt if Typed.equal(receipt.get("operation"), "turns") else {}

func _ordinary_redo_available() -> bool:
	return online_session != null and journey != null

## The redo rows on a card outside the room panel (pause, review).
func _add_redo_action(card: VBoxContainer) -> void:
	_add_redo_actions_to(card)

## The redo actions this room or journal offers now, into any row or column.
func _add_redo_actions_to(parent: Container) -> void:
	var facts := _room_facts()
	for id: String in RoomActions.REDO_ACTIONS: _add_room_action(parent, id, facts)

## Whether this online room offers a redo button now. Reading it binds the
## room's redo client.
func _redo_offered() -> bool:
	if not _ordinary_redo_available() or not journey.pending().is_empty(): return false
	var client: RefCounted = online_session.redo_client()
	if not client.busy: client.bind_room("relay",journey.snapshot())
	if not online_session.mutations_enabled() and client.pending().is_empty(): return false
	return not (RedoClient.source_for("relay",journey.snapshot()).is_empty() and client.pending().is_empty())

## Drawn with Redo requested: a friend's request is also announced once.
func _announce_pending_redo(_button: Button = null) -> void:
	var client: RefCounted = online_session.redo_client()
	if client.can_accept(): _announce_redo_request.call_deferred(client,str(journey.snapshot().get("room_id","")))

func _announce_redo_request(client: RefCounted, room_id: String) -> void:
	if is_inside_tree() and not running: redo_notice.announce(ui, client, room_id, _open_redo)

func _open_redo() -> void:
	if not _ordinary_redo_available() or online_session.busy() or running or backgrounded or _room_context_lost or is_instance_valid(_redo_screen): return
	if mode not in ["ready", "online_waiting", "paused", "review"]: return
	var client: RefCounted = online_session.redo_client()
	if not client.bind_room("relay",journey.snapshot()): return
	var previous_mode := mode
	mode = "redo_requests"
	ui.visible = false
	_redo_screen = RedoScreen.new()
	_redo_screen.client = client
	_redo_screen.allow_mutations = online_session.mutations_enabled()
	_redo_screen.closed.connect(func():
		var accepted: bool = _redo_screen.accepted or client.accepted
		_redo_screen = null
		if _leaving or not is_inside_tree(): return
		ui.visible = true
		if accepted:
			# Reconcile the accepted fork before exposing any saved recording
			# controls. The old dependent draft stays durable until that succeeds.
			if not backgrounded and not online_session.busy(): _online_refresh()
			# A read that could not start (the server asked to wait, or the
			# session is busy) waits on the waiting card, which reads the room
			# when it may.
			if mode == "redo_requests":
				mode = "online_waiting"
				_show_online_waiting()
				online_refresh_queued = true
		elif previous_mode == "paused":
			_restore_paused_draft()
		elif previous_mode == "review":
			if client.pending().get("action") == "accept":
				# A redo accepted from review: the room is read again soon.
				refresh_schedule.note_activity(Time.get_ticks_msec())
				_show_online_waiting()
			else: _show_review()
		else:
			_show_ready()
			if not backgrounded and not online_session.busy(): _online_refresh()
			else: online_refresh_queued = true)
	add_child(_redo_screen)

func _restore_paused_draft() -> void:
	if not _reset_live(true):
		hard_flow.resume_failed()
		return
	var draft: Dictionary = journey.draft()
	sim.catch_assistance = bool(draft.get("catch_assistance", true))
	# A resumed draft is the same try, after an app restart too.
	_live_tries = turn_tries.resume(_tries_slot())
	_try_due = false
	_fast_forward(draft)
	_wait().show(sim.snapshot(), true)
	running = false
	mode = "paused"
	var card := _card("Take your time.", PlayerCopy.RELAY_PREVIEW_50922961D853)
	card.add_child(_action_button("resume", _start_play))
	card.add_child(_action_button("retry", _begin))
	_add_safety_action(card)
	_add_redo_action(card)
	card.add_child(_action_button("back", _leave))

## Solo "Redo my previous turn": each tap takes back one saved turn through
## the journey's own plan. Online rooms keep the request flow above.
const SOLO_REDO_MODES := ["ready", "review", "paused", "checkpoint", "complete"]

func _solo_redo_plan() -> Dictionary:
	if online_session != null or _solo_replay_only or _solo_replay_context_error: return {}
	if journey == null or not journey.has_method("redo_plan") or journey.read_only or mode not in SOLO_REDO_MODES: return {}
	return journey.redo_plan()

func _confirm_solo_redo() -> void:
	if backgrounded or running: return
	var plan := _solo_redo_plan()
	var copy := SoloRedoOffer.confirm_copy(plan)
	if copy.is_empty(): return
	var previous_mode := mode
	var saved_journey: RefCounted = journey
	var saved_review := review.duplicate(true)
	var key := chapter_key
	mode = "confirm_solo_redo"
	var card := _card(str(copy.title), str(copy.body))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_solo_redo" and not backgrounded and not running and online_session == null and chapter_key == key and journey == saved_journey and review == saved_review and not journey.read_only and journey.redo_plan() == plan
	card.add_child(_button(str(copy.confirm), func():
		if current.call(): _run_solo_redo(plan, previous_mode)))
	_retry_cancel = func():
		if current.call(): _return_from_solo_redo(previous_mode)
	card.add_child(_action_button("cancel", _retry_cancel))

## Cancel puts back the card the offer came from, without saving anything.
func _return_from_solo_redo(previous_mode: String) -> void:
	match previous_mode:
		"review": _show_review()
		"checkpoint": _after_accept()
		"complete": _show_completed()
		"paused":
			# The paused turn is still this screen's simulation; Resume goes on from it.
			mode = "paused"
			var card := _card("Take your time.", PlayerCopy.RELAY_PREVIEW_50922961D853)
			card.add_child(_action_button("resume", _start_play))
			card.add_child(_action_button("retry", _begin))
			_add_safety_action(card)
			_add_redo_action(card)
			card.add_child(_action_button("back", _leave))
		_: _show_ready()

func _run_solo_redo(plan: Dictionary, previous_mode: String = "ready") -> void:
	if online_session != null or journey == null or not journey.has_method("redo_previous"): return
	# A first turn's review may be setting up the turn after it. That turn
	# belongs to the journey being taken back, so the reaper joins its worker.
	_drop_prefetch()
	var work := func():
		if not journey.redo_previous(plan):
			# The journey is unchanged; put back the card the player came from.
			var reason: String = journey.last_error
			_return_from_solo_redo(previous_mode)
			_note_refusal(reason)
			return
		_restart_tries()
		_fresh_live = {}
		review = {}
		replay_pair_index = -1
		_show_ready()
	# Reopening a stage replays the kept chain on this thread, and so can
	# setting up the next turn; say so first, as Save turn does.
	var slow: bool = plan.get("kind") == "stage" or (journey.has_method("expected_wait_usec") and journey.expected_wait_usec() >= VISIBLE_WAIT_USEC)
	if backgrounded or not is_processing() or not slow:
		work.call()
		return
	mode = "turn_wait"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_DA74C3A728FC, "")
	for line: Node in card.get_children():
		if line is Label and (line as Label).text.is_empty(): (line as Label).visible = false
	_wait_then = work
	_wait_frames = 0

## A refused redo or retry leaves the journey as it was, so its reason goes on
## the card the player is back on instead of a card with only Back.
func _note_refusal(reason: String) -> void:
	if reason.is_empty() or mode == "error" or not is_instance_valid(controls.modal_stack): return
	var note := Label.new()
	note.name = "RefusalNote"
	note.text = reason
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 550
	note.add_theme_font_size_override("font_size", 20)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.modal_stack.add_child(note)
	controls.modal_stack.move_child(note, mini(2, controls.modal_stack.get_child_count() - 1))

func _refresh_redo() -> bool:
	if not _ordinary_redo_available() or backgrounded or _room_context_lost or not journey.pending().is_empty(): return false
	var client: RefCounted = online_session.redo_client()
	if client.busy: return false
	var before: Dictionary = client.view()
	var room: Dictionary = journey.snapshot()
	if RedoClient.source_for("relay",room).is_empty() and client.pending().is_empty(): return false
	if not client.bind_room("relay",room): return false
	await client.refresh()
	return before != client.view()

## The narrow card's line saying whether the friend has joined.
func _add_friend_status(card: VBoxContainer, joined: bool) -> void:
	var friend_status := _label(FRIEND_JOINED if joined else WAITING_FOR_FRIEND,20)
	friend_status.name = "RoomFriendStatus"
	friend_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(friend_status)

## The friend strip at the top of the wide room panel.
func _add_friend_strip(parent: VBoxContainer, joined: bool, waiting_line: String = "") -> void:
	parent.add_child(_friend_strip(joined, waiting_line, 44.0 if _room_ready_panel.short_layout else 52.0))

## The friend's avatar, name and presence; before a friend joins, the waiting
## title with `waiting_line` under it. Presence waits for the friend too.
func _friend_strip(joined: bool, waiting_line: String, avatar_size: float) -> HBoxContainer:
	if not joined:
		return RoomFriendStrip.build("", WAITING_FOR_FRIEND, RoomFriendStrip.line(waiting_line) if not waiting_line.is_empty() else null, title_font, avatar_size)
	var room: Dictionary = journey.snapshot()
	var status: Label = _presence_badge() if _presence_available() else RoomFriendStrip.line(FRIEND_JOINED)
	var strip := RoomFriendStrip.build(_partner_id(room), FriendNicknames.sentence_start(_waiting_partner_name(room)), status, title_font, avatar_size)
	EndReactionScreen.attach_friend_latest(_end_reaction_context(), strip)
	return strip

## The stage the room panel is on, as its title row says it.
func _room_stage_title() -> String:
	if mode == "ready": return _turn_title(int(checkpoint.stage_index), role)
	var room: Dictionary = journey.snapshot()
	if room.is_empty() or int(room.get("stage_index", definition.stages.size())) >= definition.stages.size(): return ""
	return _turn_title(int(room.stage_index), "a" if _viewer_is_first(room) else "b")

## The invitation code row (RoomPageBuilder.invitation_code_row).
func _add_invitation_code_row(card: Container, _id: String, _facts: Callable, look: Dictionary) -> Button:
	RoomPageBuilder.invitation_code_row(card, ShareCodes.display(ShareCodes.ROOM, online_session.invitation_code()), look, _copy_invitation)
	return null

func _share_room_from_card(button: Button, status: Label) -> void:
	if _sharing_room or backgrounded or running or _leaving or _room_context_lost or online_session == null or online_session.busy() or not share_current_room.is_valid() or not is_instance_valid(button) or not button.is_inside_tree(): return
	var target := _share_target()
	# An automatic share already in flight owns the request; the button waits.
	if room_share_state.is_valid() and room_share_state.call(target).get("busy", false): return
	var source: RefCounted = journey
	var stop := _room_shared()
	button.disabled = true
	_sharing_room = true
	var result: Dictionary = await share_current_room.call(target, not stop)
	_sharing_room = false
	if not is_inside_tree() or backgrounded or running or _leaving or source != journey or target.room_id != journey.snapshot().get("room_id") or not is_instance_valid(button) or not button.is_inside_tree() or result.get("ignored", false): return
	update_share_controls(str(result.get("message", "Friends unavailable")))

func _copy_invitation(status: Label) -> void:
	# Copy the typed room-<code>; joining accepts it and strips the prefix.
	var code: String = ShareCodes.format(ShareCodes.ROOM, online_session.invitation_code()) if online_session != null else ""
	if code.is_empty() or not clipboard_copy.is_valid() or clipboard_copy.call(code) != true:
		RoomPageBuilder.set_feedback(status, PlayerCopy.RELAY_PREVIEW_6D5192F38DBE)
		return
	RoomPageBuilder.set_feedback(status, PlayerCopy.RELAY_PREVIEW_87AB91E6F763)

static func _copy_with_display_server(code: String) -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	DisplayServer.clipboard_set(code)
	return DisplayServer.clipboard_get() == code


## Room reads live in presentation/room_refresh_flow.gd. Its room actions,
## _process and tests call these names on the screen.
func _online_refresh() -> void:
	await refresh_flow.manual()

func _service_online_refresh() -> void:
	await refresh_flow.service()

func _online_refresh_context() -> String:
	return refresh_flow.context()

static func poll_changed(source: RefCounted, before: Dictionary, before_my_turn: bool, saved_pending: Dictionary, succeeded: bool, redo_changed: bool) -> bool:
	return RoomRefreshFlow.poll_changed(source, before, before_my_turn, saved_pending, succeeded, redo_changed)


func identity_invalidated() -> void:
	online_request_generation += 1
	if is_instance_valid(_redo_screen):
		_redo_screen.invalidate()
		_redo_screen = null
		ui.visible = true
	_clear_reaction_view()
	if is_instance_valid(reaction_photos):
		reaction_photos.invalidate()
	running = false
	if is_instance_valid(ui):
		_show_error(PlayerCopy.RELAY_PREVIEW_34409DD3D3AA)


func _pairs() -> Array:
	if online_session == null and not _replay_collection.is_empty(): return _replay_collection.duplicate(true)
	return online_session.chapter_pairs() if online_session != null else journey.pairs()


func _begin() -> void:
	if _room_context_lost: return
	if online_session != null and online_session.busy(): return
	if not _reset_live():
		return
	review = {}
	replay_pair_index = -1
	# The first start of a turn, each Retry and a restart after a failed ending.
	# A turn's first start is counted at its first tick (advance_input): one
	# stopped before it (a pause, Back or the app sent away during the glance
	# at the goal) is not a try, so a hard run goes on from it. Every later
	# start counts at once.
	# The slot is taken once here: building it copies the turn's recordings.
	_try_slot = _tries_slot()
	_live_tries = turn_tries.next(_try_slot)
	_try_due = _live_tries == 1
	if not _try_due: _live_tries = turn_tries.start(_try_slot)
	if hard_flow.slipped_on_start(_live_tries): return
	world.present(sim.snapshot(), true)
	_start_play()
	_glance_at_goal()


## The turn being played, for its try count (services/turn_tries.gd).
func _tries_slot() -> String:
	return TurnTries.slot_for(journey, _tries_chapter(), online_session != null)

## A solo hard run counts its tries apart from the chapter's own.
func _tries_chapter() -> String:
	return hard_flow.tries_chapter(chapter_key)

## Taking back a turn or restarting the chapter starts every solo count again.
func _restart_tries() -> void:
	turn_tries.restart_solo(_tries_chapter())

func _show_tries() -> void:
	var tries := _live_tries if mode == "play" else 0
	# A hard run has no second try: its pill says so and where the run is.
	var label: String = hard_flow.hud_label(int(checkpoint.get("stage_index", 0)), definition.stages.size()) if mode == "play" else ""
	var shown := "%d|%s" % [tries, label]
	if shown == _shown_pill: return
	_shown_pill = shown
	if label.is_empty(): controls.show_tries(tries)
	else: controls.show_tries(tries, label)


## Begin and Resume stay live while a room poll (or another room request) is
## out. A tap made then waits in the busy-tap gate (presentation/busy_tap_gate.gd),
## the latest one only, with the tapped button reading "Checking room…", and runs
## when the request lands if it is still this player's turn on the same stage.
## One that waits past the gate's limit gives the card back as it was.
var _turn_gate: BusyTapGate
var _turn_gate_action := ""

func _turn_tap(action: String) -> void:
	if _turn_gate == null: _turn_gate = BusyTapGate.new(controls)
	var key := _turn_key()
	_turn_gate_action = action
	await _turn_gate.tap(_ready_turn_buttons.get(action), PlayerCopy.ROOM_CHECKING,
		func() -> bool: return online_session == null or not online_session.busy(),
		_run_turn_tap.bind(action),
		func() -> bool: return mode == "ready" and not _leaving and (online_session == null or (journey.my_turn() and _turn_key() == key)),
		_show_ready)

func _run_turn_tap(action: String) -> void:
	if action == "resume": _after_visible_wait(_resume_draft)
	else: _begin()

func _turn_key() -> String:
	var room: Dictionary = journey.snapshot() if online_session != null else {}
	return "%s:%s:%s" % [str(room.get("branch", "")), str(room.get("stage_index", "")), str(room.get("active_role", ""))]

func _reset_live(resume_draft: bool = false) -> bool:
	if _ordinary_redo_available() and online_session.redo_client().pending().get("action") == "accept":
		_show_online_waiting()
		return false
	var reuse: bool = not resume_draft and _fresh_live_unchanged()
	var live: RefCounted = sim if reuse else (null if resume_draft else _take_prefetch())
	if live == null: live = journey.create_live_simulation(resume_draft)
	if live == null:
		_fresh_live = {}
		_show_error(journey.last_error)
		return false
	sim = live
	_fresh_live = _live_fingerprint(sim) if not resume_draft and online_session == null and journey.has_method("is_live_simulation") else {}
	_begin_sound_turn()
	_begin_memory_wait(journey.role(), journey.prior_recording(), true)
	_begin_run_reactions(true, {}, journey.prior_recording())
	# A family with no catch to assist (the Lighthouse) always records false.
	sim.catch_assistance = bool(settings.get("assistance", true)) and Registry.catch_assistance(chapter_key)
	_dress([journey.prior_recording()])
	_present_stage_history(_simulation.stage_by_id(definition,journey.stage_id()),journey.checkpoint())
	return true

## The ready card's simulation can start the turn when the journey still holds
## it as its live engine, it has not moved, and nothing has reset it since: a
## reset with these same inputs would build exactly this state again.
func _fresh_live_unchanged() -> bool:
	if _fresh_live.is_empty() or online_session != null or sim == null or not journey.has_method("is_live_simulation") or not journey.is_live_simulation(sim): return false
	if Journey.tick_of(sim) != 0 or not str(sim.get("error")).is_empty(): return false
	var now := _live_fingerprint(sim)
	return now == _fresh_live and now.role == journey.role() and now.stage == journey.stage_id() and now.checkpoint == str(journey.checkpoint().get("checkpoint_hash", "")) and now.prior == Canonical.digest(journey.prior_recording())

func _live_fingerprint(simulation: RefCounted) -> Dictionary:
	var held_stage: Variant = simulation.get("stage")
	var held_checkpoint: Variant = simulation.get("_checkpoint")
	return {"id": simulation.get_instance_id(), "role": str(simulation.get("role")), "stage": str(held_stage.get("id", "")) if held_stage is Dictionary else "",
		"checkpoint": str(held_checkpoint.get("checkpoint_hash", "")) if held_checkpoint is Dictionary else "", "prior": Canonical.digest(simulation.get("_prior")), "rules": simulation.get("simulation_version")}

func _present_stage_history(authored: Dictionary, verified_checkpoint: Dictionary) -> void:
	world.present_stage(authored)
	if world.has_method("present_history"): world.present_history(verified_checkpoint)


func _start_play() -> void:
	if _room_context_lost: return
	_restore_ready_world()
	mode = "play"
	overlay.visible = false
	hud.visible = true
	running = true
	_update_hud(sim.snapshot())


## A turn's first try glances at its goal when the goal starts off screen
## (the world's goal beacon, presentation/kit/goal_beacon.gd): the camera eases
## there and back on the world's clock while the turn waits, so no tick passes
## and the recording, the timer and any memory start as they would without it.
## Any touch, stick or key skips it, and that input still counts; Reduce
## motion never shows it. Only _begin starts one, so a resumed draft and a
## replay never do, and any card ends it.
func _glance_at_goal() -> void:
	_glancing = false
	if _live_tries != 1 or bool(settings.get("reduced_motion", false)) or not world.has_method("glance_at_goal"): return
	_glancing = float(world.glance_at_goal()) > 0.0

func _end_glance() -> void:
	_glancing = false
	if is_instance_valid(world) and world.has_method("end_glance"): world.end_glance()

func _input(event: InputEvent) -> void:
	if _glancing and (event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventKey) and event.is_pressed(): _end_glance()


func _resume_draft() -> void:
	if _room_context_lost: return
	if online_session != null and online_session.busy(): return
	var draft: Dictionary = journey.draft()
	if not _reset_live(true):
		# A hard draft that cannot go on ends the run (presentation/hard_run_flow.gd).
		hard_flow.resume_failed()
		return
	sim.catch_assistance = bool(draft.get("catch_assistance", true))
	# A resumed draft is the same try, after an app restart too.
	_live_tries = turn_tries.resume(_tries_slot())
	_try_due = false
	_fast_forward(draft)
	_wait().show(sim.snapshot(), true)
	if sim.finished:
		review = draft
		_show_review()
	else:
		_start_play()


func _physics_process(_delta: float) -> void:
	if mode == "drowning":
		_advance_drown_beat()
		return
	if not running or backgrounded:
		return
	if _glancing:
		if world.glancing() and stick.value == Vector2.ZERO and not action_pressed: return
		_end_glance()
	var input: Dictionary
	if mode == "replay":
		if not _replay_ready(): return
		if replay_cursor >= replay_frames.size():
			_finish_replay_playback()
			return
		input = replay_frames[replay_cursor]
	elif _fast_forward_wait():
		return
	else:
		var move: Vector2 = stick.value
		var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if keyboard.length() > 0:
			move = keyboard.limit_length()
		var right: Vector3 = world.camera.global_basis.x
		var forward: Vector3 = world.camera.global_basis.z
		var direction := (Vector3(right.x, 0, right.z).normalized() * move.x + Vector3(forward.x, 0, forward.z).normalized() * move.y).limit_length()
		input = {"move_x": direction.x, "move_z": direction.z, "interact": action_pressed}
		action_pressed = false
	advance_input(input)


func advance_input(input: Dictionary) -> void:
	if _room_context_lost: return
	if mode == "replay":
		if not _replay_ready() or replay_cursor >= replay_frames.size(): return
		input = replay_frames[replay_cursor]
	# Both touch/keyboard input and input-driven QA use this single tick path.
	var state: Dictionary = sim.step(input)
	if mode == "replay": replay_cursor += 1
	if mode == "play" and _try_due:
		_try_due = false
		_live_tries = turn_tries.start(_try_slot)
	_wait().step(state, _turn_sounds(state), mode == "play")
	_run_player().step(int(state.tick))
	_update_hud(state)
	if mode == "play" and (int(state.tick) % 30 == 0 or hard_flow.saves_tick(int(state.tick))) and not state.finished and not _persist_draft("play", true):
		return
	if state.finished:
		if Registry.is_lighthouse(chapter_key) and state.get("beacon", {}).get("lit", false):
			_show_final_moment()
		elif mode == "replay":
			_finish_replay_playback()
		elif not state.get("drowned", {}).is_empty():
			_begin_drown_beat()
		else:
			_finish()

## A spirit drowned (journey tide rules): the world shows it going under for
## DROWN_BEAT_FRAMES physics frames, then the ending's beat (turn_endings.gd:
## its badge and line over the dimmed world, skipped by a tap), then its card.
## The rules keep no draft of such a turn (the earlier autosave is cleared),
## and the controls stop taking input while the beat shows.
func _begin_drown_beat() -> void:
	running = false
	action_pressed = false
	if not _persist_draft("review"): return
	mode = "drowning"
	_ending = TurnEndings.of(sim.snapshot(), online_session == null)
	_drown_frames = DROWN_BEAT_FRAMES + int(_ending.get("beat", 0))
	_update_hud(sim.snapshot())

func _advance_drown_beat() -> void:
	if backgrounded: return
	_drown_frames -= 1
	if _drown_frames == int(_ending.get("beat", 0)) and _drown_frames > 0: _show_ending_beat()
	if _drown_frames <= 0: _end_drown_beat()

## The ending's line, big, under its badge, over the dimmed world. Still; it
## only fades in, and not under Reduce motion. A tap goes straight on.
func _show_ending_beat() -> void:
	if _ending.is_empty(): return
	hud.visible = false
	# Whatever the overlay held before the turn (its intro card) goes first.
	for child: Node in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = true
	var beat := Control.new()
	beat.name = "EndingBeat"
	beat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	beat.mouse_filter = Control.MOUSE_FILTER_STOP
	beat.gui_input.connect(_ending_beat_input)
	overlay.add_child(beat)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.10, 0.10, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beat.add_child(shade)
	# Under a camera cutout too, like every full-screen dim (SafeArea.bleed).
	SafeArea.bleed(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beat.add_child(center)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 10)
	center.add_child(stack)
	var badge := EndingBadge.new()
	badge.setup(_ending, 230.0)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(badge)
	var parts: Array = TurnEndings.line_parts(str(_ending.line))
	for index in range(2):
		if str(parts[index]).is_empty(): continue
		var label: Label = controls._label(str(parts[index]), 60 if index == 0 else 40)
		label.add_theme_font_override("font", controls.title_font)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", ControlTheme.CREAM if index == 0 else EndingBadge.LINE)
		stack.add_child(label)
	if not bool(settings.get("reduced_motion", false)):
		beat.modulate.a = 0.0
		create_tween().tween_property(beat, "modulate:a", 1.0, 0.2)

func _ending_beat_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and mode == "drowning": _end_drown_beat()

## Pause, Back and the app going to the background end the beat at once: the
## card always follows a drowning.
func _end_drown_beat() -> void:
	_drown_frames = 0
	mode = "play"
	_finish()


## The lit beacon stays on screen, as in the solo Lighthouse, until the
## player continues; a played turn is saved as a draft first.
func _show_final_moment() -> void:
	_moment_replay = mode == "replay"
	if not _moment_replay and not _persist_draft("review"): return
	# The moment holds the world still: a ring waiting for the wake sounds now.
	memory_wait.ring_now()
	running = false
	action_pressed = false
	mode = "moment"
	controls.show_moment("back" if _moment_replay else "review")
	_update_run_pill(Journey.tick_of(sim))

func _continue_final_moment() -> void:
	mode = "replay" if _moment_replay else "play"
	if _moment_replay: _finish_replay_playback()
	else: _finish()


## Maps one tick's simulation events to sound cues and who caused each one.
func _turn_sounds(state: Dictionary) -> Dictionary:
	return ChapterSoundMap.cues(chapter_key, state, _sound_seen)

## The simulation is back at tick zero: its cues restart their identities.
func _begin_sound_turn() -> void:
	var state: Dictionary = sim.snapshot()
	_sound_seen = ChapterSoundMap.remember(state)
	if is_instance_valid(soundscape): soundscape.begin_turn(chapter_key, str(state.get("stage_id", "")))

## Steps a saved draft silently, still counting its cues for the sound identity.
func _fast_forward(draft: Dictionary) -> void:
	for input: Dictionary in _simulation.expand_recording_inputs(draft):
		var state: Dictionary = sim.step(input)
		_wait().step_silently(state, _turn_sounds(state))

## The wait, pointed at this screen's current world and soundscape.
func _wait() -> RefCounted:
	memory_wait.world = world
	memory_wait.soundscape = soundscape
	if not memory_wait.present_state.is_valid():
		memory_wait.present_state = func(state: Dictionary, immediate: bool) -> void: world.present(_replay_badges(state) if mode == "replay" or (mode == "bloom" and _completion_is_replay) else state, immediate)
	return memory_wait

## The simulation is back at tick zero for `turn_role`, following `prior`.
## live: a turn being played, not a replay. A journey world's wait hints
## follow WaitHints.wanted (a second turn played beside a memory, online or
## solo, never a replay); they know when the memory ends.
func _begin_memory_wait(turn_role: String, prior_recording: Variant, live: bool = false) -> void:
	_wait().reduced_motion = bool(settings.get("reduced_motion", false))
	memory_wait.auto_skip = MemoryWait.skip_waits(settings)
	memory_wait.begin(turn_role, MemoryWait.prior_ticks(prior_recording))
	if is_instance_valid(world) and world.has_method("set_wait_hints"):
		# A memory with no length is unknown (-1): its end is never assumed.
		var ticks := MemoryWait.prior_ticks(prior_recording)
		world.set_wait_hints(WaitHints.wanted(live, turn_role == "b"), ticks if ticks > 0 else -1)
	_memory_wait_text = ""
	_update_memory_wait_hud()

## The "Waiting for Sam" row, Fast-forward and Skip, shown only in a live wait.
func _update_memory_wait_hud() -> void:
	if not is_instance_valid(controls) or not controls.has_method("show_memory_wait"): return
	if mode == "play" and memory_wait.waiting(): controls.show_memory_wait(_memory_wait_label(), memory_wait.remaining_ratio(), memory_wait.skipping)
	else: controls.hide_memory_wait()
	# Wait hints step aside for the fast-forward mark.
	if is_instance_valid(world) and world.has_method("hush_wait_hints"): world.hush_wait_hints(controls.has_method("fast_forwarding") and controls.fast_forwarding())

## "Waiting for Sam": the friend by this player's nickname for them, or "a
## friend"; a solo turn waits for the player's own earlier memory.
var _memory_wait_text := ""
func _memory_wait_label() -> String:
	if _memory_wait_text.is_empty():
		if online_session == null: _memory_wait_text = PlayerCopy.MEMORY_WAIT_SOLO
		else:
			var room: Dictionary = journey.snapshot() if journey != null and journey.has_method("snapshot") else {}
			var name := _waiting_partner_name(room)
			_memory_wait_text = PlayerCopy.MEMORY_WAIT_FOR % (name if not name.is_empty() else FriendNicknames.FALLBACK)
	return _memory_wait_text

## Hold to fast-forward and a Skip under way, one physics tick of each
## (MemoryWait.fast_forward_tick, skip_tick). True when it used this tick.
func _fast_forward_wait() -> bool:
	if not controls.has_method("fast_forward_held"): return false
	# Always skip waits presses Skip, through the same checks as a tap. A
	# draft that cannot be saved first shows its problem and ends this tick.
	if memory_wait.auto_skip_due():
		_skip_memory_wait()
		if not running: return true
	if memory_wait.skipping and mode == "play":
		var reached: Dictionary = _wait().skip_tick(sim, _turn_sounds, advance_input)
		if not reached.is_empty(): _update_hud(reached)
		return true
	var holding: bool = mode == "play" and memory_wait.waiting() and controls.fast_forward_held()
	controls.dim_stick(holding)
	if holding: _wait().fast_forward_tick(advance_input, _playing_turn)
	return holding

func _playing_turn() -> bool:
	return running and mode == "play" and not backgrounded

## Skip to end: the rest of the memory goes by on the next physics ticks.
## The draft is saved first, so an app closed mid-skip keeps the press.
func _skip_memory_wait() -> void:
	if not running or backgrounded or mode != "play" or not memory_wait.waiting(): return
	if _room_context_lost: return
	if not _persist_draft(): return
	memory_wait.skipping = true
	_update_memory_wait_hud()


func _update_hud(state: Dictionary) -> void:
	_show_tries()
	var index := int(checkpoint.stage_index)
	var turn := "Replay" if mode=="replay" else "Your first turn" if role=="a" else "Alongside a ghost"
	var title := "%s · %d / %d · %s" % [chapter.title, index+1, definition.stages.size(), turn]
	var display := state
	match Registry.stage_hud(chapter_key):
		"native":
			# The same HUD as the solo Lighthouse, from the native stage.
			var native: Dictionary = definition.stages[index].native
			title = "%s · %d / %d · %s" % [str(native.title), index+1, definition.stages.size(), turn]
			display = LighthouseHud.display(state, native)
		"stage_copy":
			var presentation := Registry.stage_presentation(chapter_key,definition.stages[index])
			var displayed_role := str(state.get("role",role))
			title = "%s · %d / %d · %s" % [presentation.title, index+1, definition.stages.size(), turn]
			display = state.duplicate()
			display.message = presentation["hint_"+displayed_role]
	if mode == "play" and Registry.is_cooperative(chapter_key) and role == "a" and state.get("can_commit",false):
		display = state.duplicate()
		display.message = PlayerCopy.MAIN_1AAC5BE95E22
	display = _name_goal_place(display)
	display = _name_lever_action(display)
	if is_instance_valid(world) and world.has_method("set_goal_beacon_live"): world.set_goal_beacon_live(mode == "play")
	_update_memory_wait_hud()
	controls.set("solo", online_session == null)
	controls.update_state(title,(int(state.get("duration_ticks", 600))-int(state.tick))/30.0,display,mode=="play")
	_update_run_pill(int(state.tick))

## A stage_copy chapter may name where a turn ends ("goal_a", "goal_b"): the
## goal card shows it under its count.
func _name_goal_place(display: Dictionary) -> Dictionary:
	if Registry.stage_hud(chapter_key) != "stage_copy" or not display.get("objective_display") is Dictionary: return display
	var place := str(Registry.stage_presentation(chapter_key, definition.stages[int(checkpoint.stage_index)]).get("goal_" + str(display.get("role", role)), ""))
	if place.is_empty(): return display
	var named := display.duplicate()
	named.objective_display = display.objective_display.duplicate()
	named.objective_display.detail = place
	return named

## The action button's words at a lever the descriptor names (a chain, a bar);
## any other action keeps the simulation's own.
func _name_lever_action(display: Dictionary) -> Dictionary:
	var action: Variant = display.get("context_action")
	if not action is Dictionary or str(action.get("id", "")) != "lever": return display
	var label := str(ChapterIndex.data(chapter_key).get("lever_actions", {}).get(str(action.get("target_id", "")), ""))
	if label.is_empty(): return display
	var named := display.duplicate()
	named.context_action = (action as Dictionary).duplicate()
	named.context_action.label = label
	return named

func _request_action() -> void:
	if running and not backgrounded and mode=="play" and sim.context_action().get("enabled",false):
		action_pressed=true


func _persist_draft(after_retry: String = "play", periodic: bool = false) -> bool:
	if Journey.tick_of(sim) == 0:
		return true
	# A turn the rules keep nowhere (a drowning) leaves no draft, in a room or
	# solo: the last autosave of it goes too.
	if sim.has_method("keeps_draft") and not sim.keeps_draft():
		if journey.save_draft({}): return true
		_show_save_problem(journey.last_error, after_retry)
		return false
	var saved: bool = journey.save_live_draft(sim, periodic) if journey.has_method("poll_live_draft_save") else journey.save_live_draft(sim)
	if saved:
		return true
	_show_save_problem(journey.last_error, after_retry)
	return false


func _finish() -> void:
	if mode == "moment":
		_continue_final_moment()
		return
	_take_review()
	if review.is_empty():
		_show_ready()
		return
	if not _persist_draft("review"):
		return
	running = false
	_start_turn_check()
	if sim.snapshot().get("complete", false):
		_begin_completion(false)
	else:
		_after_visible_wait(_show_review)

func _begin_completion(from_replay: bool) -> void:
	running = false
	mode = "bloom"
	_update_run_pill(Journey.tick_of(sim))
	_completion_is_replay = from_replay
	completion_remaining = COMPLETION_DURATION
	hint_label.text = PlayerCopy.RELAY_PREVIEW_AFC92040F3DB
	stick.release()
	stick.visible = false
	action_button.visible = false
	finish_button.visible = false

func _finish_replay_playback() -> void:
	# The rewatched turn's reactions pop above their spirits; a turn that does
	# not bloom holds on them a moment before going on.
	var hold := EndReactionScreen.pop_replay(_end_reaction_context(), _replay_runs)
	_replay_runs = []
	if sim.snapshot().get("complete", false): _begin_completion(true)
	elif hold > 0.0: _hold_replay_end(hold)
	else: _replay_ended()

## Holds a finished replay still for `seconds`, then ends it, unless the
## screen moved on meanwhile (paused, left, another replay).
func _hold_replay_end(seconds: float) -> void:
	running = false
	_replay_hold += 1
	var token := _replay_hold
	create_tween().tween_callback(func():
		# Backgrounded meanwhile or not, the replay goes on: nothing else would end it.
		if token == _replay_hold and mode == "replay" and not running: _replay_ended()).set_delay(seconds)

## What end-of-run reactions read of this screen (presentation/end_reaction_screen.gd).
func _end_reaction_context() -> Dictionary:
	var online := online_session != null
	var room: Dictionary = journey.snapshot() if online and journey != null and journey.has_method("snapshot") else {}
	var pending: bool = online and journey != null and journey.has_method("pending") and not journey.pending().is_empty()
	return {"online": online, "available": not online or (online_session.has_method("end_reactions_supported") and online_session.end_reactions_supported()),
		"pending": pending, "pending_face": journey.pending_reaction() if pending and journey.has_method("pending_reaction") else "",
		"room_id": str(room.get("room_id", "")), "viewer_slot": str(room.get("player_slot", "p0")), "chapter_key": chapter_key, "definition": definition,
		"prior": prior, "settings": settings, "soundscape": soundscape, "world": world, "hud": hud, "pairs": _pairs,
		"friend_name": func() -> String: return FriendNicknames.sentence_start(_waiting_partner_name(journey.snapshot())) if online else ""}

## The played turn's recording, and the reactions made during it, which go with it.
func _take_review() -> void:
	review = sim.export_recording()
	_review_track = run_player.live.track()

## Reactions during a run (presentation/run_reaction_player.gd): a turn starts
## on tick zero. `live`: the player plays it (their spirit can react); else
## `recording` is replayed. The memory alongside (`source`) plays its own track
## too, captioned as the friend's in a room.
func _begin_run_reactions(live: bool, recording: Dictionary, source: Variant) -> void:
	var player := _run_player()
	if live:
		_review_track = []
		player.begin(str(sim.snapshot().get("active_slot", "")) if _run_reactions_available() else "")
	else:
		player.begin()
	if not _run_reactions_available(): return
	var store := RunReactionStore.new()
	if not live: player.play(recording, _track_of(store, recording))
	if source is Dictionary and not source.is_empty():
		player.play(source, _track_of(store, source), PlayerCopy.RUN_REACTIONS_MEMORY if live and online_session != null else "")
	if is_instance_valid(run_reactions): run_reactions.color = str(SpiritLook.SLOT_COLOR_NAMES.get(player.live_slot, "peach"))

## A recording's track: kept on this phone, or the finished turn's own while it waits to be saved.
func _track_of(store: RefCounted, recording: Dictionary) -> Array:
	var recording_hash := str(recording.get("recording_hash", ""))
	if not review.is_empty() and recording_hash == str(review.get("recording_hash", "")) and not _review_track.is_empty(): return _review_track
	return store.track(recording_hash)

func _run_player() -> RefCounted:
	run_player.world = world
	run_player.hud = hud
	run_player.soundscape = soundscape
	run_player.settings = settings
	return run_player

## Solo always; in a room only while its server takes them (run_reactions_supported).
func _run_reactions_available() -> bool:
	return online_session == null or (online_session.has_method("run_reactions_supported") and online_session.run_reactions_supported())

## The pill shows while a turn is played live, with its cooldown on this tick.
func _update_run_pill(tick: int) -> void:
	if not is_instance_valid(run_reactions): return
	var shown: bool = mode == "play" and not run_player.live_slot.is_empty()
	if run_reactions.visible != shown: run_reactions.visible = shown
	if shown: run_reactions.show_cooldown(run_player.live.cooldown(tick), run_player.live.full())

## The player tapped a face: their spirit makes it now, recorded on this tick.
func _react_in_run(face: String) -> void:
	if not running or backgrounded or mode != "play": return
	var tick := Journey.tick_of(sim)
	if run_player.react(tick, face): _update_run_pill(tick)

func _resume_completion() -> void:
	if _completion_is_replay and not _replay_ready(): return
	mode = "bloom"
	running = false
	overlay.visible = false
	hud.visible = true


## A solo journey checks the turn from its own proven checkpoint, and a room's
## coordinator from the room's snapshot; each keeps the result for Save turn.
func _verify_review() -> Dictionary:
	_finish_turn_check()
	if journey != null and journey.has_method("verify_turn") and Canonical.same(checkpoint, journey.checkpoint()) and Canonical.same(prior, journey.prior_recording()):
		return journey.verify_turn(review)
	return _simulation.verify_recording(definition, review, checkpoint, prior)


func _show_review() -> void:
	mode = "review"
	var verified: Dictionary = _verify_review()
	# A hard run ends on a turn it cannot keep (presentation/hard_run_flow.gd).
	if hard_flow.verdict(verified, review): return
	var ending := TurnEndings.of(verified.get("snapshot", {}), online_session == null)
	if not ending.is_empty():
		_show_ending_card(ending)
		return
	var can_save := bool(verified.get("valid", false)) and bool(verified.get("snapshot", {}).get("can_commit", false))
	if can_save: _start_prefetch()
	var explanation: String = hard_flow.review_body(PlayerCopy.RELAY_PREVIEW_B9074234FC11)
	if not can_save:
		explanation += "\n\n" + PlayerCopy.from_canonical(str(verified.get("snapshot", {}).get("commit_reason", verified.get("error", PlayerCopy.RELAY_PREVIEW_9DDEE52F0B85))), online_session == null)
	var card := _card(PlayerCopy.RELAY_PREVIEW_93772D9A4DA5, explanation)
	EndReactionScreen.attach_ending(_end_reaction_context(), card, review, true)
	card.add_child(_action_button("preview", _preview_turn))
	var save := _action_button("save", _accept)
	save.disabled = not can_save or (online_session != null and (not online_session.mutations_enabled() or online_session.busy()))
	card.add_child(save)
	if online_session != null and not online_session.mutations_enabled():
		card.add_child(_label(PlayerCopy.RELAY_PREVIEW_FAF7DFD92132,17))
	card.add_child(_action_button("retry", _retry_review))
	_add_redo_action(card)
	_add_room_action(card, "restart")
	card.add_child(_action_button("leave_draft", _leave))


## A turn ending's card (turn_endings.gd) in place of the usual review: its
## line is the title in a teal band beside its badge, then its rows of buttons.
## Nothing on it saves the turn. It slides up into place, at once under
## Reduce motion.
func _show_ending_card(ending: Dictionary) -> void:
	var card := _card("", "")
	for line: Node in card.get_children():
		if line is Label and (line as Label).text.is_empty(): (line as Label).visible = false
	var band := PanelContainer.new()
	band.name = "EndingBand"
	var band_style := ControlTheme.rounded(Color("2b6765"), 16)
	band_style.content_margin_left = 14
	band_style.content_margin_right = 18
	band_style.content_margin_top = 12
	band_style.content_margin_bottom = 12
	band.add_theme_stylebox_override("panel", band_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	band.add_child(row)
	var badge := EndingBadge.new()
	badge.setup(ending, 118.0)
	row.add_child(badge)
	var title: Label = controls._label(str(ending.line), 32)
	title.name = "EndingTitle"
	title.add_theme_font_override("font", controls.title_font)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	card.add_child(band)
	card.move_child(band, 0)
	EndReactionScreen.attach_ending(_end_reaction_context(), card, review, not sim.has_method("keeps_draft") or sim.keeps_draft())
	var actions := {"try_again": _retry_review, "preview": _preview_turn, "leave_draft": _leave}
	for ids: Array in ending.rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		card.add_child(line)
		for id: String in ids:
			if id == "redo": _add_redo_actions_to(line)
			elif actions.has(id): line.add_child(_action_button(id, actions[id]))
		for button: Node in line.get_children():
			if button is Control: (button as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if line.get_child_count() == 0: line.queue_free()
	var slide: Node = card.get_parent().get_parent().get_parent().get_parent()
	if slide is CenterContainer and not bool(settings.get("reduced_motion", false)):
		var holder := slide as CenterContainer
		holder.position.y = 80.0
		holder.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(holder, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(holder, "modulate:a", 1.0, 0.2)

## From the review card, or (`paused_over`) from the pause card over its Preview.
func _retry_review(paused_over: String = "") -> void:
	var from_pause := mode == "paused" and _previewing_review(paused_over)
	if (mode != "review" and not from_pause) or backgrounded: return
	var verified: Dictionary = _verify_review()
	if not verified.get("valid",false) or not verified.get("snapshot",{}).get("complete",false):
		_begin()
		return
	var recording := review.duplicate(true)
	var start := checkpoint.duplicate(true)
	var first := prior.duplicate(true)
	var saved_journey: RefCounted = journey
	var source_stage: String = journey.stage_id()
	var source_role: String = journey.role()
	var generation := online_request_generation
	mode = "confirm_retry"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA, "")
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_retry" and not backgrounded and online_request_generation == generation and journey == saved_journey and review == recording and checkpoint == start and prior == first and journey.stage_id() == source_stage and journey.role() == source_role and journey.checkpoint() == start
	card.add_child(_action_button("retry",func():
		if current.call(): _begin()))
	_retry_cancel = func():
		if not current.call(): return
		if from_pause: _show_paused(paused_over)
		else: _show_review()
	card.add_child(_action_button("cancel",_retry_cancel))


func _local_restart_available() -> bool:
	return online_session == null and journey != null and not journey.read_only and not journey.chapter_complete() and journey.restart_upgrades_rules()

func _confirm_restart_chapter() -> void:
	if mode not in ["ready", "review"] or backgrounded or running or not _local_restart_available(): return
	var previous_mode := mode
	var saved_journey: RefCounted = journey
	var saved_sim: RefCounted = sim
	var saved_hash: String = sim.state_hash()
	var saved_checkpoint: Dictionary = journey.checkpoint()
	var saved_pairs: Array = journey.pairs()
	var saved_prior: Dictionary = journey.prior_recording()
	var saved_draft: Dictionary = journey.draft()
	var saved_review := review.duplicate(true)
	var key := chapter_key
	var generation := online_request_generation
	if journey.read_only: return
	mode = "confirm_restart_chapter"
	var card := _card("Restart chapter?", "")
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_restart_chapter" and not backgrounded and not running and online_session == null and online_request_generation == generation and chapter_key == key and journey == saved_journey and sim == saved_sim and sim.state_hash() == saved_hash and review == saved_review and _local_restart_available() and journey.checkpoint() == saved_checkpoint and journey.pairs() == saved_pairs and journey.prior_recording() == saved_prior and journey.draft() == saved_draft and not journey.read_only
	card.add_child(_button("Restart chapter", func():
		if not current.call(): return
		if journey.fork_from_stage(0):
			_restart_tries()
			_show_ready()
			return
		var reason: String = journey.last_error
		if previous_mode == "review": _show_review()
		else: _show_ready()
		_note_refusal(reason)))
	_retry_cancel = func():
		if not current.call(): return
		if previous_mode == "review": _show_review()
		else: _show_ready()
	card.add_child(_action_button("cancel", _retry_cancel))


func _accept() -> void:
	if online_session != null:
		if online_session.busy() or not online_session.mutations_enabled() or not journey.pending().is_empty():
			_show_online_waiting()
			return
		mode = "online_request"
		online_request_generation += 1
		var generation := online_request_generation
		_card("Saving your contribution…", PlayerCopy.RELAY_PREVIEW_D30D1660A268)
		var slot := _tries_slot()
		var tries := turn_tries.freeze(slot, str(review.get("recording_hash", "")))
		# A first try sends nothing: it shows as a turn without a count does.
		var accepted: bool = await journey.commit(review, tries if tries > 1 and online_session.turn_tries_supported() else 0, EndReactionScreen.face_to_send(_end_reaction_context(), review), _review_track if _run_reactions_available() else [])
		if not is_inside_tree() or generation != online_request_generation:
			return
		if not accepted:
			_show_online_waiting()
			return
		turn_tries.close(slot)
		# A sent turn: the partner's reply is looked for at the base cadence again.
		refresh_schedule.note_activity(Time.get_ticks_msec())
		if is_instance_valid(reaction_photos):
			# Only a validated server acknowledgement reaches this optional card.
			# Native Use and even a failed photo request never recommit the turn.
			reaction_photos.offer(journey.last_receipt(), _after_accept, true)
			return
	else:
		var slot := _tries_slot()
		turn_tries.freeze(slot, str(review.get("recording_hash", "")))
		if not journey.accept_recording(review):
			_show_save_problem(journey.last_error, "commit")
			return
		turn_tries.close(slot)
		EndReactionScreen.keep_solo(review)
		RunReactionStore.new().keep(str(review.get("recording_hash", "")), _review_track)
	_after_accept()


func _after_accept() -> void:
	if role == "b" and not journey.chapter_complete():
		mode = "checkpoint"
		var card := _card(chapter.checkpoint_title, chapter.checkpoint_text)
		_add_pollen_line(card)
		card.add_child(_action_button("continue", func(): _after_visible_wait(_show_ready)))
		_add_room_action(card, "solo_redo")
		card.add_child(_action_button("back", _leave))
	else:
		_after_visible_wait(_show_ready)


## Checking a turn (solo or a room's) and setting up the next one replay saved
## turns. When a check is still on its worker, or the journey's last such work
## was slow enough to notice, a
## card saying so is drawn before the screen holds; quick work runs at once.
## A screen without frames (backgrounded, or driven directly) runs it at once.
func _after_visible_wait(work: Callable) -> void:
	# A next turn prefetched for exactly this state is used at once; one still
	# being set up finishes behind the card, never on this thread.
	var prefetch := _prefetch_state()
	_poll_turn_check()
	# A check this device should finish within the visible-wait budget is
	# taken here, as before; a longer one stays on its worker behind the card.
	if _check_thread != null and journey.expected_check_usec(_check_job.recording) < VISIBLE_WAIT_USEC: _finish_turn_check()
	var slow: bool = _check_thread != null or prefetch == "running" or (prefetch == "none" and journey.has_method("expected_wait_usec") and journey.expected_wait_usec() >= VISIBLE_WAIT_USEC)
	if backgrounded or not is_processing() or not slow:
		work.call()
		return
	mode = "turn_wait"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_DA74C3A728FC, "")
	# A title-only card: no empty body line under it.
	for line: Node in card.get_children():
		if line is Label and (line as Label).text.is_empty(): (line as Label).visible = false
	_wait_then = work
	_wait_frames = 0


## Starts setting up the turn that follows Save turn of this reviewed first
## turn, on a worker. A prefetch for the same inputs is kept.
func _start_prefetch() -> void:
	if online_session != null or journey == null or not journey.has_method("next_turn_job") or review.is_empty(): return
	var job: Dictionary = journey.next_turn_job(review)
	if job.is_empty(): return
	if not _prefetch_job.is_empty() and _same_job(job, _prefetch_job): return
	_prefetch_turn(job)

## Sets up job's turn on a worker; _take_prefetch adopts it only if it equals
## what a setup on this thread would build at that moment.
func _prefetch_turn(job: Dictionary) -> void:
	_drop_prefetch()
	# Joined by _poll_prefetch once it ends, or by the reaper after a leave.
	Reaper.ensure()
	var thread := Thread.new()
	# Bind the journey script's static builder and a private job, never a node.
	if thread.start(Callable(Journey, "build_live").bind(job)) != OK: return
	_prefetch_thread = thread
	_prefetch_job = job

static func _same_job(first: Dictionary, second: Dictionary) -> bool:
	for key: String in ["chapter", "stage", "role", "family"]:
		if first.get(key) != second.get(key): return false
	for key: String in ["level", "checkpoint", "prior", "saved"]:
		if not Canonical.same(first.get(key), second.get(key)): return false
	return true

## Joins a prefetch whose worker has ended. Never blocks.
func _poll_prefetch() -> void:
	if _prefetch_thread == null or _prefetch_thread.is_alive(): return
	_prefetch_built = _prefetch_thread.wait_to_finish()
	_prefetch_thread = null

## "running" or "ready" for a prefetch of the turn a fresh setup would build
## now, else "none".
func _prefetch_state() -> String:
	if _prefetch_job.is_empty() or online_session != null or journey == null or not journey.has_method("next_turn_job"): return "none"
	var now: Dictionary = journey.next_turn_job({}, false)
	if now.is_empty() or not _same_job(now, _prefetch_job): return "none"
	_poll_prefetch()
	return "running" if _prefetch_thread != null else ("ready" if _prefetch_built.get("ok", false) else "none")

## The prefetched turn when it is finished and matches the journey now. A
## prefetch that is not ready is left behind (the reaper joins it) and the
## caller sets the turn up on this thread as before.
func _take_prefetch() -> RefCounted:
	if _prefetch_job.is_empty() or online_session != null or not journey.has_method("adopt_live_simulation"): return null
	_poll_prefetch()
	var live: RefCounted = null
	if _prefetch_thread == null: live = journey.adopt_live_simulation(_prefetch_job, _prefetch_built)
	_drop_prefetch()
	return live

## Checks the turn just finished on a worker, so the review that follows (and
## its Save) finds the check made. Replaying a whole turn took seconds in one
## frame at the end of a long turn; the wait card now stays up meanwhile and
## the frame keeps drawing. A room's coordinator checks its turns the same way.
func _start_turn_check() -> void:
	_drop_turn_check()
	if journey == null or not journey.has_method("turn_check_job") or review.is_empty(): return
	var job: Dictionary = journey.turn_check_job(review)
	if job.is_empty(): return
	# Joined by _poll_turn_check once it ends, or by the reaper after a leave.
	Reaper.ensure()
	var thread := Thread.new()
	# The journey's own static check and a private job, never a node.
	if thread.start(journey.turn_check_runner().bind(job)) != OK: return
	_check_thread = thread
	_check_job = job

## Takes a finished turn check. Never blocks.
func _poll_turn_check() -> void:
	if _check_thread == null or _check_thread.is_alive(): return
	_finish_turn_check()

## Takes the turn check, waiting for it if it still runs, so a review asked for
## early never replays the turn a second time.
func _finish_turn_check() -> void:
	if _check_thread == null: return
	var result: Variant = _check_thread.wait_to_finish()
	_check_thread = null
	if result is Dictionary and journey != null: journey.adopt_turn_check(_check_job, result)
	_check_job = {}

func _drop_turn_check() -> void:
	if _check_thread != null: Reaper.adopt(_check_thread)
	_check_thread = null
	_check_job = {}

func _drop_prefetch() -> void:
	if _prefetch_thread != null: Reaper.adopt(_prefetch_thread)
	_prefetch_thread = null
	_prefetch_job = {}
	_prefetch_built = {}


func _preview_turn() -> void:
	_start_replay(review, checkpoint, prior)


func _start_replay(recording: Dictionary, start: Dictionary, source: Dictionary) -> void:
	# A solo replay due while the app is away (its staged open ends, or its
	# next part follows) starts paused: nothing would start it again later.
	var start_paused := backgrounded and online_session == null
	if _room_context_lost or (backgrounded and not start_paused) or _leaving: return
	if _continue_replay_context:
		if not start_paused and not _replay_ready(): return
	else:
		_replay_context = {}
	if online_session != null and not _continue_replay_context:
		if online_session.coordinator != journey or not journey.has_method("playback_context"):
			_retire_replay()
			return
		_replay_context = journey.playback_context()
		if _replay_context.is_empty():
			_retire_replay()
			return
	# A replay from the room panel plays in the play camera.
	_restore_ready_world()
	_clear_reaction_view()
	if not Registry.reset_simulation(sim, chapter_key, definition, str(recording.stage_id), start, source, str(recording.role), recording):
		_show_error(sim.error)
		return
	_begin_sound_turn()
	_begin_memory_wait(str(recording.role), source)
	_begin_run_reactions(false, recording, source)
	sim.catch_assistance = bool(recording.get("catch_assistance", true))
	checkpoint = start
	_dress([recording, source], true)
	for item: Dictionary in definition.stages:
		if str(item.id) == str(recording.stage_id):
			_present_stage_history(item,start)
	mode = "replay"
	completion_remaining = 0.0
	_completion_is_replay = false
	_replay_runs = [recording, source]
	replay_frames = _simulation.expand_recording_inputs(recording)
	replay_cursor = 0
	overlay.visible = false
	hud.visible = true
	world.present(sim.snapshot(), true)
	_update_hud(sim.snapshot())
	running = true
	if start_paused: _pause()


func _replay_ready() -> bool:
	if backgrounded or _leaving or _room_context_lost or not is_inside_tree(): return false
	if online_session == null: return true
	if online_session.coordinator == journey and not _replay_context.is_empty() and Canonical.same(_replay_context,journey.playback_context()): return true
	_retire_replay()
	return false

## The replay's room changed under it: stop and say so. Nothing on this screen
## can act on the old room again.
func _retire_replay() -> void:
	_replay_context = {}
	if is_instance_valid(world): world.set_process(false)
	if is_instance_valid(soundscape): soundscape.stop_reunion()
	_room_context_lost = true
	online_request_generation += 1
	running = false
	action_pressed = false
	_show_error(PlayerCopy.RELAY_PREVIEW_17179ABFBE5C)

func _replay_ended() -> void:
	running = false
	if replay_pair_index >= 0:
		replay_pair_index += 1
		if replay_pair_index < _pairs().size():
			_play_collection_pair(true)
		elif _solo_replay_only:
			_leave()
		else:
			_show_ready()
	else:
		_show_review()


func _play_collection_pair(continue_collection: bool = false) -> void:
	var pairs: Array = _pairs()
	if replay_pair_index < 0 or replay_pair_index >= pairs.size():
		_show_error(PlayerCopy.RELAY_PREVIEW_3DB2A54BEB93)
		return
	var pair: Dictionary = pairs[replay_pair_index]
	# A pair may carry its own start (a kept hard run's slip); otherwise it
	# starts where the pairs before it end.
	var own_start: bool = pair.get("start") is Dictionary
	var start: Dictionary = pair.start if own_start else Registry.initial_checkpoint(chapter_key)
	for index in range(0 if own_start else replay_pair_index):
		var derived: Dictionary = _simulation.derive_checkpoint(definition, start, pairs[index].a, pairs[index].b)
		if not derived.get("valid", false):
			_show_error(str(derived.get("error", PlayerCopy.RELAY_PREVIEW_ED3A094D0041)))
			return
		start = derived.checkpoint
	# Keep the existing subclass admission hook and its three-argument API.
	# The continuation flag spans only this synchronous call.
	_continue_replay_context = continue_collection
	_start_replay(pair.b, start, pair.a)
	_continue_replay_context = false
	_load_replay_photos()


func _load_replay_photos() -> void:
	if not is_instance_valid(reaction_strip) or mode != "replay":
		return
	var pairs: Array = _pairs()
	if replay_pair_index >= 0 and replay_pair_index < pairs.size():
		reaction_strip.show_turns(online_session.replay_photo_turns(replay_pair_index, pairs[replay_pair_index]))


func _position_replay_photos() -> void:
	if not is_instance_valid(reaction_strip):
		return
	if mode != "replay" or backgrounded or not is_instance_valid(world) or not is_instance_valid(controls):
		reaction_strip.hide()
		return
	reaction_strip.show()
	var to_local := reaction_strip.get_global_transform_with_canvas().affine_inverse()
	var exclusions: Array[Rect2] = []
	for control: Control in [stick, action_button, finish_button, timer_label, chapter_label, hint_label, controls.pause_button, controls.objective_panel, controls.turn_progress, presence_hud]:
		if is_instance_valid(control) and control.is_visible_in_tree():
			var transform := to_local * control.get_global_transform_with_canvas()
			exclusions.append(transform * Rect2(Vector2.ZERO, control.size))
	reaction_strip.position_over_spirits(world.camera, world.actors, Rect2(Vector2.ZERO, reaction_strip.size), exclusions)


func _edit_replay_photo(reference: Dictionary) -> void:
	if replay_pair_index < 0 or mode not in ["replay", "paused"] or not is_instance_valid(reaction_photos):
		return
	_clear_reaction_view()
	# _card pauses presentation only. This replay engine is never saved as draft.
	reaction_photos.open_owned(reference, _resume_replay)

func _resume_replay() -> void:
	if not _replay_ready(): return
	mode = "replay"
	overlay.visible = false
	hud.visible = true
	running = true
	_load_replay_photos()

func _add_replay_photo_action(card: VBoxContainer) -> void:
	if online_session == null or not is_instance_valid(reaction_photos): return
	var pairs: Array = _pairs()
	if replay_pair_index < 0 or replay_pair_index >= pairs.size(): return
	for reference: Dictionary in online_session.replay_photo_turns(replay_pair_index, pairs[replay_pair_index]):
		if reference.get("own", false):
			card.add_child(_button("Add or edit your photo", func(): _edit_replay_photo(reference)))


func _clear_reaction_view() -> void:
	if is_instance_valid(reaction_strip):
		reaction_strip.clear()


func _show_completed() -> void:
	_clear_reaction_view()
	# A reopened chapter has no live simulation yet. Rebuild its final scene from
	# the verified recording chain before presenting the completion card.
	var pairs: Array = _pairs()
	if not pairs.is_empty(): _dress([pairs[-1].get("a"), pairs[-1].get("b")], true)
	if not pairs.is_empty() and _holds_final_turn(pairs[-1], sim) and _started_final_turn(pairs[-1]):
		# Right after Save turn the screen's simulation already stands at the end
		# of the accepted last turn, and the journey (or the room) holds its proven checkpoint.
		_scene_built = {}
		_present_stage_history(definition.stages[-1],journey.checkpoint())
		world.present(sim.snapshot(), true)
	elif not pairs.is_empty() and _scene_built.get("ok", false) and (online_session == null or _holds_final_turn(pairs[-1], _scene_built.simulation)):
		# The final turn its worker replayed from the proven checkpoint before it.
		sim = _scene_built.simulation
		_scene_built = {}
		_present_stage_history(definition.stages[-1],journey.checkpoint())
		world.present(sim.snapshot(), true)
	elif not pairs.is_empty() and _start_final_scene():
		# The wait card is up; this runs again once the worker is done.
		return
	elif not pairs.is_empty():
		var start: Dictionary = Registry.initial_checkpoint(chapter_key)
		for pair: Dictionary in pairs:
			if not sim.reset(definition, str(pair.b.stage_id), start, pair.a, "b"):
				_show_error(sim.error)
				return
			sim.catch_assistance = bool(pair.b.catch_assistance)
			for input: Dictionary in _simulation.expand_recording_inputs(pair.b):
				sim.step(input)
			var derived: Dictionary = _simulation.derive_checkpoint(definition, start, pair.a, pair.b)
			if not derived.get("valid", false):
				_show_error(str(derived.get("error", PlayerCopy.RELAY_PREVIEW_DA6BA2478FE5)))
				return
			start = derived.checkpoint
		_present_stage_history(definition.stages[-1],start)
		world.present(sim.snapshot(), true)
	mode = "complete"
	if hard_flow.complete(): return
	var card := _card(PlayerCopy.RELAY_PREVIEW_8D42D9E99BAF, str(chapter.completion_text) + "\n\n" + (PlayerCopy.RELAY_PREVIEW_FF18C2378950 if online_session != null else PlayerCopy.RELAY_PREVIEW_7DECA1CF83C7))
	# The turn that finished the chapter earned here, with its first clear.
	_add_pollen_line(card)
	if online_session != null and board_line.is_valid() and journey != null and journey.has_method("snapshot"):
		var line: Variant = board_line.call(journey.snapshot(), chapter_key)
		if line is Control: card.add_child(line)
	_set_room_state("complete")
	EndReactionScreen.attach_completed(_end_reaction_context(), card)
	_add_room_actions(card, "complete", "turn", _room_facts())

## True when this screen's simulation finished exactly the accepted turn, so
## its state is the one a rebuild from the chain would reach.
## Reopening a finished solo chapter used to replay every saved stage, and
## prove each again, in one frame (seconds; more for longer chapters). Its
## final scene is now set up from the journey's proven checkpoint before the
## last stage and only that turn replayed, on a worker behind the wait card.
## False when that does not apply; the caller then rebuilds it here as before.
func _start_final_scene() -> bool:
	if not _replay_collection.is_empty() or _scene_thread != null or not _scene_built.is_empty(): return false
	if journey == null or backgrounded or not is_processing(): return false
	var job: Dictionary = {}
	if online_session == null:
		if journey.has_method("final_scene_job"): job = journey.final_scene_job()
	elif journey.chapter_complete():
		# A room's coordinator holds the same verified chain: its final checkpoint
		# proves the last pair, so the scene is set up from the checkpoint before it.
		var pairs: Array = _pairs()
		if not pairs.is_empty(): job = Journey.final_scene_job_for(chapter_key, _simulation, definition, journey.checkpoint(), pairs[-1])
	if job.is_empty(): return false
	# Joined by _poll_final_scene once it ends, or by the reaper after a leave.
	Reaper.ensure()
	var thread := Thread.new()
	if thread.start(Callable(Journey, "build_final_scene").bind(job)) != OK: return false
	_scene_thread = thread
	mode = "turn_wait"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_DA74C3A728FC, "")
	for line: Node in card.get_children():
		if line is Label and (line as Label).text.is_empty(): (line as Label).visible = false
	# A room is checked again from the top (it may have moved on meanwhile).
	_wait_then = _show_completed if online_session == null else _show_ready
	_wait_frames = 0
	return true

## Takes the final scene once its worker ends. Never blocks.
func _poll_final_scene() -> void:
	if _scene_thread == null or _scene_thread.is_alive(): return
	var built: Variant = _scene_thread.wait_to_finish()
	_scene_thread = null
	# A failed setup is rebuilt here the old way; it is never retried.
	_scene_built = built if built is Dictionary and built.get("ok", false) else {"failed": true}

## True when this screen's turn started where the last pair did: from the
## checkpoint the final proof was built from, behind the same first turn. A
## room's snapshot can change under a turn; then the scene is set up anew. A
## solo journey whose checkpoints hold no proof cannot change under its own
## screen, and keeps reusing its turn.
func _started_final_turn(last: Dictionary) -> bool:
	var proof: Variant = journey.checkpoint().get("proof")
	if not proof is Dictionary: return online_session == null
	return Canonical.same(prior, last.get("a", {})) and Canonical.same(checkpoint, proof.get("checkpoint", {}))

func _holds_final_turn(last: Dictionary, simulation: RefCounted) -> bool:
	return simulation != null and str(simulation.get("error")).is_empty() and simulation.get("role") == "b" and Canonical.same(simulation.export_recording(), last.get("b", {})) and str(journey.checkpoint().get("next_stage_id", "x")).is_empty()

func _choose_local_checkpoint() -> void:
	if online_session != null: return
	mode = "choose_checkpoint"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_F87CE3CA6999, PlayerCopy.LIGHTHOUSE_PREVIEW_8C7F45D78BE8)
	for index in range(journey.pairs().size()):
		card.add_child(_button("%s · %d / %d" % [definition.title, index + 1, definition.stages.size()], func(): _confirm_local_checkpoint(index)))
	card.add_child(_action_button("back", _show_ready))

func _confirm_local_checkpoint(index: int) -> void:
	if online_session != null: return
	mode = "confirm_checkpoint"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA, PlayerCopy.LIGHTHOUSE_PREVIEW_64EA954F32D2)
	card.add_child(_action_button("retry", func():
		var done: bool = journey.fork_from_stage(index)
		var reason: String = journey.last_error
		if done: _restart_tries()
		_show_ready()
		if not done: _note_refusal(reason)))
	card.add_child(_action_button("cancel", _show_ready))

func _show_local_replays() -> void:
	if online_session != null: return
	var archives: Array = journey.archived_attempts()
	if archives.is_empty():
		_watch_local_pairs(journey.pairs())
		return
	mode = "replay_collection"
	var card := _card("Replays", PlayerCopy.LIGHTHOUSE_PREVIEW_E569853CE1C8)
	if not journey.pairs().is_empty():
		card.add_child(_button("Replays · %d / %d" % [journey.pairs().size(), definition.stages.size()], func(): _watch_local_pairs(journey.pairs())))
	for attempt: Dictionary in archives:
		var date := Time.get_datetime_string_from_unix_time(int(attempt.modified)).replace("T", " ")
		card.add_child(_button("%s · %d / %d" % [date, attempt.stage_count, definition.stages.size()], func():
			var saved: Array = journey.archived_pairs(str(attempt.id))
			if saved.is_empty(): _show_error(journey.last_error)
			else: _watch_local_pairs(saved)))
	card.add_child(_action_button("back", _show_ready))

func _watch_local_pairs(pairs: Array) -> void:
	_replay_collection = pairs.duplicate(true)
	replay_pair_index = 0
	_play_collection_pair()

## New room waits in a busy-tap gate, as Begin does, while the finished card's
## room read is out: a room cannot be made while the session is busy, and the
## tap used to land on an error card saying online play was unavailable.
var _new_room_gate: BusyTapGate
var _new_room_button: Button

## A tap still waiting keeps its label on the redrawn New room.
func _track_new_room_button(button: Button) -> void:
	_new_room_button = button
	if _new_room_gate != null: _new_room_gate.follow(button)

func _create_another_room() -> void:
	if online_session == null or mode not in ["complete", "hard_full"]: return
	if _new_room_gate == null: _new_room_gate = BusyTapGate.new(controls)
	var finished := mode
	# Hard mode's room-full card draws its own New room, untracked.
	var tapped: Button = _new_room_button if is_instance_valid(_new_room_button) and mode == "complete" else null
	await _new_room_gate.tap(tapped, PlayerCopy.ROOM_CHECKING,
		func() -> bool: return online_session == null or not online_session.busy(),
		_create_room_now,
		func() -> bool: return mode == finished and not _leaving and online_session != null)

func _create_room_now() -> void:
	if online_session == null or mode not in ["complete", "hard_full"]: return
	var hard_room := _hard_on()
	mode = "creating_room"
	_card("New room", PlayerCopy.RELAY_PREVIEW_AE8554BD7C76)
	var room_id: String = await online_session.create_room(chapter_key, hard_room)
	if not is_inside_tree(): return
	if room_id.is_empty():
		_show_error(online_session.last_error)
		return
	journey = online_session.coordinator
	_show_ready()


# Hard mode: its flow and cards are presentation/hard_run_flow.gd.

func _claim_hard() -> void:
	hard_flow.claim()

func _hard_on() -> bool:
	return hard_flow.on()

## Play Hard again (RoomActions "hard_again").
func _hard_again() -> void:
	hard_flow.again()


func _pause() -> void:
	if mode == "drowning":
		_end_drown_beat()
		return
	if mode == "play" and not _persist_draft():
		return
	var previous := mode
	if is_instance_valid(reaction_strip): _safety_photos = reaction_strip.report_targets()
	_show_paused(previous)


## The pause card over `previous`, the mode that was paused.
func _show_paused(previous: String) -> void:
	mode = "paused"
	soundscape.stop_reunion()
	var card := _card("Take your time.", PlayerCopy.RELAY_PREVIEW_50922961D853)
	if previous == "play":
		card.add_child(_action_button("resume", _start_play))
		card.add_child(_action_button("retry", _begin))
	elif previous == "replay":
		card.add_child(_action_button("resume", _resume_replay))
		_add_preview_retry(card, previous)
		_add_replay_photo_action(card)
	elif previous == "bloom":
		card.add_child(_action_button("resume", _resume_completion))
		_add_preview_retry(card, previous)
	else:
		card.add_child(_action_button("continue", _show_ready))
	_add_safety_action(card)
	if previous == "play": _add_redo_action(card)
	card.add_child(_action_button("back", _leave))

## Watching this turn back from its review card (Preview), as against a saved
## pair or replay: the turn is still this screen's to keep or retry.
func _previewing_review(previous: String) -> bool:
	return replay_pair_index < 0 and not review.is_empty() and (previous == "replay" or (previous == "bloom" and _completion_is_replay))

## A paused Preview offers the review card's own Retry; its Cancel comes back here.
func _add_preview_retry(card: VBoxContainer, previous: String) -> void:
	if _previewing_review(previous): card.add_child(_action_button("retry", _retry_review.bind(previous)))


func _show_error(message: String) -> void:
	mode = "error"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_CE5202BED332, message)
	card.add_child(_action_button("back", _leave))


func _show_save_problem(message: String, after_retry: String) -> void:
	# Keep the live simulation/draft in memory. A transient full disk or I/O
	# failure is recoverable here without discarding the latest contribution.
	mode = "save_error"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_DC7EDE5D9A53, message + PlayerCopy.RELAY_PREVIEW_761D2317CF80)
	card.add_child(_action_button("retry_save", func():
		if after_retry == "commit":
			_accept()
		elif _persist_draft(after_retry):
			if after_retry == "review" or sim.finished:
				_take_review()
				_show_review()
			else:
				_start_play()
	))
	card.add_child(_action_button("leave_unsaved", func(): _leave(true)))


func _leave(allow_unsaved: bool = false) -> void:
	if _leaving:
		return
	if _journal_loader != null:
		# The worker owns the journal until joined; leave once it ends.
		_leave_after_load = true
		_journal_loader.cancel()
		if is_instance_valid(_loading_label): _loading_label.text = PlayerCopy.LIGHTHOUSE_PREVIEW_28D04CCA22A1
		return
	if _world_building:
		# The world is whole within a moment; this screen leaves then.
		_leave_after_build = true
		return
	# Back on the save-error card keeps it, solo or online: Leave unsaved and
	# Retry save are the only ways on from an unsaved turn.
	if not allow_unsaved and mode == "save_error": return
	if online_session != null and journey != null:
		var durable: bool = journey.finish_live_draft_save()
		if not allow_unsaved and not durable:
			_show_save_problem(journey.last_error, "play")
			return
	_leaving = true
	running = false
	action_pressed = false
	mode = "leaving"
	online_request_generation += 1
	if is_instance_valid(stick): stick.release()
	if online_session != null:
		# The parent retains the session, including any durable pending request.
		# Leaving the presentation must not wait for a room/photo GET or discard
		# a contribution whose acknowledgement is still in flight.
		if is_instance_valid(reaction_photos):
			reaction_photos.invalidate()
		_clear_reaction_view()
		closed.emit()
	else:
		ScreenSwitch.to_home(get_tree())


func _exit_tree() -> void:
	# Never wait here for a next turn still being set up, or a turn's check.
	_drop_prefetch()
	_drop_turn_check()
	if _scene_thread != null: Reaper.adopt(_scene_thread)
	_scene_thread = null
	if _journal_loader != null:
		# Leaving with the app (not Back): the loader joins its bounded load.
		_journal_loader.finish()
		_journal_loader = null
	_restore_ready_world()
	if journey != null and journey.has_method("finish_live_draft_save"): journey.finish_live_draft_save()
	if _world_covered:
		_world_covered = false
		get_viewport().disable_3d = false
	if is_instance_valid(_safety_screen): _safety_screen.client.invalidate()
	_clear_reaction_view()
	if is_instance_valid(reaction_photos):
		reaction_photos.invalidate()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(_redo_screen): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and mode == "play":
			_request_action()
		elif event.physical_keycode == KEY_ESCAPE:
			if _photo_back(): return
			if mode in ["confirm_retry", "confirm_restart_chapter", "confirm_solo_redo"]:
				if _retry_cancel.is_valid(): _retry_cancel.call()
			else: _pause() if running or mode in ["bloom", "drowning"] else _leave()


func _process(delta: float) -> void:
	if _controls_due: _finish_ready_due()
	_service_world_cover()
	_poll_prefetch()
	_poll_turn_check()
	if mode == "loading":
		_poll_journal_load()
		return
	if journey != null and journey.has_method("poll_live_draft_save") and not journey.poll_live_draft_save():
		_show_save_problem(journey.last_error, "play")
		return
	if mode == "turn_wait":
		# The card has been drawn once; now the held work runs. A next turn
		# still being set up on its worker finishes first, behind the card.
		_wait_frames += 1
		_poll_final_scene()
		if _prefetch_thread != null or _check_thread != null or _scene_thread != null: return
		if _wait_frames >= 2 and _wait_then.is_valid():
			var work := _wait_then
			_wait_then = Callable()
			work.call()
		return
	if (mode == "replay" or (mode == "bloom" and _completion_is_replay)) and not _replay_ready():
		if is_instance_valid(world): world.set_process(false)
		return
	if is_instance_valid(world): world.set_process(not backgrounded and mode in ["play", "replay", "bloom", "drowning"])
	# The ready and waiting cards hold the world still but let its spirits
	# breathe, a few times a second (island_world.advance_idle).
	if is_instance_valid(world) and not backgrounded and not _world_covered and mode in ["ready", "online_waiting"] and world.has_method("advance_idle"): world.advance_idle(delta)
	# The friend has arrived: the ring follows the startled wake.
	if not backgrounded and mode in ["play", "replay", "bloom"]: memory_wait.advance(delta)
	_service_online_refresh()
	_position_replay_photos()
	if completion_counting():
		completion_remaining -= delta
		if completion_remaining <= 0:
			if _completion_is_replay: _replay_ended()
			else: _after_visible_wait(_show_review)


## The completion bloom counts down toward the review, or a replay's end, from
## the goal's ring (after a wait, the wake comes first). A backgrounded bloom,
## or a replay's still waiting for its frames, holds still.
func completion_counting() -> bool:
	return mode == "bloom" and not backgrounded and not memory_wait.ring_pending() and not (_completion_is_replay and not _replay_ready())


## Safety and Redo requests are opaque full-screen layers: the world behind
## them is not drawn. The 3D pass comes back when they close or this leaves.
var _world_covered := false

func _service_world_cover() -> void:
	var covered := is_instance_valid(_safety_screen) or is_instance_valid(_redo_screen)
	if covered == _world_covered: return
	_world_covered = covered
	get_viewport().disable_3d = covered


## How often this chapter needs drawing (services/frame_policy.gd): no cap
## while the world is built a step per frame; full rate while a turn, replay
## or ending moves, or a saved journal loads; calm on every card, where the
## world holds still.
func frame_demand() -> String:
	if _world_building: return Frames.LOADING
	if mode == "loading": return Frames.ACTIVE
	if (running and not backgrounded) or mode in ["play", "replay", "bloom", "moment", "drowning"]: return Frames.ACTIVE
	return Frames.CALM


## Back on the optional photo card is answered by the card and never leaves the room: the
## turn is already saved, and leaving here used to drop the player out of the room.
func _photo_back() -> bool:
	return mode == "photo" and is_instance_valid(reaction_photos) and reaction_photos.back()


## Godot runs `_notification` at every script level, base first, so a subclass
## never calls it again through super. A subclass that is not ready for this
## screen's lifecycle handling (cooperative access still checking) says so here.
func _handles_screen_notifications() -> bool:
	return true


func _notification(what: int) -> void:
	if not _handles_screen_notifications(): return
	if is_instance_valid(_redo_screen) and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]: return
	if is_instance_valid(_safety_screen) and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]: return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		backgrounded = true
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(true)
		if is_instance_valid(stick) and (running or mode in ["bloom", "drowning"]):
			_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var was_backgrounded := backgrounded
		backgrounded = false
		if online_session != null and was_backgrounded:
			online_refresh_queued = true
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(_room_options_modal):
			_close_room_options()
			return
		# Back from the chapter details returns to the room panel it came from.
		if what == NOTIFICATION_WM_GO_BACK_REQUEST and mode == "room_details":
			_show_ready()
			return
		if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(run_reactions) and run_reactions.faces_open():
			run_reactions.close_faces()
			return
		if what == NOTIFICATION_WM_GO_BACK_REQUEST and _photo_back(): return
		_finish_ready_due()
		if is_instance_valid(stick):
			if mode in ["confirm_retry", "confirm_restart_chapter", "confirm_solo_redo"]:
				if _retry_cancel.is_valid(): _retry_cancel.call()
			else: _pause() if running or mode in ["bloom", "drowning"] else _leave()


func update_notification_offer() -> void:
	if not turn_notification_status.is_valid(): return
	var state: Dictionary = turn_notification_status.call()
	var registered: bool = state.get("registered", false)
	if is_instance_valid(notification_hint):
		notification_hint.text = str(state.get("message", ""))
		# While the offer is shown and nothing is set up, the offer says it all.
		notification_hint.visible = not notification_hint.text.is_empty() and (registered or state.get("enabled", false) or state.get("busy", false))
	if is_instance_valid(notification_offer):
		notification_offer.visible = not registered
		notification_offer.disabled = state.get("busy", false)
	if mode == "online_waiting" and _waiting_notify_section and (not registered) != _waiting_notify_offered:
		_refresh_waiting_panel.call_deferred()

func notification_room_hint(room_id: String) -> void:
	if online_session != null and online_session.last_room() == room_id:
		online_refresh_queued = true

func notification_deferred(message: String) -> void:
	var known := _deferred_notes.find(message)
	if known >= 0: _deferred_notes.remove_at(known)
	_deferred_notes.append(message)
	if _deferred_notes.size() > DEFERRED_NOTES: _deferred_notes.remove_at(0)
	# A centred card grows from its middle, so a new line would move its
	# buttons. There the note waits for the next card; the room panel is
	# top-aligned and takes it at once.
	if is_instance_valid(controls) and not is_instance_valid(controls.modal_stack): _show_deferred_notes()

## The notes share one label at the end of the current card or room panel, so no
## button above them moves, and they never replace a card's controls, recording
## cursor, photo selection or saved rehearsal. During play they wait for the
## next card.
func _show_deferred_notes() -> void:
	if _deferred_notes.is_empty() or running or not is_instance_valid(controls): return
	var stack: VBoxContainer = controls.modal_stack
	if not is_instance_valid(stack) and is_instance_valid(_room_ready_panel): stack = _room_ready_panel.actions
	if not is_instance_valid(stack): return
	var note: Label = stack.get_node_or_null("NotificationDeferredHint")
	if note == null:
		note = _label("", 16)
		note.name = "NotificationDeferredHint"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(note)
	note.text = "\n".join(_deferred_notes)

## The safety row on a card outside the room panel (pause).
func _add_safety_action(card: VBoxContainer) -> void:
	_add_room_action(card, "safety")

## This room's partner as services/partner_friends.gd sees them: "" (nothing to
## offer), ADDABLE or REQUESTED. Read from what this phone keeps, never the network.
func _partner_friend_state() -> String:
	if partner_friends == null or online_session == null: return PartnerFriends.HIDDEN
	var room: Dictionary = journey.snapshot()
	return partner_friends.state(_partner_id(room), "relay", str(room.get("room_id", "")))

## Add friend: the ordinary friend request to this room's partner.
func _add_partner_friend() -> void:
	if _partner_friend_state() != PartnerFriends.ADDABLE: return
	var partner := _partner_id(journey.snapshot())
	var line := PlayerCopy.add_friend_sent(_waiting_partner_name(journey.snapshot()))
	var sent: bool = await partner_friends.send(partner)
	if not is_inside_tree(): return
	notification_deferred(line if sent else PlayerCopy.ROOM_ADD_FRIEND_FAILED)

func _partner_friend_requested() -> void:
	notification_deferred(PlayerCopy.ROOM_FRIEND_REQUESTED)

func _safety_available() -> bool:
	return online_session != null and online_session.has_method("safety_context") and not online_session.safety_context().is_empty()

func _report_partner_photo(reference: Dictionary) -> void:
	_safety_photos = [reference.photo.duplicate(true)]
	_open_safety()

func _open_safety() -> void:
	if online_session == null or is_instance_valid(_safety_screen): return
	if mode == "play" and not _persist_draft(): return
	var context: Dictionary = online_session.safety_context()
	if context.is_empty(): return
	context["photos"] = _safety_photos.duplicate(true)
	running = false
	mode = "safety"
	_clear_reaction_view()
	controls.visible = false
	_safety_screen = SafetyScreen.new(online_session.safety_client(), context, _close_safety, _blocked_safety)
	add_child(_safety_screen)

func _close_safety() -> void:
	_safety_screen = null
	controls.visible = true
	_show_ready()

func _blocked_safety() -> void:
	_safety_screen = null
	running = false
	_clear_reaction_view()
	if is_instance_valid(reaction_photos): reaction_photos.invalidate()
	closed.emit()

func _camera_exploration_active() -> bool:
	return not backgrounded and mode in ["play", "replay", "bloom"] and controls.visible and not controls.overlay.visible

func _camera_exploration_allowed(point: Vector2) -> bool:
	return not world.CameraExploration.ui_blocks(controls, point)
