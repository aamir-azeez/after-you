extends Node
## The Replays library: Your replays (solo), Shared replays (Together), the
## worker that loads an earlier-island replay, Watch/Play launches, and saving
## a finished room's replay to this phone with its friend photos.
##
## Main hosts it as a child and keeps the shared replay collection, the replay
## viewer child. The flow keeps its own state and screens,
## asks Main to navigate through the signals below, and reads Main only through
## this host contract (read at call time, so Main or a test can swap a service):
## - services: api, saves, shared_replays, relay_session, _new_relay_session,
##   _wire_shared_history, friend_nicknames, _room_context_factory, app_status,
##   _update_gate_active, _history_mode, _relay_identity, identity_loading
## - screen: mode, running, room_play, store_view_generation,
##   application_backgrounded, submission_in_flight, lifecycle_generation,
##   foreground_refresh_queued, foreground_response, _retry_cancel, ui, overlay,
##   overlay_shade, _clear_overlay, _update_shade_bounds, _bounded_card_scroll,
##   _bounded_card_stack, _set_world_visible, soundscape, title_font
## - play: levels, current_level, attempt, preview_saved_attempt,
##   _activate_preview, _room_simulation_version, relay_child, LIGHTHOUSE_SCENE,
##   _open_chapter_preview, _open_premium_chapter
## - Together viewer: shared_replay_child (this flow adds it to Main and removes it)
## - card kit: _card, _label, _paragraph, _button, _list_button, _back_button,
##   _scroll_list, _style, _fit_icon_button, _replay_preview_thumb, _toast
## - node: get_tree, is_inside_tree, add_child, remove_child
## Main calls the service_* methods each frame, cancel_collection_replay when its
## overlay is cleared, cancel_solo_collection_scan when the mode leaves Your
## replays, invalidate_identity when the identity changes and release_workers
## when it leaves the tree.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ReplayLoadingBar = preload("res://presentation/replay_loading_bar.gd")
const UpdateGate = preload("res://presentation/update_gate_screen.gd")
const WhenLabel = preload("res://presentation/when_label.gd")
const SharedReplayView = preload("res://presentation/shared_replay_view.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const ChapterThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const RoomStages = preload("res://services/room_stages.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const ReplayLoadProgress = preload("res://services/replay_load_progress.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const EarlierIslandReplay = preload("res://services/earlier_island_replay.gd")
const SharedReplays = preload("res://services/shared_replay_collection.gd")
const SoloReplayCollection = preload("res://services/solo_replay_collection.gd")
const SoloReplayIndex = preload("res://services/solo_replay_index.gd")
const SoloReplayVisibility = preload("res://services/solo_replay_visibility.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("9dbeb4")
## Main's mode on each screen of this flow.
const MODE_COLLECTION := "collection"
const MODE_COLLECTION_LOADING := "collection_loading"
const MODE_SOLO_REPLAY_ATTEMPT := "solo_replay_attempt"
const MODE_CONFIRM_DELETE := "confirm_delete_replay"
const MODE_SHARED_REPLAYS := "shared_replays"
const MODE_SHARED_MEMORIES := "shared_memories"
## A Together replay is playing in Main's viewer child.
const MODE_SHARED_REPLAY := "shared_replay"
## Replay library shows the row list beside a fixed preview card once the safe
## width reaches this; narrower screens stack the preview under the list.
const REPLAY_SPLIT_MIN_WIDTH := 1000.0
const EMPTY_SOLO_COLLECTION := PlayerCopy.EMPTY_SOLO_TEXT
const SOLO_COLLECTION_SCANNING := "Looking for more saved replays…"
## Newly settled solo rows are revealed at most this often during a scan.
const SOLO_COLLECTION_REDRAW_MS := 400
## Together waits this long for the startup account read before showing the
## sign-in explanation.
const SHARED_IDENTITY_WAIT_MS := 10000
## Most friend turn photos one Together photo fetch asks the server for.
const SHARED_PHOTO_FETCH_LIMIT := 16

signal home_requested
signal account_requested

var host: Node
# Optional hook so a friend-nickname lookup (which lives in the C client) can
# supply a saved partner's display name. Default playback shows a neutral label.
var replay_partner_label: Callable = Callable()
var _shared_replay_loading_bar: VBoxContainer
var _collection_replay_worker: Thread
var _collection_replay_job: Dictionary = {}
var _collection_replay_worker_job: Dictionary = {}
var _collection_replay_loading_bar: VBoxContainer
var _replay_library_header: VBoxContainer
var _replay_title_style: StyleBoxFlat
var _replay_hit_style: StyleBoxEmpty
var _replay_card_styles: Dictionary = {}
var solo_replays: RefCounted
var solo_replay_visibility: RefCounted = SoloReplayVisibility.new()
## Display-only rows of the last finished scan, drawn unplayable at once.
var solo_replay_index: RefCounted
var _selected_solo_attempt: Dictionary = {}
var _solo_collection_message := ""
var _solo_collection_started := false
## Solo scan feedback: the bar in the open list, the settled row count drawn
## with it, and when newly settled rows may next be drawn.
var _solo_scan_bar: VBoxContainer
var _solo_scan_found := false
var _solo_collection_shown := ""
var _solo_collection_dirty := false
var _solo_collection_redraw_at := 0
## The open Solo list as drawn, so a check that only makes rows playable can
## update them where they are instead of rebuilding the screen.
var _solo_drawn_layout := ""
var _solo_row_views: Dictionary = {}
var _solo_entries_by_key: Dictionary = {}
var _solo_preview_box: VBoxContainer
var _solo_refresh_button: Button
## View generation of a Watch/Play wait in progress; -1 when none.
var _replay_launch_view := -1
var _shared_identity_wait_until := -1
var _shared_drawn_room := ""
## Which saved shared memory is shown in the Together preview card.
var _shared_preview_id := ""
var shared_replay_room := ""
var _shared_photo_sync := false
## The Together room a Watch replay tap asked for, shown as soon as this phone
## holds it; never another room in its place.
var _shared_wanted_room := ""
## Quiet retries (seconds) when saving a finished room's replay meets a busy or
## offline moment; then the next leave or Watch replay tries again.
var replay_save_retry_s: Array[float] = [2.0, 6.0, 20.0]
## Finished rooms whose replay is being saved now, by room id.
var replay_saves: Dictionary = {}
var _shared_archive_sync := false
var _shared_archive_attempts: Dictionary = {}
## Together rooms whose friend's photos this session already looked for.
var _shared_photo_checked: Dictionary = {}
## Together rooms whose parts this session already asked the server about.
var _shared_parts_checked: Dictionary = {}

func _init(main: Node = null) -> void:
	host = main

## Main's identity changed: this session's per-room checks start again.
func invalidate_identity() -> void:
	_shared_archive_attempts.clear()
	_shared_photo_checked.clear()
	_shared_parts_checked.clear()

## Main is leaving the tree.
func release_workers() -> void:
	cancel_collection_replay()
	# Never wait here: the cancelled check stops at its next step and the reaper joins it.
	if _collection_replay_worker != null:
		Reaper.adopt(_collection_replay_worker)
		_collection_replay_worker=null
		_collection_replay_worker_job={}
	# Opening a chapter from Solo replays changes scene mid-scan. Keep what the
	# scan has settled, then let the reaper join its verifier instead of this
	# frame (the service's own teardown would block on it).
	if solo_replays != null and solo_replays.has_method("release_workers"):
		cancel_solo_collection_scan()
		solo_replays.release_workers()

func begin_collection_replay(recording: Dictionary) -> void:
	host.running=false
	host.mode=MODE_COLLECTION_LOADING
	var card: VBoxContainer = host._card(700,true)
	card.add_child(host._label("Your replay",32,CREAM,true))
	var progress := ReplayLoadProgress.new()
	_collection_replay_loading_bar=ReplayLoadingBar.new()
	_collection_replay_loading_bar.reduced_motion=bool(host.saves.data.settings.get("reduced_motion",false))
	card.add_child(_collection_replay_loading_bar)
	_collection_replay_loading_bar.update_progress(progress.snapshot())
	card.add_child(host._back_button("Back to Your replays",show_collection,false))
	_collection_replay_job={"view":host.store_view_generation,"definition":host.current_level.duplicate(true),"attempt":host.attempt.duplicate(true),"recording":recording.duplicate(true),"version":host._room_simulation_version(),"progress":progress,"storage":host.saves}
	service_collection_replay()

func cancel_collection_replay() -> void:
	if not _collection_replay_job.is_empty(): _collection_replay_job.progress.cancel()
	if not _collection_replay_worker_job.is_empty(): _collection_replay_worker_job.progress.cancel()
	_collection_replay_job={}
	_collection_replay_loading_bar=null

func _collection_replay_current(job: Dictionary) -> bool:
	return not job.is_empty() and host.mode == MODE_COLLECTION_LOADING and job.view == host.store_view_generation and not host.room_play and job.storage == host.saves and host.current_level == job.definition and host.attempt == job.attempt

func service_collection_replay() -> void:
	if host.application_backgrounded: return
	if is_instance_valid(_collection_replay_loading_bar) and not _collection_replay_job.is_empty():
		_collection_replay_loading_bar.update_progress(_collection_replay_job.progress.snapshot())
	if _collection_replay_worker != null:
		if _collection_replay_worker.is_alive(): return
		var result: Dictionary = _collection_replay_worker.wait_to_finish()
		var finished := _collection_replay_worker_job
		_collection_replay_worker=null
		_collection_replay_worker_job={}
		if _collection_replay_current(finished) and not finished.progress.cancelled():
			_collection_replay_job={}
			if not result.get("ok",false):
				show_collection(PlayerCopy.MAIN_CD2F00E32FC5+str(result.get("error","")))
				return
			host._activate_preview(finished.recording,true,result)
			return
	if _collection_replay_job.is_empty(): return
	if not _collection_replay_current(_collection_replay_job):
		cancel_collection_replay()
		return
	_collection_replay_worker_job=_collection_replay_job
	# Joined here once it ends, or by the reaper after Main leaves the tree.
	Reaper.ensure()
	_collection_replay_worker=Thread.new()
	# Only private immutable values and a mutex-backed progress tracker cross
	# this boundary. The worker never sees the live save or any scene node.
	var job := {"definition":_collection_replay_job.definition,"attempt":_collection_replay_job.attempt,"recording":_collection_replay_job.recording,"version":_collection_replay_job.version}
	if _collection_replay_worker.start(Callable(EarlierIslandReplay,"prepare").bind(job,_collection_replay_job.progress)) != OK:
		_collection_replay_worker=null
		_collection_replay_worker_job={}
		show_collection("Could not load this replay. Please try again.")

func show_collection(message: String="") -> void:
	# Redrawing the open list (scan results, selection) keeps its scroll offset.
	var kept_scroll: int=host._bounded_card_scroll.scroll_vertical if host.mode == MODE_COLLECTION and is_instance_valid(host._bounded_card_scroll) else 0
	host.running=false
	host.room_play=false
	host.mode=MODE_COLLECTION
	_solo_collection_message=message
	if solo_replays == null: solo_replays=SoloReplayCollection.new()
	if not _solo_collection_started:
		_solo_collection_started=solo_replays.begin_scan()
	var scanning: bool=solo_replays.scan_pending()
	var entries := _solo_collection_entries()
	_solo_collection_shown=_solo_scan_signature(solo_replays.scan_progress()) if scanning else ""
	_solo_collection_dirty=false
	_solo_collection_redraw_at=Time.get_ticks_msec()+SOLO_COLLECTION_REDRAW_MS
	_select_solo_entry(entries)
	var shell := _begin_replay_split("solo")
	var wide: bool=shell.wide
	var left: VBoxContainer=shell.left
	_solo_row_views={}
	_solo_entries_by_key={}
	_solo_preview_box=null
	_solo_refresh_button=null
	_solo_drawn_layout=_solo_layout(entries,scanning,wide)
	left.add_child(host._label("Your recordings",24,CREAM,true))
	left.add_child(host._label("Completed turns",17,MUTED))
	_solo_scan_bar=null
	# "Looking for more" only once a playable row is listed; snapshot rows
	# still being checked keep the general loading text.
	_solo_scan_found=entries.any(func(entry: Dictionary) -> bool: return not entry.get("checking",false))
	if scanning:
		# Present from the first frame of the screen until the scan finishes.
		_solo_scan_bar=ReplayLoadingBar.new()
		_solo_scan_bar.reduced_motion=bool(host.saves.data.settings.get("reduced_motion",false))
		_add_replay_wait_bar(left,_solo_scan_bar,wide and (entries.is_empty() or _selected_solo_attempt.is_empty()))
		_solo_scan_bar.update_progress(_solo_scan_progress())
	for entry: Dictionary in entries:
		var selected: bool=wide and str(entry.get("key",""))==str(_selected_solo_attempt.get("key",""))
		_solo_entries_by_key[str(entry.get("key",""))]=entry
		left.add_child(_solo_collection_row(entry,selected,wide))
	# Failed sources simply drop out; the error shows only when nothing could be checked.
	if not scanning and not solo_replays.last_error.is_empty() and solo_replays.items().is_empty(): left.add_child(host._paragraph(solo_replays.last_error,620))
	if not _solo_collection_message.is_empty(): left.add_child(host._paragraph(_solo_collection_message,620))
	# "Nothing saved" only after a finished scan has found nothing.
	if entries.is_empty() and not scanning:
		ControlTheme.empty_state(left,"replays_solo",PlayerCopy.EMPTY_SOLO_TITLE,EMPTY_SOLO_COLLECTION)
	if not wide:
		var refresh: Button = host._button("Refresh saved replays",func(): _solo_collection_started=false; show_collection(),false)
		refresh.disabled=scanning
		left.add_child(refresh)
		_solo_refresh_button=refresh
	if wide and not entries.is_empty() and not _selected_solo_attempt.is_empty():
		_solo_preview_box=shell.right
		_fill_solo_preview(shell.right)
	else:
		shell.preview_panel.visible=false
	if kept_scroll>0: _restore_replay_scroll.call_deferred(shell.scroll,kept_scroll)

## What decides the screen's layout: every row's identity and text, the
## messages and the wait bar's placement. Rows turning playable change none
## of it.
func _solo_layout(entries: Array, scanning: bool, wide: bool) -> String:
	var parts := PackedStringArray([str(wide),_solo_collection_message,str(entries.is_empty() and not scanning),str(scanning and wide and _selected_solo_attempt.is_empty())])
	parts.append(solo_replays.last_error if not scanning and solo_replays.items(false).is_empty() else "")
	for entry: Dictionary in entries: parts.append("%s|%s|%d" % [entry.get("key",""),entry.get("title",""),int(entry.get("parts",1))])
	return "\n".join(parts)

## Applies a scan step to the open list. Rows already on screen become
## playable where they are; only a changed layout redraws the screen.
func _refresh_solo_collection() -> void:
	var scanning: bool=solo_replays.scan_pending()
	var entries := _solo_collection_entries()
	var wide: bool=is_instance_valid(host._bounded_card_scroll) and host.ui.size.x>=REPLAY_SPLIT_MIN_WIDTH
	var previous_key := str(_selected_solo_attempt.get("key",""))
	_select_solo_entry(entries)
	if str(_selected_solo_attempt.get("key",""))!=previous_key or _solo_layout(entries,scanning,wide)!=_solo_drawn_layout:
		# New or removed rows redraw at most every SOLO_COLLECTION_REDRAW_MS.
		if Time.get_ticks_msec()>=_solo_collection_redraw_at: show_collection(_solo_collection_message)
		return
	_solo_collection_shown=_solo_scan_signature(solo_replays.scan_progress()) if scanning else ""
	_solo_collection_dirty=false
	_solo_scan_found=entries.any(func(entry: Dictionary) -> bool: return not entry.get("checking",false))
	var preview_changed := false
	for entry: Dictionary in entries:
		var key := str(entry.get("key",""))
		var was: Dictionary=_solo_entries_by_key.get(key,{})
		_solo_entries_by_key[key]=entry
		if bool(was.get("checking",false))==bool(entry.get("checking",false)): continue
		if key==previous_key: preview_changed=true
		var view: Dictionary=_solo_row_views.get(key,{})
		if view.is_empty() or not is_instance_valid(view.play): continue
		var enabled: bool=wide or not entry.get("checking",false)
		view.title.disabled=not enabled
		view.hit.disabled=not enabled
		var play := _solo_watch_button("Play",entry,0,false,true)
		play.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var slot: int=view.play.get_index()
		var rowbox: Node=view.play.get_parent()
		rowbox.remove_child(view.play)
		view.play.queue_free()
		rowbox.add_child(play)
		rowbox.move_child(play,slot)
		view.play=play
	if preview_changed and is_instance_valid(_solo_preview_box):
		for child: Node in _solo_preview_box.get_children():
			_solo_preview_box.remove_child(child)
			child.queue_free()
		_solo_preview_box.remove_meta("thumbnail")
		_fill_solo_preview(_solo_preview_box)
	if is_instance_valid(_solo_scan_bar):
		if scanning: _solo_scan_bar.update_progress(_solo_scan_progress())
		else:
			# Its wide-screen wrapper row goes with it.
			var holder: Node=_solo_scan_bar.get_parent()
			var gone: Node=holder if holder is HBoxContainer else _solo_scan_bar
			gone.get_parent().remove_child(gone)
			gone.queue_free()
			_solo_scan_bar=null
	if is_instance_valid(_solo_refresh_button): _solo_refresh_button.disabled=scanning

## Writes the display snapshot as the list currently stands: checked rows of
## settled chapters, and the snapshot's own rows for chapters still pending.
func _store_solo_snapshot() -> void:
	if solo_replays == null: return
	if solo_replay_index == null: solo_replay_index=SoloReplayIndex.new()
	solo_replay_index.store_display(solo_replays.settled_items(false),solo_replays.pending_chapters())

func _add_replay_wait_bar(parent: VBoxContainer, bar: Control, without_preview: bool) -> void:
	# On a wide screen with no preview card the list spans the whole width;
	# keep the bar to the width the list has beside that card.
	if not without_preview:
		parent.add_child(bar)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bar.size_flags_stretch_ratio=1.15
	row.add_child(bar)
	var rest := Control.new()
	rest.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rest.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(rest)
	parent.add_child(row)

func _solo_scan_signature(progress: Dictionary) -> String:
	return "%d:%d" % [int(progress.get("settled",0)),int(progress.get("pending",0))]

func _solo_scan_progress() -> Dictionary:
	var progress: Dictionary=solo_replays.scan_progress()
	if _solo_scan_found: progress["label"]=SOLO_COLLECTION_SCANNING
	return progress

func _restore_replay_scroll(scroll: ScrollContainer, value: int) -> void:
	if is_instance_valid(scroll) and scroll.is_inside_tree(): scroll.scroll_vertical=value

func _solo_collection_entries() -> Array:
	# Flat, ordered list of saved solo recordings: the legacy per-level copies
	# first (in level order), then every discovered chapter attempt grouped by
	# its stages. Each entry carries a stable key so the preview selection can
	# survive a redraw.
	var entries: Array=[]
	for i in range(host.levels.size()):
		var saved: Dictionary=host.saves.replay(host.levels[i].id)
		if saved.get("b",{}).is_empty(): continue
		entries.append({"family":"legacy","key":"legacy:%d" % i,"level_index":i,"attempt":saved.duplicate(true),"title":str(host.levels[i].title),"chapter_key":"legacy-"+str(host.levels[i].id),"parts":1})
	# During a scan only chapters with every source checked are listed, so an
	# attempt keeps the number it is first shown with. Chapters still pending
	# show the last finished scan's display rows, which are never playable.
	var scanning: bool=solo_replays.scan_pending()
	# Scan rows are shared read-only; nothing here or in playback mutates them.
	var scanned: Array=solo_replays.settled_items(false) if scanning else solo_replays.items(false)
	if scanning:
		if solo_replay_index == null: solo_replay_index=SoloReplayIndex.new()
		var pending: Dictionary=solo_replays.pending_chapters()
		for row: Dictionary in solo_replay_index.rows():
			if pending.has(str(row.chapter_key)): scanned.append(row)
	var groups: Dictionary={}
	for row: Dictionary in scanned:
		if solo_replay_visibility.is_hidden(row): continue
		var group_key := str(row.get("chapter_key",""))+":"+str(row.get("attempt_id",row.get("source_id","")))
		if not groups.has(group_key): groups[group_key]=[]
		groups[group_key].append(row)
	var ordered_groups: Array=[]
	for group_key: String in groups: ordered_groups.append({"key":group_key,"rows":groups[group_key]})
	ordered_groups.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.key)<str(b.key))
	var attempt_numbers: Dictionary={}
	for item: Dictionary in ordered_groups:
		var rows: Array=item.rows
		rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.stage_index)<int(b.stage_index))
		var chapter_key := str(rows[0].chapter_key)
		attempt_numbers[chapter_key]=int(attempt_numbers.get(chapter_key,0))+1
		var checking: bool=rows.any(func(row: Dictionary) -> bool: return row.get("checking",false))
		entries.append({"family":"chapter","key":"chapter:"+str(item.key),"rows":rows,"title":"%s · Attempt %d" % [str(rows[0].chapter_title),int(attempt_numbers[chapter_key])],"chapter_key":chapter_key,"parts":rows.size(),"checking":checking})
	return entries

