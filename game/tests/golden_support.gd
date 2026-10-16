extends RefCounted
## Shared rules for the golden safety-net suites: registry_golden, replay_golden
## (+ _physical, _journey), sound_map and world_fingerprint (+ _physical,
## _journey, _lighthouse). Each pins today's observable output so a refactor can
## prove it changed nothing. Goldens live in tests/fixtures/golden/.
##
## A golden differs: read the printed chapter and paths first. Regenerate only
## for an intended change, then review the JSON diff before committing it.
##   Direct run (writes into this checkout):
##     godot --headless --path game --script res://tests/test_<suite>.gd -- --write-golden
##   Isolated runner (it copies game/ to a temp folder and passes no arguments):
##     $env:AFTER_YOU_WRITE_GOLDEN = "<absolute path to game/tests/fixtures/golden>"
##     run-godot-suites-isolated.ps1 ... -Suites <suite>
##     Remove-Item Env:AFTER_YOU_WRITE_GOLDEN
##   AFTER_YOU_WRITE_GOLDEN=1 writes to res://tests/fixtures/golden/ instead.
## A write run compares nothing; it prints each file it wrote. sound_map reads
## the replay goldens, so regenerate those first, in an earlier runner call.
##
## Goldens hold no floats: values are rounded to integers (mm, 1/1000, 1/255)
## or tagged as "f:<value>" strings, so they match on every platform.
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Families = preload("res://services/chapter_families.gd")
const GOLDEN_DIR := "res://tests/fixtures/golden/"
const WRITE_ARGUMENT := "--write-golden"
const WRITE_ENV := "AFTER_YOU_WRITE_GOLDEN"

## Chapters whose registry outputs, replays, worlds and sounds are pinned.
const GOLDEN_KEYS: Array[String] = ["first-steps@1", "relay-isles@2", "high-and-low@1", "rolling-home@1", "a-house-for-two@1", "conservatory@1", "long-way-home@1", "the-wishing-well@1", "long-way-home@2", "turn-of-the-tide@1", "sleeping-lighthouse@2"]
## Registered chapters not pinned yet: the unreleased ones (released: false in
## their descriptor), so the goldens ignore a chapter in development. It moves
## to GOLDEN_KEYS when it ships: add its fixture chain to test_replay_golden.gd
## and test_registry_golden.gd, place it in one suite of each split, regenerate.
static var NEW_KEYS: Array[String] = Registry.UNRELEASED

static func write_mode() -> bool:
	return WRITE_ARGUMENT in OS.get_cmdline_user_args() or not OS.get_environment(WRITE_ENV).is_empty()

static func golden_path(name: String) -> String:
	var target := OS.get_environment(WRITE_ENV)
	if write_mode() and not target.is_empty() and target != "1":
		return target.path_join(name)
	return GOLDEN_DIR + name

## Every registered key is either pinned or explicitly new. Returns problems.
static func coverage_problems() -> Array[String]:
	var problems: Array[String] = []
	for key: String in Registry.keys():
		if key in GOLDEN_KEYS and key in NEW_KEYS:
			problems.append("Chapter %s is pinned in GOLDEN_KEYS in tests/golden_support.gd but unreleased in its descriptor; release it or unpin it." % key)
		elif key not in GOLDEN_KEYS and key not in NEW_KEYS:
			problems.append("Chapter %s is released but not covered by the golden suites. Add it to GOLDEN_KEYS and regenerate the goldens (see tests/golden_support.gd's header), or mark it released: false in its descriptor." % key)
	for key: String in GOLDEN_KEYS:
		if key not in Registry.keys():
			problems.append("Pinned chapter %s is no longer registered. Removing a published chapter breaks saves and rooms." % key)
	return problems

## JSON-safe, platform-stable form: sorted String keys, ints kept, floats tagged.
static func stable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = []
			for key: Variant in value: keys.append(str(key))
			keys.sort()
			var source: Dictionary = {}
			for key: Variant in value: source[str(key)] = value[key]
			var result: Dictionary = {}
			for key: String in keys: result[key] = stable(source[key])
			return result
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var result: Array = []
			for item: Variant in value: result.append(stable(item))
			return result
		TYPE_FLOAT:
			return "f:" + ("%.6f" % value)
		TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_NIL:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
	return "<%s>" % type_string(typeof(value))

## Digest that keeps int and float apart, unlike Canonical.digest.
static func typed_digest(value: Variant) -> String:
	return JSON.stringify(stable(value)).sha256_text()

