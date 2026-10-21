extends RefCounted
## End-of-run reactions: the faces a player can pick when a run ends, and what
## this phone knows of them. Presentation only: a face is never part of a
## recording, its hash, a checkpoint or a replay's bytes. The picker and the
## bubble are presentation/end_reactions.gd.
##
## A face belongs to a run, named by its recording hash:
## - a pick not yet sent lives in memory (pick/picked), so a review card that
##   is rebuilt keeps it, and Retry or Leave simply forget it;
## - a saved solo turn, or a room turn the server accepted, keeps its face in
##   this phone's file (keep), as does every face a room read brought (note_room
##   and remember, both players' alike);
## - each room's friend face (the face on the friend's latest turn) is kept per
##   room for the room's ready and waiting cards.
## Every change re-reads the file first, so screens that each hold one of these
## never undo each other's faces.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Catalog = preload("res://services/reaction_catalog.gd")
const FILE_PATH := "user://end-reactions.json"
const VERSION := 1
## The faces and the heart: the shared catalog's (services/reaction_catalog.gd).
const FACES: Array[String] = Catalog.FACES
const HEART := Catalog.HEART
const DEFAULT_FACE := "happy"
const MAX_KEPT := 1024
const MAX_ROOMS := 128
## A room holds at most 128 turns; a server list longer than one more is refused.
const MAX_LISTED := 129
## Picks not yet sent, by run. Shared by every screen in this run of the app.
static var _picks: Dictionary = {}
const MAX_PICKS := 32

var path := FILE_PATH
var _kept: Dictionary = {}
var _partners: Dictionary = {}
var _reads: Dictionary = {}
var _last := ""

func _init(storage_path: String = FILE_PATH) -> void:
	path = storage_path
	_load()

static func is_face(value: Variant) -> bool:
	return Catalog.is_face(value)

## The spirit expression a face draws, or &"" for the heart.
static func expression(face: String) -> StringName:
	return Catalog.expression(face)

## A run's pick made on an ending card, before it is sent or saved.
static func pick(run: String, face: String) -> void:
	if run.is_empty() or not is_face(face): return
	_picks.erase(run)
	_picks[run] = face
	_trim(_picks, MAX_PICKS)

## The run's unsent pick, or "".
static func picked(run: String) -> String:
	return str(_picks.get(run, ""))

static func drop_pick(run: String) -> void:
	_picks.erase(run)

## The face a run carries: its kept face, else its unsent pick, else "".
func face(recording_hash: String) -> String:
	var kept := str(_kept.get(recording_hash, ""))
	return kept if not kept.is_empty() else picked(recording_hash)

## The kept face only: what was saved or sent, or what a room read said.
func kept(recording_hash: String) -> String:
	return str(_kept.get(recording_hash, ""))

## The last face this phone picked, for the split pill's quick half.
func last_face() -> String:
	return _last if is_face(_last) else DEFAULT_FACE

## A pick: remembered for its run and as the last face used.
func choose(run: String, face_id: String) -> void:
	if not is_face(face_id): return
	pick(run, face_id)
	_load()
	if _last == face_id: return
	_last = face_id
	_save()

## The run was saved, or its room turn accepted, with `face_id`: it is kept.
func keep(recording_hash: String, face_id: String) -> void:
	drop_pick(recording_hash)
	if not _hash(recording_hash) or not is_face(face_id): return
	_load()
	_keep(recording_hash, face_id)
	_save()

## A room's latest friend face, or "".
func partner(room_id: String) -> String:
	return str(_partners.get(room_id, ""))

## What a room read or a turn reply carried (`end_reactions`): every face of the
## room by recording hash, and the friend's latest. Unknown faces and anything
## out of shape are skipped one by one; a reply with no list changes nothing.
func note_room(room_id: String, value: Variant) -> void:
	if room_id.is_empty() or not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not value.get("faces") is Dictionary: return
	_load()
	_merge(value.faces)
	var friend: Variant = value.get("partner")
	_partners.erase(room_id)
	if is_face(friend): _partners[room_id] = friend
	_trim(_partners, MAX_ROOMS)
	_save()

## Faces a Replays list read brought for a room, and what that read covered.
func remember(faces: Variant, room_id: String = "", covered: String = "") -> void:
	_load()
	if faces is Dictionary: _merge(faces)
	if not room_id.is_empty():
		_reads.erase(room_id)
		_reads[room_id] = covered
		_trim(_reads, MAX_ROOMS)
	_save()

## Whether a room's faces should be read again: `covered` names what the room
## lists (its parts), and changes when a turn is added.
func read_wanted(room_id: String, covered: String) -> bool:
	return _reads.get(room_id) != covered

func _merge(faces: Dictionary) -> void:
	if faces.size() > MAX_LISTED: return
	for recording_hash: Variant in faces:
		if _hash(recording_hash) and is_face(faces[recording_hash]) and kept(recording_hash) != faces[recording_hash]: _keep(recording_hash, faces[recording_hash])

func _keep(recording_hash: String, face_id: String) -> void:
	_kept.erase(recording_hash)
	_kept[recording_hash] = face_id
	_trim(_kept, MAX_KEPT)

## Oldest first: a key is re-added at the end whenever it changes.
static func _trim(values: Dictionary, limit: int) -> void:
	while values.size() > limit: values.erase(values.keys()[0])

static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number()

func _load() -> void:
	# The accepted copy is parsed once: its parse is kept from the check.
	var accepted: Array = [null]
	var text := AtomicFile.read_text(path, func(candidate: String) -> bool:
		accepted[0] = _parse(candidate)
		return accepted[0] != null)
	var parsed: Variant = accepted[0] if not text.is_empty() else null
	_kept = parsed.kept if parsed != null else {}
	_partners = parsed.partners if parsed != null else {}
	_reads = parsed.reads if parsed != null else {}
	_last = parsed.last if parsed != null else ""

## The checked contents of a saved file's text, or null when it is not one.
## Entries that do not fit are dropped one by one.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK: return null
	var value: Variant = json.data
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), VERSION): return null
	for field: String in ["kept", "partners", "reads"]:
		if not value.get(field) is Dictionary: return null
	var kept_faces := {}
	for key: Variant in value.kept:
		if _hash(key) and is_face(value.kept[key]): kept_faces[key] = value.kept[key]
	var partners := {}
	for key: Variant in value.partners:
		if key is String and key.length() <= 64 and is_face(value.partners[key]): partners[key] = value.partners[key]
	var reads := {}
	for key: Variant in value.reads:
		if key is String and key.length() <= 64 and value.reads[key] is String and value.reads[key].length() <= 64: reads[key] = value.reads[key]
	_trim(kept_faces, MAX_KEPT)
	_trim(partners, MAX_ROOMS)
	_trim(reads, MAX_ROOMS)
	return {"kept": kept_faces, "partners": partners, "reads": reads, "last": value.get("last") if is_face(value.get("last")) else ""}

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "kept": _kept, "partners": _partners, "reads": _reads, "last": _last}, "", false))