func _select_solo_entry(entries: Array) -> void:
	# Keep the previewed recording selected across redraws; default to the first
	# entry and clamp the chosen part if the attempt changed under us.
	if entries.is_empty():
		_selected_solo_attempt={}
		return
	var current := str(_selected_solo_attempt.get("key",""))
	for entry: Dictionary in entries:
		if str(entry.get("key",""))==current:
			var part: int=clampi(int(_selected_solo_attempt.get("part",0)),0,maxi(0,int(entry.get("parts",1))-1))
			_selected_solo_attempt=entry.duplicate()
			_selected_solo_attempt["part"]=part
			return
	_selected_solo_attempt=entries[0].duplicate()
	_selected_solo_attempt["part"]=0

func _solo_part_subtitle(parts: int) -> String:
	return "%d %s · Saved offline" % [parts,"part" if parts==1 else "parts"]

func _begin_replay_split(selected: String, back_text: String="Back", back_callback: Callable=Callable()) -> Dictionary:
	# Shared full-screen Replays shell for Solo and Together. A fixed header
	# (Back + title + Solo/Together tabs) sits above one bounded scroller. On
	# wide screens it holds only the row list, beside a fixed preview card whose
	# picture shrinks to keep every action visible; on narrow screens the list
	# and the stacked preview scroll together.
	host._clear_overlay()
	var shade := ColorRect.new()
	shade.color=Color(0.025,0.10,0.10,0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.overlay.add_child(shade)
	host.overlay_shade=shade
	host._update_shade_bounds()
	var wide: bool=host.ui.size.x>=REPLAY_SPLIT_MIN_WIDTH
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,22)
	host.overlay.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",12)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	var back: Button = host._back_button(back_text,back_callback if back_callback.is_valid() else (func(): home_requested.emit()),false)
	back.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	header.add_child(back)
	header.add_child(host._label("Replays",34,CREAM,true))
	outer.add_child(header)
	_add_replay_library_tabs(outer,selected)
	_replay_library_header=outer
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var body := BoxContainer.new()
	body.vertical=not wide
	body.add_theme_constant_override("separation",18)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var list_column := VBoxContainer.new()
	list_column.add_theme_constant_override("separation",10)
	list_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if wide:
		# Side by side, only the list scrolls; the preview card stays put.
		body.size_flags_vertical=Control.SIZE_EXPAND_FILL
		outer.add_child(body)
		scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio=1.15
		body.add_child(scroll)
		scroll.add_child(list_column)
	else:
		outer.add_child(scroll)
		scroll.add_child(body)
		body.add_child(list_column)
	var preview_panel := PanelContainer.new()
	preview_panel.add_theme_stylebox_override("panel",host._style(Color("12332f"),20,Color("3f6b61")))
	preview_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	body.add_child(preview_panel)
	var preview_margin := MarginContainer.new()
	for side in ["left","top","right","bottom"]:
		preview_margin.add_theme_constant_override("margin_"+side,16)
	preview_panel.add_child(preview_margin)
	var preview := VBoxContainer.new()
	preview.add_theme_constant_override("separation",10)
	preview_margin.add_child(preview)
	var available: Control = body if wide else scroll
	preview.set_meta("available_scroll",available)
	preview.set_meta("preview_panel",preview_panel)
	available.resized.connect(_fit_replay_preview.bind(preview).call_deferred)
	ControlTheme.touch_scroll(scroll)
	host._bounded_card_scroll=scroll
	host._bounded_card_stack=null
	return {"outer":outer,"scroll":scroll,"body":body,"left":list_column,"right":preview,"preview_panel":preview_panel,"wide":wide}