static func text(value: Variant) -> String:
	return JSON.stringify(Canonical.normalized(stable(value)), "\t") + "\n"

## Compares value (a Dictionary of sections) with the named golden, or writes
## it in write mode. A difference is reported per chapter under "chapters" and
## per other section. Sections named in advisory are reported but never fail.
## Returns {"ok", "written", "messages": Array[String], "advisories": Array[String]}.
static func check(name: String, value: Dictionary, advisory: Array = []) -> Dictionary:
	var current: Dictionary = Canonical.normalized(stable(value))
	var path := golden_path(name)
	var result := {"ok": true, "written": false, "messages": [], "advisories": []}
	if write_mode():
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			result.ok = false
			result.messages.append("Could not write golden " + path)
			return result
		file.store_string(text(value))
		file.close()
		print("GOLDEN WRITTEN %s (%s)" % [path, FileAccess.get_sha256(path)])
		result.written = true
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		result.ok = false
		result.messages.append("Golden %s is missing or unreadable. Generate it deliberately (see tests/golden_support.gd)." % path)
		return result
	var expected: Dictionary = Canonical.normalized(parsed)
	if expected == current: return result
	for section: Variant in _union(expected, current):
		var old: Variant = expected.get(section)
		var now: Variant = current.get(section)
		if old == now: continue
		var target: Array = result.advisories if section in advisory else result.messages
		if section == "chapters" and old is Dictionary and now is Dictionary:
			for key: Variant in _union(old, now):
				if old.get(key) == now.get(key): continue
				var differences: Array[String] = []
				difference(old.get(key), now.get(key), "", differences, 12)
				target.append("Chapter %s differs from golden %s: %s" % [key, name, "; ".join(differences)])
		else:
			var differences: Array[String] = []
			difference(old, now, "", differences, 12)
			target.append("Section %s differs from golden %s: %s" % [section, name, "; ".join(differences)])
	result.ok = result.messages.is_empty()
	return result

static func _union(first: Dictionary, second: Dictionary) -> Array:
	var keys: Dictionary = {}
	for key: Variant in first: keys[key] = true
	for key: Variant in second: keys[key] = true
	var sorted := keys.keys()
	sorted.sort()
	return sorted

## Lists up to limit differing paths as "path: golden -> now".
static func difference(expected: Variant, current: Variant, path: String, out: Array[String], limit: int) -> void:
	if out.size() >= limit: return
	if expected is Dictionary and current is Dictionary:
		var keys: Dictionary = {}
		for key: Variant in expected: keys[key] = true
		for key: Variant in current: keys[key] = true
		var sorted := keys.keys()
		sorted.sort()
		for key: Variant in sorted:
			if out.size() >= limit: return
			if not expected.has(key): out.append("%s/%s: added" % [path, key])
			elif not current.has(key): out.append("%s/%s: removed" % [path, key])
			elif expected[key] != current[key]: difference(expected[key], current[key], "%s/%s" % [path, key], out, limit)
		return
	if expected is Array and current is Array and expected.size() == current.size():
		for index in range(expected.size()):
			if out.size() >= limit: return
			if expected[index] != current[index]: difference(expected[index], current[index], "%s[%d]" % [path, index], out, limit)
		return
	out.append("%s: %s -> %s" % [path, _short(expected), _short(current)])

static func _short(value: Variant) -> String:
	var printed := JSON.stringify(value)
	return printed if printed.length() <= 96 else printed.substr(0, 93) + "..."

## Name prefixes of a chapter's own fixtures in its family folder
## (tests/fixtures/<fixture_dir>/): "chapter" comes before definition,
## initial-checkpoint and final-checkpoint, "stages" before <stage id>-a, -b and
## -checkpoint. A first version names its stage fixtures by stage id alone; a
## later one adds "<level id>-v<version>-". {} for an unregistered key.
static func fixture_prefixes(key: String) -> Dictionary:
	var data := Index.data(key)
	if data.is_empty(): return {}
	var folder: String = Families.row(data.family).fixture_dir + "/"
	var id := key.get_slice("@", 0)
	var version := int(key.get_slice("@", 1))
	if version == 1: return {"chapter": "%s%s-" % [folder, id], "stages": folder}
	var prefix := "%s%s-v%d-" % [folder, id, version]
	return {"chapter": prefix, "stages": prefix}

static func fixture(name: String) -> Dictionary:
	var path := "res://tests/fixtures/" + name
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
