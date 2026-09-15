extends VBoxContainer
## A small, independently refreshed card. It never replaces the scene or moves
## the replay cursor; optional network errors cannot block gameplay controls.
const Labels = preload("res://presentation/room_reactions.gd")
const Clock = preload("res://services/refresh_schedule.gd")
var controller: RefCounted
var _session: RefCounted
var _clock := Clock.new()
var _summary: Label
var _notice: Label
var _status: Label
var _choices: Array[Button] = []
var _check: Button
var _retry: Button
var _keep: Button
var _seen: Dictionary = {}
var _last_state: Dictionary = {}
var _first_read := true
var _alive := true

func configure(session: RefCounted, reference: Dictionary, button_factory: Callable) -> void:
	_session = session
	controller = session.create_pair_reaction_controller()
	name = "PairReactions"
	add_theme_constant_override("separation", 6)
	var heading := _label("React to stage %d" % (int(str(reference.pair_id).get_slice("-", 1)) + 1), 18)
	add_child(heading)
	_summary = _label("", 16)
	_summary.name = "PairReactionSummary"
	add_child(_summary)
	var options := HFlowContainer.new()
	add_child(options)
	for code: String in Labels.PRESETS:
		var button: Button = button_factory.call(Labels.PRESETS[code], func(): _choose(code), false)
		button.name = "PairReaction_" + code
		options.add_child(button)
		_choices.append(button)
	_notice = _label("", 16)
	_notice.name = "PairReactionNotice"
	add_child(_notice)
	_status = _label("", 15)
	_status.name = "PairReactionStatus"
	add_child(_status)
	_check = button_factory.call("Check reaction", _check_pending, false)
	_retry = button_factory.call("Retry the same reaction", _retry_pending, false)
	_keep = button_factory.call("Keep current reaction", _keep_current, false)
	for button: Button in [_check, _retry, _keep]: add_child(button)
	controller.bind(reference)
	_clock.bind(str(controller.get_instance_id()), Time.get_ticks_msec())
	_clock.request_now(Time.get_ticks_msec())
	_render()

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func request_refresh() -> void:
	_clock.request_now(Time.get_ticks_msec())

func service(now: int, eligible: bool) -> void:
	if not _alive or controller == null or not is_visible_in_tree(): return
	var ticket := _clock.begin_if_due(now, eligible, _session.photo_request_busy() or controller.busy())
	if ticket.is_empty(): return
	# Both paths are GET-only, including an uncertain selection restored cold.
	var succeeded := false
	if controller.pending().is_empty():
		succeeded = await controller.refresh()
	else:
		succeeded = await controller.check_pending()
	_clock.complete(ticket, Time.get_ticks_msec(), succeeded, controller.retry_after_ms, controller.terminal)
	if _alive and is_inside_tree(): _render(succeeded)

func _choose(code: String) -> void:
	if _session.photo_request_busy() or controller.busy(): return
	for button: Button in _choices: button.disabled = true
	_status.text = "Sending your reaction…"
	_status.show()
	var succeeded: bool = await controller.choose(code)
	if _alive and is_inside_tree(): _render(succeeded)

func _check_pending() -> void:
	if _session.photo_request_busy() or controller.busy(): return
	var succeeded: bool = await controller.check_pending()
	if _alive and is_inside_tree(): _render(succeeded)

func _retry_pending() -> void:
	if _session.photo_request_busy() or controller.busy(): return
	var succeeded: bool = await controller.retry_pending()
	if _alive and is_inside_tree(): _render(succeeded)

func _keep_current() -> void:
	if controller.keep_current_reaction(): request_refresh()
	_render()

func _render(fetched: bool = false) -> void:
	var state: Dictionary = controller.state()
	var owner: String = _session.photo_identity().get("player_id", "")
	var lines: PackedStringArray = []
	var own := ""
	for row: Dictionary in state.get("reactions", []):
		if row.player_id == owner:
			own = str(row.reaction)
			lines.append("Your reaction: " + Labels.PRESETS[row.reaction])
		else:
			lines.insert(0, "Your friend reacted: " + Labels.PRESETS[row.reaction])
			if fetched and not _first_read and _partner_changed(row):
				var notice_key := "%s:%s:%s" % [state.pair_id, row.player_id, row.reaction_revision]
				if not _seen.has(notice_key):
					while _seen.size() >= 128: _seen.erase(_seen.keys()[0])
					_seen[notice_key] = true
					_notice.text = "Your friend reacted: " + Labels.PRESETS[row.reaction]
	_summary.text = "\n".join(lines) if not lines.is_empty() else ("No reactions yet." if not state.is_empty() else "Checking this stage’s reactions…")
	if fetched and not state.is_empty():
		_first_read = false
		_last_state = state.duplicate(true)
	for button: Button in _choices:
		button.disabled = not controller.can_choose()
		button.text = Labels.PRESETS[str(button.name).trim_prefix("PairReaction_")] + (" ✓" if str(button.name) == "PairReaction_" + own else "")
	var pending: Dictionary = controller.pending()
	_check.visible = not pending.is_empty()
	_retry.visible = not pending.is_empty() and controller.retry_allowed
	_keep.visible = not pending.is_empty() and not str(pending.get("rejected", "")).is_empty()
	for button: Button in [_check, _retry, _keep]: button.disabled = controller.busy()
	_status.text = "Sending your reaction…" if controller.busy() else controller.last_error
	if _status.text.is_empty() and not pending.is_empty(): _status.text = "This reaction is not confirmed yet. Check its saved receipt."
	if _status.text.is_empty() and not _session.preset_reactions_enabled(): _status.text = "Sending reactions is currently unavailable. Saved reactions can still be read."
	_notice.visible = not _notice.text.is_empty()
	_status.visible = not _status.text.is_empty()

func _partner_changed(row: Dictionary) -> bool:
	for previous: Dictionary in _last_state.get("reactions", []):
		if previous.player_id == row.player_id:
			return int(row.reaction_revision) > int(previous.reaction_revision)
	return true

func _exit_tree() -> void:
	invalidate()

func invalidate() -> void:
	_alive = false
	if controller != null: controller.invalidate_identity()