func _fit_replay_preview(preview: VBoxContainer) -> void:
	if not is_instance_valid(preview) or not preview.has_meta("thumbnail"): return
	var available: Control=preview.get_meta("available_scroll")
	var panel: PanelContainer=preview.get_meta("preview_panel")
	var thumbnail: Control=preview.get_meta("thumbnail")
	if not is_instance_valid(available) or not is_instance_valid(panel) or not is_instance_valid(thumbnail): return
	# Spend remaining safe height on the picture after reserving every label,
	# part selector and action. A short viewport shrinks the picture first,
	# never touch targets, and stacked layouts still scroll.
	var controls_height: float=panel.get_combined_minimum_size().y-thumbnail.custom_minimum_size.y
	thumbnail.custom_minimum_size.y=clampf(available.size.y-controls_height-2.0,96.0,220.0)

func _part_chip(label: String, selected: bool, callback: Callable) -> Button:
	var chip: Button = host._button(label,callback,false)
	chip.custom_minimum_size=Vector2(0,48)
	chip.disabled=selected
	if selected: _selected_look(chip)
	return chip

func _selected_look(button: Button) -> void:
	## The current tab or part can't be pressed again, but it should read as
	## selected rather than unavailable: the hub's lighter teal pill. Cream stays
	## reserved for the screen's primary action.
	ControlTheme.selected_tab(button)

func _replay_row_title(title: Button) -> void:
	## A row title reads as a heading that starts flush with its caption below.
	title.add_theme_font_override("font",host.title_font)
	title.add_theme_font_size_override("font_size",24)
	if _replay_title_style == null:
		_replay_title_style=host._style(Color.TRANSPARENT,10)
		_replay_title_style.content_margin_left=0
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		title.add_theme_stylebox_override(state,_replay_title_style)
	title.add_theme_color_override("font_color",CREAM)
	title.add_theme_color_override("font_focus_color",CREAM)
	for state: String in ["hover","pressed","hover_pressed"]:
		title.add_theme_color_override("font_"+state+"_color",MINT)

func _replay_row_card(thumb_key: String, title_text: String, caption_text: String, selected: bool, open: Callable, enabled: bool=true) -> Dictionary:
	## Shared Solo/Together replay row. The whole card is one tap target: an
	## invisible full-card button sits under the art, title and caption, which
	## let presses through, so the caption, art and padding select the row like
	## the title does. Play and delete stay their own targets on top.
	var panel := PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_PASS
	# Two shared looks; the card's inset lives in the margin below so the tap
	# target reaches every edge.
	if not _replay_card_styles.has(selected):
		var look: StyleBoxFlat = host._style(Color("27564e") if selected else Color("1b443e"),16,Color("6fb39d") if selected else Color.TRANSPARENT)
		for edge: String in ["left","top","right","bottom"]: look.set("content_margin_"+edge,0)
		_replay_card_styles[selected]=look
	panel.add_theme_stylebox_override("panel",_replay_card_styles[selected])
	var hit := Button.new()
	hit.name="RowTapTarget"
	hit.flat=true
	hit.focus_mode=Control.FOCUS_NONE
	hit.mouse_filter=Control.MOUSE_FILTER_PASS
	hit.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if _replay_hit_style == null: _replay_hit_style=StyleBoxEmpty.new()
	for state: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]: hit.add_theme_stylebox_override(state,_replay_hit_style)
	hit.disabled=not enabled
	hit.pressed.connect(open)
	panel.add_child(hit)
	var pad := MarginContainer.new()
	for side in ["left","right"]: pad.add_theme_constant_override("margin_"+side,28)
	for side in ["top","bottom"]: pad.add_theme_constant_override("margin_"+side,20)
	pad.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(pad)
	var rowbox := HBoxContainer.new()
	rowbox.add_theme_constant_override("separation",12)
	rowbox.mouse_filter=Control.MOUSE_FILTER_IGNORE
	pad.add_child(rowbox)
	rowbox.add_child(host._replay_preview_thumb(thumb_key,Vector2(128,72),10))
	var textcol := VBoxContainer.new()
	textcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	textcol.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	textcol.add_theme_constant_override("separation",0)
	textcol.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var title: Button = host._list_button(title_text,open,false)
	title.set_meta("replay_row",true)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.alignment=HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text=true
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.y=48
	_replay_row_title(title)
	title.disabled=not enabled
	textcol.add_child(title)
	var caption: Label = host._paragraph(caption_text,260)
	caption.add_theme_font_size_override("font_size",17)
	if selected: caption.add_theme_color_override("font_color",MINT)
	textcol.add_child(caption)
	rowbox.add_child(textcol)
	return {"panel":panel,"rowbox":rowbox,"title":title,"hit":hit}

func _solo_collection_row(entry: Dictionary, selected: bool, wide: bool) -> Control:
	# One saved-recording row: real chapter art, a human title, a short "N parts
	# · Saved offline" caption and a quick Play. On wide screens the title selects
	# the row for the preview card; on narrow screens it opens the part preview.
	var key := str(entry.get("key",""))
	var open := func():
		# The row may have been checked since it was drawn.
		_selected_solo_attempt=_solo_entries_by_key.get(key,entry).duplicate()
		_selected_solo_attempt["part"]=0
		if wide: show_collection()
		else: _show_solo_replay_attempt()
	# A row still being checked opens nothing that could play it.
	var card := _replay_row_card(str(entry.get("chapter_key","")),str(entry.get("title","Replay")),_solo_part_subtitle(int(entry.get("parts",1))),selected,open,wide or not entry.get("checking",false))
	var panel: PanelContainer=card.panel
	var rowbox: HBoxContainer=card.rowbox
	var play := _solo_watch_button("Play",entry,0,false,true)
	play.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	rowbox.add_child(play)
	_solo_row_views[key]={"title":card.title,"hit":card.hit,"play":play}
	if not wide and entry.get("family")=="legacy":
		rowbox.add_child(_collection_delete_button(func(): _confirm_delete_collection_replay(int(entry.get("level_index",-1)),entry.get("attempt",{})),str(entry.get("title",""))))
	return panel

func _fill_solo_preview(preview: VBoxContainer) -> void:
	var entry := _selected_solo_attempt
	var parts: int=int(entry.get("parts",1))
	var part: int=clampi(int(entry.get("part",0)),0,maxi(0,parts-1))
	var thumbnail: Control = host._replay_preview_thumb(str(entry.get("chapter_key","")),Vector2(0,220),16)
	preview.add_child(thumbnail)
	preview.set_meta("thumbnail",thumbnail)
	preview.add_child(host._label(str(entry.get("title","Replay")),28,CREAM,true))
	if entry.get("family")=="chapter" and parts>1:
		preview.add_child(host._label("Choose a part",17,MUTED))
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation",8)
		for index in range(parts):
			chips.add_child(_part_chip("Part %d" % (index+1),index==part,func(selected_index=index): _selected_solo_attempt["part"]=selected_index; show_collection()))
		preview.add_child(chips)
	else:
		preview.add_child(host._label("Part %d / %d" % [part+1,parts],17,MUTED))
	preview.add_child(_solo_watch_button("Watch replay",entry,part,true))
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation",10)
	if parts>1:
		var watch_all := _solo_watch_button("Watch all parts",entry,parts-1,false)
		watch_all.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		secondary.add_child(watch_all)
	var options: Button = host._button("Options",_open_solo_options,false)
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	secondary.add_child(options)
	if entry.get("family")=="legacy":
		secondary.add_child(_collection_delete_button(func(): _confirm_delete_collection_replay(int(entry.get("level_index",-1)),entry.get("attempt",{})),str(entry.get("title",""))))
	else:
		var rows: Array=entry.get("rows",[])
		if part<rows.size():
			var remove := _collection_delete_button(func(): _confirm_remove_solo_part(rows[part]),_part_title(rows[part]))
			remove.disabled=remove.disabled or entry.get("checking",false)
			secondary.add_child(remove)
	preview.add_child(secondary)
	_fit_replay_preview.call_deferred(preview)

