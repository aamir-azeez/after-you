extends Node
## Home, after After You closed while the camera was open: says a turn's photo is waiting and
## offers to open its room. The room's photo card then shows that photo for the same saved
## turn (reaction_photo_flow.gd). Nothing is sent from here.
signal open_requested(room_id: String)
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Capture = preload("res://services/optional_photo_capture.gd")
const Local = preload("res://services/turn_photo_local.gd")
const Resume = preload("res://services/photo_capture_resume.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
var capture_override: Node
## Native photo service override for tests; null uses the native plugin.
var native_override: Object
var resume_store: RefCounted
var modal: Control
var _parent: Control

## The newest turn of this owner still waiting for its photo, or {}. Reads the native side
## once, so a photo recovered after the restart is attached to its turn first.
func check(owner: String) -> Dictionary:
	if resume_store == null:
		resume_store = Resume.new()
	var capture: Node = capture_override if capture_override != null else Capture.new(native_override)
	if capture.get_parent() == null: add_child(capture)
	var local: Node = Local.new(capture)
	add_child(local)
	var list: Array[Dictionary] = []
	if capture.is_available():
		list = await resume_store.sync_native(owner, local.request)
	else:
		list = resume_store.entries(owner)
	local.queue_free()
	if capture != capture_override: capture.queue_free()
	return list[0] if not list.is_empty() else {}

func show_prompt(parent: Control, entry: Dictionary) -> void:
	close_prompt()
	var waiting: bool = entry.get("photo", {}) is Dictionary and not entry.get("photo", {}).is_empty()
	modal = InGameModal.open(parent, "PhotoResumeModal", PlayerCopy.PHOTO_RESUME_TITLE if waiting else PlayerCopy.PHOTO_MISSING_TITLE)
	modal.label(PlayerCopy.PHOTO_RESUME_BODY if waiting else PlayerCopy.PHOTO_RESUME_MISSING_BODY)
	var room := str(entry.get("room_id", ""))
	var open: Button = modal.add_actions(PlayerCopy.PHOTO_RESUME_OPEN, func():
		close_prompt()
		open_requested.emit(room), PlayerCopy.PHOTO_NOT_NOW)
	open.name = "PhotoResumeOpen"
	open.grab_focus()
	# Home was left another way (a notification, the rooms list): the room itself offers the
	# photo when it opens, so this prompt goes.
	_parent = parent
	parent.visibility_changed.connect(_parent_visibility_changed)

func _parent_visibility_changed() -> void:
	if is_instance_valid(_parent) and not _parent.is_visible_in_tree(): close_prompt()

## Closes the prompt and stops watching Home, so no closed prompt is ever called back.
func close_prompt() -> void:
	if is_instance_valid(modal): modal.close(false)
	modal = null
	if is_instance_valid(_parent) and _parent.visibility_changed.is_connected(_parent_visibility_changed):
		_parent.visibility_changed.disconnect(_parent_visibility_changed)
	_parent = null
