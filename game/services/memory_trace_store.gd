extends RefCounted
## Where open turns' checked turns persist (core/physical/memory_trace.gd): one
## file per turn, named by its id's digest, written through atomic_file.gd,
## the newest MAX_FILES kept. journey_proofs.gd attaches it beside the proofs.
const AtomicFile = preload("res://services/atomic_file.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const SUFFIX := ".trace"
const MAX_FILES := 8
static var _folder := ""
static var _lock := Mutex.new()

## Persists kept turns under `folder` from now on.
static func attach(folder: String) -> void:
	_lock.lock()
	_folder = folder
	_lock.unlock()
	MemoryTrace._lock.lock()
	MemoryTrace.persist = Callable(load("res://services/memory_trace_store.gd"), "save")
	MemoryTrace.restore = Callable(load("res://services/memory_trace_store.gd"), "read")
	MemoryTrace._lock.unlock()

## Stops persisting (tests).
static func detach() -> void:
	MemoryTrace._lock.lock()
	MemoryTrace.persist = Callable()
	MemoryTrace.restore = Callable()
	MemoryTrace._lock.unlock()

static func _path(id: String) -> String:
	_lock.lock()
	var folder := _folder
	_lock.unlock()
	return "" if folder.is_empty() else folder.path_join(id.sha256_text() + SUFFIX)

static func save(id: String, bytes: PackedByteArray) -> void:
	var path := _path(id)
	if path.is_empty(): return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if AtomicFile.write_bytes(path, bytes): _prune(path.get_base_dir())

static func read(id: String) -> PackedByteArray:
	var path := _path(id)
	if path.is_empty() or not FileAccess.file_exists(path): return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)

## Keeps the newest MAX_FILES turns.
static func _prune(folder: String) -> void:
	var files: Array = []
	for name: String in DirAccess.get_files_at(folder):
		if name.ends_with(SUFFIX): files.append([FileAccess.get_modified_time(folder.path_join(name)), name])
	if files.size() <= MAX_FILES: return
	files.sort()
	for index in range(files.size() - MAX_FILES): DirAccess.remove_absolute(folder.path_join(files[index][1]))