func _play_solo_entry(entry: Dictionary, part: int) -> void:
	if entry.get("checking",false): return
	if entry.get("family")=="legacy":
		var index := int(entry.get("level_index",-1))
		if index<0 or index>=host.levels.size(): return
		var selected: Dictionary=entry.get("attempt",{}).duplicate(true)
		if selected.get("b",{}).is_empty(): return
		host.preview_saved_attempt(index,selected)
	else:
		var rows: Array=entry.get("rows",[])
		if rows.is_empty(): return
		var chosen := clampi(part,0,rows.size()-1)
		_selected_solo_attempt=entry.duplicate(true)
		_selected_solo_attempt["part"]=chosen
		await _launch_modern_solo_replay(rows[chosen])

func _solo_watch_button(text: String, entry: Dictionary, part: int, primary: bool, row: bool=false) -> Button:
	## Chapter replays open another scene, so their wait shows before it loads.
	## Earlier-island replays open their own loading card at once.
	var launch := func(): await _play_solo_entry(entry,part)
	if entry.get("checking",false):
		var waiting: Button = host._list_button(text,launch,primary) if row else host._button(text,launch,primary)
		waiting.disabled=true
		return waiting
	if entry.get("family")=="chapter": return _replay_launch_button(text,launch,primary,row)
	return host._list_button(text,launch,primary) if row else host._button(text,launch,primary)

func _replay_launch_button(text: String, launch: Callable, primary: bool, row: bool=false) -> Button:
	var button: Button = host._list_button(text,launch,primary) if row else host._button(text,launch,primary)
	button.pressed.disconnect(launch)
	button.pressed.connect(_begin_replay_launch.bind(button,launch))
	button.set_meta("replay_launch",true)
	return button

func _begin_replay_launch(control: Button, launch: Callable) -> void:
	# One launch per screen: every Watch/Play control is disabled and a wait bar
	# sits under the tapped one until the replay opens or is refused.
	var view: int = host.store_view_generation
	if _replay_launch_view == view or not is_instance_valid(control) or control.disabled: return
	_replay_launch_view=view
	var paused: Array[Button]=[]
	for node: Node in host.overlay.find_children("*","Button",true,false):
		var button := node as Button
		if button.has_meta("replay_launch") and not button.disabled:
			button.disabled=true
			paused.append(button)
	var wait := ReplayLoadingBar.new()
	wait.name="ReplayLaunchWait"
	wait.reduced_motion=bool(host.saves.data.settings.get("reduced_motion",false))
	var anchor: Node=control
	while anchor.get_parent() != null and not anchor.get_parent() is VBoxContainer: anchor=anchor.get_parent()
	if anchor.get_parent() != null:
		anchor.get_parent().add_child(wait)
		anchor.get_parent().move_child(wait,anchor.get_index()+1)
	wait.update_progress({"phase":"preparing"})
	var preview := wait.get_parent() as VBoxContainer
	if preview != null and preview.has_meta("thumbnail"): _fit_replay_preview.call_deferred(preview)
	elif is_instance_valid(host._bounded_card_scroll) and host._bounded_card_scroll.is_ancestor_of(wait): host._bounded_card_scroll.ensure_control_visible.call_deferred(wait)
	# Two frame boundaries put the disabled control and the bar on screen before
	# a scene load or store check can hold this thread.
	for frame in range(2):
		if not host.is_inside_tree(): return
		await host.get_tree().process_frame
	# The chapter opens at once even while the Solo scan's verifier is checking
	# a source: chapter rules are safe on both threads. Leaving this screen
	# hands that verifier to the reaper (see release_workers), so nothing waits on it.
	if view == host.store_view_generation: await launch.call()
	# A scene change removes this node and navigation redraws the screen; only a
	# refused launch on the same screen restores its controls.
	if not host.is_inside_tree() or view != host.store_view_generation: return
	_replay_launch_view=-1
	for button: Button in paused:
		if is_instance_valid(button): button.disabled=false
	if is_instance_valid(wait): wait.queue_free()

func _open_solo_options() -> void:
	var modal := InGameModal.open(host.ui,"SoloReplayOptions","Options")
	var refresh: Button = modal.add_actions("Refresh saved replays",func():
		modal.close()
		_solo_collection_started=false
		show_collection())
	refresh.disabled=solo_replays!=null and solo_replays.scan_pending()

func cancel_solo_collection_scan() -> void:
	if solo_replays != null and solo_replays.has_method("cancel_scan") and solo_replays.scan_pending():
		_store_solo_snapshot()
		solo_replays.cancel_scan()
		_solo_collection_started=false

func service_solo_collection() -> void:
	if host.mode != MODE_COLLECTION: return
	# A Watch/Play wait owns the screen until the replay opens or is refused.
	if solo_replays == null or _replay_launch_view == host.store_view_generation: return
	if solo_replays.scan_pending():
		var finished: bool=not solo_replays.advance_scan()
		var progress: Dictionary=_solo_scan_progress()
		if is_instance_valid(_solo_scan_bar): _solo_scan_bar.update_progress(progress)
		if finished:
			_solo_collection_started=true
			_solo_collection_dirty=true
			_solo_collection_redraw_at=Time.get_ticks_msec()
			_store_solo_snapshot()
		elif _solo_scan_signature(progress) != _solo_collection_shown:
			_solo_collection_dirty=true
			# Each settled chapter is kept at once, so leaving early or closing
			# the app still opens the full list next time.
			_store_solo_snapshot()
	var now := Time.get_ticks_msec()
	if not _solo_collection_dirty: return
	# Do not change rows under a press or drag on the list; a stuck pointer
	# state can hold them back only briefly. A press on a button always waits.
	if TouchInput.press_held(host.overlay): return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and now < _solo_collection_redraw_at+2000: return
	_refresh_solo_collection()

func _show_solo_replay_attempt() -> void:
	if host.mode != MODE_COLLECTION or _selected_solo_attempt.is_empty() or _selected_solo_attempt.get("checking",false): return
	host.mode=MODE_SOLO_REPLAY_ATTEMPT
	var card: VBoxContainer = host._card(740,true)
	var legacy: bool = _selected_solo_attempt.get("family")=="legacy"
	var rows: Array=_selected_solo_attempt.get("rows",[])
	var title := str(host.levels[int(_selected_solo_attempt.get("level_index",0))].title) if legacy else str(rows[0].get("chapter_title","Your replay"))
	card.add_child(host._label(title,34,CREAM,true))
	var list: VBoxContainer = host._scroll_list(card,false)
	if legacy:
		var legacy_index := int(_selected_solo_attempt.level_index)
		var selected: Dictionary=_selected_solo_attempt.attempt.duplicate(true)
		list.add_child(host._paragraph("Solo · Accepted part",600))
		list.add_child(host._button("Watch replay",func(): host.preview_saved_attempt(legacy_index,selected),true))
		list.add_child(host._button("Remove from this device",func(): _confirm_delete_collection_replay(legacy_index,selected),false))
	else:
		for row: Dictionary in rows:
			var frozen := row.duplicate(true)
			var part_index := int(row.get("stage_index",0))
			var action_row := HBoxContainer.new()
			var watch := _replay_launch_button("Part %d · %s" % [part_index+1,_part_title(row)],func(): await _launch_modern_solo_replay(frozen),true,true)
			watch.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			action_row.add_child(watch)
			action_row.add_child(_collection_delete_button(func(): _confirm_remove_solo_part(frozen),_part_title(row)))
			list.add_child(action_row)
		if rows.is_empty(): list.add_child(host._paragraph("This replay can't be found anymore.",600))
	card.add_child(host._back_button("Back to Solo replays",show_collection,false))

static func _solo_replay_context_from_rows(chapter_key: String, rows: Array, selected: Dictionary) -> Dictionary:
	# Build the replay-only playback context from the accepted prefix of a
	# discovered attempt. Pure (no scene or disk side effects) so the exact
	# bytes the preview scene later consumes can be verified end to end.
	# The solo Lighthouse is outside the registry; its own scene checks the pairs.
	if ChapterRegistry.descriptor(chapter_key).is_empty() and chapter_key != SoloReplayCollection.LIGHTHOUSE_KEY: return {}
	var ordered := rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.stage_index)<int(b.stage_index))
	var index := int(selected.get("stage_index",-1))
	if index<0 or index>=ordered.size() or ordered[index].get("id")!=selected.get("id"): return {}
	var accepted_pairs: Array=[]
	for row_index in range(index+1): accepted_pairs.append(ordered[row_index].pair.duplicate(true))
	return {"schema_version":1,"chapter_key":chapter_key,"selected_stage_index":index,"accepted_pairs":accepted_pairs,"visibility_key":str(selected.get("visibility_key",""))}

func _part_title(row: Dictionary) -> String:
	## Older saves name a part by its stage id; show it as words instead.
	var title := str(row.get("title","")).strip_edges()
	if title.is_empty(): return "Saved turn"
	if title == title.to_lower() and not title.contains(" "): return title.replace("-"," ").replace("_"," ").capitalize()
	return title

func _launch_modern_solo_replay(selected: Dictionary) -> void:
	if host.mode not in [MODE_COLLECTION,MODE_SOLO_REPLAY_ATTEMPT] or _selected_solo_attempt.get("family")!="chapter" or _selected_solo_attempt.get("checking",false) or not selected.has("pair"): return
	var chapter_key := str(selected.get("chapter_key",""))
	var context := _solo_replay_context_from_rows(chapter_key,_selected_solo_attempt.get("rows",[]),selected)
	if context.is_empty(): return
	var lighthouse := chapter_key == SoloReplayCollection.LIGHTHOUSE_KEY
	var scene: String = host.LIGHTHOUSE_SCENE if lighthouse else ChapterRegistry.solo_scene(chapter_key)
	if scene.is_empty(): return
	if lighthouse or ChapterRegistry.descriptor(chapter_key).premium:
		await host._open_premium_chapter(scene,context)
	else:
		host._open_chapter_preview(scene,context)

