extends SceneTree

const Catalog = preload("res://services/licenses.gd")
var failures: Array[String] = []

func _init() -> void:
	var entries: Array[Dictionary] = Catalog.entries()
	var titles: Dictionary = {}
	for entry in entries:
		check(entry.get("title") is String and not entry.title.is_empty(), "Every notice needs a readable title.")
		check(not titles.has(entry.title), "License titles must remain unique.")
		titles[entry.title] = true
		check(entry.get("text") is String and entry.text.length() > 100, "Every notice must include substantive text.")
		check(not entry.text.contains("unavailable in this build"), "All referenced notices must exist.")
		check(not entry.text.contains("C:/Users/") and not entry.text.contains("C:\\Users\\"), "Public notices must not expose private workspace paths.")
	for path in Catalog.file_paths():
		check(FileAccess.file_exists(path), "The exported notice file list must be complete.")
	check(entries.any(func(entry: Dictionary): return entry.title == "Godot Engine" and entry.text == Engine.get_license_text()), "Engine attribution must come from the running engine version.")
	check(entries.any(func(entry: Dictionary): return entry.title == "Fredoka font" and entry.text.contains("SIL OPEN FONT LICENSE Version 1.1") and entry.text.contains("Copyright 2016")), "Fredoka must retain its complete OFL and copyright.")
	check(entries.any(func(entry: Dictionary): return entry.title == "Nunito font" and entry.text.contains("SIL OPEN FONT LICENSE Version 1.1") and entry.text.contains("Copyright 2014")), "Nunito must retain its complete OFL and copyright.")
	check(entries.any(func(entry: Dictionary): return entry.title == "RevenueCat Android 10.15.1" and entry.text.contains("Copyright (c) 2018 RevenueCat, Inc.")), "RevenueCat must retain the SDK's own copyright notice.")
	if failures.is_empty():
		print("PASS: license catalog content, engine source, fonts and public-path checks")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
