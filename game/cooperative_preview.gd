extends "res://relay_preview.gd"
## Local premium admission wraps the existing journey and chapter presentation.
## Online host access is checked by RoomV2; invited guests need no purchase.
const ChapterAccess = preload("res://services/chapter_access.gd")
var purchase_service_factory: Callable
var tester_access_factory: Callable
var admission: Node
var _prepared := false
var _admission_save_failed := false
var _held_mode := "ready"

func _ready() -> void:
	var requires_access: bool = Registry.descriptor(chapter_key).get("premium", false) and online_session == null and (OS.get_name() == "Android" or purchase_service_factory.is_valid() or tester_access_factory.is_valid())
	if not requires_access:
		_prepare_chapter()
		return
	_build_ui()
	admission = ChapterAccess.new()
	admission.purchase_service_factory = purchase_service_factory
	admission.tester_access_factory = tester_access_factory
	admission.state_changed.connect(_access_changed)
	add_child(admission)
	admission.check_access()

func _prepare_chapter() -> void:
	if _prepared: return
	if is_instance_valid(controls):
		remove_child(controls)
		controls.queue_free()
	_prepared = true
	super._ready()

func _access_changed(state: String, _reason: String) -> void:
	if _leaving or not is_inside_tree(): return
	if state == "granted":
		if not _prepared:
			_prepare_chapter()
		elif _admission_save_failed:
			_show_save_problem(journey.last_error, "review" if _held_mode in ["review", "bloom"] else "play")
		elif _held_mode in ["review", "bloom"] and not review.is_empty():
			_show_review()
		else:
			_show_ready()
		return
	if _prepared and mode != "access":
		_held_mode = mode
		if mode == "play": _admission_save_failed = not _persist_draft()
		running = false
		action_pressed = false
		stick.release()
		soundscape.stop_reunion()
		world.set_process(false)
	_show_access()

func _show_access() -> void:
	if not is_instance_valid(controls): return
	mode = "access"
	var checking: bool = is_instance_valid(admission) and admission.state == "checking"
	var reason := str(admission.reason) if is_instance_valid(admission) else "checking"
	var message := PlayerCopy.LIGHTHOUSE_PREVIEW_F16A117F0B10 if checking else PlayerCopy.LIGHTHOUSE_PREVIEW_8215C097B885
	if reason in ["provider_unavailable", "timeout"]: message = PlayerCopy.LIGHTHOUSE_PREVIEW_2485A17DBAB1
	elif reason == "purchase_revoked": message = PlayerCopy.LIGHTHOUSE_PREVIEW_1453A93A9BD0
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_95BCA9EBB0C2 if checking else "Full Journey", message)
	hud.visible = false
	var retry := _button("Check again", func(): admission.check_access(true))
	retry.disabled = checking or backgrounded
	card.add_child(retry)
	card.add_child(_action_button("back", _leave))

func _access_allowed() -> bool:
	if not is_instance_valid(admission) or admission.is_granted(): return true
	_show_access()
	return false

func _show_ready() -> void:
	if _access_allowed(): super._show_ready()

func _reset_live(resume_draft: bool = false) -> bool:
	return super._reset_live(resume_draft) if _access_allowed() else false

func _start_play() -> void:
	if _access_allowed(): super._start_play()

func _resume_draft() -> void:
	if _access_allowed(): super._resume_draft()

func advance_input(input: Dictionary) -> void:
	if _prepared and running and not backgrounded and _access_allowed(): super.advance_input(input)

func _show_local_replays() -> void:
	if _access_allowed(): super._show_local_replays()

func _watch_local_pairs(pairs: Array) -> void:
	if _access_allowed(): super._watch_local_pairs(pairs)

func _choose_local_checkpoint() -> void:
	if _access_allowed(): super._choose_local_checkpoint()

func _confirm_local_checkpoint(index: int) -> void:
	if _access_allowed(): super._confirm_local_checkpoint(index)

func _accept() -> void:
	if _access_allowed(): await super._accept()

func _start_replay(recording: Dictionary, start: Dictionary, source: Dictionary) -> void:
	if _access_allowed(): super._start_replay(recording, start, source)

func _resume_replay() -> void:
	if _access_allowed(): super._resume_replay()

func _persist_draft(after_retry: String = "play") -> bool:
	var saved := super._persist_draft(after_retry)
	_admission_save_failed = not saved
	return saved

func _process(delta: float) -> void:
	if _prepared and mode != "access": super._process(delta)

func _notification(what: int) -> void:
	if _prepared: super._notification(what)
	elif what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST] and is_instance_valid(controls): _leave()
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		backgrounded = true
		if is_instance_valid(admission): admission.set_backgrounded(true)
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		backgrounded = false
		if is_instance_valid(admission): admission.set_backgrounded(false)

func _exit_tree() -> void:
	_leaving = true
	if is_instance_valid(admission): admission.close()
	super._exit_tree()
