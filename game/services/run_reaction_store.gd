extends RefCounted
## What this phone keeps of reactions made during a run: each recording's track
## (services/run_reaction_track.gd), by recording hash. A saved solo turn and a
## room turn the server accepted keep their own track here, and every track a
## room read, a turn reply or a Replays list read brought is kept too, so a
## memory, a retry and a replay play the same reactions. Presentation only, like
## services/end_reaction_store.gd, whose rules it follows: every change re-reads
## the file first, so screens that each hold one of these never undo each other.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Track = preload("res://services/run_reaction_track.gd")
const FILE_PATH := "user://run-reactions.json"
const VERSION := 1
## Only recordings that carried reactions have a track; the oldest go first.
const MAX_KEPT := 512
## A room holds at most 128 turns; a server list longer than one more is refused.
const MAX_LISTED := 129

var path := FILE_PATH
var _tracks: Dictionary = {}

func _init(storage_path: String = FILE_PATH) -> void:
	path = storage_path
	_load()

## A recording's track, or [] when it has none.
func track(recording_hash: String) -> Array:
	var kept: Variant = _tracks.get(recording_hash)
	return (kept as Array).duplicate(true) if kept is Array else []

## A turn this phone made was saved, or its room turn accepted, with `entries`.
func keep(recording_hash: String, entries: Array) -> void:
	var parsed := Track.parse(entries)
	if not _hash(recording_hash) or parsed.is_empty(): return
	_load()
	_keep(recording_hash, parsed)
	_save()

## What a room read, a turn reply or a Replays list read carried
## (`run_reactions`: {schema_version 1, tracks by recording hash}). A track out
## of shape is skipped on its own; a reply without the field changes nothing.
func note(value: Variant) -> void:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not value.get("tracks") is Dictionary: return
	var listed: Dictionary = value.tracks
	if listed.is_empty() or listed.size() > MAX_LISTED: return
	_load()
	var changed := false
	for recording_hash: Variant in listed:
		var parsed := Track.parse(listed[recording_hash])
		if not _hash(recording_hash) or parsed.is_empty() or Typed.same(_tracks.get(recording_hash), parsed): continue
		_keep(recording_hash, parsed)
		changed = true
	if changed: _save()

func _keep(recording_hash: String, entries: Array) -> void:
	_tracks.erase(recording_hash)
	_tracks[recording_hash] = entries
	while _tracks.size() > MAX_KEPT: _tracks.erase(_tracks.keys()[0])

static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number()

func _load() -> void:
	var accepted: Array = [null]
	var text := AtomicFile.read_text(path, func(candidate: String) -> bool:
		accepted[0] = _parse(candidate)
		return accepted[0] != null)
	_tracks = accepted[0] if not text.is_empty() and accepted[0] is Dictionary else {}

## The tracks a saved file's text holds, or null when it is not one. Tracks
## that do not fit are dropped one by one.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK: return null
	var value: Variant = json.data
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), VERSION) or not value.get("tracks") is Dictionary: return null
	var tracks := {}
	for key: Variant in value.tracks:
		var parsed := Track.parse(value.tracks[key])
		if _hash(key) and not parsed.is_empty(): tracks[key] = parsed
	while tracks.size() > MAX_KEPT: tracks.erase(tracks.keys()[0])
	return tracks

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "tracks": _tracks}, "", false))