func _confirm_remove_solo_part(row: Dictionary) -> void:
	if host.mode!=MODE_SOLO_REPLAY_ATTEMPT or solo_replay_visibility.is_hidden(row): return
	host.mode=MODE_CONFIRM_DELETE
	var card: VBoxContainer = host._card(700)
	card.add_child(host._label("Remove this replay?",32,CREAM,true))
	card.add_child(host._paragraph(str(row.get("chapter_title","Replay"))+" · "+_part_title(row),590))
	card.add_child(host._paragraph("This will hide the replay on this device only.",590))
	card.add_child(host._button("Remove",func():
		if host.mode!=MODE_CONFIRM_DELETE or host.application_backgrounded: return
		var okay: bool=solo_replay_visibility.hide(row)
		show_collection("Replay removed" if okay else solo_replay_visibility.last_error),false))
	card.add_child(host._back_button("Cancel",func(): _show_solo_replay_attempt(),false))

func _collection_delete_button(callback: Callable, title: String) -> Button:
	var remove: Button = host._list_button("",callback,false)
	remove.icon=preload("res://assets/ui/social/trash.svg")
	remove.expand_icon=true
	remove.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	remove.custom_minimum_size=Vector2(48,48)
	remove.add_theme_constant_override("icon_max_width",22)
	host._fit_icon_button(remove)
	ControlTheme.danger(remove,remove.icon)
	remove.tooltip_text="Delete replay: "+title
	remove.accessibility_name=remove.tooltip_text
	remove.disabled=host.saves.read_only or host.application_backgrounded or host.submission_in_flight
	return remove

func _confirm_delete_collection_replay(index: int, expected: Dictionary) -> void:
	if host.mode not in [MODE_COLLECTION,MODE_SOLO_REPLAY_ATTEMPT] or host.application_backgrounded or host.submission_in_flight or index < 0 or index >= host.levels.size(): return
	var level_id := str(host.levels[index].id)
	if expected.get("b",{}).is_empty() or not Canonical.same(host.saves.replay(level_id),expected): return
	var storage: RefCounted = host.saves
	var selected := expected.duplicate(true)
	host.mode=MODE_CONFIRM_DELETE
	var card: VBoxContainer = host._card(700)
	card.add_child(host._label("Delete replay?",32,CREAM,true))
	card.add_child(host._paragraph(str(host.levels[index].title),590))
	card.add_child(host._paragraph("Remove this replay from Your replays on this phone? Progress, unfinished attempts and keepsakes will stay.",590))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and host.mode == MODE_CONFIRM_DELETE and host.saves == storage
	card.add_child(host._button("Delete",func():
		if not current.call() or host.application_backgrounded or host.submission_in_flight: return
		var removed: bool = storage.remove_replay(level_id,selected)
		show_collection("Replay deleted" if removed else (storage.last_error if not storage.last_error.is_empty() else "Could not remove this replay. Please try again.")),false))
	host._retry_cancel = func():
		if current.call(): show_collection()
	card.add_child(host._button("Cancel",host._retry_cancel))

func show_shared_replays(wanted: String = "") -> void:
	_shared_wanted_room = wanted
	# The Together tab opens straight into the parts/preview screen for the most
	# recent room (or the one last viewed this session). "Choose another room"
	# switches rooms from inside that view, so there is no separate room-list
	# entry point. The empty, loading, offline and unsupported states still show
	# here, and Back leaves to Home like Solo's Back.
	host.running=false
	host.room_play=false
	host.mode=MODE_SHARED_REPLAYS
	if not host._relay_identity().ready:
		var now := Time.get_ticks_msec()
		if host.identity_loading and (_shared_identity_wait_until < 0 or now < _shared_identity_wait_until):
			# The saved account is still being read after a cold start.
			if _shared_identity_wait_until < 0: _shared_identity_wait_until=now+SHARED_IDENTITY_WAIT_MS
			var shell := _begin_replay_split("together","Back",func(): home_requested.emit())
			var left: VBoxContainer=shell.left
			left.add_child(host._label("Together",24,MINT,true))
			left.add_child(host._paragraph(PlayerCopy.MAIN_529CFAE68DF1,630))
			_shared_replay_loading_bar=ReplayLoadingBar.new()
			_shared_replay_loading_bar.reduced_motion=bool(host.saves.data.settings.get("reduced_motion",false))
			_add_replay_wait_bar(left,_shared_replay_loading_bar,shell.wide)
			_shared_replay_loading_bar.update_progress({})
			var account: Button = host._button("Account & recovery",func(): account_requested.emit(),false)
			account.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			left.add_child(account)
			shell.preview_panel.visible=false
			return
		_shared_identity_wait_until=-1
		var held: VBoxContainer = host._card(700)
		held.add_child(host._label("Your shared replays",34,CREAM,true))
		held.add_child(host._paragraph(PlayerCopy.MAIN_1E12325B0B49,600))
		held.add_child(host._button("Account & recovery",func(): account_requested.emit()))
		held.add_child(host._back_button("Back",func(): home_requested.emit(),false))
		return
	_shared_identity_wait_until=-1
	if host.shared_replays==null: host.shared_replays=SharedReplays.new(host.api,host._relay_identity)
	host._wire_shared_history()
	host.shared_replays.configure_context_factory(host._room_context_factory())
	# Queue the local check before the only draw, so the first frame already
	# carries its loading bar rather than an empty state.
	host.shared_replays.begin_local_load(host.saves.data.get("room",{}))
	_open_default_shared_room()

func _listed_shared_rooms() -> Array:
	# Rooms whose local verification still retains at least one saved replay and
	# that the player is allowed to open here.
	if host.shared_replays == null: return []
	var rooms: Array = host.shared_replays.rooms().filter(func(room: Dictionary): return not host.shared_replays.memories(SharedReplays._room_key(room),true).is_empty()).filter(_replay_room_allowed)
	# Newest first; rooms this phone has no time for keep their order after them.
	var order: Array = []
	for index in range(rooms.size()): order.append([host.shared_replays.updated_at(rooms[index]),index])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	return order.map(func(item: Array) -> Dictionary: return rooms[item[1]])

func _default_shared_replay_key() -> String:
	# Prefer the room viewed earlier this session; otherwise the first listed
	# room. Returns "" when nothing can be shown yet (still loading or empty).
	var rooms := _listed_shared_rooms()
	if rooms.is_empty(): return ""
	for room: Dictionary in rooms:
		if SharedReplays._room_key(room) == shared_replay_room: return shared_replay_room
	return SharedReplays._room_key(rooms[0])

func _open_default_shared_room() -> void:
	if not _shared_wanted_room.is_empty():
		_open_wanted_shared_room()
		return
	var key := _default_shared_replay_key()
	if key.is_empty():
		_draw_shared_replay_empty()
		return
	show_shared_replay_room(key)

func service_shared_replays() -> void:
	if _shared_identity_wait_until >= 0:
		if host.mode != MODE_SHARED_REPLAYS: _shared_identity_wait_until=-1
		elif not host.identity_loading or Time.get_ticks_msec() >= _shared_identity_wait_until:
			show_shared_replays(_shared_wanted_room)
			return
	if host.shared_replays == null or host.mode not in [MODE_SHARED_REPLAYS, MODE_SHARED_MEMORIES] or not host.shared_replays.local_loading(): return
	# A step can redraw the page; it waits for a tap in progress to finish.
	if TouchInput.press_held(host.overlay): return
	if not host.shared_replays.advance_local_load():
		if is_instance_valid(_shared_replay_loading_bar): _shared_replay_loading_bar.update_progress(host.shared_replays.local_progress())
		return
	# Every open checks each saved room again; one that lists what is already
	# shown no longer rebuilds the whole page. The last one always redraws.
	var changed: bool = host.shared_replays.local_load_changed() or not host.shared_replays.local_loading()
	if not changed and is_instance_valid(_shared_replay_loading_bar): _shared_replay_loading_bar.update_progress(host.shared_replays.local_progress())
	if host.mode == MODE_SHARED_REPLAYS:
		if changed: _open_default_shared_room()
	else:
		if changed: _draw_shared_replay_memories(host.shared_replays.listed(shared_replay_room))
		_check_shared_room_parts(shared_replay_room)
		_fetch_missing_shared_photos(shared_replay_room)

func _add_shared_replay_loading_bar(card: VBoxContainer, without_preview: bool = false) -> void:
	_shared_replay_loading_bar=null
	if not host.shared_replays.local_loading(): return
	_shared_replay_loading_bar=ReplayLoadingBar.new()
	_shared_replay_loading_bar.reduced_motion=bool(host.saves.data.settings.get("reduced_motion",false))
	_add_replay_wait_bar(card,_shared_replay_loading_bar,without_preview)
	_shared_replay_loading_bar.update_progress(host.shared_replays.local_progress())

## Earlier-island rooms and chapter rooms. Replays this phone kept from the
## withdrawn Story feature show like any chapter's; requests for that room are
## refused by the server and held by the room context.
func _replay_room_allowed(room: Dictionary) -> bool:
	return room.get("family") == "legacy" or (room.get("family") == "chapter" and host._relay_identity().ready)

func _replay_key_allowed(key: String) -> bool:
	if host.shared_replays == null: return false
	for room: Dictionary in host.shared_replays.rooms():
		if SharedReplays._room_key(room) == key: return _replay_room_allowed(room)
	return false

func _current_shared_room() -> Dictionary:
	if host.shared_replays == null: return {}
	for room: Dictionary in host.shared_replays.rooms():
		if SharedReplays._room_key(room) == shared_replay_room: return room
	return {}

## One line that tells shared rooms apart: the chapter (when asked), the friend
## and when the room last changed, in local time.
func _shared_room_line(room: Dictionary, with_title: bool) -> String:
	var parts: Array[String] = []
	if with_title: parts.append(str(room.get("title","Shared room")))
	var partner := _room_partner_name(room)
	if not partner.is_empty(): parts.append("With "+partner)
	var when := WhenLabel.text(host.shared_replays.updated_at(room)) if host.shared_replays != null and not room.is_empty() else ""
	if not when.is_empty(): parts.append(when)
	return " · ".join(parts)

## The friend in a shared room, by the nickname this player gave them, or
## "a friend". Never a raw id.
func _room_partner_name(room: Dictionary) -> String:
	if room.is_empty(): return ""
	var shown := _room_partner_nickname(room)
	return shown if not shown.is_empty() else FriendNicknames.FALLBACK

## The nickname of the other player in a shared room, or "".
func _room_partner_nickname(room: Dictionary) -> String:
	var owner := str(host._relay_identity().player_id)
	var friend := str(room.get("guest_id","")) if str(room.get("host_id",""))==owner else str(room.get("host_id",""))
	if friend.is_empty() or friend == "<null>": return ""
	if replay_partner_label.is_valid():
		var resolved := str(replay_partner_label.call(friend))
		if not resolved.is_empty(): return resolved
	if host.friend_nicknames == null: return ""
	return str(host.friend_nicknames.nickname(str(host.api.base_url),str(host.api.player_id),friend))

