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
	check(not entries.is_empty() and entries[0].title == "After You", "After You's own notice opens the list.")
	# A Windows checkout may hold the notice with CRLF line ends.
	var own: String = str(entries[0].text).replace("\r\n", "\n") if not entries.is_empty() else ""
	check(own.begins_with("After You\nCopyright (c) 2026 Aamir Abdul Azeez (https://aamirazeez.com)\n"), "The app opens with the project's copyright notice.")
	check(own.contains("licensed under the GNU Affero General Public License, version 3 only (AGPL-3.0-only)"), "The notice names the code license as AGPL-3.0-only.")
	check(own.contains("GNU AFFERO GENERAL PUBLIC LICENSE\n                       Version 3, 19 November 2007") and own.contains("  13. Remote Network Interaction; Use with the GNU General Public License.") and own.contains("END OF TERMS AND CONDITIONS"), "The app shows the complete AGPL-3.0 text.")
	check(own.contains("MIT license they were published with") and own.contains("hackathon-shipaton@aamirazeez.com"), "The app notes earlier MIT versions and the other licensing contact.")
	check(own.contains("# After You assets") and own.contains("All rights reserved.") and own.contains("not covered by this notice"), "The app shows the all rights reserved assets notice and its third-party exclusions.")
	check(not own.contains("PolyForm") and not own.begins_with("MIT License"), "The app no longer presents After You as PolyForm or MIT licensed.")
	check(entries.any(func(entry: Dictionary): return entry.title == "Godot Engine" and entry.text == Engine.get_license_text()), "Engine attribution must come from the running engine version.")
	check(entries.any(func(entry: Dictionary): return entry.title == "Fredoka font" and entry.text.contains("SIL OPEN FONT LICENSE Version 1.1") and entry.text.contains("Copyright 2016")), "Fredoka must retain its complete OFL and copyright.")
	check(entries.any(func(entry: Dictionary): return entry.title == "Nunito font" and entry.text.contains("SIL OPEN FONT LICENSE Version 1.1") and entry.text.contains("Copyright 2014")), "Nunito must retain its complete OFL and copyright.")
	check(entries.any(func(entry: Dictionary): return entry.title == "After You Date Pen font (from Nanum Pen Script)" and entry.text.contains("SIL OPEN FONT LICENSE Version 1.1") and entry.text.contains("Copyright (c) 2010, NHN Corporation") and entry.text.contains("Reserved Font Name Nanum")), "The date pen font must retain Nanum Pen Script's complete OFL, copyright and reserved names.")
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
