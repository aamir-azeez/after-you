extends Node3D
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const Frames = preload("res://services/frame_policy.gd")
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")

const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const World = preload("res://presentation/island_world.gd")
const HomeStage = preload("res://presentation/home_stage.gd")
const ScreenSwitch = preload("res://services/screen_switch.gd")
const HomeKeepsakes = preload("res://services/home_keepsakes.gd")
const ChapterCompletion = preload("res://presentation/chapter_completion.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const LocalSave = preload("res://services/local_save.gd")
const Typed = preload("res://services/typed_values.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const TurnState = preload("res://services/turn_state.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const RelayOnline = preload("res://services/relay_online_session.gd")
const RelayPreview = preload("res://relay_preview.gd")
const PaidThumbnails = preload("res://presentation/paid_level_thumbnails.gd")
const Purchases = preload("res://services/purchases.gd")
const TesterAccess = preload("res://services/tester_access.gd")
const StoreFlow = preload("res://presentation/store_flow.gd")
const AccountFlow = preload("res://presentation/account_flow.gd")
const ReplaysFlow = preload("res://presentation/replays_flow.gd")
const NotificationFlow = preload("res://presentation/notification_flow.gd")
const RoomHubFlow = preload("res://presentation/room_hub_flow.gd")
const FriendsFlow = preload("res://presentation/friends_flow.gd")
const DuelsFlow = preload("res://presentation/duels/duels_flow.gd")
const TurnFlow = preload("res://presentation/turn_flow.gd")
const LegacyRoomFlow = preload("res://presentation/legacy_room_flow.gd")
const RelayLobbyFlow = preload("res://presentation/relay_lobby_flow.gd")
const SettingsFlow = preload("res://presentation/settings_flow.gd")
const PlatformGamesFlow = preload("res://presentation/platform_games_flow.gd")
const DisplayNameFlow = preload("res://presentation/display_name_flow.gd")
const WardrobeFlow = preload("res://presentation/wardrobe_flow.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const JourneyFlow = preload("res://presentation/journey_flow.gd")
const EarlierIslandsFlow = preload("res://presentation/earlier_islands_flow.gd")
const PartnerFriends = preload("res://services/partner_friends.gd")
const PollenClient = preload("res://services/pollen_client.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenGrantCard = preload("res://presentation/pollen_grant_card.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const RecoveryDetails = preload("res://services/recovery_details.gd")
const Secrets = preload("res://services/secure_store.gd")
const RoomReactions = preload("res://presentation/room_reactions.gd")
const Soundscape = preload("res://services/soundscape.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
const TurnNotifications = preload("res://services/turn_notifications.gd")
const HostingNotificationPreferences = preload("res://services/hosting_notification_preferences.gd")
const FriendPresence = preload("res://services/friend_presence.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const FriendRoomEventsClient = preload("res://services/friend_room_events_client.gd")
const RoomSharing = preload("res://services/room_sharing.gd")
const LiveConnection = preload("res://services/live_connection.gd")
const ChapterThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const LeaderboardCelebration = preload("res://presentation/leaderboard_celebration.gd")
const LeaderboardPlacings = preload("res://services/leaderboard_placings.gd")
const LeaderboardRuns = preload("res://services/leaderboard_runs.gd")
## Meta on the control that leaves a screen (see _mark_screen_back).
const SCREEN_BACK := &"screen_back"
const Changelog = preload("res://services/changelog.gd")
const WhatsNewCard = preload("res://presentation/whats_new_card.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const ThumbnailShelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const PresenceBadge = preload("res://presentation/friend_presence_badge.gd")
const Toast = preload("res://presentation/toast.gd")
const FriendPlayIcon = preload("res://presentation/friend_play_icon.gd")
const NotificationBridge = preload("res://services/turn_notification_bridge.gd")
const InviteLinkBridge = preload("res://services/invite_link_bridge.gd")
const InviteShare = preload("res://services/invite_share.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const AppStatus = preload("res://services/app_status.gd")
const ClientIdentity = preload("res://services/client_identity.gd")
const UpdateGate = preload("res://presentation/update_gate_screen.gd")
## An invite link waits at most this long for a safe moment and a ready identity.
const INVITE_LINK_TTL_MS := 600000
const INVITE_LINK_RETRY_MS := 15000
const INVITE_LINK_ATTEMPTS := 3
# Invite links open Friends by themselves only from these modes, and only when idle.
const INVITE_LINK_MODES := ["home", RoomHubFlow.MODE_ROOMS, FriendsFlow.MODE_FRIENDS]
## Screens a tapped notification may leave to open its room (Friends too, for a hosting alert).
const NOTIFICATION_ROUTE_MODES := ["home", RoomHubFlow.MODE_ROOMS, LegacyRoomFlow.MODE_ROOM, JourneyFlow.MODE_JOURNEY, JourneyFlow.MODE_EARLIER_ISLANDS, ReplaysFlow.MODE_COLLECTION, "saved", RelayLobbyFlow.MODE_LOBBY]
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const SeedTimerBar = preload("res://presentation/seed_timer_bar.gd")
const DeletedPhotos = preload("res://services/deleted_identity_photo_cleanup.gd")
const PhotoResumePrompt = preload("res://presentation/photo_resume_prompt.gd")
const NativeFiles = preload("res://services/native_files.gd")
const HistoryStore = preload("res://services/history_store.gd")
const BackupPlan = preload("res://services/backup_plan.gd")
const AuxiliaryContext = preload("res://services/auxiliary_room_context.gd")
const SharedReplays = preload("res://services/shared_replay_collection.gd")
const LighthouseMigration = preload("res://services/lighthouse_migration.gd")
const ChapterLoadingCard = preload("res://presentation/chapter_loading_card.gd")
const ChapterAccess = preload("res://services/chapter_access.gd")
const ProofWarmup = preload("res://services/journey_proof_warmup.gd")
const GlWarmup = preload("res://services/gl_warmup.gd")
const WorldPrewarm = preload("res://services/world_prewarm.gd")
const ScenePrewarm = preload("res://services/scene_prewarm.gd")
## What's new: this version's notes have not been opened since an update.
var _whats_new_unseen := false
var _whats_new_card: Control
var _whats_new_card_mode := ""
## A Pollen flush finished: Home looks once for a monthly Pollen card to show (presentation/pollen_grant_card.gd).
var grant_card_check := false
## The leaderboard celebration Home opened, while it is up.
var _home_celebration: Control
## Tests set this to see a link instead of opening the browser.
var external_link_opener: Callable
var _bounded_card_scroll: ScrollContainer
var _bounded_card_stack: VBoxContainer
## The card an open of a chapter waits behind; one open at a time.
var _chapter_opening: CanvasLayer
## Proves saved solo journeys on a worker while Home is idle.
var _proof_warmup: Node
## Compiles the chapters' GL programs offscreen while Home is idle, once per install.
var _gl_warmup: Node
var _world_prewarm: Node
var _scene_prewarm: Node
const Safety = preload("res://services/safety_client.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const HomeMenu = preload("res://presentation/home_menu.gd")
const INK := UiTokens.INK
const CREAM := UiTokens.CREAM
const MINT := UiTokens.MINT
const MUTED := UiTokens.MUTED
const GOLD := Color("f1c48a")
const COMPLETION_MOMENT_SECONDS := EarlierIslandsFlow.COMPLETION_MOMENT_SECONDS
enum IdentityReadState { UNCHECKED, LOADING, MISSING, LOADED, FAILED, RECOVERY_PENDING }

var world: Node3D
var _suspended_world_id := 0
## True while Friends or the room hub covers the whole screen: the Home world
## behind them is neither drawn nor run (_service_world_cover).
var _world_covered := false
var _world_was_processing := false
var sim := Simulation.new()
var saves := LocalSave.new()
var home_keepsakes := HomeKeepsakes.new()
var home_stage_view: Control
var _keepsake_poll := 0.0
## The frame Home last asked for its keepsake sources to be checked again, or
## -1; the check runs on a later frame (see _show_home).
var _keepsakes_reconcile_frame := -1
var _keepsake_identity: Dictionary = {}
## The Hard marks file's change time and the together Hard switch Home last saw.
var _home_hard_stamp: Array = []
var api: Node
var purchases: Node
var secrets: Node
var soundscape: Node
var config: Dictionary={}
var shared_replays: RefCounted
var friends_client: RefCounted
var friend_nicknames: RefCounted = FriendNicknames.new()
var friend_room_events: RefCounted
var friend_share_target: Dictionary = {}
## Sharing the hosted room with friends and the hosting alert it owes.
var room_sharing: RoomSharing = _host_room_sharing()
## The live socket; the room page, hub and Friends read on its hints.
var live_connection: LiveConnection = _host_live_connection()
var shared_replay_child: Node3D
var photo_transfer_child: Node
var ui: Control
var overlay: Control
var overlay_shade: ColorRect
var hud: Control
var stick: Control
var timer_label: Label
var objective_panel: PanelContainer
var hint_label: Label
var role_label: Label
var progress: SeedTimerBar
var interact_button: Button
var finish_button: Button
## The pop-up (presentation/toast.gd), above every screen.
var toast: Toast
var title_font: Font=preload("res://assets/fonts/fredoka.ttf")
var body_font: Font=preload("res://assets/fonts/nunito.ttf")
var levels: Array=[]
var level_index := 0
var current_level: Dictionary={}
var attempt: Dictionary={}
var role := "a"
var completion_time_left := 0.0
var mode := "home":
	set(value):
		if mode=="completion" and value!="completion":
			completion_time_left=0.0
		if mode==ReplaysFlow.MODE_COLLECTION and value!=ReplaysFlow.MODE_COLLECTION:
			replays_flow.cancel_solo_collection_scan()
		mode=value
var running := false
var action_pressed := false
var replay_frames: Array=[]
var replay_index := 0
var review_recording: Dictionary={}
var _retry_cancel: Callable
var active_room: Dictionary={}
var room_play := false
var identity_request := ""
var recovery_read_request := ""
var pending_recovery: Dictionary = {}
## A saved recovery request was found but is not one the server could accept
## (malformed or from an older format). Settings offers to remove it.
var pending_recovery_unusable := false
## The saved recovery request could not be read this time, so one may still
## wait in storage unseen. No new recovery may start (it would overwrite that
## request) until a read finds it or definitively finds none.
var recovery_read_failed := false
var capture_path := ""
var capture_frames := 0
var ui_theme: Theme
var frame_times: Array[float]=[]
var collection_preview := false
var identity_loading := false
var identity_read_state := IdentityReadState.UNCHECKED
var identity_busy := false
var identity_data: Dictionary = {}
var secret_results: Dictionary = {}
var tester_access_factory: Callable
var tester_access: Node
## The store, paywall, purchase, restore and tester-code flow, with its state.
## Built with Main itself, so harnesses that replace _ready still have it.
var store_flow: StoreFlow = _host_store_flow()
## Account & recovery, identity recovery and deleted-identity cleanup, with their state.
var account_flow: AccountFlow = _host_account_flow()
## Your replays, Shared replays, replay launches and finished-room replay saves, with their state.
var replays_flow: ReplaysFlow = _host_replays_flow()
## Notification settings, alerts while the app is open and opening a tapped alert, with their state.
var notification_flow: NotificationFlow = _host_notification_flow()
## Play with a friend: the room hub, its taps and its rooms list, with their state.
var room_hub_flow: RoomHubFlow = _host_room_hub_flow()
## Friends: its screen and its Leave, Host, Return and Join taps.
var friends_flow: FriendsFlow = _host_friends_flow()
## Duels: the lobby, its pages and Play into a duel's room.
var duels_flow: DuelsFlow = _host_duels_flow()
## Earlier-island turns: submitting one, checking an unanswered one and the held turn.
var turn_flow: TurnFlow = _host_turn_flow()
## The earlier-island room page, its redo request, fork and advance.
var legacy_room_flow: LegacyRoomFlow = _host_legacy_room_flow()
## The chapter room lobby: checking rooms, its progress card and its create, join, retry and open steps.
var relay_lobby_flow: RelayLobbyFlow = _host_relay_lobby_flow()
## Settings: one page of categories, and a licence's text.
var settings_flow: SettingsFlow = _host_settings_flow()
## Play Games / Game Center: Settings' row, the progress choice and Main's side of PlatformGames.
var platform_games_flow: PlatformGamesFlow = _host_platform_games_flow()
## Display names: the first-run prompt, the prompt from Friends and the Friends header chip.
var display_name_flow: DisplayNameFlow = _host_display_name_flow()
## The Wardrobe: buying and wearing pip cosmetics with Pollen, opened from Settings.
var wardrobe_flow: WardrobeFlow = _host_wardrobe_flow()
## Play Solo: the Chapters page, Earlier islands and which chapter a card opens.
var journey_flow: JourneyFlow = _host_journey_flow()
## Playing an earlier island, solo or in a legacy room (presentation/earlier_islands_flow.gd).
var earlier_islands_flow: EarlierIslandsFlow = _host_earlier_islands_flow()
## Adding a room partner as a friend (room options and the room list's menu).
var partner_friends: RefCounted = PartnerFriends.new(_names_scope, _friends_client)
## Sends Pollen claims that wait and reads the wallet when this phone has none
## (services/pollen_client.gd): when the server's capabilities are read, and on resume.
var pollen_client: RefCounted
var store_view_generation := 0
var identity_restart_required := false
var application_backgrounded := false
var foreground_refresh_queued := false
var foreground_refresh_running := false
var foreground_schedule := RefreshClock.new()
var foreground_response: Dictionary = {}
var lifecycle_generation := 0
var submission_in_flight := false
var relay_session: RefCounted
var relay_child: Node3D
var relay_identity_epoch := 0
var room_reaction_notices: Dictionary = {}
var deleted_identity_owner := ""
var safety_screen: CanvasLayer
var safety_return := "settings"
## Home prompt for a turn photo that After You closed under (photo_resume_prompt.gd).
var photo_resume_prompt: Node
var _photo_resume_checked := false
var turn_notifications: Node
var hosting_notification_preferences := HostingNotificationPreferences.new()
var friend_presence: Node
var presence_hud: Label
var invite_link_bridge: Node
## Native inbox override for tests; production uses the native plugin.
var invite_link_native: Object
## In-memory only: one validated friend ID from an invite link, never persisted or auto-added.
var invite_link_pending := ""
var invite_link_expires_ms := 0
var invite_link_retry_ms := 0
var invite_link_attempts := 0
var invite_link_busy := false
var invite_link_notice := false
## Home invite share outputs; empty uses the system share sheet and clipboard fallback.
var invite_share_text: Callable
var invite_clipboard_copy: Callable
## Required-update check (services/app_status.gd). Its answer is kept in memory only.
var app_status: Node
## "Play Solo" on the update screen: Home stops showing it for this session, while
## online features still do.
var update_gate_dismissed := false
## Opens the Update button's store page; empty uses OS.shell_open. Tests replace it.
var update_gate_open_url: Callable

func _ready() -> void:
	var heading := FontVariation.new()
	heading.base_font=title_font
	heading.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	title_font=heading
	var body := FontVariation.new()
	body.base_font=body_font
	body.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	body_font=body
	# A replay open that never reached its chapter leaves nothing behind.
	SoloReplayLaunch.discard()
	saves.load_data()
	if saves.fresh: saves.data.settings.merge(LocalSave.NEW_PLAYER_SETTINGS, true)
	saves.start_fresh_if_unreadable()
	# Kept hard runs name their friend as this phone names them now.
	HardModeView.friend_name = _friend_display_name
	_decide_whats_new()
	home_keepsakes.load_data()
	home_keepsakes.activate()
	if soundscape==null:
		soundscape=Soundscape.new()
	# Configure before entering the tree: saved mute must also mute startup.
	soundscape.configure(saves.data.settings)
	add_child(soundscape)
	levels=Levels.all_levels()
	current_level=levels[0]
	var loaded_config: Variant=_parse_json(FileAccess.get_file_as_string("res://app_config.json"))
	config=loaded_config if loaded_config is Dictionary else {}
	api=RoomsApi.new()
	api.base_url=str(config.get("api_base_url",""))
	add_child(api)
	pollen_client=PollenClient.new(api,_names_scope)
	# The player's own look follows the signed-in player (services/own_look.gd).
	Wardrobe.shared().scope_source=_names_scope
	pollen_client.solo_levels=home_keepsakes.solo_finished_levels
	# Only a phone with Full Journey reads the wallet for the monthly grant; each flush may bring a card.
	pollen_client.subscribed=_full_journey_access
	# An item bloom's item is owned at once in the wardrobe.
	PollenWallet.shared().item_dropped.connect(Wardrobe.shared().note_drop)
	pollen_client.settled.connect(func() -> void: grant_card_check=true)
	# Only a phone with the synced native write that passes its startup check tells
	# the server it keeps room attempts; every other build keeps today's behaviour.
	if NativeFiles.durable_available(): RoomsApi.history_supported = HistoryStore.new().self_test()
	# Keep presence independent of gameplay and alive across solo chapter scenes.
	# Offline/headless builds create no singleton or network work.
	if friend_presence == null and api.configured(): friend_presence = FriendPresence.shared(get_tree())
	if is_instance_valid(friend_presence):
		friend_presence.set_enabled(bool(saves.data.settings.get("share_online_status", true)))
	purchases=Purchases.new()
	add_child(purchases)
	purchases.completed.connect(store_flow.purchase_completed)
	purchases.failed.connect(store_flow.purchase_failed)
	purchases.customer_info_changed.connect(_customer_info_changed)
	secrets=Secrets.new()
	add_child(secrets)
	secrets.completed.connect(_secret_completed)
	secrets.failed.connect(_secret_failed)
	tester_access = tester_access_factory.call() if tester_access_factory.is_valid() else TesterAccess.new()
	add_child(tester_access)
	_setup_turn_notifications()
	_setup_invite_links()
	_proof_warmup = ProofWarmup.new()
	_proof_warmup.idle = func() -> bool: return mode == "home" and not application_backgrounded and not is_instance_valid(relay_child) and not is_instance_valid(_chapter_opening)
	add_child(_proof_warmup)
	_gl_warmup = GlWarmup.new()
	_gl_warmup.settings = func() -> Dictionary: return saves.data.settings
	_gl_warmup.next_chapter = journey_flow.next_solo_chapter
	_gl_warmup.idle = func() -> bool: return mode in ["home", JourneyFlow.MODE_JOURNEY] and not application_backgrounded and not is_instance_valid(relay_child) and not is_instance_valid(_chapter_opening)
	add_child(_gl_warmup)
	# The chapter screen scripts Home never loads, on a worker once Home has
	# settled (services/scene_prewarm.gd).
	_scene_prewarm = ScenePrewarm.new()
	_scene_prewarm.chapters = journey_flow.openable_chapters
	_scene_prewarm.idle = func() -> bool: return mode in ["home", JourneyFlow.MODE_JOURNEY] and not application_backgrounded and not is_instance_valid(relay_child) and not is_instance_valid(_chapter_opening) and _keepsakes_reconcile_frame < 0 and not _home_settling() and not (is_instance_valid(_gl_warmup) and _gl_warmup.running())
	add_child(_scene_prewarm)
	# Heavy chapter worlds, built unseen once Home has settled and nothing
	# else warms (services/world_prewarm.gd).
	_world_prewarm = WorldPrewarm.new()
	_world_prewarm.settings = func() -> Dictionary: return saves.data.settings
	_world_prewarm.chapters = journey_flow.openable_chapters
	_world_prewarm.away = func() -> bool: return is_instance_valid(relay_child) or is_instance_valid(shared_replay_child)
	_world_prewarm.idle = func() -> bool: return mode in ["home", JourneyFlow.MODE_JOURNEY] and not application_backgrounded and not is_instance_valid(relay_child) and not is_instance_valid(_chapter_opening) and _keepsakes_reconcile_frame < 0 and not _home_settling() and not (is_instance_valid(_gl_warmup) and _gl_warmup.running()) and not (is_instance_valid(_scene_prewarm) and _scene_prewarm.running())
	add_child(_world_prewarm)
	var thumbnails := ThumbnailShelf.new()
	thumbnails.idle = func() -> bool: return mode == "home" and not application_backgrounded and not is_instance_valid(relay_child) and not is_instance_valid(_chapter_opening)
	thumbnails.paused = func() -> bool: return application_backgrounded or is_instance_valid(_chapter_opening)
	thumbnails.playing = func() -> bool: return is_instance_valid(relay_child) or is_instance_valid(shared_replay_child)
	thumbnails.warm_paths = journey_flow.thumbnail_paths
	add_child(thumbnails)
	world=World.new()
	add_child(world)
	_sync_world_processing()
	world.footstep.connect(func(spirit: String):
		if mode=="home" or (running and mode in ["play","preview"]): soundscape.play_footstep(spirit))
	world.reunion.connect(func():
		if mode=="home" or (running and mode in ["play","preview"]): soundscape.play_reunion())
	soundscape.listen_to(world,"home")
	world.load_level(current_level)
	sim.reset(current_level)
	world.present(sim.snapshot(),true)
	_build_theme()
	# Before any list exists: lists wait for a finger's slop before scrolling.
	TouchInput.install(get_viewport())
	_build_ui()
	world.configure_camera_exploration(_camera_exploration_active, _camera_exploration_allowed)
	SafeArea.watch(self,_refresh_safe_area)
	_refresh_safe_area()
	_refresh_safe_area.call_deferred()
	_apply_settings()
	_show_home()
	# Home shows at once; the update screen replaces it if the answer says so.
	app_status = AppStatus.new()
	app_status.base_url = api.base_url
	app_status.configured = api.configured()
	add_child(app_status)
	if api.has_signal("update_required"): api.update_required.connect(_on_update_required)
	_check_app_status()
	if not saves.last_error.is_empty():
		_toast(saves.last_error)
	if secrets.is_available():
		_load_saved_identity()
	platform_games_flow.attach()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path=arg.trim_prefix("--capture=")
		if arg=="--preview-island":
			_start_practice(0)
			_close_overlay()
			running=false
	get_tree().auto_accept_quit=false

func _build_theme() -> void:
	ui_theme=Theme.new()
	ui_theme.default_font=body_font
	ui_theme.default_font_size=20
	ui_theme.set_color("font_color","Label",CREAM)
	ui_theme.set_color("font_color","Button",INK)
	ui_theme.set_color("font_hover_color","Button",INK)
	ui_theme.set_color("font_pressed_color","Button",INK)
	ui_theme.set_color("font_hover_pressed_color","Button",INK)
	ui_theme.set_color("font_disabled_color","Button",Color("71867b"))
	ui_theme.set_stylebox("normal","Button",_style(CREAM,16))
	ui_theme.set_stylebox("hover","Button",_style(Color("ffffff"),16))
	ui_theme.set_stylebox("pressed","Button",_style(MINT,16))
	ui_theme.set_stylebox("hover_pressed","Button",_style(MINT.lightened(0.08),16))
	ui_theme.set_stylebox("disabled","Button",_style(Color("3e5e55"),16))
	ui_theme.set_stylebox("focus","Button",_style(Color(0,0,0,0),16,MINT))
	ui_theme.set_stylebox("normal","LineEdit",_style(Color("254b45"),12,Color("4e7064")))
	ui_theme.set_color("font_color","LineEdit",CREAM)
	ui_theme.set_color("font_placeholder_color","LineEdit",MUTED)

func _style(color: Color, radius: int=16, border: Color=Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1 if border.a>0 else 0)
	style.border_color=border
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=12
	style.content_margin_bottom=12
	return style

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui=Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=ui_theme
	layer.add_child(ui)
	hud=Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var top := _label("AFTER YOU",22,CREAM,true)
	top.position=Vector2(36,26)
	hud.add_child(top)
	role_label=_label("",18,MUTED)
	role_label.position=Vector2(36,61)
	hud.add_child(role_label)
	var menu_button := _action_button("pause",earlier_islands_flow.pause)
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.position=Vector2(-168,24)
	menu_button.size=Vector2(132,54)
	hud.add_child(menu_button)
	# The same seed timer as every chapter HUD; it owns the remaining-seconds number.
	progress=SeedTimerBar.new()
	hud.add_child(progress)
	progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	progress.offset_left=-160
	progress.offset_top=24
	progress.offset_right=160
	progress.offset_bottom=24+SeedTimerBar.MIN_SIZE.y
	timer_label=progress.label
	objective_panel=ObjectivePanel.new()
	hud.add_child(objective_panel)
	objective_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	objective_panel.offset_left=-260
	objective_panel.offset_top=124
	objective_panel.offset_right=-36
	objective_panel.offset_bottom=124
	hint_label=_label("",22,CREAM)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position=Vector2(-370,-98)
	hint_label.size=Vector2(740,65)
	hint_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(hint_label)
	stick=Joystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position=Vector2(12,-210)
	stick.size=Vector2(Joystick.HIT_SIZE,Joystick.HIT_SIZE)
	hud.add_child(stick)
	interact_button=_button("Throw seed",earlier_islands_flow.request_context_action)
	interact_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	interact_button.position=Vector2(-232,-168)
	interact_button.size=Vector2(195,72)
	hud.add_child(interact_button)
	finish_button=_action_button("finish",earlier_islands_flow.finish_recording)
	finish_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	finish_button.position=Vector2(-247,-87)
	finish_button.size=Vector2(210,54)
	hud.add_child(finish_button)
	overlay=Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)
	toast=Toast.new()
	toast.theme=ui_theme
	toast.reduced_motion=func() -> bool: return bool(saves.data.settings.get("reduced_motion",false))
	toast.in_header=friends_flow.is_open
	add_child(toast)

func _refresh_safe_area() -> void:
	if not is_instance_valid(ui):
		return
	TouchInput.install(get_viewport())
	_apply_safe_area(SafeArea.rect(get_viewport()))

func _apply_safe_area(safe: Rect2) -> void:
	SafeArea.inset(ui,safe)
	_layout_hint()
	_layout_bounded_card.call_deferred()

func _layout_hint() -> void:
	var bounds := ControlTheme.hint_bounds(ui.size.x, bool(saves.data.settings.get("left_handed",false)))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.offset_left=bounds.position.x
	hint_label.offset_top=bounds.position.y
	hint_label.offset_right=bounds.end.x
	hint_label.offset_bottom=bounds.end.y

func _label(text: String, font_size: int=20, color: Color=CREAM, title: bool=false) -> Label:
	var label := Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	if title:
		label.add_theme_font_override("font",title_font)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _action_button(action_id: String, callback: Callable) -> Button:
	var button := ActionButtons.create(action_id,callback)
	button.custom_minimum_size.y=54
	# A card's Back is its way back for Android Back too.
	if action_id == "back": _mark_screen_back(button)
	return button

func _button(text: String, callback: Callable, primary: bool=true) -> Button:
	var button := Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,54)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	# No callback: the caller connects one that needs the button itself.
	if callback.is_valid(): button.pressed.connect(callback)
	if text == "Back" or text.begins_with("Back to "):
		ControlTheme.danger(button,preload("res://assets/ui/back.svg"))
	elif text == "Delete":
		ControlTheme.danger(button,preload("res://assets/ui/social/trash.svg"))
	elif not primary:
		button.add_theme_stylebox_override("normal",_style(Color("254b45"),14,Color("54766a")))
		button.add_theme_color_override("font_color",CREAM)
	button.focus_mode=Control.FOCUS_ALL
	return button

## Marks the control that leaves the current screen. Android Back presses it
## on a screen with no rule of its own, so Back and the on-screen control agree.
static func _mark_screen_back(button: Button) -> Button:
	button.set_meta(SCREEN_BACK, true)
	return button

## A button that leaves the current screen, marked for Android Back.
func _back_button(text: String, callback: Callable, primary: bool=true) -> Button:
	return _mark_screen_back(_button(text,callback,primary))

## Android Back where no screen rule applies: the screen's own marked way back
## is pressed. A screen with none (Home) stays as it is, and a chapter being
## opened keeps its loading card.
func _back_on_screen() -> void:
	if is_instance_valid(_chapter_opening): return
	for node: Node in overlay.find_children("*","Button",true,false):
		var button := node as Button
		if button.has_meta(SCREEN_BACK) and button.is_visible_in_tree() and not button.disabled and not button.is_queued_for_deletion():
			button.pressed.emit()
			return

## Android Back on the topmost card Main opened over a screen (InGameModal), if
## any: a step back inside the card, or closing it.
func _close_top_modal() -> bool:
	var modal := _top_modal()
	if modal == null: return false
	modal.go_back()
	return true

## The topmost card open over the screen (InGameModal, or a leaderboard
## celebration), or null.
func _top_modal() -> Node:
	for index in range(ui.get_child_count()-1,-1,-1):
		var child := ui.get_child(index)
		if (child.get_script() == InGameModal or child.is_in_group(LeaderboardCelebration.GROUP)) and not child.is_queued_for_deletion(): return child
	return null

func _list_button(text: String, callback: Callable, primary: bool=true) -> Button:
	var button := _button(text,callback,primary)
	# Let the scroll container receive a drag that starts on a row. Its built-in
	# scroll notification cancels the pending tap once the gesture starts moving.
	button.mouse_filter=Control.MOUSE_FILTER_PASS
	return button

func _fit_icon_button(button: Button) -> void:
	# Text-button padding would squeeze a 48px icon target down to a few pixels.
	for state: String in ["normal","hover","pressed","disabled"]:
		var source := button.get_theme_stylebox(state) if button.has_theme_stylebox_override(state) else ui.theme.get_stylebox(state,"Button")
		var style := source.duplicate() as StyleBox
		for edge: String in ["left","top","right","bottom"]: style.set("content_margin_"+edge,8)
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("icon_normal_color",CREAM)
	button.add_theme_color_override("icon_hover_color",INK)
	button.add_theme_color_override("icon_pressed_color",INK)
	button.add_theme_color_override("icon_disabled_color",MUTED)

func _clear_overlay() -> void:
	room_hub_flow.release()
	replays_flow.cancel_collection_replay()
	store_view_generation += 1
	_bounded_card_scroll=null
	_bounded_card_stack=null
	overlay_shade=null
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible=true

func _close_overlay() -> void:
	_clear_overlay()
	overlay.visible=false

func _card(width: float=560.0, bounded: bool=false) -> VBoxContainer:
	_clear_overlay()
	var shade := ColorRect.new()
	shade.color=Color(0.025,0.10,0.10,0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The world and dialog backdrop fill the screen; only interactive UI is inset.
	SafeArea.bleed(shade)
	overlay.add_child(shade)
	overlay_shade=shade
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size=Vector2(width,0)
	panel.add_theme_stylebox_override("panel",_style(Color("163c36"),24,Color("51786a")))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,14)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",14)
	if bounded:
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation",14)
		margin.add_child(outer)
		_bounded_card_scroll=ScrollContainer.new()
		_bounded_card_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		_bounded_card_scroll.follow_focus=true
		# Card buttons pass drags to the scroller, like _list_button rows.
		ControlTheme.touch_scroll(_bounded_card_scroll)
		outer.add_child(_bounded_card_scroll)
		_bounded_card_scroll.add_child(stack)
		stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_bounded_card_stack=stack
		stack.minimum_size_changed.connect(_layout_bounded_card.call_deferred)
		_layout_bounded_card.call_deferred()
	else:
		margin.add_child(stack)
	return stack

func _layout_bounded_card() -> void:
	if not is_instance_valid(_bounded_card_scroll) or not is_instance_valid(_bounded_card_stack): return
	# Leave room for the panel padding and an inset from the safe screen edges.
	_bounded_card_scroll.custom_minimum_size.y=minf(_bounded_card_stack.get_combined_minimum_size().y,maxf(0.0,ui.size.y-100.0))

func _paragraph(text: String, width: float=480) -> Label:
	var result := _label(text,19,MUTED)
	result.custom_minimum_size.x=width
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return result

func _show_home() -> void:
	running=false
	mode="home"
	# Home meetups are not recorded, so their chime stays random.
	soundscape.clear_turn()
	room_play=false
	hud.visible=false
	world.home_view=true
	_clear_overlay()
	var home_stage := HomeStage.new()
	home_stage_view = home_stage
	home_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Keepsakes already earned (and any award still waiting to be saved) show
	# at once; the check of their sources, which reads and hashes the saves,
	# starts on the next frame (_service_home_keepsakes), not in this one.
	home_keepsakes.advance_backfill(0)
	_keepsakes_reconcile_frame = Engine.get_process_frames()
	var home_active := func() -> bool: return mode=="home" and not application_backgrounded and not is_instance_valid(relay_child)
	# A build that sells nothing counts and shows the free chapters' keepsakes alone.
	home_stage.configure(world,home_active,home_keepsakes.earned_descriptors(),_paid_content_hidden())
	# A card over Home (What's new) keeps its wheel and pinch for itself.
	home_stage.input_blocked = func() -> bool: return _top_modal() != null
	_set_home_hard(home_stage)
	home_stage.play_cue = soundscape.play_keepsake_cue
	overlay.add_child(home_stage)
	# The menu panel, its actions and Full Journey (presentation/home_menu.gd).
	var menu := HomeMenu.new()
	overlay.add_child(menu)
	# A tap made while the room session is still busy waits on the Play button (RoomHubFlow.open_from_home).
	menu.build({"play":room_hub_flow.open_from_home,"solo":journey_flow.show_journey,"friends":_show_friends,"duels":_show_duels,"replays":replays_flow.show_collection,"invite":_share_invite_from_home,"whats_new":_open_whats_new_from_home,"settings":settings_flow.show_settings,"full_journey":store_flow.show_paywall},title_font)
	menu.set_play_icon(FriendPlayIcon.new())
	# The Duels row shows once the server says duels are on.
	duels_flow.offer(menu)
	menu.journey_offer.visible = _full_journey_offered()
	if _whats_new_unseen: menu.mark_whats_new_unseen(Changelog.current_version())
	home_stage.set_header_actions(menu.header_actions())

func _share_invite_from_home() -> void:
	if mode != "home" or application_backgrounded: return
	if _online_gated(): return
	# A ready identity's player ID is the friend code. Otherwise the Friends entry
	# creates or checks the identity and shows its existing message, never a dead tap.
	# A short name (friend-aamir) from the loaded Friends page replaces the long code.
	var alias: String = friends_client.friend_alias() if friends_client != null else ""
	if _relay_identity().ready and InviteShare.share(alias if not alias.is_empty() else str(api.player_id),invite_share_text,invite_clipboard_copy): return
	await _show_friends()

func _screen_shell(title: String, back_callback: Callable) -> Dictionary:
	## Full-screen page with the Replays header: a labelled coral Back beside
	## the page title. The caller fills the rest of `outer`. The backdrop is a
	## little denser than a dialog's so the home island cannot show between
	## picture cards and read as part of them.
	_clear_overlay()
	var shade := ColorRect.new()
	shade.color=Color(0.025,0.10,0.10,0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The world and dialog backdrop fill the screen; only interactive UI is inset.
	SafeArea.bleed(shade)
	overlay.add_child(shade)
	overlay_shade=shade
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,22)
	overlay.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",12)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	var back := _back_button("Back",back_callback,false)
	back.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	header.add_child(back)
	var heading := _label(title,34,CREAM,true)
	heading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)
	outer.add_child(header)
	return {"margin":margin,"outer":outer,"header":header}

## Locked Full Journey art is dimmed and desaturated by the shared chapter picker.
const LOCKED_PICTURE_TINT := ChapterPicker.LOCKED_PICTURE_TINT

## Every chapter's hard marks (HardMode.states); together ones only where
## the server has said it hosts hard rooms (`together`, or the relay session
## when null).
func hard_states(together: Variant = null) -> Dictionary:
	return HardMode.new().states(_chapter_marks(), hard_together() if together == null else bool(together))

## Hands Home's keepsakes the Hard marks and the together Hard switch, and
## remembers what it handed, so the keepsake poll only hands them on again
## when the marks file or the switch changed.
func _set_home_hard(stage: Control) -> void:
	_home_hard_stamp = [FileAccess.get_modified_time(HardMode.MARKS_PATH), hard_together()]
	stage.set_hard(HardMode.new().marks(), hard_together())

func hard_together() -> bool:
	return relay_session != null and relay_session.hard_mode_supported()

func _chapter_marks() -> Dictionary:
	return ChapterCompletion.chapters(home_keepsakes.earned_descriptors())

## What the chapter unlock gate answers from (services/chapter_unlocks.gd):
## the marks Home's keepsakes read, the chapters already played or in a room
## (RoomHubFlow.known_rooms) and Full Journey access. Worked out again only
## when one of those changed, so a draw's several asks cost one build. While
## the keepsake ledger is held or still being rebuilt it may be missing marks,
## so every chapter is open and joins say nothing (ChapterUnlocks.unsettled).
var _unlocks_kept: Array = []
func _chapter_unlocks() -> Dictionary:
	if home_keepsakes.read_only or home_keepsakes.backfill_pending(): return ChapterUnlocks.unsettled(_full_journey_access())
	var earned := home_keepsakes.earned_descriptors()
	var rooms: Dictionary = room_hub_flow.known_rooms()
	# A duel's clear counts too (services/duels_client.gd finished_chapters).
	var finished: Array = rooms.finished + duels_flow.finished_chapters()
	var stamp := [hash(earned), FileAccess.get_modified_time(HardMode.MARKS_PATH), hash(rooms), _full_journey_access(), hash(finished)]
	if _unlocks_kept.size() == 2 and _unlocks_kept[0] == stamp: return _unlocks_kept[1]
	var progress := ChapterUnlocks.progress(earned, HardMode.new().marks(), ChapterUnlocks.touched(rooms.chapters), stamp[3], finished)
	_unlocks_kept = [stamp, progress]
	return progress

## The @1 Lighthouse screen, where its earlier replays play.
const LIGHTHOUSE_SCENE := LighthouseMigration.V1_SCENE

## hard: a hard open for the scene (HardMode.hand_over), or {}.
func _open_premium_chapter(scene: String, replay_context: Dictionary = {}, hard: Dictionary = {}) -> void:
	if _tester_checks_enabled():
		var view := store_view_generation
		var lifecycle := lifecycle_generation
		var context := _tester_context()
		# A tap before Home has read the saved tester receipt waits for that read
		# on the chapter's opening card; the open then puts up its own card.
		var waiting: ChapterLoadingCard = null
		if not context.is_empty() and is_instance_valid(tester_access) and tester_access.cache_checked_context != context and not is_instance_valid(_chapter_opening):
			waiting = ChapterLoadingCard.new()
			waiting.start(get_tree(), scene, bool(saves.data.settings.get("reduced_motion", false)))
			_chapter_opening = waiting
			# Main leaving during the read takes its waiting card with it.
			tree_exiting.connect(waiting.cancel, CONNECT_ONE_SHOT)
		await _load_cached_tester()
		if is_instance_valid(waiting):
			if tree_exiting.is_connected(waiting.cancel): tree_exiting.disconnect(waiting.cancel)
			waiting.cancel()
			if _chapter_opening == waiting: _chapter_opening = null
		if application_backgrounded or view != store_view_generation or lifecycle != lifecycle_generation or context != _tester_context(): return
	if identity_restart_required or identity_loading or identity_busy:
		_toast(PlayerCopy.MAIN_FCB8424B7F88)
		return
	if _tester_active():
		_open_chapter_preview(scene,replay_context,hard)
		return
	if not purchases.has_entitlement():
		store_flow.show_paywall()
		return
	if not store_flow.identity_ready():
		# An offline SDK setup can fail after cached customer information arrives.
		# Re-enter the retryable store flow instead of waiting for a callback that
		# has already failed. This does not grant access from the cached label.
		store_flow.show_paywall()
		return
	_open_chapter_preview(scene,replay_context,hard)

func _open_chapter_preview(scene: String, replay_context: Dictionary = {}, hard: Dictionary = {}) -> void:
	if is_instance_valid(_chapter_opening): return
	# The chapter's own open proves what the warm-up has not reached yet.
	if is_instance_valid(_proof_warmup): _proof_warmup.stop()
	if is_instance_valid(_gl_warmup): _gl_warmup.stop()
	if is_instance_valid(_world_prewarm): _world_prewarm.stop()
	if is_instance_valid(_scene_prewarm): _scene_prewarm.stop()
	if _chapter_open_busy():
		_toast(PlayerCopy.MAIN_A776CD47C8D9)
		return
	# Home's keepsake check stops after its current stage, so it does not
	# compete with the build; Home checks that source again later.
	home_keepsakes.stop_worker()
	# The chapter builds in one frame after the scene change; its card is
	# drawn first. Nothing changes until it is up.
	var opening := ChapterLoadingCard.new()
	_chapter_opening = opening
	var view := mode
	opening.start(get_tree(), scene, bool(saves.data.settings.get("reduced_motion", false)))
	await opening.drawn()
	# Never waits for Home's keepsake check: leaving Home hands it to the reaper.
	await opening.prepare(scene, replay_context.is_empty(), self)
	if not is_inside_tree() or mode != view or _chapter_open_busy():
		opening.cancel()
		return
	if is_instance_valid(friend_presence): friend_presence.monitor_room("", "")
	if not replay_context.is_empty() and not _write_solo_replay_context(replay_context):
		opening.cancel()
		_toast("Replay could not be opened. Please try again.")
		return
	RelayPreview.request_staged_build(scene)
	# Every open says whether it is a hard one, so none is left for a later open.
	HardMode.hand_over(hard)
	_hand_over_tester_check(scene)
	if opening.change_scene(scene) != OK:
		RelayPreview.request_staged_build("")
		HardMode.drop()
		ChapterAccess.drop_hand_over()
		opening.cancel()
		if not replay_context.is_empty(): SoloReplayLaunch.discard()
		_toast(PlayerCopy.MAIN_EB8856600899)
		return
	opening.follow_scene_change(self)

func _chapter_open_busy() -> bool:
	return submission_in_flight or foreground_refresh_running or identity_loading or identity_busy or (relay_session != null and relay_session.busy())

static func _write_solo_replay_context(context: Dictionary) -> bool:
	return SoloReplayLaunch.write(context)

## Opens an earlier island (EarlierIslandsFlow.start_practice): JourneyFlow's
## Earlier islands list and the flow's Next island and Cancel reach it here.
func _start_practice(index: int) -> void:
	await earlier_islands_flow.start_practice(index)

## The open earlier-island turn or Preview steps in Main's physics callback.
func _physics_process(delta: float) -> void:
	earlier_islands_flow.physics_step(delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if legacy_room_flow.redo_open():
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			legacy_room_flow.close_redo()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(relay_child) or is_instance_valid(shared_replay_child):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_SPACE and mode=="play" and running:
			earlier_islands_flow.request_context_action()
		if event.physical_keycode==KEY_ESCAPE:
			if account_flow.holds_back() or mode == "update_gate":
				get_viewport().set_input_as_handled()
				return
			if mode == ReplaysFlow.MODE_COLLECTION_LOADING: replays_flow.show_collection()
			elif mode in ["confirm_retry", "confirm_restart", ReplaysFlow.MODE_CONFIRM_DELETE]:
				if _retry_cancel.is_valid(): _retry_cancel.call()
			elif mode == RelayLobbyFlow.MODE_LOBBY: _return_to_room_hub()
			elif mode == RoomHubFlow.MODE_ROOMS and room_hub_flow.is_open(): room_hub_flow.go_back()
			else: earlier_islands_flow.pause() if running or mode=="completion" else _show_home()

func _react(reaction: String) -> void:
	var code := RoomReactions.code_for_label(reaction)
	if code.is_empty():
		return
	if room_play:
		await _one_room_write(_send_reaction.bind(code))
		return
	saves.data["last_reaction"]=reaction
	saves.flush()
	_toast(reaction)

func _send_reaction(code: String) -> void:
	if not saves.data.get("pending_turn",{}).is_empty():
		_toast(PlayerCopy.MAIN_D808B160901A)
		return
	var identity := _relay_identity()
	if not identity.ready or active_room.get("active_role") != "complete":
		_toast(PlayerCopy.MAIN_5DD61CC297CD)
		return
	var context := {"identity": identity.duplicate(true), "room": active_room.duplicate(true), "mode": mode, "generation": lifecycle_generation}
	var path := "/v1/rooms/" + str(active_room.room_id)
	var body := {"base_revision": active_room.revision, "idempotency_key": RoomsApi.new_key(), "reaction": code}
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST, path + "/reactions", body)
	if not _reaction_response_current(context):
		return
	# Two friends may react from the same revision. Refresh once and retry only
	# while this is still the exact same completed island/attempt.
	if not response.ok and response.get("code") == "stale_revision":
		var latest: Dictionary = await api.request_json(HTTPClient.METHOD_GET, path)
		if not _reaction_response_current(context):
			return
		if not latest.ok or not latest.get("data") is Dictionary or not RoomReactions.same_completed_room(context.room, latest.data):
			_toast(PlayerCopy.MAIN_78DF8178BC2B)
			return
		body.base_revision = latest.data.revision
		body.idempotency_key = RoomsApi.new_key()
		response = await api.request_json(HTTPClient.METHOD_POST, path + "/reactions", body)
		if not _reaction_response_current(context):
			return
	if response.ok:
		var incoming: Variant = response.get("data")
		if not incoming is Dictionary or not RoomReactions.same_completed_room(context.room, incoming) or not incoming.get("reactions") is Dictionary or incoming.reactions.get(identity.player_id) != code:
			_toast(PlayerCopy.MAIN_B94C73E90E5B)
			return
		legacy_room_flow.accept_room(response)
		_toast("Reaction sent.")
	else:
		_toast(str(response.get("error", PlayerCopy.MAIN_B94C73E90E5B)))

func _reaction_response_current(context: Dictionary) -> bool:
	return is_inside_tree() and mode == context.mode and lifecycle_generation == context.generation \
		and _relay_identity() == context.identity and RoomReactions.same_completed_room(context.room, active_room)

func _add_room_reaction_summary(card: VBoxContainer, room: Dictionary) -> void:
	for row: Dictionary in RoomReactions.rows(room, str(api.player_id)):
		var label := _paragraph(row.text)
		label.name = "YourRoomReaction" if row.own else "FriendRoomReaction"
		card.add_child(label)

func _notice_room_reactions(previous: Dictionary, incoming: Dictionary) -> void:
	var notice := RoomReactions.new_partner_notice(previous, incoming, str(api.player_id), room_reaction_notices)
	if not notice.is_empty():
		_toast(notice)

func _replay_preview_thumb(key: String, min_size: Vector2, radius: int) -> Control:
	# One framed picture for every chapter view; the chapter picker owns it.
	return ChapterPicker.thumbnail(key,min_size,radius)

func _open_photo_transfer() -> void:
	if _online_gated(): return
	if not _relay_identity().ready:
		_toast(PlayerCopy.MAIN_2BCA37F28163)
		return
	if submission_in_flight or foreground_refresh_running or (relay_session!=null and relay_session.busy()):
		_toast(PlayerCopy.MAIN_27C2299C47EE)
		return
	if is_instance_valid(photo_transfer_child): return
	var screen: Script=load("res://presentation/photo_transfer_screen.gd")
	if screen==null: _toast(PlayerCopy.MAIN_E595640A21FC); return
	lifecycle_generation+=1
	foreground_refresh_queued=false
	foreground_response={}
	mode="photo_transfer"
	running=false
	_set_world_visible(false)
	ui.visible=false
	soundscape.set_backgrounded(true)
	photo_transfer_child=screen.new(api,_relay_identity,_leave_photo_transfer)
	add_child(photo_transfer_child)

func _leave_photo_transfer() -> void:
	if is_instance_valid(photo_transfer_child):
		remove_child(photo_transfer_child)
		photo_transfer_child.queue_free()
	photo_transfer_child=null
	_set_world_visible(true)
	ui.visible=true
	soundscape.set_backgrounded(application_backgrounded)
	lifecycle_generation+=1
	settings_flow.show_settings(SettingsFlow.ACCOUNT)

## At launch, before anything writes the save: after an update this version's
## notes wait to be opened; a fresh install or a downgrade only records the
## version, in memory, so the next ordinary save keeps it.
func _decide_whats_new() -> void:
	var current := Changelog.current_version()
	var decision := Changelog.decide(saves.data.get(Changelog.SAVE_KEY), not saves.loaded_from.is_empty(), saves.read_only, current)
	if decision.remember: saves.data[Changelog.SAVE_KEY] = current
	_whats_new_unseen = decision.unseen

## True after an update until the player opens this version's notes.
func whats_new_unseen() -> bool:
	return _whats_new_unseen

## Opening the card or the full page counts as seeing this version's notes.
func _remember_whats_new() -> void:
	_whats_new_unseen = false
	var current := Changelog.current_version()
	if saves.read_only or Typed.equal(saves.data.get(Changelog.SAVE_KEY), current): return
	saves.update_values({Changelog.SAVE_KEY: current})

## A notification or link that changes the screen takes an open card away with it.
func _service_whats_new() -> void:
	if is_instance_valid(_whats_new_card) and mode != _whats_new_card_mode: _whats_new_card.close(false)

## This version's card, opened from the Home button or the Settings row. It never
## opens on its own.
func _open_whats_new_card(opener: Control = null) -> void:
	if mode not in ["home", SettingsFlow.MODE_SETTINGS] or is_instance_valid(_whats_new_card): return
	# A build that sells nothing leaves out the lines about Full Journey (Changelog.without_paid).
	var paid_hidden := _paid_content_hidden()
	var entries := Changelog.load_entries(Changelog.channel(config),Changelog.PATH,paid_hidden)
	if entries.is_empty() or entries[0].version != Changelog.current_version(): return
	_remember_whats_new()
	if is_instance_valid(overlay): WhatsNewCard.clear_unseen(overlay.find_child("HomeWhatsNew",true,false))
	var see_all: Callable = _open_release_notes if Changelog.releases_link_offered() else Callable()
	# Earlier versions reads the archive only when the player opens that list.
	var earlier: Callable = (func() -> Array: return Changelog.earlier_entries(entries[0].version,Changelog.PATH,Changelog.ARCHIVE_PATH,paid_hidden)) if Changelog.has_earlier(entries) else Callable()
	_whats_new_card = WhatsNewCard.open(ui,entries[0],earlier,see_all,opener)
	_whats_new_card_mode = mode

func _open_whats_new_from_home() -> void:
	_open_whats_new_card(overlay.find_child("HomeWhatsNew",true,false) as Control)

## Every release's full notes, on GitHub.
func _open_release_notes() -> void:
	if is_instance_valid(_whats_new_card): _whats_new_card.close(false)
	_open_external_link(Changelog.RELEASES_URL)

func _open_external_link(url: String) -> void:
	if external_link_opener.is_valid(): external_link_opener.call(url)
	else: OS.shell_open(url)

func _apply_settings() -> void:
	GraphicsPolicy.apply(world,saves.data.settings)
	if is_instance_valid(friend_presence): friend_presence.set_enabled(bool(saves.data.settings.get("share_online_status", true)))
	soundscape.configure(saves.data.settings)
	world.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	var left := bool(saves.data.settings.get("left_handed",false))
	stick.anchor_left=1.0 if left else 0.0
	stick.anchor_right=stick.anchor_left
	# Once parented, position is absolute in the HUD. Use anchor-relative
	# offsets so right-aligned controls remain inside the viewport on resize.
	stick.offset_left=-208 if left else 12
	stick.offset_right=stick.offset_left+Joystick.HIT_SIZE
	for button in [interact_button,finish_button]:
		var width := 210 if button==finish_button else 195
		button.anchor_left=0.0 if left else 1.0
		button.anchor_right=button.anchor_left
		button.offset_left=36 if left else -37-width
		button.offset_right=button.offset_left+width
	_layout_hint()

## An internal child: it leaves Main's own child order alone.
func _host_store_flow() -> StoreFlow:
	var flow := StoreFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.settings_requested.connect(func(): settings_flow.show_settings(SettingsFlow.ACCOUNT))
	flow.chapters_requested.connect(func(): journey_flow.show_journey())
	flow.rooms_requested.connect(func(): room_hub_flow.show_rooms())
	flow.lighthouse_requested.connect(func(): journey_flow.open_solo_chapter(ChapterRegistry.LIGHTHOUSE_V2))
	flow.google_play_requested.connect(_open_google_play)
	return flow

## An internal child, like StoreFlow.
func _host_account_flow() -> AccountFlow:
	var flow := AccountFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.settings_requested.connect(func(): settings_flow.show_settings(SettingsFlow.ACCOUNT))
	flow.photo_transfer_requested.connect(_open_photo_transfer)
	flow.safety_requested.connect(func(): _open_safety({},"account"))
	return flow

## An internal child, like StoreFlow.
func _host_replays_flow() -> ReplaysFlow:
	var flow := _new_replays_flow()
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.home_requested.connect(_show_home)
	flow.account_requested.connect(func(): settings_flow.show_settings(SettingsFlow.ACCOUNT))
	return flow

## The flow Main hosts and wires; a subclass may return its own ReplaysFlow.
func _new_replays_flow() -> ReplaysFlow:
	return ReplaysFlow.new(self)

## An internal child, like StoreFlow.
func _host_notification_flow() -> NotificationFlow:
	var flow := _new_notification_flow()
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	live_connection.friends_changed.connect(flow.friends_hint)
	return flow

## The flow Main hosts and wires; a subclass may return its own NotificationFlow.
func _new_notification_flow() -> NotificationFlow:
	return NotificationFlow.new(self)

## An internal child, like StoreFlow.
func _host_room_hub_flow() -> RoomHubFlow:
	var flow := RoomHubFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.home_requested.connect(_show_home)
	flow.journey_requested.connect(func(): journey_flow.show_journey())
	flow.hosting_locked_requested.connect(func(chapter_key: String): store_flow.show_hosting_locked(chapter_key))
	flow.tester_access_requested.connect(func(): store_flow.show_tester_access())
	flow.shared_replay_requested.connect(func(room_id: String): replays_flow.open_shared_replay_room(room_id))
	return flow

## An internal child, so a quiet alert retry ends with Main.
func _host_room_sharing() -> RoomSharing:
	var sharing := RoomSharing.new(_friends_client, _friend_events, _relay_identity, _tester_context, _current_room_share_allowed, _friends_route_context, _friends_route_current, _room_share_changed)
	add_child(sharing,false,Node.INTERNAL_MODE_BACK)
	return sharing

## An internal child, so the socket closes with Main. It opens once an online
## screen is up (the hub, a room or Friends) and reuses the capability answer
## the relay session already holds.
func _host_live_connection() -> LiveConnection:
	var live := LiveConnection.new()
	live.capabilities = func() -> Dictionary: return relay_session.capabilities if relay_session != null else {}
	live.wanted = func() -> bool: return mode in [RoomHubFlow.MODE_ROOMS, FriendsFlow.MODE_FRIENDS, "relay_online"] or is_instance_valid(relay_child)
	add_child(live,false,Node.INTERNAL_MODE_BACK)
	return live

## An internal child, like StoreFlow.
func _host_duels_flow() -> DuelsFlow:
	var flow := DuelsFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.home_requested.connect(_show_home)
	return flow

## An internal child, like StoreFlow.
func _host_friends_flow() -> FriendsFlow:
	var flow := FriendsFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.home_requested.connect(_show_home)
	flow.rooms_requested.connect(func(): room_hub_flow.show_rooms())
	flow.hosting_view_ready.connect(func(events: Array): notification_flow.hosting_view_ready(events))
	return flow

## An internal child, like StoreFlow.
func _host_turn_flow() -> TurnFlow:
	var flow := TurnFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.rooms_requested.connect(func(): room_hub_flow.show_rooms())
	return flow

## An internal child, like StoreFlow.
func _host_legacy_room_flow() -> LegacyRoomFlow:
	var flow := _new_legacy_room_flow()
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.rooms_requested.connect(func(): room_hub_flow.show_rooms())
	flow.home_requested.connect(_show_home)
	return flow

## The flow Main hosts and wires; a test harness may return its own LegacyRoomFlow.
func _new_legacy_room_flow() -> LegacyRoomFlow:
	return LegacyRoomFlow.new(self)

## An internal child, like StoreFlow.
func _host_relay_lobby_flow() -> RelayLobbyFlow:
	var flow := _new_relay_lobby_flow()
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	return flow

## The flow Main hosts; a test harness may return its own RelayLobbyFlow.
func _new_relay_lobby_flow() -> RelayLobbyFlow:
	return RelayLobbyFlow.new(self)

## An internal child, like StoreFlow.
func _host_platform_games_flow() -> PlatformGamesFlow:
	var flow := PlatformGamesFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	return flow

## An internal child, like StoreFlow.
func _host_display_name_flow() -> DisplayNameFlow:
	var flow := DisplayNameFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	return flow

## An internal child, like StoreFlow. Its Back returns to Settings, where it opens.
func _host_wardrobe_flow() -> WardrobeFlow:
	var flow := WardrobeFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.back_requested.connect(func(): settings_flow.show_settings())
	return flow

## An internal child, like StoreFlow.
func _host_journey_flow() -> JourneyFlow:
	var flow := JourneyFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	return flow

## An internal child, like JourneyFlow.
func _host_earlier_islands_flow() -> EarlierIslandsFlow:
	var flow := EarlierIslandsFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	return flow

## The server and player that key the names and friends this phone keeps, or {}.
func _names_scope() -> Dictionary:
	if api == null or not _relay_identity().ready: return {}
	return {"server": str(api.base_url), "owner": str(api.player_id)}

## An internal child, like StoreFlow.
func _host_settings_flow() -> SettingsFlow:
	var flow := SettingsFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.home_requested.connect(_show_home)
	return flow

func _play_store_enabled() -> bool:
	return Purchases.store_enabled(config)

func _open_google_play() -> void:
	OS.shell_open(UpdateGate.PLAY_LISTING_URL)

func _hosting_entitled() -> bool:
	return _hosting_lock_reason().is_empty()

## Why hosting a Full Journey chapter is locked, from the one shared rule: a
## tester code opens it in every build; in the GitHub Test Store build a
## purchase opens solo only, so hosting waits for a code; a Google Play purchase
## opens hosting too. Reads cached entitlement only, never a per-screen store query.
func _hosting_lock_reason() -> String:
	return Purchases.hosting_lock_reason(config,purchases.has_entitlement(),_tester_active())

## The identity half of the store's readiness: a saved identity that no load,
## recovery, restart or deletion holds.
func _store_identity_settled() -> bool:
	return not api.device_token.is_empty() and not identity_loading and not identity_busy and not identity_restart_required and pending_recovery.is_empty() and deleted_identity_owner.is_empty() and not saves.data.has(DeletedPhotos.MARKER_KEY)

## A loaded identity that purchases may bind their session to.
func _purchase_session_identity() -> bool:
	return identity_read_state == IdentityReadState.LOADED and not identity_restart_required and not identity_loading and not identity_busy and pending_recovery.is_empty() and not saves.data.has(DeletedPhotos.MARKER_KEY)

func _customer_info_changed(_payload: Dictionary) -> void:
	# The store may finish loading after the grid opens. Refresh the locks here;
	# button callbacks still check the current entitlement when pressed. The
	# store reports on every launch and resume, mostly with nothing new, and a
	# redraw frees the card under a finger, so only a change in access redraws,
	# after any tap in progress.
	if mode in [JourneyFlow.MODE_JOURNEY,JourneyFlow.MODE_EARLIER_ISLANDS]:
		await journey_flow.access_changed()
	elif mode==RoomHubFlow.MODE_ROOMS and room_hub_flow.is_open():
		room_hub_flow.redraw_chapters()

func _load_saved_identity() -> void:
	if identity_loading or identity_busy or identity_restart_required:
		return
	_invalidate_relay_identity(false)
	identity_read_state=IdentityReadState.LOADING
	identity_loading=true
	pending_recovery_unusable=false
	recovery_read_failed=false
	# A saved rotation takes precedence over possibly revoked device credentials.
	recovery_read_request=secrets.get_secret("recovery_pending")

func _secret_completed(id: String, operation: String, payload: Dictionary) -> void:
	secret_results[id]={"ok":true,"payload":payload}
	if id==recovery_read_request and operation=="get":
		secret_results.erase(id)
		if payload.get("found") is bool and payload.found==false and payload.get("value")==null:
			identity_request=secrets.get_secret("player_identity")
			return
		identity_loading=false
		identity_read_state=IdentityReadState.FAILED
		if payload.get("found") is bool and payload.found==true and payload.get("value") is String:
			var saved: Variant=_parse_json(payload.value)
			if RecoveryDetails.valid_pending(saved):
				pending_recovery=saved
				identity_read_state=IdentityReadState.RECOVERY_PENDING
				identity_restart_required=true
				_toast(PlayerCopy.MAIN_B3B03D36065F)
			else:
				# The server accepts only the formats valid_pending checks, so
				# this request never rotated anything and holds no live credentials.
				pending_recovery_unusable=true
		else:
			recovery_read_failed=true
	elif id==identity_request and operation=="get":
		identity_loading=false
		# Only an explicit not-found response permits a new identity. Failed
		# decryption or malformed stored data must never become a fresh install.
		identity_read_state=IdentityReadState.FAILED
		if payload.get("found") is bool and payload.found==false and payload.get("value")==null:
			identity_read_state=IdentityReadState.MISSING
		elif payload.get("found") is bool and payload.found==true and payload.get("value") is String:
			var identity: Variant=_parse_json(payload.value)
			if identity is Dictionary and identity.get("player_id") is String and identity.get("device_token") is String and not identity.player_id.is_empty() and not identity.device_token.is_empty():
				identity_read_state=IdentityReadState.LOADED
				identity_data=identity
				api.player_id=identity.player_id
				api.device_token=identity.device_token
				if saves.data.has(DeletedPhotos.MARKER_KEY):
					identity_restart_required=true
					deleted_identity_owner=DeletedPhotos.marker_owner(saves.data[DeletedPhotos.MARKER_KEY])
				store_flow.configure_purchases()
		if saves.data.has(DeletedPhotos.MARKER_KEY):
			identity_restart_required=true
			deleted_identity_owner=DeletedPhotos.marker_owner(saves.data[DeletedPhotos.MARKER_KEY])
		secret_results.erase(id)
	# Settings' Account & recovery shows rows by identity state.
	if id in [identity_request,recovery_read_request]: settings_flow.refresh()

func _secret_failed(id: String, _operation: String, code: String) -> void:
	secret_results[id]={"ok":false,"code":code}
	if id==identity_request or id==recovery_read_request:
		if id==recovery_read_request: recovery_read_failed=true
		identity_loading=false
		identity_read_state=IdentityReadState.FAILED
		secret_results.erase(id)
		settings_flow.refresh()

func _await_secret(id: String) -> Dictionary:
	var deadline := Time.get_ticks_msec()+10000
	while not secret_results.has(id) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	var result: Dictionary=secret_results.get(id,{"ok":false,"code":"storage_timeout"})
	secret_results.erase(id)
	return result

## Leaving a room or a failed room request lands on the hub. When the hub
## cannot open (no service or identity), Home is the safe place instead.
func _return_to_room_hub(notice: String = "", refresh: bool = true) -> void:
	relay_lobby_flow.cancel()
	if not api.configured() or not _relay_identity().ready:
		_show_home()
		if not notice.is_empty(): _toast(notice)
		return
	room_hub_flow.open_hub(notice,refresh)

## The server removed a room from the hub: this device forgets its share, its
## alert and, for a legacy room with nothing unsent, its saved copy.
func forget_removed_room(version: int, room_id: String) -> void:
	if friend_room_events != null: friend_room_events.forget({"api_version":version,"room_id":room_id})
	if friend_share_target.get("api_version") == version and friend_share_target.get("room_id") == room_id: friend_share_target = {}
	var saved: Dictionary = saves.data.get("room",{})
	if version == 1 and saved.get("room_id") == room_id and saves.data.get("pending_turn",{}).is_empty() and saves.data.get("room_draft",{}).is_empty():
		saves.update_values({"room":{}})
		if active_room.get("room_id") == room_id: active_room = {}

func _friend_display_name(friend: String) -> String:
	## One place to turn a friend's or room partner's player id into the name
	## shown on screen (FriendNicknames.display_name): their local nickname, then
	## the name they chose, then their anonymous name while names are on, else
	## "a friend". Never the raw id.
	if friend.is_empty(): return ""
	if friend_nicknames == null: return FriendNicknames.FALLBACK
	return friend_nicknames.display_name(str(api.base_url),str(api.player_id),friend)

## What a hub tap waits for: work its online flow refuses during (_relay_available).
func _online_flow_idle() -> bool:
	return not submission_in_flight and not foreground_refresh_running

## ... plus the room session, for taps that open or make a chapter room. A saved
## legacy turn is not transient; the room flow opens it (_relay_available).
func _room_session_idle() -> bool:
	return _online_flow_idle() and (relay_session == null or not relay_session.busy())

## Duels from Home's row, while the server has them on (presentation/duels/duels_flow.gd).
func _show_duels(report: Callable = Callable()) -> void:
	if _online_gated(): return
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available(report) or not await _ensure_identity(report): return
	if view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded or duels_flow.is_open() or friends_flow.is_open(): return
	room_hub_flow.drop()
	duels_flow.open()

func _show_friends(report: Callable = Callable()) -> void:
	if _online_gated(): return
	var from_home := mode == "home"
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available(report) or not await _ensure_identity(report): return
	if view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded or friends_flow.is_open(): return
	# Friends is a full-screen takeover. Release the room hub so it cannot sit
	# behind the Friends layer and intercept input while Friends is open.
	room_hub_flow.drop()
	friends_flow.open(from_home)

## Friends leads to Play with a friend or a room: the hub's mode is set before
## the Friends layer closes, so its close callback does not navigate again.
func _friends_to_rooms() -> void:
	mode = RoomHubFlow.MODE_ROOMS
	ui.visible = true

func _current_room_share_allowed(target: Dictionary) -> bool:
	if application_backgrounded or not _relay_identity().ready or not FriendsClient._room(target): return false
	var room := {}
	if target.api_version == 2:
		if mode != "relay_online" or not is_instance_valid(relay_child) or relay_session == null or relay_session.coordinator == null or relay_child.journey != relay_session.coordinator: return false
		room = relay_session.coordinator.snapshot()
	elif target.api_version == 1:
		if mode != LegacyRoomFlow.MODE_ROOM: return false
		room = active_room
	return room.get("room_id") == target.room_id and room.get("host_id") == api.player_id

func _room_share_changed(target: Dictionary) -> void:
	if target.get("api_version") == 2 and is_instance_valid(relay_child) and relay_child.has_method("update_share_controls"): relay_child.update_share_controls()

func _friends_route_context() -> Dictionary:
	return {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}

func _friends_route_current(context: Dictionary) -> bool:
	return not application_backgrounded and _relay_identity().ready and context == _friends_route_context()

func _relay_identity() -> Dictionary:
	return {"ready": api != null and not identity_loading and not identity_busy and not identity_restart_required and pending_recovery.is_empty() and identity_read_state==IdentityReadState.LOADED and not api.player_id.is_empty() and not api.device_token.is_empty(), "player_id": str(api.player_id) if api != null else "", "epoch": relay_identity_epoch}

func _new_relay_session() -> RefCounted:
	if shared_replays == null: shared_replays = SharedReplays.new(api,_relay_identity)
	_wire_shared_history()
	var session := RelayOnline.new(api,_relay_identity)
	# A join carries the chapters open to this player (services/chapter_unlocks.gd).
	session.join_unlocks = _chapter_unlocks
	session.accepted_pair_cache = shared_replays.cache_accepted_receipt
	if pollen_client != null: session.pollen_flush = pollen_client.flush
	session.replay_archive_cache = shared_replays.cache_transferred_entries
	session.replay_history_cache = shared_replays.cache_history_pairs
	return session

## Android backs up when the phone is idle; the list it follows is refreshed whenever
## the app goes to the background, so it names the files saved since.
func _write_backup_plan() -> void:
	if OS.get_name() == "Android": BackupPlan.write()

## Replays plays a part the server let go from this phone's copy of its attempt.
func _wire_shared_history() -> void:
	shared_replays.history_pair = _history_pair
	shared_replays.ask_for_attempt = _ask_for_attempt
	shared_replays.turn_tries_supported = _turn_tries_supported
	shared_replays.end_reactions_supported = _end_reactions_supported

func _history_pair(room_id: String, chapter_key: String, pair_id: String) -> Dictionary:
	ensure_relay_session()
	return relay_session.history_pair(room_id, chapter_key, pair_id)

func _ask_for_attempt(room_id: String, position: int) -> void:
	ensure_relay_session()
	if relay_session.capabilities.is_empty(): await relay_session.load_capabilities()
	await relay_session.want_room_attempt(room_id, position)

func _turn_tries_supported() -> bool:
	ensure_relay_session()
	if relay_session.capabilities.is_empty(): await relay_session.load_capabilities()
	return relay_session.turn_tries_supported()

func _end_reactions_supported() -> bool:
	ensure_relay_session()
	if relay_session.capabilities.is_empty(): await relay_session.load_capabilities()
	return relay_session.end_reactions_supported()

func _invalidate_relay_identity(clear_notifications: bool = true) -> void:
	replays_flow.invalidate_identity()
	# A returning Main re-reads the same credentials before reusing its session.
	# Recovery/deletion clear authority; ordinary identity loading only holds it.
	Purchases.suspend_session(clear_notifications)
	friend_share_target = {}
	var had_redo_screen := legacy_room_flow.invalidate_identity()
	_keepsake_identity.clear()
	if friends_client != null: friends_client.invalidate()
	if friend_room_events != null: friend_room_events.invalidate()
	notification_flow.forget_friends_news()
	room_hub_flow.drop()
	if friends_flow.is_open():
		if mode == FriendsFlow.MODE_FRIENDS: mode = RoomHubFlow.MODE_ROOMS
		friends_flow.close()
		ui.visible = true
	if duels_flow.is_open():
		if mode == DuelsFlow.MODE_DUELS: mode = RoomHubFlow.MODE_ROOMS
		duels_flow.close()
		ui.visible = true
	if is_instance_valid(friend_presence): friend_presence.set_identity({})
	if is_instance_valid(tester_access):
		tester_access.forget_cache_check()
		tester_access.invalidate()
	if purchases is Purchases: purchases.invalidate_review_access()
	if clear_notifications and is_instance_valid(turn_notifications):
		turn_notifications.invalidate_identity()
	# Recovery or deletion drops an unopened invite link with the old account.
	if clear_notifications: invite_link_pending = ""
	lifecycle_generation += 1
	foreground_response = {}
	relay_identity_epoch += 1
	relay_lobby_flow.cancel()
	if relay_session != null:
		relay_session.invalidate_identity()
	if is_instance_valid(relay_child):
		relay_child.identity_invalidated()
	if is_instance_valid(safety_screen):
		safety_screen.client.invalidate()
		safety_screen.queue_free()
		safety_screen = null
		ui.visible = true
	if shared_replays!=null: shared_replays.invalidate_identity()
	if is_instance_valid(shared_replay_child): shared_replay_child.identity_invalidated()
	if is_instance_valid(photo_transfer_child):
		if photo_transfer_child.has_method("identity_invalidated"): photo_transfer_child.identity_invalidated()
		elif photo_transfer_child.has_method("invalidate"): photo_transfer_child.invalidate()
	# The room hub needs a ready identity, so a stale redo panel returns Home.
	if had_redo_screen and mode == LegacyRoomFlow.MODE_REDO: _show_home()

## Whether an online action may start. A request still out refuses with its
## reason (report). An unsent turn refuses by opening it (turn_flow.show_unsent_turn),
## so the player always has a way back to online play.
func _relay_available(report: Callable = Callable()) -> bool:
	if submission_in_flight or foreground_refresh_running:
		_report(report,PlayerCopy.MAIN_8184DEB41266)
		return false
	if not saves.data.get("pending_turn",{}).is_empty():
		turn_flow.show_unsent_turn(report)
		return false
	return true

## A room flow that stopped before drawing anything (the caller already left
## the hub or Friends) returns to the hub instead of leaving a bare screen.
func _settle_room_flow() -> void:
	# The reason moves from the pop-up into the hub's notice, where it stays.
	if mode in [RoomHubFlow.MODE_ROOMS, RelayLobbyFlow.MODE_LOBBY] and not room_hub_flow.is_open(): _return_to_room_hub(toast.take_plain())

## The Friends client; made here on first use when create is set.
func _friends_client(create: bool) -> RefCounted:
	if create and friends_client == null: friends_client = FriendsClient.new(api,_relay_identity)
	return friends_client

func _friend_events() -> FriendRoomEventsClient:
	if friend_room_events == null: friend_room_events = FriendRoomEventsClient.new(api,_relay_identity)
	return friend_room_events as FriendRoomEventsClient

func _enter_online_relay() -> void:
	if not legacy_room_flow.navigation_ready(): return
	if relay_session == null or relay_session.coordinator == null or relay_session.busy() or is_instance_valid(relay_child):
		return
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	running = false
	room_hub_flow.release()
	mode = "relay_online"
	friend_share_target = {"api_version":2,"room_id":relay_session.coordinator.snapshot().room_id}
	room_play = false
	_set_world_visible(false)
	ui.visible = false
	soundscape.set_backgrounded(true)
	relay_child = RelayPreview.new()
	relay_child.chapter_key = relay_session.chapter_key()
	relay_child.online_session = relay_session
	relay_child.friend_presence = friend_presence
	relay_child.live_connection = live_connection
	relay_child.settings = saves.data.settings.duplicate(true)
	relay_child.save_photo_prompt_preference = settings_flow.save_photo_prompt_preference
	relay_child.turn_notification_status = notification_flow.status
	relay_child.enable_turn_notifications = notification_flow.enable
	relay_child.share_current_room = room_sharing.share
	relay_child.room_share_state = room_sharing.view
	relay_child.partner_friends = partner_friends
	relay_child.closed.connect(_leave_online_relay)
	add_child(relay_child)
	_sync_presence()

func _leave_online_relay() -> void:
	if is_instance_valid(relay_child):
		remove_child(relay_child)
		relay_child.queue_free()
	relay_child = null
	_set_world_visible(true)
	ui.visible = true
	soundscape.set_backgrounded(application_backgrounded)
	lifecycle_generation += 1
	_sync_presence()
	_return_to_room_hub(relay_session.last_error if relay_session != null else "",false)
	_deliver_then_refresh_hub.call_deferred()

## The one replay delivery after leaving play goes first; the hub reads its
## rooms after, so neither request finds the API busy and gives up.
func _deliver_then_refresh_hub() -> void:
	await replays_flow.deliver_completed_replay()
	if room_hub_flow.is_open() and mode == RoomHubFlow.MODE_ROOMS: room_hub_flow.refresh()

func _ensure_identity(report: Callable = Callable()) -> bool:
	if saves.data.has(DeletedPhotos.MARKER_KEY) or not deleted_identity_owner.is_empty():
		_report(report,PlayerCopy.MAIN_A9AD59F7E952)
		return false
	if not pending_recovery.is_empty():
		_report(report,PlayerCopy.MAIN_0F8B4A22AEFC)
		return false
	if identity_restart_required:
		_report(report,PlayerCopy.MAIN_5BC549F4B951)
		return false
	if identity_loading:
		var deadline := Time.get_ticks_msec()+10000
		while identity_loading and Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
		if identity_loading:
			_report(report,PlayerCopy.MAIN_29B12DE56EEF)
			return false
	if not api.player_id.is_empty() and not api.device_token.is_empty():
		return true
	if identity_busy:
		_report(report,PlayerCopy.MAIN_21155817127A)
		return false
	if not secrets.is_available():
		_report(report,PlayerCopy.for_platform(PlayerCopy.MAIN_3E8E7DA4CEE6,PlayerCopy.MAIN_3E8E7DA4CEE6_IOS))
		return false
	if identity_read_state!=IdentityReadState.MISSING:
		_report(report,PlayerCopy.MAIN_F0A53024D858)
		return false
	identity_busy=true
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/identity")
	if not response.ok:
		identity_busy=false
		_report(report,response.error)
		return false
	var persisted: Dictionary=await _await_secret(secrets.put_secret("player_identity",JSON.stringify(response.data)))
	identity_busy=false
	if not persisted.ok:
		identity_read_state=IdentityReadState.FAILED
		_report(report,PlayerCopy.MAIN_71B742112D9F)
		return false
	identity_read_state=IdentityReadState.LOADED
	identity_data=response.data.duplicate(true)
	api.player_id=str(response.data.player_id)
	api.device_token=str(response.data.device_token)
	store_flow.configure_purchases()
	settings_flow.refresh()
	return true

func _room_simulation_version() -> int:
	return TurnState.simulation_version({},role,active_room) if room_play else 0

## Starts this player's turn in the open legacy room, resuming the draft saved
## for its revision. The room page's Play your turn checks first
## (legacy_room_flow.play_turn).
func _start_room_turn() -> void:
	room_play=true
	level_index=int(active_room.level_index)
	current_level=Levels.get_level(str(active_room.level_id))
	role=str(active_room.active_role)
	attempt=LocalSave.normalize_attempt(active_room.get("recordings",{}))
	var local: Dictionary=saves.data.get("room_draft",{})
	if local.get("room_id","")==active_room.room_id and int(local.get("revision",-1))==int(active_room.revision):
		attempt.draft=local.get("attempt",{}).get("draft",{})
	earlier_islands_flow.prepare_turn()

func _watch_room_replay() -> void:
	room_play=true
	level_index=int(active_room.level_index)
	current_level=Levels.get_level(str(active_room.level_id))
	attempt=LocalSave.normalize_attempt(active_room.get("recordings",{}))
	earlier_islands_flow.preview(attempt.b,true)

## Legacy room writes (a turn, its check, Next island, a fork, a reaction) run
## one at a time: submission_in_flight holds while one is out, so a second tap
## meanwhile does nothing and other flows wait for it. Returns the work's
## result; nothing when another write is already out.
func _one_room_write(work: Callable) -> Variant:
	if submission_in_flight: return {"ok": false, "status": 0, "code": "request_busy", "ignored": true}
	submission_in_flight = true
	var result: Variant = await work.call()
	submission_in_flight = false
	return result

func _scroll_list(card: VBoxContainer, scrolling: bool=true) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	if scrolling:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size=Vector2(600,270)
		# Every row passes drags up, including plain _button links.
		ControlTheme.touch_scroll(scroll)
		card.add_child(scroll)
		scroll.add_child(list)
	else:
		card.add_child(list)
	return list

static func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text)==OK else null

func _set_world_visible(value: bool) -> void:
	if is_instance_valid(world):
		world.visible = value
	_sync_world_processing()

func _sync_world_processing() -> void:
	if not is_instance_valid(world):
		_suspended_world_id = 0
		return
	var world_id := world.get_instance_id()
	if application_backgrounded or not world.visible or _world_covered:
		if _suspended_world_id != world_id:
			_suspended_world_id = world_id
			_world_was_processing = world.is_processing()
		world.set_process(false)
	elif _suspended_world_id == world_id:
		world.set_process(_world_was_processing)
		_suspended_world_id = 0
	else:
		_suspended_world_id = 0

## Friends, the room hub, Safety and Redo requests are opaque full-screen layers, and full pages
## (chapters, Replays, Together) sit behind a 0.9 shade. Behind all of them the
## 3D Home world was still drawn (some 400 draw calls) and run every frame.
## Behind an opaque layer it is simply not drawn or run. Behind a page shade a
## still of it (one render through its own camera) takes its place under the
## shade, so the page looks the same. The live world returns when they close;
## its own visibility is left to its owners.
## The still lives while the world is frozen behind it: a page that redraws
## behind a new shade gets the same still back, with no new render or readback
## and the 3D pass left off. It is retaken when the world, its camera, the
## screen size or the render scale changed, and let go once the live world shows.
const FROZEN_SHADE_ALPHA := 0.85
var _backdrop_view: SubViewport
var _backdrop_shade_id := 0
var _backdrop_frames := 0
var _backdrop_ready := false
var _backdrop_still: Texture2D
var _backdrop_key: Array = []
## Reads the rendered still from its view; a test stands in here for a
## renderer that gives no image (headless).
var backdrop_reader: Callable

func _service_world_cover() -> void:
	var shade: ColorRect = overlay_shade if is_instance_valid(overlay_shade) and overlay_shade.color.a >= FROZEN_SHADE_ALPHA and overlay.visible and is_instance_valid(world) and world.visible and not application_backgrounded else null
	var shade_id := shade.get_instance_id() if shade != null else 0
	if shade_id != _backdrop_shade_id: _start_backdrop(shade)
	elif shade != null and not _backdrop_ready and is_instance_valid(_backdrop_view): _finish_backdrop(shade)
	# A shared replay draws its own world, even over Friends (a leaderboard run).
	var covered := not is_instance_valid(shared_replay_child) and (friends_flow.is_open() or room_hub_flow.is_open() or settings_flow.is_open() or is_instance_valid(safety_screen) or legacy_room_flow.redo_open() or (shade != null and _backdrop_ready))
	if not covered and _backdrop_still != null:
		_backdrop_still = null
		_backdrop_key = []
	if covered == _world_covered: return
	_world_covered = covered
	get_viewport().disable_3d = covered
	_sync_world_processing()

## How often this screen needs drawing (services/frame_policy.gd): chapters
## and replays answer for themselves; play, the completion moment and a
## chapter's loading card need full rate; every menu, card and page is calm
## (touching the screen, Home's camera included, brings full rate back).
func frame_demand() -> String:
	if not capture_path.is_empty(): return Frames.ACTIVE
	if is_instance_valid(relay_child): return relay_child.frame_demand() if relay_child.has_method("frame_demand") else Frames.ACTIVE
	if is_instance_valid(_chapter_opening): return Frames.ACTIVE
	if is_instance_valid(shared_replay_child): return Frames.ACTIVE if shared_replay_child.get("mode") in ["replay", "bloom"] else Frames.CALM
	if running or mode == "completion": return Frames.ACTIVE
	# A keepsake playing its tap at Home moves for a few seconds, then settles.
	if mode == "home" and is_instance_valid(home_stage_view) and home_stage_view.keepsake_playing(): return Frames.ACTIVE
	return Frames.CALM

## Renders the world once, through a copy of its camera, for the page shade.
func _start_backdrop(shade: ColorRect) -> void:
	if is_instance_valid(_backdrop_view): _backdrop_view.queue_free()
	_backdrop_view = null
	_backdrop_shade_id = shade.get_instance_id() if shade != null else 0
	_backdrop_ready = false
	_backdrop_frames = 0
	if shade == null or not is_instance_valid(world.get("camera")): return
	var source: Camera3D = world.camera
	if _backdrop_still != null and _backdrop_key_for(source) == _backdrop_key:
		_place_still(shade, _backdrop_still)
		return
	_backdrop_still = null
	_backdrop_key = []
	var view := SubViewport.new()
	view.size = get_viewport().size
	view.world_3d = get_viewport().world_3d
	# The same render scale as the live world (GraphicsPolicy), not native.
	view.scaling_3d_mode = get_viewport().scaling_3d_mode
	view.scaling_3d_scale = get_viewport().scaling_3d_scale
	view.msaa_3d = get_viewport().msaa_3d
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lens := Camera3D.new()
	lens.projection = source.projection
	lens.keep_aspect = source.keep_aspect
	lens.fov = source.fov
	lens.size = source.size
	lens.near = source.near
	lens.far = source.far
	lens.h_offset = source.h_offset
	lens.v_offset = source.v_offset
	lens.cull_mask = source.cull_mask
	lens.environment = source.environment
	view.add_child(lens)
	add_child(view)
	lens.global_transform = source.global_transform
	lens.current = true
	_backdrop_view = view

## What a still shows: this world through this camera, at this size, scale and
## quality. Low and Balanced share a scale, so the quality tells their motes
## and lighting apart.
func _backdrop_key_for(source: Camera3D) -> Array:
	var root := get_viewport()
	return [world.get_instance_id(), source.get_instance_id(), source.global_transform, source.fov, source.size,
		source.h_offset, source.v_offset, root.size, root.scaling_3d_scale, root.msaa_3d, GraphicsPolicy.normalize(saves.data.settings.get("graphics_quality"))]

## Puts the still under the shade once it is rendered. A renderer that gives
## no image (headless) keeps the live world.
func _finish_backdrop(shade: ColorRect) -> void:
	_backdrop_frames += 1
	if _backdrop_frames < 2: return
	var image: Image = backdrop_reader.call(_backdrop_view) if backdrop_reader.is_valid() else _backdrop_view.get_texture().get_image()
	_backdrop_view.queue_free()
	_backdrop_view = null
	if image == null or image.is_empty(): return
	_backdrop_still = ImageTexture.create_from_image(image)
	# Keyed on the camera as the still freezes it: the live world ran on while
	# the still rendered and stops from here, so a redraw finds it unchanged.
	if is_instance_valid(world.get("camera")): _backdrop_key = _backdrop_key_for(world.camera)
	_place_still(shade, _backdrop_still)

func _place_still(shade: ColorRect, texture: Texture2D) -> void:
	var still := TextureRect.new()
	still.name = "FrozenWorld"
	still.texture = texture
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_SCALE
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(still)
	shade.get_parent().add_child(still)
	shade.get_parent().move_child(still, shade.get_index())
	_backdrop_ready = true

func _foreground_refresh_safe() -> bool:
	# A paused rehearsal is still active work. Do not swap its source recording,
	# revision or review screen behind the player's back.
	return not is_instance_valid(relay_child) and not application_backgrounded and not running and not submission_in_flight and mode in ["home",RoomHubFlow.MODE_ROOMS,LegacyRoomFlow.MODE_ROOM,JourneyFlow.MODE_JOURNEY,ReplaysFlow.MODE_COLLECTION,SettingsFlow.MODE_SETTINGS,"saved"]

func _background_application() -> void:
	if application_backgrounded:
		return
	application_backgrounded=true
	_sync_world_processing()
	if is_instance_valid(soundscape):
		soundscape.set_backgrounded(true)
	lifecycle_generation+=1
	foreground_response={}
	action_pressed=false
	if is_instance_valid(stick):
		stick.release()
	if running:
		earlier_islands_flow.pause()
	else:
		# Covers the narrow interval between finishing a live turn and presenting
		# review. Preview and menu modes do not create or overwrite drafts.
		earlier_islands_flow.save_draft()

func _resume_application() -> void:
	# Android may deliver more than one resume/focus notification. A single
	# background-to-foreground transition schedules only one refresh.
	if not application_backgrounded:
		return
	application_backgrounded=false
	_sync_world_processing()
	store_flow.resume_purchase_access()
	if is_instance_valid(soundscape):
		# A full-screen child that muted Home (a room, a Together replay, Photo transfer) keeps it muted.
		soundscape.set_backgrounded(is_instance_valid(relay_child) or is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child))
	lifecycle_generation+=1
	foreground_response={}
	foreground_refresh_queued=true
	if app_status != null and app_status.due(): _check_app_status()
	if pollen_client != null: pollen_client.flush()
	# Do not resume the simulation automatically. The player explicitly presses
	# Continue on the pause card, keeping the recording clock under their control.

## Asks whether this build must update before playing online: at launch, and on a
## resume once the last answer is six hours old. A later answer replaces an earlier
## one, so "off" or any error lifts a block.
func _check_app_status() -> void:
	if app_status == null or app_status.busy: return
	await app_status.check()
	if _update_gate_active(): return
	update_gate_dismissed = false
	if mode == "update_gate": _show_home()

## True while online play needs a newer build and there is a store page to get it from.
func _update_gate_active() -> bool:
	return app_status != null and app_status.required() and not UpdateGate.target(ClientIdentity.channel(), config).is_empty()

## Online entry points ask first: while gated they show the update screen instead.
func _online_gated() -> bool:
	if not _update_gate_active(): return false
	# A full-screen child (a room, a replay, Photo transfer, Safety, a redo request)
	# keeps its own Back; the screen then waits for Home instead of drawing beneath it.
	if is_instance_valid(relay_child) or is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or legacy_room_flow.redo_open():
		_toast(PlayerCopy.UPDATE_REQUIRED_ERROR)
		_request_update_gate()
		return true
	_show_update_gate()
	return true

## A notification or invite link that would open an online screen: the update screen
## shows on Home instead, once Home is free.
func _request_update_gate() -> void:
	update_gate_dismissed = false

## Replaces Home with the update screen when an answer says so. A turn, a chapter or
## any other screen is never interrupted; the screen waits for Home, and for a finger
## on a Home button to lift so that tap is not lost.
func _service_update_gate() -> void:
	if update_gate_dismissed or not _update_gate_active() or not _home_free_for_card(): return
	_show_update_gate()

## Whether Home is free for a screen or card to come up of its own accord (the
## update screen, the Pollen card, a leaderboard celebration): Home is up with
## nothing over it, no turn, chapter or other screen, no card (What's new, a
## confirmation, a celebration) waiting to be read and closed, no finger held on
## a Home button, and no walk or pinch on the island in Explore. Online entries
## still ask _online_gated, which shows the update screen at once.
func _home_free_for_card() -> bool:
	if mode != "home" or application_backgrounded or running or is_instance_valid(relay_child) or is_instance_valid(_chapter_opening) or friends_flow.is_open() or room_hub_flow.is_open(): return false
	if is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or legacy_room_flow.redo_open(): return false
	if is_instance_valid(_whats_new_card) or _top_modal() != null or TouchInput.press_held(overlay): return false
	return not (is_instance_valid(home_stage_view) and home_stage_view.is_exploring())

## "Your monthly Pollen arrived", once per instalment, on Home only and only
## when nothing else is up: never over a turn, a card or a held finger.
func _service_grant_card() -> void:
	if not grant_card_check or not _grant_card_allowed() or _update_gate_active() or not _home_free_for_card(): return
	grant_card_check=false
	var scope := _names_scope()
	if scope.is_empty(): return
	var card: Dictionary = PollenGrant.shared().pending(str(scope.server),str(scope.owner))
	if card.is_empty(): return
	PollenGrant.shared().mark_shown(str(scope.server),str(scope.owner),str(card.key))
	PollenGrantCard.open(ui,card)

## A run of this player's that a board confirmed in its top 10
## (services/leaderboard_placings.gd) is celebrated once on Home, when Home is
## free: never over a turn, a chapter, another screen or card, or a held
## finger, and only while the server has leaderboards on. On the board itself
## the leaderboard screen celebrates it. Home left another way (a notification,
## a link) takes the celebration with it: it was already marked shown.
func _service_leaderboard_celebration() -> void:
	if is_instance_valid(_home_celebration) and (mode != "home" or not ui.visible): _home_celebration.close()
	if api == null or is_instance_valid(_home_celebration): return
	var owner := str(api.player_id)
	if owner.is_empty() or not LeaderboardPlacings.shared().has_pending(owner): return
	if relay_session == null or not relay_session.leaderboards_supported(): return
	if _home_settling() or _update_gate_active() or not _home_free_for_card(): return
	_home_celebration = LeaderboardCelebration.show_next(ui, owner, bool(saves.data.settings.get("reduced_motion", false)))
	if _home_celebration != null: _home_celebration.view_board.connect(_view_leaderboard)

## A celebration's View board on Home: Friends' leaderboards, on that board's chapter.
func _view_leaderboard(board: String) -> void:
	await _show_friends()
	if friends_flow.is_open(): friends_flow.open_leaderboards(LeaderboardRuns.chapter_of(board))

func _show_update_gate() -> void:
	running=false
	room_play=false
	hud.visible=false
	mode="update_gate"
	# Friends is a layer above the overlay: close it so the screen is never hidden.
	friends_flow.close()
	ui.visible=true
	var view := UpdateGate.view(str(app_status.result.get("min_version","")))
	var card := _card(600)
	card.add_child(_label(view.title,34,CREAM,true))
	card.add_child(_paragraph(view.body,560))
	var update := _button(view.update,_open_update_target)
	update.name = "UpdateGateUpdate"
	card.add_child(update)
	var solo := _button(view.solo,_play_solo_from_update_gate,false)
	solo.name = "UpdateGateSolo"
	card.add_child(solo)

func _open_update_target() -> void:
	var target := UpdateGate.target(ClientIdentity.channel(), config)
	if target.is_empty(): return
	if update_gate_open_url.is_valid(): update_gate_open_url.call(target)
	else: OS.shell_open(target)

func _play_solo_from_update_gate() -> void:
	update_gate_dismissed = true
	journey_flow.show_journey()

## A route refused this build as too old: ask again, at most once a minute.
func _on_update_required() -> void:
	if app_status == null or app_status.busy: return
	if app_status.checked_at >= 0.0 and absf(app_status.now() - app_status.checked_at) < 60.0: return
	_request_update_gate()
	_check_app_status()

func _service_foreground_refresh() -> void:
	if not _foreground_refresh_safe() or foreground_refresh_running:
		return
	if not foreground_response.is_empty():
		var deferred := foreground_response
		foreground_response={}
		if int(deferred.get("generation",-1))==lifecycle_generation and str(deferred.get("context",""))==_foreground_room_context(str(deferred.room_id)):
			_apply_foreground_response(deferred.response,str(deferred.room_id))
	if api==null or identity_loading or identity_busy:
		return
	if not api.configured() or identity_restart_required or api.player_id.is_empty() or api.device_token.is_empty():
		foreground_refresh_queued=false
		return
	var pending: Dictionary=saves.data.get("pending_turn",{})
	var room_id := str(saves.data.get("room",{}).get("room_id",""))
	if not pending.is_empty() and turn_flow.pending_owned(pending):
		room_id=str(pending.get("room_id",""))
	if room_id.is_empty():
		foreground_refresh_queued=false
		foreground_schedule.bind("",Time.get_ticks_msec())
		return
	var now := Time.get_ticks_msec()
	var context := _foreground_room_context(room_id)
	foreground_schedule.bind(context,now)
	if foreground_refresh_queued:
		foreground_schedule.request_now(now)
		foreground_refresh_queued=false
	elif mode not in [LegacyRoomFlow.MODE_ROOM,RoomHubFlow.MODE_ROOMS]:
		return
	var ticket: Dictionary=foreground_schedule.begin_if_due(now,true,false)
	if ticket.is_empty():
		return
	foreground_refresh_running=true
	var generation := lifecycle_generation
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id)
	foreground_refresh_running=false
	var current := context==_foreground_room_context(room_id)
	# A room that reads the same as last time waits longer before the next read.
	var changed: bool = not response.get("ok",false) or foreground_schedule.changed(response.get("data"))
	foreground_schedule.complete(ticket,Time.get_ticks_msec(),response.get("ok",false),int(response.get("retry_after_ms",0)),response.get("status",0) in [401,403,404,410],changed)
	if generation!=lifecycle_generation or not current:
		return
	if not _foreground_refresh_safe():
		foreground_response={"response":response,"room_id":room_id,"generation":generation,"context":context}
		return
	_apply_foreground_response(response,room_id)

func _foreground_room_context(room_id: String) -> String:
	return JSON.stringify([api.player_id,_token_digest(),relay_identity_epoch,lifecycle_generation,room_id])

func _apply_foreground_response(response: Dictionary, requested_room: String) -> void:
	if not response.get("ok",false):
		if mode in [LegacyRoomFlow.MODE_ROOM,RoomHubFlow.MODE_ROOMS]:
			_toast(str(response.get("error",PlayerCopy.MAIN_076E60DB25EC)))
		return
	var incoming: Variant=response.get("data",{})
	if incoming is Dictionary:
		incoming=incoming.get("room",incoming)
	if not incoming is Dictionary or str(incoming.get("room_id",""))!=requested_room or Levels.get_level(str(incoming.get("level_id",""))).is_empty():
		return
	if not legacy_room_flow.navigation_ready(requested_room,false): return
	var displayed: bool=str(active_room.get("room_id",""))==requested_room
	var remembered: bool=str(saves.data.get("room",{}).get("room_id",""))==requested_room
	var pending: Dictionary=saves.data.get("pending_turn",{})
	var confirmed: bool=TurnState.pending_status(pending,incoming)=="accepted"
	if not displayed and not remembered and not confirmed:
		return
	var known_revision := -1
	if displayed:
		known_revision=maxi(known_revision,int(active_room.get("revision",-1)))
	if remembered:
		known_revision=maxi(known_revision,int(saves.data.room.get("revision",-1)))
	if int(incoming.get("revision",-1))<known_revision:
		return
	var changes: Dictionary={}
	if remembered and saves.data.room!=incoming:
		changes["room"]=incoming.duplicate(true)
	var erased: Array=["pending_turn","room_draft"] if confirmed else []
	if not changes.is_empty() or not erased.is_empty():
		if not saves.update_values(changes,erased):
			_toast(saves.last_error)
			return
	if displayed:
		var changed: bool=active_room!=incoming
		_notice_room_reactions(active_room,incoming)
		if not TurnState.my_turn(active_room,api.player_id) and TurnState.my_turn(incoming,api.player_id):
			_toast(PlayerCopy.MAIN_09164F93CEA2)
		active_room=incoming.duplicate(true)
		if mode==LegacyRoomFlow.MODE_ROOM and changed:
			legacy_room_flow.redraw_when_free(requested_room)
	if confirmed:
		_toast(PlayerCopy.MAIN_A917FC21E486)
	# An unmatched pending request stays queued for explicit reconciliation.
	# Returning to the app never starts or retries a POST automatically.
	if mode == LegacyRoomFlow.MODE_ROOM: legacy_room_flow.refresh_redo()

## A flow's reason for stopping goes where its caller shows reasons: Home's
## toast by default, the hub's notice (RoomHubFlow.message) for a hub tap.
func _report(report: Callable, text: String) -> void:
	if report.is_valid(): report.call(text)
	else: _toast(text)

func _toast(text: String) -> void:
	toast.post(text)

func _process(delta: float) -> void:
	_service_world_cover()
	replays_flow.service_collection_replay()
	replays_flow.service_solo_collection()
	replays_flow.service_shared_replays()
	_service_home_keepsakes(delta)
	_sync_presence()
	_sync_live()
	earlier_islands_flow.advance_completion_moment(delta)
	_service_foreground_refresh()
	if is_instance_valid(turn_notifications):
		turn_notifications.service(Time.get_ticks_msec(), not application_backgrounded, not submission_in_flight and not foreground_refresh_running and not running and (relay_session == null or not relay_session.busy()))
		notification_flow.service_route()
	_service_invite_link()
	notification_flow.service_friends()
	_service_whats_new()
	_service_update_gate()
	_service_grant_card()
	_service_leaderboard_celebration()
	_service_photo_resume()
	if not capture_path.is_empty():
		capture_frames+=1
		if capture_frames==90:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_path)
			get_tree().quit()

## Home has just opened: its island still folds, or the screen before it is
## still being freed (services/screen_switch.gd).
func _home_settling() -> bool:
	return (is_instance_valid(home_stage_view) and home_stage_view.folding()) or ScreenSwitch.pending_count() > 0

func _service_home_keepsakes(delta: float) -> void:
	if mode not in ["home",JourneyFlow.MODE_JOURNEY] or application_backgrounded or is_instance_valid(relay_child) or is_instance_valid(_chapter_opening): return
	# In a frame of its own: after Home's island has folded and the screen
	# before it has been freed, which both take the first frames.
	if _keepsakes_reconcile_frame >= 0 and Engine.get_process_frames() > _keepsakes_reconcile_frame and not _home_settling():
		_keepsakes_reconcile_frame = -1
		home_keepsakes.reconcile_solo(saves.data.get("replays", {}))
		if shared_replays != null: home_keepsakes.reconcile_friend(shared_replays)
	_keepsake_poll += delta
	if _keepsake_poll < 0.15: return
	_keepsake_poll = 0.0
	var identity := _relay_identity()
	if identity.ready and identity != _keepsake_identity:
		_keepsake_identity = identity.duplicate()
		if shared_replays == null: shared_replays = SharedReplays.new(api,_relay_identity)
		# The cached index is enough here. Loading every saved room would replay
		# its full proof on the home thread; verification is queued by the service.
		home_keepsakes.reconcile_friend(shared_replays)
	if home_keepsakes.backfill_pending(): home_keepsakes.advance_backfill(1)
	if mode == JourneyFlow.MODE_JOURNEY:
		journey_flow.refresh_marks()
	elif is_instance_valid(home_stage_view):
		home_stage_view.set_keepsakes(home_keepsakes.earned_descriptors())
		if [FileAccess.get_modified_time(HardMode.MARKS_PATH), hard_together()] != _home_hard_stamp: _set_home_hard(home_stage_view)
		var offer := overlay.get_node_or_null("HomeFullJourney") as Button
		if offer != null: offer.visible = _full_journey_offered()

func _notification(what: int) -> void:
	# The retained parent owns services, while the child owns its active draft,
	# input and Back/close behavior. Never let both screens process Back.
	# Checks what first: other notifications arrive before the flows exist and after they are freed.
	if what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST] and (is_instance_valid(relay_child) or is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or friends_flow.is_open() or duels_flow.is_open() or legacy_room_flow.redo_open()):
		return
	if what==NOTIFICATION_APPLICATION_PAUSED:
		_background_application()
		_write_backup_plan()
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		if is_instance_valid(turn_notifications): turn_notifications.queue_reconcile()
		_resume_application()
	elif what==NOTIFICATION_APPLICATION_FOCUS_OUT and running:
		# A notification shade or another app over a turn pauses it, as in a chapter.
		earlier_islands_flow.pause()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		# The update screen has no Back: the player updates or picks Play Solo.
		if account_flow.holds_back() or mode == "update_gate": return
		if _close_top_modal(): return
		if is_instance_valid(_whats_new_card): _whats_new_card.close()
		elif mode == ReplaysFlow.MODE_COLLECTION_LOADING: replays_flow.show_collection()
		elif mode in ["confirm_retry", "confirm_restart", ReplaysFlow.MODE_CONFIRM_DELETE]:
			if _retry_cancel.is_valid(): _retry_cancel.call()
		# Together replays: Android Back goes where their on-screen Back goes.
		elif mode in [ReplaysFlow.MODE_SHARED_REPLAYS, ReplaysFlow.MODE_SHARED_MEMORIES] and not is_instance_valid(shared_replay_child): _show_home()
		elif running or mode=="completion":
			earlier_islands_flow.pause()
		elif mode==SettingsFlow.MODE_LICENSE_TEXT:
			settings_flow.show_licenses()
		elif mode == StoreFlow.MODE_TESTER_ACCESS:
			settings_flow.show_settings(SettingsFlow.ACCOUNT)
		elif mode==RelayLobbyFlow.MODE_LOBBY:
			_return_to_room_hub()
		elif mode==RoomHubFlow.MODE_ROOMS and room_hub_flow.is_open():
			room_hub_flow.go_back()
		elif mode==RoomHubFlow.MODE_ROOMS:
			# A room flow that left no hub behind: Back still goes Home.
			room_hub_flow.close()
		else:
			_back_on_screen()
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not earlier_islands_flow.save_draft():
			earlier_islands_flow.pause()
			_toast(PlayerCopy.MAIN_A3FDAA4A9D35)
			return
		get_tree().quit()

func _setup_turn_notifications() -> void:
	var native := NotificationBridge.new()
	add_child(native)
	turn_notifications = TurnNotifications.new()
	notification_flow.configure_service(turn_notifications, native)
	add_child(turn_notifications)

## The device token's SHA-256, kept until the token changes: several services
## build identity keys from it every frame.
var _digested_token := ""
var _token_sha := ""
func _token_digest() -> String:
	if api.device_token != _digested_token:
		_digested_token = api.device_token
		_token_sha = _digested_token.sha256_text()
	return _token_sha

## The online session, created on first use.
func ensure_relay_session() -> void:
	if relay_session == null: relay_session = _new_relay_session()

## The open legacy room is read again at the next foreground refresh.
func queue_foreground_refresh() -> void:
	foreground_refresh_queued = true

## An explicit read of the legacy room supersedes the foreground refresh: a queued
## read and a held answer are dropped, and one still out is ignored when it returns.
func supersede_foreground_refresh() -> void:
	foreground_refresh_queued=false
	foreground_response={}
	lifecycle_generation+=1

## Once a session, on Home: a turn that still waits for its photo because After You closed
## while the camera was open. Its room opens on request and offers that photo again.
func _service_photo_resume() -> void:
	if _photo_resume_checked or not _photo_resume_safe(): return
	_photo_resume_checked = true
	if not is_instance_valid(photo_resume_prompt):
		photo_resume_prompt = PhotoResumePrompt.new()
		photo_resume_prompt.open_requested.connect(_open_photo_resume_room)
		add_child(photo_resume_prompt)
	var owner := str(_relay_identity().player_id)
	var entry: Dictionary = await photo_resume_prompt.check(owner)
	if entry.is_empty() or not _photo_resume_safe() or str(_relay_identity().player_id) != owner: return
	photo_resume_prompt.show_prompt(ui, entry)

func _photo_resume_safe() -> bool:
	if mode != "home" or application_backgrounded or running or submission_in_flight or identity_loading or identity_busy or foreground_refresh_running or is_instance_valid(relay_child) or saves.read_only: return false
	if is_instance_valid(_whats_new_card): return false # One Home card at a time; this one waits.
	if _update_gate_active(): return false # The room cannot open until this build is updated.
	if not _relay_identity().ready or not saves.data.get("pending_turn", {}).is_empty() or not saves.data.get("room_draft", {}).is_empty(): return false
	if relay_session != null and (relay_session.busy() or not relay_session.can_leave_for_legacy() or (relay_session.coordinator != null and not relay_session.coordinator.draft().is_empty())): return false
	return legacy_room_flow.navigation_ready("", false)

func _open_photo_resume_room(room_id: String) -> void:
	if _online_gated(): return
	if not _photo_resume_safe():
		_toast(PlayerCopy.MAIN_BE8E691311EE)
		return
	ensure_relay_session()
	if relay_session.capabilities.is_empty():
		if not await relay_session.load_lobby():
			_toast(PlayerCopy.MAIN_571E92F64ED1)
			return
		if not _photo_resume_safe(): return
	if not await relay_session.open_room(room_id):
		_toast(PlayerCopy.MAIN_BE8E691311EE)
		return
	# The room's first view finds the waiting photo and opens its card (relay_preview.gd).
	if _photo_resume_safe(): _enter_online_relay()

func _setup_invite_links() -> void:
	invite_link_bridge = InviteLinkBridge.new()
	invite_link_bridge._native = invite_link_native
	invite_link_bridge.received.connect(_invite_link_received)
	add_child(invite_link_bridge)
	# A link the last Main was holding when a solo chapter replaced it.
	var held := InviteLinkBridge.take_held()
	if not held.is_empty() and Time.get_ticks_msec() < int(held.expires_ms):
		invite_link_pending = str(held.id)
		invite_link_expires_ms = int(held.expires_ms)

func _invite_link_received(result: Dictionary) -> void:
	if not result.get("ok", false) or result.get("type") != ShareCodes.FRIEND:
		if is_instance_valid(toast): _toast(PlayerCopy.FRIEND_CODE_INVALID)
		return
	# A newer link replaces one that has not been shown yet.
	invite_link_pending = str(result.id)
	invite_link_expires_ms = Time.get_ticks_msec() + INVITE_LINK_TTL_MS
	invite_link_retry_ms = 0
	invite_link_attempts = 0
	invite_link_notice = false

## True while the player is in the middle of something a link must not interrupt.
func _invite_link_occupied() -> bool:
	if running or mode not in INVITE_LINK_MODES: return true
	if is_instance_valid(relay_child) or is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or legacy_room_flow.redo_open(): return true
	if not saves.data.get("pending_turn", {}).is_empty() or not saves.data.get("room_draft", {}).is_empty(): return true
	if relay_session != null and relay_session.coordinator != null and not relay_session.coordinator.draft().is_empty(): return true
	return false

## Short-lived work (requests, refreshes, identity reads) that only delays the link.
func _invite_link_settling() -> bool:
	if application_backgrounded or submission_in_flight or foreground_refresh_running or identity_loading or identity_busy: return true
	if identity_read_state in [IdentityReadState.UNCHECKED, IdentityReadState.LOADING]: return true
	return relay_session != null and relay_session.busy()

## At least as strict as NotificationFlow.route_safe. A link never creates an identity:
## without one it waits until the player opens Friends themselves.
func _invite_link_safe() -> bool:
	if saves.read_only or _invite_link_settling() or _invite_link_occupied(): return false
	if not _relay_identity().ready: return false
	if mode == FriendsFlow.MODE_FRIENDS and not friends_flow.is_open(): return false
	if not legacy_room_flow.navigation_ready("", false): return false
	return relay_session == null or relay_session.can_leave_for_legacy()

func _service_invite_link() -> void:
	if invite_link_pending.is_empty(): return
	var now := Time.get_ticks_msec()
	if now >= invite_link_expires_ms:
		invite_link_pending = ""
		return
	if invite_link_busy or now < invite_link_retry_ms: return
	if saves.read_only:
		# Friends cannot open with read-only saves; drop the link without a message.
		invite_link_pending = ""
		return
	if _update_gate_active():
		# Friends is online: the link is dropped at once (it could never open while
		# gated) and Home shows the update screen.
		invite_link_pending = ""
		_request_update_gate()
		return
	if not _invite_link_safe():
		# Only real activity gets the one short note; brief work and a missing identity wait quietly.
		if not invite_link_notice and not _invite_link_settling() and _invite_link_occupied():
			invite_link_notice = true
			_toast(PlayerCopy.INVITE_LINK_WAITING)
		return
	invite_link_busy = true
	var friend := invite_link_pending
	# Same authenticated entry as the Home Friends button; identity is already loaded here.
	if mode != FriendsFlow.MODE_FRIENDS or not friends_flow.is_open(): await _show_friends()
	invite_link_busy = false
	if friend != invite_link_pending: return
	if mode == FriendsFlow.MODE_FRIENDS and friends_flow.is_open():
		invite_link_pending = ""
		friends_flow.confirm_invite_link(friend)
		return
	# _show_friends already showed the existing identity or availability message.
	invite_link_attempts += 1
	invite_link_retry_ms = Time.get_ticks_msec() + INVITE_LINK_RETRY_MS
	if invite_link_attempts >= INVITE_LINK_ATTEMPTS: invite_link_pending = ""

func _room_safety() -> void:
	if active_room.is_empty() or not _relay_identity().ready: return
	var peer: Variant = active_room.get("guest_id") if active_room.get("host_id") == api.player_id else active_room.get("host_id")
	if not Safety.Store.id(peer): return
	_open_safety({"room_family": "legacy", "room_id": active_room.room_id, "peer_id": peer}, "room")

func _open_safety(context: Dictionary = {}, return_to: String = "settings") -> void:
	if is_instance_valid(safety_screen): return
	if submission_in_flight or foreground_refresh_running or (relay_session != null and relay_session.busy()):
		_toast(PlayerCopy.MAIN_8D6F750820DC)
		return
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	safety_return = return_to
	mode = "safety"
	running = false
	ui.visible = false
	safety_screen = SafetyScreen.new(Safety.new(api, _relay_identity, null, Callable(), _room_context_factory()), context, _close_safety, _blocked_safety.bind(str(context.get("room_id",""))))
	add_child(safety_screen)

func _close_safety() -> void:
	safety_screen = null
	ui.visible = true
	if safety_return == "room" and not active_room.is_empty(): legacy_room_flow.show_room()
	elif safety_return == "account": settings_flow.show_settings(SettingsFlow.ACCOUNT)
	else: settings_flow.show_settings(SettingsFlow.ABOUT)

## room_id is the earlier-island room the block came from; only such a room
## can be blocked from here.
func _blocked_safety(room_id: String = "") -> void:
	safety_screen = null
	ui.visible = true
	running = false
	# The server leaves the blocked room out of the hub. This phone forgets it as
	# a removed room would be and stops showing it.
	if not room_id.is_empty():
		active_room = {}
		# The server has confirmed the block, so nothing saved for this room can
		# ever be sent: an unsent turn is kept like a held turn, a turn left part
		# way is dropped, and online play reopens.
		var pending: Dictionary = Typed.as_dict(saves.data.get("pending_turn")).duplicate(true)
		if str(pending.get("room_id","")) == room_id and turn_flow.pending_owned(pending):
			turn_flow.keep_held_turn(turn_flow.reject_pending(pending),{})
		if str(Typed.as_dict(saves.data.get("room_draft")).get("room_id","")) == room_id and not saves.update_values({},["room_draft"]): _toast(saves.last_error)
		forget_removed_room(1,room_id)
		room_hub_flow.hide_room(1,room_id)
	_return_to_room_hub()


func _tester_checks_enabled() -> bool:
	return PlatformSupport.store_gated() or tester_access_factory.is_valid()

func _tester_context() -> String:
	if not _relay_identity().ready: return ""
	return JSON.stringify([api.base_url, api.player_id, _token_digest(), relay_identity_epoch])

func _tester_active() -> bool:
	return _tester_checks_enabled() and is_instance_valid(tester_access) and not _tester_context().is_empty() and tester_access.active(api.base_url, api.player_id, api.device_token)

func _full_journey_access() -> bool:
	return _tester_active() or purchases.has_entitlement()

## True on an iOS build that sells nothing: every paid surface (chapter cards,
## earlier islands, the Full Journey offer, hosting access) is left out, never
## shown locked. The one rule is Purchases.paid_content_hidden.
func _paid_content_hidden() -> bool:
	return Purchases.paid_content_hidden(config)

## The monthly grant card names Full Journey, so this build's configuration
## decides it the way every Pollen surface does (services/pollen_surfaces.gd).
func _grant_card_allowed() -> bool:
	return PollenSurfaces.for_configuration(config).full_journey_visible()

## Home's Full Journey offer: shown while there is something to unlock and buy.
func _full_journey_offered() -> bool:
	return not _full_journey_access() and not _paid_content_hidden()

## Paid gates wait on the one saved tester receipt read for this identity.
func _load_cached_tester() -> void:
	if not _tester_checks_enabled() or not is_instance_valid(tester_access): return
	await tester_access.check_cache_once(_tester_context(),_tester_context,api.base_url,api.player_id,api.device_token)

## A paid scene's first access check takes Main's read of the saved tester
## receipt, written in the frame the scene opens, when that read is for the
## identity now in use. Otherwise the scene reads the receipt itself.
func _hand_over_tester_check(scene: String) -> void:
	if _tester_checks_enabled() and is_instance_valid(tester_access) and tester_access.checked_for(_tester_context(), api.base_url, api.player_id, api.device_token):
		ChapterAccess.hand_over(scene, api.base_url, _tester_active())
	else:
		ChapterAccess.drop_hand_over()

## The identity presence and the live socket follow.
func _online_identity() -> Dictionary:
	var identity := _relay_identity()
	identity["base_url"] = api.base_url
	identity["device_token"] = api.device_token
	# A pending account deletion cannot republish an old credential.
	if saves.data.has(DeletedPhotos.MARKER_KEY) or not deleted_identity_owner.is_empty(): identity.ready = false
	return identity

func _sync_live() -> void:
	live_connection.api = api
	live_connection.set_identity(_online_identity())

func _sync_presence() -> void:
	if not is_instance_valid(friend_presence): return
	friend_presence.set_identity(_online_identity())
	var family := ""
	var room := ""
	if is_instance_valid(relay_child) and relay_session != null:
		family = "v2"
		room = relay_session.last_room()
	elif not active_room.is_empty() and (mode == LegacyRoomFlow.MODE_ROOM or (room_play and mode in ["ready", "play", "preview", "review", "paused", "saved", "completion"])):
		family = "v1"
		room = str(active_room.get("room_id", ""))
	if family == "v2":
		var factory := _room_context_factory()
		var context: RefCounted = factory.for_room(room,"presence")
		friend_presence.monitor_room(family,room,context,true)
	else:
		friend_presence.monitor_room(family,room)
	if is_instance_valid(presence_hud) and (presence_hud.room_id != room or presence_hud.family != family):
		presence_hud.queue_free()
		presence_hud = null
	if family == "v1" and not room.is_empty() and not is_instance_valid(presence_hud):
		presence_hud = PresenceBadge.new()
		presence_hud.configure(friend_presence, family, room)
		hud.add_child(presence_hud)
		presence_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		presence_hud.offset_left = -270
		presence_hud.offset_right = -36
		presence_hud.offset_top = 88
		presence_hud.offset_bottom = 112
		presence_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if is_instance_valid(presence_hud): presence_hud.visible = family == "v1" and room_play

func _exit_tree() -> void:
	# The next scene draws 3D in this same root viewport.
	if is_instance_valid(_backdrop_view): _backdrop_view.queue_free()
	if _world_covered:
		_world_covered = false
		get_viewport().disable_3d = false
	replays_flow.release_workers()
	platform_games_flow.detach()
	home_keepsakes.deactivate()
	# A waiting invite link outlives a scene change (a solo chapter); it never reaches disk.
	InviteLinkBridge.hold(invite_link_pending, invite_link_expires_ms)
	# The room view ends here; foreground presence continues in standalone scenes.
	if is_instance_valid(friend_presence): friend_presence.monitor_room("", "")

func _camera_exploration_active() -> bool:
	return not application_backgrounded and mode in ["play", "preview", "completion"] and not overlay.visible

func _camera_exploration_allowed(point: Vector2) -> bool:
	return not world.CameraExploration.ui_blocks(ui, point)

## The identity-bound factory for chapter-room photo, presence, safety and
## replay requests. Without an online identity every target it gives is held.
## Shared replays always use the current one.
func _room_context_factory() -> RefCounted:
	if not _relay_identity().ready: return AuxiliaryContext.new(null,{})
	ensure_relay_session()
	var factory: RefCounted = relay_session.auxiliary_context_factory()
	if shared_replays != null: shared_replays.configure_context_factory(factory)
	return factory

func _prepare_ordinary_navigation(report: Callable = Callable()) -> bool:
	if _relay_identity().ready: _room_context_factory()
	if relay_session == null:
		_report(report,PlayerCopy.MAIN_21155817127A)
		return false
	var session: RefCounted = relay_session
	# The session refuses while busy (a replay save can outlive its screen) and has no reason of its own to give.
	if session.busy():
		_report(report,PlayerCopy.ROOMS_API_DA75E6F7A674)
		return false
	var context := {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}
	var prepared: bool = await session.prepare_archived_navigation()
	# The player moved on meanwhile: nothing to say on a screen they left.
	if relay_session != session or application_backgrounded or context != {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}: return false
	# The session also refuses, without a reason, an identity that is not ready (or changed).
	if not prepared or not _relay_identity().ready:
		_report(report,session.last_error if _relay_identity().ready and not session.last_error.is_empty() else PlayerCopy.MAIN_21155817127A)
		return false
	# The last room was found gone with a request still held for it.
	var note: String = session.take_released_room_note()
	if not note.is_empty(): _report(report,note)
	return true
