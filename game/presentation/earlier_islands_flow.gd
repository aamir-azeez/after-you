extends Node
## Playing an earlier island (a v1 level): its ready card, the turn itself,
## the completion moment, the review, retry and restart cards, Preview, the
## pause card and the celebration. Solo practice opens it from the Earlier
## islands list (JourneyFlow) and Your replays; a legacy room's turn and replay
## run through the same cards (Main._start_room_turn, Main._watch_room_replay)
## with Main.room_play set.
##
## Main hosts it as a child. The flow keeps no state of its own: the open island
## and its turn stay on Main, which the room flows, Replays, Back and the
## lifecycle share. Main keeps the engine callbacks and calls in:
## _physics_process (physics_step), _process (advance_completion_moment),
## _unhandled_key_input and _notification (request_context_action, pause,
## save_draft), the HUD's buttons and _start_practice (start_practice), which
## JourneyFlow's host contract names. The flow reads Main only through this host
## contract (read at call time, so Main or a test can swap a service or override
## an entry point):
## - services: saves, levels, sim, world, soundscape, store_flow, journey_flow,
##   room_hub_flow, replays_flow, turn_flow, legacy_room_flow
## - the open island: level_index, current_level, attempt, role, room_play,
##   active_room
## - the turn: mode, running, action_pressed, review_recording,
##   collection_preview, replay_frames, replay_index, completion_time_left,
##   _retry_cancel
## - guards: submission_in_flight, application_backgrounded,
##   store_view_generation, lifecycle_generation, _tester_checks_enabled,
##   _tester_context, _load_cached_tester, _full_journey_access,
##   _paid_content_hidden, _room_simulation_version, _relay_identity
## - HUD: hud, stick, role_label, interact_button, finish_button, progress,
##   objective_panel, hint_label
## - screen: _card, _label, _paragraph, _button, _action_button (a card's Back is
##   Android Back too), _close_overlay, _toast, _show_home
## - room reactions: _react, _add_room_reaction_summary
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Simulation = preload("res://core/simulation.gd")
const HomeKeepsakes = preload("res://services/home_keepsakes.gd")
const LocalSave = preload("res://services/local_save.gd")
const TurnState = preload("res://services/turn_state.gd")
const ReplaysFlow = preload("res://presentation/replays_flow.gd")
const Soundscape = preload("res://services/soundscape.gd")
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const CREAM := UiTokens.CREAM
const COMPLETION_MOMENT_SECONDS := 3.0

var host: Node

func _init(main: Node = null) -> void:
	host = main

func start_practice(index: int) -> void:
	if index >= 3 and host._tester_checks_enabled():
		var view: int = host.store_view_generation
		var lifecycle: int = host.lifecycle_generation
		var context: String = host._tester_context()
		await host._load_cached_tester()
		if host.application_backgrounded or view != host.store_view_generation or lifecycle != host.lifecycle_generation or context != host._tester_context(): return
	if host.submission_in_flight:
		host._toast(PlayerCopy.MAIN_996946E90346)
		return
	if index<0 or index>=host.levels.size():
		return
	if index>=3 and not host._full_journey_access():
		host.store_flow.show_paywall()
		return
	host.room_play=false
	host.collection_preview=false
	host.level_index=index
	host.current_level=host.levels[index]
	host.attempt=host.saves.attempt(host.current_level.id)
	host.role="b" if not host.attempt.get("a",{}).is_empty() else "a"
	if not host.attempt.get("b",{}).is_empty():
		host.mode="completed_attempt"
		var card: VBoxContainer = host._card()
		card.add_child(host._label(PlayerCopy.MAIN_0984B81F14AB,34,CREAM,true))
		card.add_child(host._paragraph(PlayerCopy.MAIN_CCB173FD54CF))
		card.add_child(host._action_button("replay",func(): preview(host.attempt.b,true)))
		card.add_child(host._button("Start a fresh attempt",_confirm_restart_attempt,false))
		card.add_child(host._action_button("back",host.journey_flow.show_journey))
		return
	prepare_turn()