func _draw_shared_replay_empty(message: String="") -> void:
	# Shown only when there is no room to open yet: still loading, nothing saved,
	# or offline. Keeps the Together shell, loading bar, offline/error text and a
	# refresh, with Back leaving to Home like Solo's Back.
	var shell := _begin_replay_split("together","Back",func(): home_requested.emit())
	host.mode=MODE_SHARED_REPLAYS
	var left: VBoxContainer=shell.left
	left.add_child(host._label("Together",24,MINT,true))
	left.add_child(host._paragraph(PlayerCopy.MAIN_529CFAE68DF1,630))
	_add_shared_replay_loading_bar(left,shell.wide)
	if not message.is_empty(): left.add_child(host._paragraph(message,630))
	elif not host.shared_replays.last_error.is_empty(): left.add_child(host._paragraph(host.shared_replays.last_error,630))
	var refresh: Button = host._button("Refresh shared rooms",_refresh_shared_replay_rooms,false)
	refresh.disabled=host.shared_replays.busy()
	if host.shared_replays.local_loading(): left.add_child(refresh)
	else: ControlTheme.empty_state(left,"replays_together",PlayerCopy.EMPTY_TOGETHER_TITLE,PlayerCopy.EMPTY_TOGETHER_TEXT,refresh)
	shell.preview_panel.visible=false

func _refresh_shared_replay_rooms() -> void:
	# Replays already on this phone stay; new downloads wait for the update.
	if host._update_gate_active():
		host._toast(UpdateGate.notice(str(host.app_status.result.get("min_version",""))))
		return
	if host.shared_replays==null or host.shared_replays.busy() or not host._relay_identity().ready: return
	if host.mode==MODE_SHARED_REPLAYS: _draw_shared_replay_empty(PlayerCopy.MAIN_2CEDB8F94036)
	var view: int = host.store_view_generation
	var owner: Dictionary = host._relay_identity()
	var okay: bool=await host.shared_replays.refresh_rooms()
	if host.mode not in [MODE_SHARED_REPLAYS,MODE_SHARED_MEMORIES] or view!=host.store_view_generation or owner!=host._relay_identity(): return
	if _default_shared_replay_key().is_empty():
		_draw_shared_replay_empty(PlayerCopy.MAIN_A931AA250D92 if okay else host.shared_replays.last_error)
		return
	_open_default_shared_room()

func show_shared_replay_room(key: String) -> void:
	if host.shared_replays==null or not host._relay_identity().ready or not _replay_key_allowed(key): return
	if key!=shared_replay_room: _shared_preview_id=""
	shared_replay_room=key
	_draw_shared_replay_memories(host.shared_replays.memories(key, host.shared_replays.local_loading()))
	_check_shared_room_parts(key)
	_fetch_missing_shared_photos(key)

func open_shared_replay_room(room_id: String) -> void:
	# Public entry for the room hub: open the Together library on one room.
	# While this phone is still checking its saved rooms the loading view
	# stays up; a room it does not hold yet is saved from the server first.
	# It never shows a different room in its place.
	show_shared_replays("chapter:" + room_id if not room_id.is_empty() else "")

func _open_wanted_shared_room() -> void:
	var key := _shared_wanted_room
	var room_id := key.substr(8)
	if not key.begins_with("chapter:") or not _replay_room_allowed({"family": "chapter", "room_id": room_id}):
		_shared_wanted_room = ""
		_open_default_shared_room()
		return
	# A finished room this phone holds whole opens at once; one it holds only
	# part of (the friend finished it) is saved whole first.
	if not _shared_replay_key_for_room(room_id).is_empty() and not host.shared_replays.local_sequence(key).is_empty():
		_shared_wanted_room = ""
		show_shared_replay_room(key)
		# Room history: the friend's phone may have asked for an attempt this phone keeps.
		if RoomsApi.history_supported: save_finished_replay(room_id)
		return
	if host.shared_replays.local_loading():
		_draw_shared_replay_empty()
		return
	_draw_shared_replay_empty("Saving replays…")
	# A save already running (leaving that room's play) opens it when done.
	save_finished_replay(room_id)

## A finished room's save ended: show it when a Watch replay tap is waiting.
func _finished_replay_saved(room_id: String, saved: bool) -> void:
	var key := "chapter:" + room_id
	if _shared_wanted_room != key or host.mode not in [MODE_SHARED_REPLAYS,MODE_SHARED_MEMORIES] or not host._relay_identity().ready: return
	if host.shared_replays != null and not _shared_replay_key_for_room(room_id).is_empty():
		_shared_wanted_room = ""
		show_shared_replay_room(key)
	elif not saved and replay_saves.is_empty():
		_shared_wanted_room = ""
		_draw_shared_replay_empty("Could not save replays")

func _shared_replay_key_for_room(room_id: String) -> String:
	if host.shared_replays==null or room_id.is_empty(): return ""
	for room: Dictionary in host.shared_replays.rooms():
		if str(room.get("room_id",""))!=room_id: continue
		var key: String=SharedReplays._room_key(room)
		if not host.shared_replays.memories(key,true).is_empty() and _replay_room_allowed(room): return key
	return ""

func _draw_shared_replay_memories(rows: Array, message: String="") -> void:
	if not _replay_key_allowed(shared_replay_room): return
	# A redraw of the same room (a checked room arriving) keeps the scroll offset.
	var kept_scroll: int=host._bounded_card_scroll.scroll_vertical if host.mode == MODE_SHARED_MEMORIES and _shared_drawn_room == shared_replay_room and is_instance_valid(host._bounded_card_scroll) else 0
	_shared_drawn_room=shared_replay_room
	var back_text := "Back"
	var back_callback: Callable = func(): home_requested.emit()
	var shell := _begin_replay_split("together",back_text,back_callback)
	host.mode=MODE_SHARED_MEMORIES
	var wide: bool=shell.wide
	var left: VBoxContainer=shell.left
	var room := _current_shared_room()
	left.add_child(host._label(str(room.get("title",PlayerCopy.MAIN_C8F7A8FDC485)) if not room.is_empty() else PlayerCopy.MAIN_C8F7A8FDC485,24,CREAM,true))
	var about := _shared_room_line(room, false)
	if not about.is_empty(): left.add_child(host._label(about,17,MUTED))
	_add_shared_room_selector(left)
	_add_shared_replay_loading_bar(left,wide and rows.is_empty())
	_select_shared_memory(rows)
	for index in range(rows.size()):
		var row: Dictionary=rows[index].duplicate(true)
		var selected: bool=wide and str(row.get("id",""))==_shared_preview_id
		left.add_child(_shared_memory_row(row,_shared_part(row,index),selected,wide))
	if rows.is_empty() and not host.shared_replays.local_loading(): left.add_child(host._paragraph(PlayerCopy.MAIN_DE8FFD26387B,640))
	if not message.is_empty(): left.add_child(host._paragraph(message,650))
	elif not host.shared_replays.last_error.is_empty(): left.add_child(host._paragraph(host.shared_replays.last_error,650))
	# The selection hint only makes sense once there is a stage to select.
	if not rows.is_empty(): left.add_child(host._paragraph(PlayerCopy.MAIN_4CACA12BCD58,650))
	var has_preview: bool=wide and not rows.is_empty() and not _shared_preview_id.is_empty()
	if not has_preview:
		var options: Button = host._button("Options",_open_shared_options,false)
		options.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		left.add_child(options)
	if has_preview:
		_fill_shared_preview(shell.right,rows)
	else:
		shell.preview_panel.visible=false
	if kept_scroll>0: _restore_replay_scroll.call_deferred(shell.scroll,kept_scroll)

func _add_shared_room_selector(left: VBoxContainer) -> void:
	# "Choose another room" lists every shared room that still has a saved
	# replay by chapter title and partner, so switching stays on this view.
	var rooms: Array=_listed_shared_rooms()
	if rooms.size()<=1: return
	var option := OptionButton.new()
	# A selector is a secondary control; Watch replay stays the one cream action.
	ControlTheme.secondary(option)
	for state: String in ["hover","pressed","hover_pressed"]:
		option.add_theme_stylebox_override(state,ControlTheme.padded(ControlTheme.rounded(Color("2b5550"),14,Color("54766a"))))
		option.add_theme_color_override("font_"+state+"_color",CREAM)
	option.custom_minimum_size.y=48
	option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	option.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	var current := 0
	for i in range(rooms.size()):
		var room: Dictionary=rooms[i]
		var key: String=SharedReplays._room_key(room)
		option.add_item(_shared_room_line(room, true))
		option.set_item_metadata(i,key)
		if key==shared_replay_room: current=i
	option.select(current)
	option.item_selected.connect(func(index: int):
		var key := str(option.get_item_metadata(index))
		if not key.is_empty() and key!=shared_replay_room: show_shared_replay_room(key))
	left.add_child(option)

func _shared_room_thumb_key(row: Dictionary = {}) -> String:
	var room := _current_shared_room()
	var key := str(room.get("chapter_key","")) if not room.is_empty() else ""
	if not key.is_empty() and ChapterThumbnailCatalog.texture(key) != null: return key
	# Earlier-island rooms: match the part to its island for a real picture.
	var title := str(row.get("title",""))
	for level: Dictionary in host.levels:
		if str(level.get("title","")) == title: return "legacy-"+str(level.get("id",""))
	return key

func _select_shared_memory(rows: Array) -> void:
	if rows.is_empty():
		_shared_preview_id=""
		return
	for row: Dictionary in rows:
		if str(row.get("id",""))==_shared_preview_id: return
	_shared_preview_id=str(rows[0].get("id",""))

func _shared_memory_row(row: Dictionary, part: int, selected: bool, wide: bool) -> Control:
	var key := shared_replay_room
	var open := func():
		if wide:
			# A tap anywhere selects the part; one not saved yet starts saving.
			_shared_preview_id=str(row.get("id",""))
			_draw_shared_replay_memories(host.shared_replays.listed(key))
			if not row.get("cached",false): _save_shared_memory(key,row)
		else:
			_open_shared_memory(key,row)
	var card := _replay_row_card(_shared_room_thumb_key(row),str(row.get("title","Replay")),"Part %d · %s" % [part,"Saved offline" if row.get("cached",false) else "Download replay"],selected,open)
	var panel: PanelContainer=card.panel
	var rowbox: HBoxContainer=card.rowbox
	var play := _shared_watch_button("Play",key,row,false,true)
	play.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	rowbox.add_child(play)
	if not wide and row.get("cached",false):
		var remove := _collection_delete_button(func(): _confirm_delete_shared_memory(key,row),str(row.get("title","")))
		remove.disabled=not _can_delete_shared_memory(key)
		rowbox.add_child(remove)
	return panel

## A shared chapter memory's part is its stage; earlier-island rows (no stage)
## keep their place in the list.
static func _shared_part(row: Dictionary, index: int) -> int:
	return int(row.stage_index) + 1 if row.has("stage_index") else index + 1

