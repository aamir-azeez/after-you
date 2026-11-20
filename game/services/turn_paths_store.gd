extends RefCounted
## Where the squares each checked turn's pip walked persist (presentation/kit/
## turn_paths.gd): one small file per turn, named by its id's digest, written
## through atomic_file.gd, the newest MAX_FILES kept. A restart then opens a
## fog cover's history without reading or simulating the stage's turns again.
## journey_proofs.gd attaches it beside the memory traces. Drawing only.
const AtomicFile = preload("res://services/atomic_file.gd")
const TurnPaths = preload("res://presentation/kit/turn_paths.gd")
const SUFFIX := ".paths"
const MAX_FILES := 256
const MAX_BYTES := 262144
static var _folder := ""
static var _lock := Mutex.new()

## Persists walked turns under `folder` from now on.
static func attach(folder: String) -> void:
	_lock.lock()
	_folder = folder
	_lock.unlock()
	TurnPaths.persist = Callable(load("res://services/turn_paths_store.gd"), "save")
	TurnPaths.restore = Callable(load("res://services/turn_paths_store.gd"), "read")

## Stops persisting (tests).
static func detach() -> void:
	TurnPaths.persist = Callable()
	TurnPaths.restore = Callable()

static func _path(id: String) -> String:
	_lock.lock()
	var folder := _folder
	_lock.unlock()
	return "" if folder.is_empty() else folder.path_join(id.sha256_text() + SUFFIX)

static func save(id: String, bytes: PackedByteArray) -> void:
	var path := _path(id)
	if path.is_empty() or bytes.size() > MAX_BYTES: return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if AtomicFile.write_bytes(path, bytes): _prune(path.get_base_dir())

static func read(id: String) -> PackedByteArray:
	var path := _path(id)
	if path.is_empty() or not FileAccess.file_exists(path): return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	return bytes if bytes.size() <= MAX_BYTES else PackedByteArray()

## Keeps the newest MAX_FILES turns.
static func _prune(folder: String) -> void:
	var files: Array = []
	for name: String in DirAccess.get_files_at(folder):
		if name.ends_with(SUFFIX): files.append([FileAccess.get_modified_time(folder.path_join(name)), name])
	if files.size() <= MAX_FILES: return
	files.sort()
	for index in range(files.size() - MAX_FILES): DirAccess.remove_absolute(folder.path_join(files[index][1]))