func prepare_turn() -> void:
	if host.submission_in_flight:
		host._toast(PlayerCopy.MAIN_996946E90346)
		return
	host.running=false
	host.mode="ready"
	host.collection_preview=false
	host.review_recording={}
	host.action_pressed=false
	host.stick.release()
	host.attempt=LocalSave.normalize_attempt(host.attempt)
	host.world.home_view=false
	host.world.load_level(host.current_level)
	var ruleset := TurnState.simulation_version(host.attempt, host.role, host.active_room if host.room_play else {}, false)
	if not host.sim.reset(host.current_level,host.attempt.get("a",{}) if host.role=="b" else {},host.role,ruleset):
		host._toast(host.sim.error)
		host.journey_flow.show_journey()
		return
	_begin_sound_turn()
	host.sim.catch_assistance=bool(host.saves.data.settings.get("assistance",true))
	host.world.present(host.sim.snapshot(),true)
	host.hud.visible=true
	host.role_label.text="%02d / %s  ·  %s" % [host.level_index+1,host.current_level.title,"Your first turn" if host.role=="a" else "Alongside a ghost"]
	host.interact_button.text="Throw seed" if host.role=="a" else "Plant seed"
	host.finish_button.visible=host.role=="a"
	host.stick.visible=true
	host.interact_button.visible=true
	update_hud(host.sim.snapshot())
	var card: VBoxContainer = host._card()
	card.add_child(host._label("Leave a moment." if host.role=="a" else PlayerCopy.MAIN_408402D8E83C,34,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.from_canonical(str(host.current_level.get("hint_"+host.role,"")))))
	card.add_child(host._paragraph(PlayerCopy.MAIN_0141427332B8))
	var draft: Dictionary=host.attempt.get("draft",{})
	if draft.get("role","")==host.role and int(draft.get("duration_ticks",0))>0:
		card.add_child(host._action_button("resume",func(): resume_draft(draft)))
	card.add_child(host._action_button("record",begin_turn))
	card.add_child(host._action_button("back",host.room_hub_flow.show_rooms if host.room_play else host.journey_flow.show_journey))

## The simulation is back at tick zero: its cues restart their identities.
func _begin_sound_turn() -> void:
	host.soundscape.begin_turn(Soundscape.ISLANDS_CHAPTER,str(host.current_level.get("id","")))

func _sound_sources(state: Dictionary) -> Array:
	var sources: Array=[]
	for event: Variant in state.get("events",[]): sources.append(Soundscape.event_source(str(event),host.role))
	return sources

func begin_turn() -> void:
	if host.application_backgrounded or host.submission_in_flight:
		return
	host._close_overlay()
	host.mode="play"
	host.running=true
	host.action_pressed=false
	host.stick.release()
	update_hud(host.sim.snapshot())

func resume_draft(draft: Dictionary) -> void:
	var check: Dictionary=TurnState.review(host.current_level,draft,host.attempt,host._room_simulation_version())
	if not check.valid or draft.get("role","")!=host.role:
		host._toast(PlayerCopy.MAIN_EA192FA7B9B0+str(check.get("error","")))
		return
	host.sim.catch_assistance=bool(draft.get("catch_assistance",true))
	if not host.sim.reset(host.current_level,host.attempt.a if host.role=="b" else {},host.role,int(draft.simulation_version)):
		host._toast(host.sim.error)
		return
	_begin_sound_turn()
	for input in Simulation.expand_recording_inputs(draft):
		var state: Dictionary=host.sim.step(input)
		host.soundscape.note_turn_events(state.events,_sound_sources(state))
	host.world.present(host.sim.snapshot(),true)
	if host.sim.finished:
		host.review_recording=draft.duplicate(true)
		show_review()
		return
	begin_turn()

## One physics tick of the open turn or Preview (Main._physics_process).
func physics_step(_delta: float) -> void:
	if not host.running:
		return
	var input: Dictionary={}
	if host.mode=="preview":
		if host.replay_index>=host.replay_frames.size():
			host.running=false
			show_review()
			return
		input=host.replay_frames[host.replay_index]
		host.replay_index+=1
	else:
		var movement: Vector2=host.stick.value
		var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if keyboard.length()>0:
			movement=keyboard.limit_length()
		# Screen-relative input follows the fixed camera's horizontal axes.
		var right: Vector3=host.world.camera.global_basis.x
		var forward: Vector3=host.world.camera.global_basis.z
		var world_move := (Vector3(right.x,0,right.z).normalized()*movement.x + Vector3(forward.x,0,forward.z).normalized()*movement.y).limit_length()
		input={"move_x":world_move.x,"move_z":world_move.z,"interact":host.action_pressed}
		host.action_pressed=false
	var previous_tick: int=host.sim.tick
	var state: Dictionary=host.sim.step(input)
	if int(state.tick)!=previous_tick:
		host.soundscape.consume_turn_events(state.events,_sound_sources(state),host.mode=="play")
	host.world.present(state)
	update_hud(state)
	if host.mode=="play" and host.sim.tick%30==0 and not state.finished:
		if not save_draft():
			host._toast(host.saves.last_error)
	if state.finished:
		host.running=false
		var draft_saved := true
		if host.mode=="play":
			host.review_recording=host.sim.export_recording()
			draft_saved=save_draft()
			if not draft_saved:
				host._toast(host.saves.last_error)
		if state.complete and draft_saved:
			_begin_completion_moment()
		else:
			show_review()

