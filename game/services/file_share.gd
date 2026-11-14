extends RefCounted
## The single path that hands one file to the phone's own share sheet (Android's
## chooser, iOS's activity sheet): AfterYouAndroid or AfterYouIOS share_file writes
## the bytes to its own export folder and offers them. Desktop builds, and an iOS
## build older than the method, have no sheet: false, and nothing is written.
const NativeBridge = preload("res://services/native_bridge.gd")

const MIME_TYPE := "application/octet-stream"
## The plugins' own limit (Android ExportFiles via HistoryFiles.MAX_BYTES, iOS AY_EXPORT_MAX_BYTES).
const MAX_BYTES := 8 * 1024 * 1024
const MAX_NAME := 96
const NAME_PATTERN := "^[a-z0-9][a-z0-9._-]*[a-z0-9]$"

## True when `file_name` is already in the plain shape both plugins keep unchanged.
static func valid_name(file_name: String) -> bool:
	return file_name.length() <= MAX_NAME and not file_name.contains("..") and RegEx.create_from_string(NAME_PATTERN).search(file_name) != null

## True when the share sheet was asked to open with the file.
static func share_file(bytes: PackedByteArray, file_name: String) -> bool:
	if bytes.is_empty() or bytes.size() > MAX_BYTES or not valid_name(file_name): return false
	var native := NativeBridge.singleton("share")
	if not NativeBridge.has_method_on(native, "share_file"): return false
	return native.callv("share_file", [bytes, file_name, MIME_TYPE]) == true