## Parts in the current shared room's chapter, or the rows listed when it has none.
func _shared_part_count(rows: Array) -> int:
	var room := _current_shared_room()
	var stages := RoomStages.count(ChapterRegistry.definition(str(room.get("chapter_key","")))) if not room.is_empty() else 0
	return stages if stages > 0 else rows.size()

func _fill_shared_preview(preview: VBoxContainer, rows: Array) -> void:
	var key := shared_replay_room
	var part := 0
	var current: Dictionary={}
	for index in range(rows.size()):
		if str(rows[index].get("id",""))==_shared_preview_id:
			current=rows[index].duplicate(true)
			part=index
			break
	if current.is_empty(): return
	var thumbnail: Control = host._replay_preview_thumb(_shared_room_thumb_key(current),Vector2(0,220),16)
	preview.add_child(thumbnail)
	preview.set_meta("thumbnail",thumbnail)
	preview.add_child(host._label(str(current.get("title","Replay")),28,CREAM,true))
	preview.add_child(host._label("Part %d / %d" % [_shared_part(current,part),_shared_part_count(rows)],17,MUTED))
	preview.add_child(_shared_watch_button("Watch replay",key,current,true))
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation",10)
	var sequence: Array=host.shared_replays.local_sequence(key)
	if not sequence.is_empty():
		var watch_all: Button = host._button("Watch all parts",func(): _play_shared_entries(sequence),false)
		watch_all.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		secondary.add_child(watch_all)
	var options: Button = host._button("Options",_open_shared_options,false)
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	secondary.add_child(options)
	if current.get("cached",false):
		var remove := _collection_delete_button(func(): _confirm_delete_shared_memory(key,current),str(current.get("title","")))
		remove.disabled=not _can_delete_shared_memory(key)
		secondary.add_child(remove)
	preview.add_child(secondary)
	_fit_replay_preview.call_deferred(preview)

func _shared_watch_button(text: String, key: String, row: Dictionary, primary: bool, list_row: bool=false) -> Button:
	## A saved replay opens its viewer, with its own loading bar, at once; one
	## that must be downloaded first shows the launch wait while it arrives.
	var launch := func(): await _open_shared_memory(key,row)
	if not row.get("cached",false): return _replay_launch_button(text,launch,primary,list_row)
	return host._list_button(text,launch,primary) if list_row else host._button(text,launch,primary)

func _open_shared_options() -> void:
	if host.shared_replays==null: return
	var modal := InGameModal.open(host.ui,"SharedReplayOptions","Options")
	var busy: bool=host.shared_replays.busy() or _shared_photo_sync or _shared_archive_sync
	var refresh: Button = host._button("Refresh memories",func(): modal.close(); _refresh_shared_replay_memories(),false)
	refresh.disabled=busy
	modal.content.add_child(refresh)
	# Keep server room discovery reachable now that Together opens straight
	# into a room instead of a list; it refreshes the "Choose another room"
	# set and stays on the current room when it is still present.
	var rooms: Button = host._button("Find more rooms",func(): modal.close(); _refresh_shared_replay_rooms(),false)
	rooms.disabled=busy
	modal.content.add_child(rooms)
	var photos: Button = host._button("Sync photos",func(): modal.close(); _sync_shared_photos(),false)
	photos.disabled=busy or host.shared_replays.local_entries(shared_replay_room).is_empty()
	modal.content.add_child(photos)
	if shared_replay_room.begins_with("chapter:"):
		var offline: Button = host._button("Save all replays offline",func(): modal.close(); _sync_shared_archive(),false)
		offline.disabled=busy or (host.relay_session!=null and host.relay_session.busy())
		modal.content.add_child(offline)

