extends RefCounted
## A real older empty journal for tests using immutable published recordings.
## This never changes an existing save, recording, checkpoint or authored pin.
const Registry = preload("res://services/chapter_registry.gd")
const Storage = preload("res://services/local_save.gd")
const Canonical = preload("res://core/v2/canonical.gd")

static func seed(path: String, chapter: String = Registry.RELAY) -> bool:
	if FileAccess.file_exists(path): return false
	var level := Registry.definition(chapter)
	if level.is_empty(): return false
	var value := Storage.defaults()
	value["relay"] = {"schema_version":level.schema_version,"simulation_version":level.simulation_version,
		"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"pairs":[],"a":{},"draft":{}}
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value)); file.close()
	return true