func _begin_completion_moment() -> void:
	# The live draft is already durable; replay leaves its saved source untouched.
	# Keep presentation alive without another simulation step or delayed callback.
	host.running=false
	host.mode="completion"
	host.completion_time_left=COMPLETION_MOMENT_SECONDS
	host.action_pressed=false
	host.stick.release()
	host.stick.visible=false
	host.interact_button.visible=false
	host.finish_button.visible=false
	host._close_overlay()

func advance_completion_moment(delta: float) -> void:
	if host.mode!="completion" or host.application_backgrounded:
		return
	host.completion_time_left=maxf(0.0,host.completion_time_left-delta)
	if host.completion_time_left<=0.0:
		show_review()

func update_hud(state: Dictionary) -> void:
	host.progress.reduced_motion=bool(host.saves.data.settings.get("reduced_motion",false))
	host.progress.set_remaining(maxi(0,int(state.duration_ticks)-int(state.tick))/30.0,int(state.duration_ticks)/30.0)
	host.objective_panel.show_objective(ObjectivePanel.legacy_progress(state,30.0))
	host.hint_label.text=PlayerCopy.from_canonical(str(state.message))
	var interactive: bool = host.mode=="play" and host.running and not host.application_backgrounded
	host.finish_button.disabled=not interactive or not bool(state.get("can_commit",false))
	var action: Dictionary=state.get("context_action",{})
	host.interact_button.text=PlayerCopy.from_canonical(str(action.get("label","Interact")))
	host.interact_button.disabled=not interactive or not bool(action.get("enabled",false))
	host.interact_button.tooltip_text=PlayerCopy.from_canonical(str(action.get("reason","")))

func request_context_action() -> void:
	if host.mode=="play" and host.running and not host.application_backgrounded and host.sim.context_action().get("enabled",false):
		host.action_pressed=true

func save_draft() -> bool:
	if host.mode!="play" or host.sim.tick==0:
		return true
	host.attempt["draft"]=host.sim.export_recording()
	if host.room_play:
		return host.saves.update_values({"room_draft":{"room_id":host.active_room.get("room_id",""),"revision":host.active_room.get("revision",-1),"attempt":host.attempt.duplicate(true)}})
	return host.saves.save_attempt(host.current_level.id,host.attempt)

func finish_recording() -> void:
	if host.mode!="play" or not host.running or not host.sim.can_commit():
		return
	host.running=false
	host.review_recording=host.sim.export_recording()
	save_draft()
	show_review()

func show_review() -> void:
	host.running=false
	host.stick.release()
	var check: Dictionary=TurnState.review(host.current_level,host.review_recording,host.attempt,host._room_simulation_version())
	var valid: bool=check.valid and check.can_commit
	var complete: bool = valid and bool(host.review_recording.get("completed",false))
	host.mode=ReplaysFlow.MODE_COLLECTION if host.collection_preview else "review"
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_CBFD9EB78DBC if complete else (PlayerCopy.MAIN_6F96DCC47A05 if valid else "Another little try?"),32,CREAM,true))
	var description := PlayerCopy.MAIN_32A4E00F108C if complete else (PlayerCopy.MAIN_92F966458583 if valid else PlayerCopy.MAIN_A01274C34177)
	if complete and host.collection_preview:
		description=PlayerCopy.SHARED_REPLAY_VIEW_8432676D063D
	card.add_child(host._paragraph(description))
	if not host.review_recording.is_empty():
		card.add_child(host._action_button("replay" if host.collection_preview else "preview",func(): preview(host.review_recording,host.collection_preview)))
	var already_saved: bool = host.collection_preview
	if valid and not already_saved:
		card.add_child(host._action_button("save",commit_turn))
	if not already_saved:
		card.add_child(host._action_button("retry",retry_review))
	card.add_child(host._action_button("back",host.room_hub_flow.show_rooms if host.room_play else host.journey_flow.show_journey))

