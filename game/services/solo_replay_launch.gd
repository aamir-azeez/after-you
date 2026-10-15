extends RefCounted
## The one hand-off from a solo Watch replay tap to the chapter scene it opens.
## Main writes the replay context file and says this open is a replay; the
## chapter scene claims that request once and reads the file only then. Any
## file left by an open that never finished is removed, so it can never block
## another chapter or room.
const PATH := "user://solo-replay-playback.json"
const MAX_BYTES := 2097152
static var _requested := false

## Writes the context for the scene about to open and marks the open as a replay.
static func write(context: Dictionary) -> bool:
	_requested = false
	var bytes := JSON.stringify(context).to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return false
	var temporary := PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if not okay:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	if FileAccess.file_exists(PATH) and DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH)) != OK: return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(PATH)) != OK: return false
	_requested = true
	return true

## True once for the scene the replay open is for. An online screen never
## plays a solo replay; any other screen removes a leftover file instead.
static func claim(online: bool) -> bool:
	var requested := _requested and not online
	_requested = false
	if not requested: discard()
	return requested

## Removes the context and its request, whatever state the open ended in.
static func discard() -> void:
	_requested = false
	for path: String in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