func _add_replay_library_tabs(parent: VBoxContainer, selected: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	var solo: Button = host._button("Solo",show_collection,false)
	var together: Button = host._button("Together",show_shared_replays,false)
	solo.disabled=selected=="solo"
	together.disabled=selected=="together"
	_selected_look(solo if selected=="solo" else together)
	ControlTheme.plain_tab(together if selected=="solo" else solo)
	row.add_child(solo)
	row.add_child(together)
	parent.add_child(row)

func _can_delete_shared_memory(key: String) -> bool:
	return host.shared_replays != null and not host.shared_replays.busy() and not _shared_photo_sync and not _shared_archive_sync and (host.relay_session == null or not host.relay_session.busy()) and not host.application_backgrounded and host._relay_identity().ready and key == shared_replay_room and _replay_key_allowed(key)

func _confirm_delete_shared_memory(key: String, row: Dictionary) -> void:
	if host.mode != MODE_SHARED_MEMORIES or not row.get("cached",false) or not _can_delete_shared_memory(key): return
	var expected: Dictionary = {}
	for entry: Dictionary in host.shared_replays.local_entries(key):
		if SharedReplays.summary(entry) == row:
			expected=entry
			break
	if expected.is_empty(): return
	var owner: Dictionary = host._relay_identity()
	host.mode=MODE_CONFIRM_DELETE
	var card: VBoxContainer = host._card(700)
	card.add_child(host._label("Delete replay?",32,CREAM,true))
	card.add_child(host._paragraph(str(row.title),590))
	card.add_child(host._paragraph(PlayerCopy.SHARED_REPLAY_DELETE_CONFIRM,590))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and host.mode == MODE_CONFIRM_DELETE
	card.add_child(host._button("Delete",func():
		if not current.call() or owner != host._relay_identity() or not _can_delete_shared_memory(key): return
		var removed: bool = host.shared_replays.remove_memory(key,str(row.id),expected)
		_draw_shared_replay_memories(host.shared_replays.listed(key),"Replay deleted" if removed else host.shared_replays.last_error),false))
	host._retry_cancel = func():
		if not current.call(): return
		if owner == host._relay_identity() and host._relay_identity().ready and _replay_key_allowed(key): show_shared_replay_room(key)
		else: show_shared_replays()
	card.add_child(host._button("Cancel",host._retry_cancel))

## Opening a chapter room asks the server once a session for parts this phone
## has not saved, so a room the friend finished elsewhere lists every part.
func _check_shared_room_parts(key: String) -> void:
	if host._update_gate_active(): return
	if _shared_parts_checked.has(key) or not key.begins_with("chapter:") or host.shared_replays == null or host.shared_replays.local_loading() or key != shared_replay_room: return
	if not host.shared_replays.local_sequence(key).is_empty(): return
	# The replay collection may be saving a part for this room: wait for it
	# briefly rather than skip the check until the player refreshes by hand.
	_shared_parts_checked[key] = false
	var deadline := Time.get_ticks_msec() + 10000
	while host.shared_replays.busy() and Time.get_ticks_msec() < deadline and key == shared_replay_room and host.mode == MODE_SHARED_MEMORIES:
		await host.get_tree().create_timer(0.1).timeout
	if key == shared_replay_room and host.mode == MODE_SHARED_MEMORIES and await _refresh_shared_replay_memories(): _shared_parts_checked[key] = true
	else: _shared_parts_checked.erase(key)

func _refresh_shared_replay_memories() -> bool:
	if host._update_gate_active(): return false
	if host.shared_replays==null or host.shared_replays.busy() or not host._relay_identity().ready or not _replay_key_allowed(shared_replay_room): return false
	var context := _shared_room_context()
	var key: String = context.key
	# A finger on the page lifts first; then the checks above hold again or nothing starts.
	if not await TouchInput.redraw_when_released(host.overlay,func() -> bool: return _shared_room_current(context) and not host.shared_replays.busy(),
		func() -> void: _draw_shared_room_status(context,host.shared_replays.memories(key),"Checking completed stages…")): return false
	var rows: Array=await host.shared_replays.refresh_memories(key)
	if _shared_room_current(context): await _redraw_shared_room(context,"",func() -> Array: return rows)
	return true

## The Together page as one task found it, captured once as
## _friends_route_context does for Friends: its room, its view and the player.
## A task that draws its own status takes that view (_draw_shared_room_status).
## any_view: a background task that only needs the same room and player.
func _shared_room_context(any_view: bool = false) -> Dictionary:
	return {"key": shared_replay_room, "view": -1 if any_view else host.store_view_generation, "owner": host._relay_identity()}

func _shared_room_current(context: Dictionary) -> bool:
	return host.mode == MODE_SHARED_MEMORIES and context.key == shared_replay_room and context.owner == host._relay_identity() and (int(context.view) < 0 or context.view == host.store_view_generation) and not is_instance_valid(host.shared_replay_child)

## Draws the room with a task's status line; the task then owns the view the draw starts.
func _draw_shared_room_status(context: Dictionary, rows: Array, message: String) -> void:
	_draw_shared_replay_memories(rows,message)
	if int(context.view) >= 0: context.view = host.store_view_generation

## Automatic Together-page redraws (parts or photos that landed, a task that
## ended) wait for a finger on the page to lift, then redraw only while the page
## is still the context's and `still` holds, so a row never rebuilds under a tap.
## rows defaults to the room's listed parts. False when the page moved on.
func _redraw_shared_room(context: Dictionary, message: String = "", rows: Callable = Callable(), still: Callable = Callable()) -> bool:
	var key: String = context.key
	return await TouchInput.redraw_when_released(host.overlay,func() -> bool: return _shared_room_current(context) and (not still.is_valid() or still.call()),
		func() -> void: _draw_shared_replay_memories(rows.call() if rows.is_valid() else host.shared_replays.listed(key),message))

func _sync_shared_photos() -> void:
	if host._update_gate_active(): return
	if _shared_photo_sync or _shared_archive_sync or host.shared_replays == null or host.shared_replays.busy() or not host._relay_identity().ready or not _replay_key_allowed(shared_replay_room): return
	var context := _shared_room_context()
	_draw_shared_room_status(context, host.shared_replays.listed(context.key), "Syncing photos…")
	var result := await _fetch_shared_room_photos(context.key, false)
	await _redraw_shared_room(context,str(result.get("error","")))

## Looks once a session for the friend's photos of a Together room that are not
## on this phone yet, without holding up the room or its replay; photos that
## arrive show in the list and in a replay already playing.
func _fetch_missing_shared_photos(key: String) -> void:
	if host._update_gate_active(): return
	if _shared_photo_checked.has(key) or _shared_photo_sync or not key.begins_with("chapter:") or host.shared_replays == null or not host._relay_identity().ready or not _replay_key_allowed(key): return
	if host.shared_replays.local_entries(key).is_empty(): return
	_shared_photo_checked[key] = true
	var context := _shared_room_context(true)
	context.key = key
	var result := await _fetch_shared_room_photos(key, true)
	if int(result.get("fetched",0)) == 0 or context.owner != host._relay_identity(): return
	if is_instance_valid(host.shared_replay_child): host.shared_replay_child.refresh_photos()
	else: await _redraw_shared_room(context,"",Callable(),func() -> bool: return not _shared_archive_sync and not _shared_photo_sync)

## The one path that brings a friend's turn photos for a Together room into this
## phone's photo library. With missing_only it asks only for the friend's turns
## not saved here; the photo controller then downloads bytes only for a digest
## the library lacks, saves them durably, then sends the delivery ACK. Requests
## go one at a time when the API is free and stop at SHARED_PHOTO_FETCH_LIMIT
## turns. The server still checks membership and blocking for every request,
## and the replay's photo strip applies its own hiding rules when it shows them.
func _fetch_shared_room_photos(key: String, missing_only: bool) -> Dictionary:
	if _shared_photo_sync or host.shared_replays == null or not host._relay_identity().ready or not key.begins_with("chapter:"): return {"fetched":0,"error":""}
	var owner: Dictionary = host._relay_identity()
	var session := SharedReplayView.ReadSession.new(host.api, host._relay_identity)
	session.photo_context_factory = host._room_context_factory()
	var targets: Array = []
	for entry: Dictionary in host.shared_replays.local_entries(key):
		for target: Dictionary in SharedReplays._verified_photo_turns(entry, owner.player_id):
			if missing_only and target.own: continue
			if not targets.has(target): targets.append(target)
	session.photo_targets = targets
	_shared_photo_sync = true
	var wanted: Array = []
	if missing_only:
		var saved: RefCounted = session.create_photo_controller(Callable())
		for target: Dictionary in targets:
			if (await saved.read_shared(target.room_id, target.turn_id, target.recording_hash)).is_empty(): wanted.append(target)
	else: wanted = targets
	if wanted.size() > SHARED_PHOTO_FETCH_LIMIT: wanted.resize(SHARED_PHOTO_FETCH_LIMIT)
	session.local_replay_only = false
	var controller: RefCounted = session.create_photo_controller(Callable())
	var fetched := 0
	for target: Dictionary in wanted:
		# Each photo takes its turn in the one request queue with whatever the player does meanwhile.
		if owner != host._relay_identity(): break
		var photo: Dictionary = await controller.read_shared(target.room_id, target.turn_id, target.recording_hash)
		if not photo.get("bytes", PackedByteArray()).is_empty(): fetched += 1
	var error := str(controller.last_error) if owner == host._relay_identity() else ""
	session.invalidate_identity()
	_shared_photo_sync = false
	return {"fetched":fetched,"error":error}

func _sync_shared_archive() -> void:
	if _shared_archive_sync or _shared_photo_sync or host.shared_replays == null or host.shared_replays.busy() or host.relay_session == null or host.relay_session.busy() or not host._relay_identity().ready or not shared_replay_room.begins_with("chapter:") or not _replay_key_allowed(shared_replay_room): return
	var context := _shared_room_context()
	var key: String = context.key
	var session: RefCounted = host.relay_session
	_shared_archive_sync = true
	_draw_shared_room_status(context, host.shared_replays.listed(key), "Saving replays…")
	var result := {"ok": false}
	if await session.load_capabilities() and _shared_room_current(context):
		result = await session.sync_complete_replay(key.substr(8))
	_shared_archive_sync = false
	await _redraw_shared_room(context,"Saved offline" if result.get("ok", false) else "Could not save replays")
	if result.get("ok", false) and context.owner == host._relay_identity():
		_shared_photo_checked.erase(key)
		_fetch_missing_shared_photos(key)

## Downloads and saves one listed part without playing it, then shows it saved.
func _save_shared_memory(key: String, row: Dictionary) -> void:
	if host.shared_replays==null or host.shared_replays.busy() or not host._relay_identity().ready or not _replay_key_allowed(key): return
	var context := _shared_room_context()
	context.key = key
	var entry: Dictionary=await host.shared_replays.open_memory(key,str(row.id),row)
	if not _shared_room_current(context): return
	if entry.is_empty(): host._toast(host.shared_replays.last_error); return
	await _redraw_shared_room(context)
	_shared_photo_checked.erase(key)
	_fetch_missing_shared_photos(key)

func _open_shared_memory(key: String, row: Dictionary) -> void:
	if host.shared_replays==null or (host.shared_replays.busy() and not row.get("cached",false)) or not host._relay_identity().ready or is_instance_valid(host.shared_replay_child) or not _replay_key_allowed(key): return
	var view: int = host.store_view_generation
	var owner: Dictionary = host._relay_identity()
	var entry: Dictionary=await host.shared_replays.open_memory(key,str(row.id),row)
	if host.mode!=MODE_SHARED_MEMORIES or view!=host.store_view_generation or owner!=host._relay_identity() or key!=shared_replay_room or not _replay_key_allowed(key): return
	if entry.is_empty(): host._toast(host.shared_replays.last_error); return
	_play_shared_entries([entry])
	if not row.get("cached",false):
		# A part saved just now may bring the friend's photos; they appear as they arrive.
		_shared_photo_checked.erase(key)
		_fetch_missing_shared_photos(key)

func _play_shared_entries(entries: Array) -> void:
	if entries.is_empty() or host.mode != MODE_SHARED_MEMORIES or not host._relay_identity().ready or is_instance_valid(host.shared_replay_child) or not _replay_key_allowed(shared_replay_room): return
	host.lifecycle_generation+=1
	host.foreground_refresh_queued=false
	host.foreground_response={}
	host.mode=MODE_SHARED_REPLAY
	host.running=false
	host._set_world_visible(false)
	host.ui.visible=false
	host.soundscape.set_backgrounded(true)
	host.shared_replay_child=SharedReplayView.new()
	host.shared_replay_child.entry=entries[0]
	host.shared_replay_child.sequence=entries
	host.shared_replay_child.settings=host.saves.data.settings.duplicate(true)
	host.shared_replay_child.api=host.api
	host.shared_replay_child.identity=host._relay_identity
	host.shared_replay_child.context_factory=host._room_context_factory()
	host.shared_replay_child.friend_name=_room_partner_nickname(_current_shared_room())
	host.shared_replay_child.closed.connect(_leave_shared_replay)
	host.add_child(host.shared_replay_child)

func _leave_shared_replay() -> void:
	var blocked: bool = is_instance_valid(host.shared_replay_child) and host.shared_replay_child.blocked_exit
	if is_instance_valid(host.shared_replay_child):
		host.remove_child(host.shared_replay_child)
		host.shared_replay_child.queue_free()
	host.shared_replay_child=null
	host._set_world_visible(true)
	host.ui.visible=true
	host.soundscape.set_backgrounded(host.application_backgrounded)
	host.lifecycle_generation+=1
	if blocked: show_shared_replays()
	elif host._relay_identity().ready: show_shared_replay_room(shared_replay_room)
	else: show_shared_replays()

## Brings a finished room's whole replay to this phone and, once both phones
## hold it, lets the server keep only a compact record; then fetches the
## friend's photos for it. Safe to repeat: the download and its ACK are keyed
## by the room's replay epoch, and a room already saved is not asked again.
## With a revision (leaving that room's play) it stops once the room moves
## on, such as a redo. Not while a turn or a replay plays: it runs on an idle
## screen. True when this phone holds the replay afterwards.
func save_finished_replay(room_id: String, revision: int = -1, in_play: bool = false) -> bool:
	# One save per room at a time; a second caller is served by the first.
	if replay_saves.has(room_id): return false
	replay_saves[room_id] = true
	var saved: bool = await _save_finished_replay_once(room_id, revision, in_play)
	replay_saves.erase(room_id)
	_finished_replay_saved(room_id, saved)
	return saved

func _save_finished_replay_once(room_id: String, revision: int, in_play: bool = false) -> bool:
	var owner: Dictionary = host._relay_identity()
	var key := str(owner.player_id) + ":" + room_id + ":" + str(revision)
	if not owner.ready or _shared_archive_attempts.has(key): return _shared_archive_attempts.get(key, false) == true
	if host.relay_session == null: host.relay_session = host._new_relay_session()
	var session: RefCounted = host.relay_session
	var delays: Array[float] = [0.0]
	delays.append_array(replay_save_retry_s)
	for delay: float in delays:
		if delay > 0.0: await host.get_tree().create_timer(delay).timeout
		var deadline := Time.get_ticks_msec() + 5000
		while (session.busy() or _shared_archive_sync or _shared_photo_sync) and Time.get_ticks_msec() < deadline:
			await host.get_tree().create_timer(0.1).timeout
		if owner != host._relay_identity() or session != host.relay_session or host.application_backgrounded or not _replay_save_idle(): return false
		if revision >= 0:
			var bound: Dictionary = session.coordinator.snapshot() if session.coordinator != null else {}
			if bound.get("room_id") != room_id or int(bound.get("revision", -1)) != revision or (bound.get("active_role") != "complete" and not in_play) or not session.coordinator.pending().is_empty(): return false
		if session.busy() or _shared_archive_sync or _shared_photo_sync: continue
		if session.capabilities.is_empty() and not await session.load_capabilities(): continue
		if owner != host._relay_identity() or session != host.relay_session: return false
		if session.has_method("last_room"): session.last_room() # Loads the saved room index the proof below reads.
		if (session.capabilities.get("replay_transfer_version") != 1 and not host._history_mode(session)) or (in_play and not host._history_mode(session)) or (not host._history_mode(session) and not session.standalone_room_proven(room_id)): return false
		if session.busy() or _shared_archive_sync: continue
		_shared_archive_sync = true
		var result: Dictionary
		if in_play: result = await session.sync_room_history(room_id)
		else: result = await session.sync_complete_replay(room_id)
		_shared_archive_sync = false
		if owner != host._relay_identity(): return false
		if result.get("ok", false):
			# A room history pass from Watch replay may run again on a later tap.
			if revision >= 0 or not host._history_mode(session): _shared_archive_attempts[key] = true
			# The replay now plays from this phone, so bring the friend's photos with it.
			await _fetch_shared_room_photos("chapter:" + room_id, true)
			return true
		if not _replay_save_transient(result):
			_shared_archive_attempts[key] = false
			return false
	return false

## Saving reads and verifies a whole replay: never during a turn or playback.
func _replay_save_idle() -> bool:
	return not host.running and host.mode != MODE_SHARED_REPLAY and not is_instance_valid(host.shared_replay_child) and not (is_instance_valid(host.relay_child) and host.relay_child.running)

## A save that met a busy API, a lost connection or an outage; worth repeating.
static func _replay_save_transient(result: Dictionary) -> bool:
	var status := int(result.get("status", 0))
	return status == 0 or status == 429 or status >= 500 or str(result.get("code", "")) in ["request_busy", "connection_interrupted", "replay_transfer_busy", "replay_transfer_unavailable", "replay_transfer_context_changed", "rate_limited", "replay_transfer_rate_limited"]