## From the review card, or (`paused_over`) from the pause card over its Preview.
func retry_review(paused_over: String = "") -> void:
	var from_pause: bool = host.mode == "paused" and _previewing_review(paused_over)
	if (host.mode != "review" and not from_pause) or host.application_backgrounded or host.submission_in_flight: return
	var checked: Dictionary = TurnState.review(host.current_level,host.review_recording,host.attempt,host._room_simulation_version())
	if not checked.valid or not checked.can_commit or not bool(host.review_recording.get("completed",false)):
		prepare_turn()
		return
	var recording: Dictionary = host.review_recording.duplicate(true)
	var saved_attempt: Dictionary = host.attempt.duplicate(true)
	var room: Dictionary = host.active_room.duplicate(true)
	var was_room_play: bool = host.room_play
	var recorded_role: String = host.role
	var level_id := str(host.current_level.id)
	var identity: Dictionary = host._relay_identity()
	host.mode = "confirm_retry"
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA,32,CREAM,true))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and host.mode == "confirm_retry" and not host.application_backgrounded and not host.submission_in_flight and host.room_play == was_room_play and host.role == recorded_role and str(host.current_level.id) == level_id and host.review_recording == recording and host.attempt == saved_attempt and host.active_room == room and host._relay_identity() == identity
	card.add_child(host._action_button("retry",func():
		if current.call(): prepare_turn()))
	host._retry_cancel = func():
		if not current.call(): return
		if from_pause: show_paused(paused_over)
		else: show_review()
	card.add_child(host._action_button("cancel",host._retry_cancel))

## Plays an earlier island's saved attempt from Your replays.
func preview_saved_attempt(index: int, saved: Dictionary) -> void:
	host.level_index=index
	host.current_level=host.levels[index]
	host.attempt=saved.duplicate(true)
	preview(saved.b,true)

func preview(recording: Dictionary, collection: bool=false) -> void:
	if collection and not host.room_play:
		host.replays_flow.begin_collection_replay(recording)
		return
	var check: Dictionary=TurnState.review(host.current_level,recording,host.attempt,host._room_simulation_version())
	if not check.valid:
		host._toast(PlayerCopy.MAIN_CD2F00E32FC5+str(check.get("error","")))
		return
	activate_preview(recording,collection)

func activate_preview(recording: Dictionary, collection: bool, prepared: Dictionary = {}) -> void:
	host.review_recording=recording.duplicate(true)
	host.role=str(recording.role)
	host.world.load_level(host.current_level)
	host.world.home_view=false
	if prepared.is_empty():
		host.sim.catch_assistance=bool(recording.get("catch_assistance",true))
		if not host.sim.reset(host.current_level,host.attempt.get("a",{}) if host.role=="b" else {},host.role,int(recording.simulation_version)):
			host._toast(host.sim.error)
			return
		host.replay_frames=Simulation.expand_recording_inputs(recording)
	else:
		host.sim=prepared.simulation
		host.replay_frames=prepared.frames
	_begin_sound_turn()
	host.replay_index=0
	host.mode="preview"
	host.collection_preview=collection
	host._close_overlay()
	host.hud.visible=true
	host.stick.visible=false
	host.interact_button.visible=false
	host.finish_button.visible=false
	host.role_label.text=host.current_level.title+"  ·  Your shared replay"
	host.running=true

func commit_turn() -> void:
	if host.mode!="review" or host.collection_preview:
		return
	var check: Dictionary=TurnState.review(host.current_level,host.review_recording,host.attempt,host._room_simulation_version())
	if not check.valid or not check.can_commit:
		host._toast(PlayerCopy.MAIN_C4E0C9A50B65+str(check.get("error","")))
		return
	if host.room_play:
		await host.turn_flow.commit_online()
		return
	var committed: Dictionary = host.attempt.duplicate(true)
	committed[host.role]=host.review_recording.duplicate(true)
	committed["draft"]={}
	if not host.saves.save_attempt(host.current_level.id,committed,host.role=="b"):
		host._toast(PlayerCopy.MAIN_1A6455ED3E4B)
		return
	if host.role == "b": HomeKeepsakes.record_legacy_solo(host.current_level.id)
	host.attempt=committed
	host.mode="saved"
	if host.role=="a":
		host.role="b"
		prepare_turn()
	else:
		show_celebration()

