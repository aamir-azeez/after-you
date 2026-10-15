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
var resume_store: RefCounted
var modal: Control

## The newest turn of this owner still waiting for its photo, or {}. Reads the native side
## once, so a photo recovered after the restart is attached to its turn first.
func check(owner: String) -> Dictionary:
	if resume_store == null:
		resume_store = Resume.new()
	var capture: Node = capture_override if capture_override != null else Capture.new()
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
	if is_instance_valid(modal): modal.close(false)
	var waiting: bool = entry.get("photo", {}) is Dictionary and not entry.get("photo", {}).is_empty()
	modal = InGameModal.open(parent, "PhotoResumeModal", PlayerCopy.PHOTO_RESUME_TITLE if waiting else PlayerCopy.PHOTO_MISSING_TITLE)
	modal.label(PlayerCopy.PHOTO_RESUME_BODY if waiting else PlayerCopy.PHOTO_RESUME_MISSING_BODY)
	var room := str(entry.get("room_id", ""))
	var open: Button = modal.add_actions(PlayerCopy.PHOTO_RESUME_OPEN, func():
		if is_instance_valid(modal): modal.close(false)
		modal = null
		open_requested.emit(room), PlayerCopy.PHOTO_NOT_NOW)
	open.name = "PhotoResumeOpen"
	open.grab_focus()

func close_prompt() -> void:
	if is_instance_valid(modal): modal.close(false)
	modal = null
