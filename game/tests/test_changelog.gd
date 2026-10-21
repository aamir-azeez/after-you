extends SceneTree
## The release notes that ship with the app: every version has its entry, the
## file stays plain and in bounds, highlights stay short and fit every build,
## each build sees only its own paragraphs, and the launch decision that marks an
## update's notes as unseen. The archive of older versions keeps every version
## ever shipped: the file plus the archive run unbroken back to the first one.
const Changelog = preload("res://services/changelog.gd")
const VersionOrder = preload("res://services/version_order.gd")
const PlatformSupport = preload("res://services/platform_support.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_versions()
	_shipped_file()
	_text_rules()
	_channels()
	for mode: Variant in [[1], {"x": 1}, true, 1]:
		_check(Changelog.channel({"purchase_mode": mode}) == Changelog.GITHUB, "A configuration with a wrongly typed purchase mode reads as the GitHub build")
	_highlights()
	_archive()
	_listed_versions()
	_continuity()
	_earlier()
	_malformed()
	_decide()
	_export()
	print("AFTER YOU CHANGELOG: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _versions() -> void:
	_check(VersionOrder.parse("0.6.2") == [0, 6, 2], "A plain version reads as three numbers")
	for bad: Variant in ["", "0.6", "0.6.2.1", "v0.6.2", "0.06.2", "0.6.2 ", "0.6.-1", 6, null]:
		_check(not VersionOrder.valid(bad), "Not a version: " + str(bad))
	_check(VersionOrder.compare("0.6.2", "0.6.10") == -1, "Versions compare by number, not by text")
	_check(VersionOrder.compare("1.0.0", "0.99.99") == 1, "A major version outranks the minor and patch")
	_check(VersionOrder.compare("0.6.2", "0.6.2") == 0, "Equal versions compare equal")
	_check(VersionOrder.compare("bad", "0.6.2") == 0, "An invalid version never reads as newer or older")

func _shipped_file() -> void:
	var raw := Changelog.parse(FileAccess.get_file_as_string(Changelog.PATH))
	_check(not raw.is_empty(), "The shipped changelog passes the strict loader")
	_check(FileAccess.get_file_as_bytes(Changelog.PATH).size() <= Changelog.MAX_FILE_BYTES, "The shipped changelog stays under its size limit")
	if raw.is_empty(): return
	var current := Changelog.current_version()
	# The guard that a release commit added its notes along with the version bump.
	_check(raw[0].version == current, "The newest changelog entry is this build's version (%s), found %s" % [current, raw[0].version])
	_check(raw.size() <= Changelog.MAX_ENTRIES, "The app keeps at most %d versions" % Changelog.MAX_ENTRIES)
	for channel: String in Changelog.CHANNELS:
		for platform: String in [PlatformSupport.ANDROID, PlatformSupport.IOS]:
			PlatformSupport.override_platform = platform
			var visible := Changelog.for_channel(raw, channel)
			_check(not visible.is_empty() and visible[0].version == current, "This version has notes for %s on %s" % [channel, platform])
	PlatformSupport.override_platform = ""

func _text_rules() -> void:
	var raw := Changelog.parse(FileAccess.get_file_as_string(Changelog.PATH))
	var url := RegEx.create_from_string("https?://|www\\.|\\.com\\b")
	for entry: Dictionary in raw:
		for paragraph: Dictionary in entry.paragraphs:
			for field: String in ["text", "ios_text"]:
				if not paragraph.has(field): continue
				var text: String = paragraph[field]
				var where := "%s %s: %s" % [entry.version, field, text.left(40)]
				for mark: String in ["—", "–", " -- ", "**", "<", ">", "[", "`", "“", "”"]:
					_check(not mark in text, "Notes stay plain, without '%s': %s" % [mark, where])
				_check(not text.begins_with("#") and not text.begins_with("- "), "Notes are paragraphs, not headings or lists: " + where)
				_check(url.search(text) == null, "Notes carry no links: " + where)
				_check(text.is_empty() or text.ends_with(".") or text.ends_with("?"), "Each paragraph ends a sentence: " + where)

func _channels() -> void:
	var raw := Changelog.parse(FileAccess.get_file_as_string(Changelog.PATH))
	var store_words := ["Test Store", "tester", "APK", "RevenueCat"]
	var platform_words := ["Android", "Google Play", "Play Store", "APK", "Play Console"]
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	var github := _all_text(Changelog.for_channel(raw, Changelog.GITHUB))
	var play := _all_text(Changelog.for_channel(raw, Changelog.PLAY))
	_check(github.contains("RevenueCat Test Store"), "GitHub builds show the Test Store note")
	for word: String in store_words:
		_check(not play.containsn(word), "Google Play builds never mention: " + word)
	PlatformSupport.override_platform = PlatformSupport.IOS
	var ios := _all_text(Changelog.for_channel(raw, Changelog.APP_STORE))
	for word: String in platform_words + store_words:
		_check(not ios.containsn(word), "iOS notes never mention: " + word)
	_check(Changelog.channel({"purchase_mode": "google_play"}) == Changelog.APP_STORE, "An iOS build is always the App Store build")
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	_check(Changelog.channel({"purchase_mode": "google_play"}) == Changelog.PLAY, "A Google Play build reads the Play notes")
	for mode: String in ["test_store", "tester_only", ""]:
		_check(Changelog.channel({"purchase_mode": mode}) == Changelog.GITHUB, "A %s build reads the GitHub notes" % mode)
	_check(Changelog.channel({"purchase_mode": "app_store"}) == Changelog.APP_STORE, "The App Store purchase mode reads the App Store notes")
	PlatformSupport.override_platform = ""
	# Filtering on a small file: the GitHub-only paragraph and the iOS wording.
	var sample := Changelog.parse(JSON.stringify(_sample()))
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	_check(Changelog.for_channel(sample, Changelog.PLAY)[0].paragraphs == ["Both.", "Android words."], "A GitHub-only paragraph is absent from the Play list, and Android keeps its own wording")
	_check(Changelog.for_channel(sample, Changelog.GITHUB)[0].paragraphs == ["Both.", "Android words.", "GitHub only."], "A GitHub-only paragraph is present in the GitHub list")
	PlatformSupport.override_platform = PlatformSupport.IOS
	_check(Changelog.for_channel(sample, Changelog.APP_STORE)[0].paragraphs == ["Both.", "iOS words."], "iOS reads the iOS wording and skips the GitHub paragraph")
	_check(Changelog.for_channel(sample, Changelog.APP_STORE)[1].paragraphs == ["Older."], "An empty iOS wording hides that paragraph on iOS")
	PlatformSupport.override_platform = ""

func _all_text(entries: Array) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append_array(entry.paragraphs)
	return "\n".join(parts)

func _sample() -> Dictionary:
	return {"schema_version": 1, "entries": [
		{"version": "0.7.0", "date": "2026-11-01", "highlights": [{"icon": "spark", "text": "First line"}, {"icon": "leaf", "text": "Second line"}], "paragraphs": [{"text": "Both."}, {"text": "Android words.", "ios_text": "iOS words."}, {"text": "GitHub only.", "channels": ["github"]}]},
		{"version": "0.6.9", "date": "2026-10-30", "highlights": [{"icon": "sun", "text": "Older line"}], "paragraphs": [{"text": "Older."}, {"text": "Android only.", "ios_text": ""}]},
	]}

func _highlights() -> void:
	var raw := Changelog.parse(FileAccess.get_file_as_string(Changelog.PATH))
	_highlight_rules(raw)
	_highlight_rules(Changelog.load_archive())
	PlatformSupport.override_platform = PlatformSupport.IOS
	var ios := Changelog.for_channel(raw, Changelog.APP_STORE)
	PlatformSupport.override_platform = ""
	var play := Changelog.for_channel(raw, Changelog.PLAY)
	_check(not raw.is_empty() and ios[0].highlights == raw[0].highlights and play[0].highlights == raw[0].highlights, "Every build shows the same highlights")
	var sample := Changelog.for_channel(Changelog.parse(JSON.stringify(_sample())), Changelog.GITHUB)
	_check(sample[0].highlights == [{"icon": "spark", "text": "First line"}, {"icon": "leaf", "text": "Second line"}], "The loader hands over the highlights and their icons in order")
	for name: String in Changelog.ICONS + ["gift"]:
		_check(ResourceLoader.exists("res://assets/ui/whats_new/%s.svg" % name), "The What's new icon ships: " + name)

## Highlights show on every build, so they never name a store, a platform or a
## test build; the archived ones keep the same rules.
func _highlight_rules(entries: Array) -> void:
	var banned := ["Test Store", "tester", "APK", "RevenueCat", "Android", "Google Play", "Play Store", "iOS", "iPhone", "App Store", "GitHub"]
	for entry: Dictionary in entries:
		var lines: Array = entry.highlights
		_check(lines.size() >= 1 and lines.size() <= Changelog.MAX_HIGHLIGHTS, "%s has one to %d highlights" % [entry.version, Changelog.MAX_HIGHLIGHTS])
		var seen := {}
		for item: Dictionary in lines:
			var line: String = item.text
			var where := "%s: %s" % [entry.version, line]
			_check(item.icon in Changelog.ICONS and ResourceLoader.exists("res://assets/ui/whats_new/%s.svg" % item.icon), "A highlight's icon is in the set and ships: " + where)
			_check(line.length() <= Changelog.MAX_HIGHLIGHT_CHARS, "A highlight fits one short line: " + where)
			_check(line.left(1) == line.left(1).to_upper(), "A highlight starts with a capital: " + where)
			_check(not line.ends_with(".") and not line.ends_with("!"), "A highlight is a line, not a sentence: " + where)
			for mark: String in ["—", "–", " - ", "**", "<", "`", "“", "”", "!"]:
				_check(not mark in line, "A highlight stays plain, without '%s': %s" % [mark, where])
			for word: String in banned:
				_check(not line.containsn(word), "A highlight never mentions %s: %s" % [word, where])
			_check(not seen.has(line), "Highlights don't repeat: " + where)
			seen[line] = true

## The first published release, and the versions that never had a published
## release: 0.1.0 to 0.1.2 came before it, 0.2.0 shipped only as previews (1, 4
## and 7 unpublished), and 0.4.6 was a Story build that was never released. A
## version skipped from now on is added here on purpose.
const FIRST_VERSION := "0.1.3"
const NEVER_RELEASED := ["0.1.0", "0.1.1", "0.1.2", "0.2.0-preview1", "0.2.0-preview4", "0.2.0-preview7", "0.2.0", "0.2.2", "0.4.6", "0.4.17"]

func _archive() -> void:
	var bytes := FileAccess.get_file_as_bytes(Changelog.ARCHIVE_PATH)
	_check(not bytes.is_empty() and bytes.size() <= Changelog.MAX_ARCHIVE_BYTES, "The shipped archive exists and stays under its size limit")
	var archive := Changelog.parse_archive(bytes.get_string_from_utf8())
	_check(not archive.is_empty(), "The shipped archive passes its strict loader")
	_check(archive == Changelog.load_archive(), "The archive loads from its own path")
	_check(Changelog.parse_archive(JSON.stringify({"schema_version": 1, "entries": []})) == [], "An empty archive is valid and lists nothing")
	_check(not Changelog.parse_archive(JSON.stringify(_archive_sample())).is_empty(), "The sample archive is valid")
	var previews := _archive_sample()
	previews.entries.insert(1, {"version": "0.6.8-preview10", "date": "2026-10-19", "highlights": [{"icon": "spark", "text": "Tenth preview"}]})
	previews.entries.insert(2, {"version": "0.6.8-preview9", "date": "2026-10-19", "highlights": [{"icon": "spark", "text": "Ninth preview"}]})
	_check(Changelog.parse_archive(JSON.stringify(previews)).size() == 4, "The archive lists preview builds below their release, by number")
	for name: String in ARCHIVE_BROKEN:
		_check(Changelog.parse_archive(_broken_archive(name)).is_empty(), "A broken archive loads as no entries: " + name)
	_check(Changelog.load_archive("res://content/missing-archive.json").is_empty(), "A missing archive loads as no entries")

## Archive names: a plain version or exactly x.y.z-previewN, a preview older than
## its release and previews ordered by number. The plain comparer is unchanged.
func _listed_versions() -> void:
	_check(VersionOrder.parse_listed("0.2.0-preview9") == [0, 2, 0, 9] and VersionOrder.parse_listed("0.4.16") == [0, 4, 16, 0], "A preview reads as its release and its number")
	for bad: Variant in ["0.2.0-preview0", "0.2.0-preview01", "0.2.0-preview", "0.2.0-Preview2", "0.2.0-preview-2", "0.2.0-rc.1", "0.2.0-preview2.1", "0.2", "", 2]:
		_check(VersionOrder.parse_listed(bad).is_empty(), "Only exact preview names read: " + str(bad))
	_check(VersionOrder.compare_listed("0.2.0-preview9", "0.2.0-preview10") < 0, "Preview 9 is older than preview 10")
	_check(VersionOrder.compare_listed("0.2.0-preview9", "0.2.0") < 0 and VersionOrder.compare_listed("0.2.0", "0.2.0-preview9") > 0, "A preview is older than its release")
	_check(VersionOrder.compare_listed("0.1.3", "0.2.0-preview2") < 0 and VersionOrder.compare_listed("0.2.0-preview9", "0.2.1") < 0, "A preview sits between the versions around its release")
	_check(VersionOrder.compare_listed("0.2.0-preview3", "0.2.0-preview3") == 0 and VersionOrder.compare_listed("0.4.16", "0.4.15") > 0, "Equal and plain names compare as before")
	_check(not VersionOrder.valid("0.2.0-preview9") and VersionOrder.compare("0.2.0-preview9", "0.1.3") == 0, "The plain comparer still reads plain names only")

## The newest file and the archive together hold every version back to the first,
## newest first with no repeats, and a version leaves the file only into the
## archive: each step down the list is the release right before it.
func _continuity() -> void:
	var file := Changelog.parse(FileAccess.get_file_as_string(Changelog.PATH))
	var archive := Changelog.load_archive()
	_check(not file.is_empty(), "The file is there to join to the archive")
	if file.is_empty(): return
	var versions: Array[String] = []
	for entry: Dictionary in file + archive: versions.append(str(entry.version))
	_check(versions[-1] == FIRST_VERSION, "Every version back to %s stays listed; the oldest is %s" % [FIRST_VERSION, versions[-1]])
	if not archive.is_empty():
		_check(file.size() == Changelog.MAX_ENTRIES, "The archive takes versions only from a full file (%d of %d)" % [file.size(), Changelog.MAX_ENTRIES])
		_check(VersionOrder.compare_listed(archive[0].version, file[-1].version) < 0, "The archive starts below the file's oldest version")
	for version: String in versions:
		_check(version not in NEVER_RELEASED, "A version listed as never released is not in the list: " + version)
	for index: int in range(1, versions.size()):
		var newer := versions[index - 1]
		var older := versions[index]
		_check(VersionOrder.compare_listed(older, newer) < 0, "Versions run newest first without repeats: %s then %s" % [newer, older])
		_check(_follows(older, newer), "%s comes right after %s. A release that drops the file's oldest entry moves its version, date and highlights to the top of content/changelog_archive.json" % [newer, older])
	var chain := Changelog.earlier_entries(Changelog.current_version())
	var listed: Array[String] = []
	for entry: Dictionary in chain: listed.append(str(entry.version))
	_check(listed == versions.slice(1), "Earlier versions lists every version before this one, newest first")

## True when `newer` is the release right after `older`, stepping over versions
## that were never released. After x.y.z comes the next patch, minor or major, or
## the first preview of one; after a preview comes the next preview or its release.
func _follows(older: String, newer: String) -> bool:
	var frontier: Array[String] = [older]
	for guard: int in range(NEVER_RELEASED.size() + 1):
		var skipped: Array[String] = []
		for step: String in frontier:
			for next: String in _next_versions(step):
				if next == newer: return true
				if next in NEVER_RELEASED and next not in skipped: skipped.append(next)
		if skipped.is_empty(): return false
		frontier = skipped
	return false

func _next_versions(version: String) -> Array[String]:
	var v := VersionOrder.parse_listed(version)
	var result: Array[String] = []
	if v.is_empty(): return result
	if v[3] > 0:
		result.append("%d.%d.%d-preview%d" % [v[0], v[1], v[2], v[3] + 1])
		result.append("%d.%d.%d" % [v[0], v[1], v[2]])
		return result
	for release: String in ["%d.%d.%d" % [v[0], v[1], v[2] + 1], "%d.%d.0" % [v[0], v[1] + 1], "%d.0.0" % [v[0] + 1]]:
		result.append(release)
		result.append(release + "-preview1")
	return result

## Earlier versions on small files: the rest of the file, then an archive that
## fits below it. A missing, broken or overlapping archive leaves the file's rows.
func _earlier() -> void:
	var stamp := Crypto.new().generate_random_bytes(6).hex_encode()
	var file := "user://changelog-file-test-%s.json" % stamp
	var path := "user://changelog-archive-test-%s.json" % stamp
	var missing := "res://content/missing-archive.json"
	_write(file, JSON.stringify(_sample()))
	var file_rows := [{"version": "0.6.9", "date": "2026-10-30", "highlights": [{"icon": "sun", "text": "Older line"}]}]
	_check(Changelog.earlier_entries("0.7.0", file, missing) == file_rows, "Without an archive, Earlier versions lists the rest of the file")
	_check(Changelog.earlier_entries("0.6.9", file, missing) == [], "The oldest version has nothing before it")
	_check(Changelog.earlier_entries("bad", file, missing) == [], "A garbled current version lists nothing")
	var entries := Changelog.load_entries(Changelog.GITHUB, file)
	_check(Changelog.has_earlier(entries, missing), "A file with two versions has earlier ones")
	_check(not Changelog.has_earlier(entries.slice(0, 1), missing), "One version and no archive has none")
	_write(path, JSON.stringify(_archive_sample()))
	var joined := Changelog.earlier_entries("0.7.0", file, path)
	_check(joined.size() == 3 and joined[0].version == "0.6.9" and joined[1].version == "0.6.8" and joined[2].version == "0.6.7", "The archive follows the file, newest first")
	_check(Changelog.has_earlier(entries.slice(0, 1), path), "An archive alone counts as earlier versions")
	_write(path, "{")
	_check(Changelog.earlier_entries("0.7.0", file, path) == file_rows, "A broken archive leaves only the file's rows")
	var overlap := _archive_sample()
	overlap.entries[0].version = "0.6.9"
	_write(path, JSON.stringify(overlap))
	_check(Changelog.earlier_entries("0.7.0", file, path) == file_rows, "An archive that repeats the file's oldest version is left out")
	overlap.entries[0].version = "0.7.5"
	overlap.entries[1].version = "0.7.4"
	_write(path, JSON.stringify(overlap))
	_check(Changelog.earlier_entries("0.7.0", file, path) == file_rows, "An archive newer than the file's oldest version is left out")
	_write(path, "x".repeat(Changelog.MAX_ARCHIVE_BYTES + 1))
	_check(Changelog.load_archive(path).is_empty(), "An archive over its size limit loads as no entries")
	# A version whose paragraphs are all for one build still lists on every build.
	var narrow := _sample()
	narrow.entries[1].paragraphs = [{"text": "GitHub only.", "channels": ["github"]}]
	_write(file, JSON.stringify(narrow))
	_check(Changelog.load_entries(Changelog.PLAY, file).size() == 1 and Changelog.earlier_entries("0.7.0", file, missing) == file_rows, "A version with no Play paragraphs still lists under Earlier versions")
	# A build that hides paid content (paid_hidden) leaves out paid lines, never a
	# version's card while a free highlight is left.
	var paid := _sample()
	paid.entries[0].highlights[1].paid = true
	for paragraph: Dictionary in paid.entries[0].paragraphs: paragraph.paid = true
	paid.entries[1].highlights[0].paid = true
	_write(file, JSON.stringify(paid))
	PlatformSupport.override_platform = PlatformSupport.IOS
	var free := Changelog.load_entries(Changelog.APP_STORE, file, true)
	_check(free.size() == 1 and free[0].version == "0.7.0" and free[0].highlights == [{"icon": "spark", "text": "First line"}] and free[0].paragraphs.is_empty(), "With every paragraph paid, this version still opens on its free highlights")
	_check(Changelog.load_entries(Changelog.APP_STORE, file).size() == 2 and Changelog.load_entries(Changelog.APP_STORE, file)[0].paragraphs == ["Both.", "iOS words."], "Without the rule paid lines stay")
	PlatformSupport.override_platform = ""
	_check(Changelog.earlier_entries("0.7.0", file, missing, true) == [] and Changelog.earlier_entries("0.7.0", file, missing).size() == 1, "A version left with no free highlight is not listed")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(file)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _archive_sample() -> Dictionary:
	return {"schema_version": 1, "entries": [
		{"version": "0.6.8", "date": "2026-10-20", "highlights": [{"icon": "star", "text": "Archived line"}]},
		{"version": "0.6.7", "date": "2026-10-19", "highlights": [{"icon": "leaf", "text": "Oldest line"}, {"icon": "tap", "text": "Another line"}]},
	]}

const ARCHIVE_BROKEN := ["not JSON", "not an object", "extra top-level key", "wrong schema", "entries not a list", "too many versions", "entry not an object", "paragraphs kept", "missing date", "bad date", "bad version", "unsorted", "duplicate version", "no highlights", "unknown icon", "long highlight", "highlight line break", "preview zero", "preview leading zero", "preview without number", "capital preview", "other prerelease", "preview above its release", "previews unsorted", "paid not true"]

func _broken_archive(name: String) -> String:
	var d := _archive_sample()
	var first: Dictionary = d.entries[0]
	match name:
		"not JSON": return "{"
		"not an object": return "[]"
		"extra top-level key": d.extra = 1
		"wrong schema": d.schema_version = 2
		"entries not a list": d.entries = {}
		"too many versions":
			d.entries.clear()
			for i: int in range(Changelog.MAX_ARCHIVE_ENTRIES + 1):
				d.entries.append({"version": "0.%d.0" % (2000 - i), "date": "2026-10-01", "highlights": [{"icon": "spark", "text": "One"}]})
		"entry not an object": d.entries[1] = "0.6.7"
		"paragraphs kept": first.paragraphs = [{"text": "One."}]
		"missing date": first.erase("date")
		"bad date": first.date = "Oct 1"
		"bad version": first.version = "0.6"
		"unsorted": d.entries.reverse()
		"duplicate version": d.entries[1].version = "0.6.8"
		"no highlights": first.highlights = []
		"paid not true": first.highlights[0].paid = false
		"unknown icon": first.highlights[0].icon = "rocket"
		"long highlight": first.highlights[0].text = "a".repeat(Changelog.MAX_HIGHLIGHT_CHARS + 1)
		"highlight line break": first.highlights[0].text = "One\nTwo"
		"preview zero": d.entries[1].version = "0.6.7-preview0"
		"preview leading zero": d.entries[1].version = "0.6.7-preview01"
		"preview without number": d.entries[1].version = "0.6.7-preview"
		"capital preview": d.entries[1].version = "0.6.7-Preview2"
		"other prerelease": d.entries[1].version = "0.6.7-rc.1"
		"preview above its release": first.version = "0.6.7-preview1"
		"previews unsorted":
			first.version = "0.6.7-preview9"
			d.entries[1].version = "0.6.7-preview10"
	return JSON.stringify(d)

const BROKEN := ["missing highlights", "no highlights", "too many highlights", "long highlight", "highlight not text", "empty highlight", "highlight line break", "unknown icon", "highlight extra key", "highlight without icon", "not JSON", "extra top-level key", "wrong schema", "no entries", "extra entry key", "missing date", "bad date", "bad version", "unsorted", "duplicate version", "wrong paragraph type", "extra paragraph key", "empty text", "too long", "line break", "unknown channel", "empty channels", "repeated channel", "too many paragraphs", "too many versions", "preview version", "highlight paid not true", "paragraph paid not true"]

func _malformed() -> void:
	_check(not Changelog.parse(JSON.stringify(_sample())).is_empty(), "The sample file is valid")
	for name: String in BROKEN:
		_check(Changelog.parse(_broken(name)).is_empty(), "A broken file loads as no entries: " + name)
	_check(Changelog.load_entries(Changelog.GITHUB, "res://content/missing-changelog.json").is_empty(), "A missing file loads as no entries")

func _broken(name: String) -> String:
	var d := _sample()
	var first: Dictionary = d.entries[0]
	match name:
		"not JSON": return "{"
		"missing highlights": first.erase("highlights")
		"no highlights": first.highlights = []
		"too many highlights":
			for i: int in range(Changelog.MAX_HIGHLIGHTS): first.highlights.append({"icon": "spark", "text": "More %d" % i})
		"long highlight": first.highlights[0].text = "a".repeat(Changelog.MAX_HIGHLIGHT_CHARS + 1)
		"highlight not text": first.highlights = ["First line"]
		"empty highlight": first.highlights[0].text = ""
		"highlight line break": first.highlights[0].text = "One\nTwo"
		"unknown icon": first.highlights[0].icon = "rocket"
		"highlight extra key": first.highlights[0].bold = true
		"highlight without icon": first.highlights[0].erase("icon")
		"highlight paid not true": first.highlights[0].paid = false
		"paragraph paid not true": first.paragraphs[0].paid = "yes"
		"extra top-level key": d.extra = 1
		"wrong schema": d.schema_version = 2
		"no entries": d.entries = []
		"extra entry key": first.notes = "x"
		"missing date": first.erase("date")
		"bad date": first.date = "Oct 1"
		"bad version": first.version = "0.7"
		"preview version": first.version = "0.7.0-preview1"
		"unsorted": d.entries.reverse()
		"duplicate version": d.entries[1].version = "0.7.0"
		"wrong paragraph type": first.paragraphs[0] = "Both."
		"extra paragraph key": first.paragraphs[0].bold = true
		"empty text": first.paragraphs[0].text = ""
		"too long": first.paragraphs[0].text = "a".repeat(Changelog.MAX_PARAGRAPH_CHARS + 1)
		"line break": first.paragraphs[0].text = "One.\nTwo."
		"unknown channel": first.paragraphs[2].channels = ["web"]
		"empty channels": first.paragraphs[2].channels = []
		"repeated channel": first.paragraphs[2].channels = ["github", "github"]
		"too many paragraphs":
			for i: int in range(Changelog.MAX_PARAGRAPHS): first.paragraphs.append({"text": "More."})
		"too many versions":
			d.entries.clear()
			for i: int in range(Changelog.MAX_ENTRIES + 1):
				d.entries.append({"version": "0.%d.0" % (50 - i), "date": "2026-10-01", "highlights": [{"icon": "spark", "text": "One"}], "paragraphs": [{"text": "One."}]})
	return JSON.stringify(d)

func _decide() -> void:
	var fresh := Changelog.decide(null, false, false, "0.7.0")
	_check(not fresh.unseen and fresh.remember, "A fresh install records the version and has nothing unseen")
	var upgrade := Changelog.decide(null, true, false, "0.7.0")
	_check(upgrade.unseen and not upgrade.remember, "A save from before the key marks this version's notes unseen")
	var older := Changelog.decide("0.6.9", true, false, "0.7.0")
	_check(older.unseen and not older.remember, "An older seen version marks the notes unseen")
	var same := Changelog.decide("0.7.0", true, false, "0.7.0")
	_check(not same.unseen and not same.remember, "The same version does nothing")
	var downgrade := Changelog.decide("0.8.0", true, false, "0.7.0")
	_check(not downgrade.unseen and downgrade.remember, "A downgrade records this version with nothing unseen")
	var garbled := Changelog.decide(7, true, false, "0.7.0")
	_check(garbled.unseen, "A garbled saved value counts as a save from before the key")
	var locked := Changelog.decide(null, true, true, "0.7.0")
	_check(not locked.unseen and not locked.remember, "A read-only save never marks notes unseen, since opening them can't be saved")

func _export() -> void:
	# Desktop tests read res:// from disk; the phone builds only carry what the
	# export filters let through.
	var presets := ConfigFile.new()
	_check(presets.load("res://export_presets.cfg") == OK, "Export presets load")
	var found := 0
	for section: String in presets.get_sections():
		if not section.ends_with(".options") and presets.has_section_key(section, "platform"):
			found += 1
			var include := str(presets.get_value(section, "include_filter", ""))
			var exclude := str(presets.get_value(section, "exclude_filter", ""))
			for shipped: String in [Changelog.PATH, Changelog.ARCHIVE_PATH]:
				var path := shipped.trim_prefix("res://")
				_check(_matches(include, path), "%s exports include %s" % [presets.get_value(section, "platform"), path])
				_check(not _matches(exclude, path), "%s exports do not exclude %s" % [presets.get_value(section, "platform"), path])
	_check(found >= 2, "Both the Android and iOS presets were checked")
	var android_exclude := str(presets.get_value("preset.0", "exclude_filter", ""))
	for kept_out: String in ["tests/test_changelog.gd", "content/campaigns/a-place-for-two-v1.json", "content/compatibility/a-place-for-two-definition-v1.json"]:
		_check(_matches(android_exclude, kept_out), "Android exports leave out " + kept_out)
	_check(presets.get_value("preset.1", "platform", "") == "iOS", "The iOS preset follows Android")
	_check(str(presets.get_value("preset.1", "exclude_filter", "")) == android_exclude and presets.get_value("preset.1", "include_filter", "") == presets.get_value("preset.0", "include_filter", ""), "iOS ships exactly the files Android ships")
	_check(presets.get_value("preset.1.options", "application/bundle_identifier", "") == presets.get_value("preset.0.options", "package/unique_name", "x"), "The iOS bundle id matches the Android package")

func _matches(filters: String, path: String) -> bool:
	for pattern: String in filters.split(",", false):
		if path.match(pattern.strip_edges()): return true
	return false

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