func show_celebration() -> void:
	host.mode="saved"
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_754724C78F04,34,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_A74DFEBB0414))
	if host.room_play:
		host._add_room_reaction_summary(card, host.active_room)
	var row := HBoxContainer.new()
	for reaction in ["Beautiful!","We did it!","Again soon"]:
		row.add_child(host._button(reaction,func(): host._react(reaction),false))
	card.add_child(row)
	if host.level_index<7 and (host.room_play or not bool(host.levels[host.level_index+1].get("premium",false)) or not host._paid_content_hidden()):
		card.add_child(host._button("Next island",_next_island))
	card.add_child(host._action_button("replay",func(): preview(host.attempt.b,true)))
	card.add_child(host._action_button("back",host._show_home))

func _next_island() -> void:
	if host.room_play:
		await host.legacy_room_flow.advance_room()
	elif host.level_index+1>=3 and not host._full_journey_access():
		host.store_flow.show_paywall()
	else:
		host._start_practice(mini(host.level_index+1,7))

func _confirm_restart_attempt() -> void:
	if host.room_play or host.application_backgrounded or host.submission_in_flight: return
	var saved_attempt: Dictionary = host.attempt.duplicate(true)
	var index: int = host.level_index
	host.mode = "confirm_restart"
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA,32,CREAM,true))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and host.mode == "confirm_restart" and not host.application_backgrounded and not host.submission_in_flight and not host.room_play and host.level_index == index and host.attempt == saved_attempt and host.saves.attempt(str(host.current_level.id)) == saved_attempt
	card.add_child(host._action_button("retry",func():
		if current.call(): _restart_attempt()))
	host._retry_cancel = func():
		if current.call(): host._start_practice(index)
	card.add_child(host._action_button("cancel",host._retry_cancel))

func _restart_attempt() -> void:
	if host.room_play:
		await host.legacy_room_flow.fork_room()
		return
	var old_data: Dictionary=host.saves.data.duplicate(true)
	if not host.attempt.get("a",{}).is_empty():
		var archive: Array=host.saves.data.get("attempt_archive",[])
		archive.append({"level_id":host.current_level.id,"attempt":host.attempt.duplicate(true)})
		host.saves.data["attempt_archive"]=archive
	var fresh := {"a":{},"b":{},"draft":{}}
	if not host.saves.save_attempt(host.current_level.id,fresh):
		host.saves.data=old_data
		host._toast(host.saves.last_error)
		return
	host.attempt=fresh
	host.role="a"
	prepare_turn()

func pause() -> void:
	if host.mode=="completion":
		show_review()
		return
	if host.mode not in ["play","preview"] or not host.running:
		return
	var previous_mode: String = host.mode
	host.running=false
	host.stick.release()
	host.action_pressed=false
	var draft_saved := save_draft()
	show_paused(previous_mode,draft_saved)

## The pause card over `previous_mode` ("play" or "preview").
func show_paused(previous_mode: String, draft_saved: bool=true) -> void:
	host.mode="paused"
	host.soundscape.stop_reunion()
	var card: VBoxContainer = host._card()
	card.add_child(host._label("There’s no hurry.",36,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_1A19AF19EDB1 if previous_mode=="preview" else (PlayerCopy.MAIN_9E4FF2796D8F if draft_saved else PlayerCopy.MAIN_359B02B14B2E)))
	card.add_child(host._action_button("resume",func(): host.mode=previous_mode; host._close_overlay(); host.running=true))
	if previous_mode=="play":
		card.add_child(host._action_button("retry",prepare_turn))
	elif _previewing_review(previous_mode):
		# A Preview from the review card keeps that card's Retry; its Cancel comes back here.
		card.add_child(host._action_button("retry",retry_review.bind(previous_mode)))
	card.add_child(host._action_button("back",host._show_home))

## Watching this turn back from its review card (Preview), as against a saved replay.
func _previewing_review(previous_mode: String) -> bool:
	return previous_mode=="preview" and not host.collection_preview and not host.review_recording.is_empty()
