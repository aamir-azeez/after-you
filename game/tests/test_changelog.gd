extends SceneTree
## The release notes that ship with the app: every version has its entry, the
## file stays plain and in bounds, each build sees only its own paragraphs, and
## the launch decision for the one-time Home card.
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
	_malformed()
	_since()
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
		{"version": "0.7.0", "date": "2026-11-01", "paragraphs": [{"text": "Both."}, {"text": "Android words.", "ios_text": "iOS words."}, {"text": "GitHub only.", "channels": ["github"]}]},
		{"version": "0.6.9", "date": "2026-10-30", "paragraphs": [{"text": "Older."}, {"text": "Android only.", "ios_text": ""}]},
	]}

const BROKEN := ["not JSON", "extra top-level key", "wrong schema", "no entries", "extra entry key", "missing date", "bad date", "bad version", "unsorted", "duplicate version", "wrong paragraph type", "extra paragraph key", "empty text", "too long", "line break", "unknown channel", "empty channels", "repeated channel", "too many paragraphs", "too many versions"]

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
		"extra top-level key": d.extra = 1
		"wrong schema": d.schema_version = 2
		"no entries": d.entries = []
		"extra entry key": first.notes = "x"
		"missing date": first.erase("date")
		"bad date": first.date = "Oct 1"
		"bad version": first.version = "0.7"
		"unsorted": d.entries.reverse()
		"duplicate version": d.entries[1].version = "0.7.0"
		"wrong paragraph type": first.paragraphs[0] = "Both."
		"extra paragraph key": first.paragraphs[0].bold = true
		"empty text": first.paragraphs[0].text = ""
		"too long": first.paragraphs[0].text = "a".repeat(Changelog.MAX_PARAGRAPH_CHARS + 1)
		"line break": first.paragraphs[0].text = "One.
Two."
		"unknown channel": first.paragraphs[2].channels = ["web"]
		"empty channels": first.paragraphs[2].channels = []
		"repeated channel": first.paragraphs[2].channels = ["github", "github"]
		"too many paragraphs":
			for i: int in range(Changelog.MAX_PARAGRAPHS): first.paragraphs.append({"text": "More."})
		"too many versions":
			d.entries.clear()
			for i: int in range(Changelog.MAX_ENTRIES + 1):
				d.entries.append({"version": "0.%d.0" % (50 - i), "date": "2026-10-01", "paragraphs": [{"text": "One."}]})
	return JSON.stringify(d)

func _since() -> void:
	var entries: Array = []
	for version: String in ["0.7.2", "0.7.1", "0.7.0", "0.6.9", "0.6.8", "0.6.7"]:
		entries.append({"version": version, "date": "2026-10-01", "paragraphs": ["Notes for " + version]})
	_check(Changelog.since(entries, "0.7.1", "0.7.1").is_empty(), "Nothing new when the seen version is this one")
	_check(_names(Changelog.since(entries, "0.7.0", "0.7.1")) == ["0.7.1"], "One version newer shows that version")
	_check(_names(Changelog.since(entries, "0.6.7", "0.7.2")) == ["0.7.2", "0.7.1", "0.7.0"], "Five versions newer shows only the newest three")
	_check(Changelog.since(entries, "0.8.0", "0.7.2").is_empty(), "A downgrade shows nothing")
	_check(_names(Changelog.since(entries, "", "0.7.1")) == ["0.7.1"], "No seen version shows only this version")
	_check(_names(Changelog.since(entries, "0.6.9", "0.7.1")) == ["0.7.1", "0.7.0"], "Notes newer than this build are never shown")
	_check(_names(Changelog.since(entries, "0.6.8", "0.7.1")) == ["0.7.1", "0.7.0", "0.6.9"], "Every version between the seen one and this build shows, newest first")

func _names(entries: Array) -> Array:
	return entries.map(func(entry: Dictionary) -> String: return entry.version)

func _decide() -> void:
	var fresh := Changelog.decide(null, false, false, "0.7.0")
	_check(not fresh.show and fresh.remember, "A fresh install records the version and shows no card")
	var upgrade := Changelog.decide(null, true, false, "0.7.0")
	_check(upgrade.show and upgrade.since == "" and not upgrade.remember, "A save from before the card shows this version once")
	var older := Changelog.decide("0.6.9", true, false, "0.7.0")
	_check(older.show and older.since == "0.6.9", "An older seen version shows what changed since")
	var same := Changelog.decide("0.7.0", true, false, "0.7.0")
	_check(not same.show and not same.remember, "The same version does nothing")
	var downgrade := Changelog.decide("0.8.0", true, false, "0.7.0")
	_check(not downgrade.show and downgrade.remember, "A downgrade records this version without a card")
	var garbled := Changelog.decide(7, true, false, "0.7.0")
	_check(garbled.show and garbled.since == "", "A garbled saved value counts as a save from before the card")
	var locked := Changelog.decide(null, true, true, "0.7.0")
	_check(not locked.show and not locked.remember, "A read-only save never shows the card, so it can't repeat every launch")

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
			var path := Changelog.PATH.trim_prefix("res://")
			_check(_matches(include, path), "%s exports include %s" % [presets.get_value(section, "platform"), path])
			_check(not _matches(exclude, path), "%s exports do not exclude %s" % [presets.get_value(section, "platform"), path])
	_check(found >= 2, "Both the Android and iOS presets were checked")

func _matches(filters: String, path: String) -> bool:
	for pattern: String in filters.split(",", false):
		if path.match(pattern.strip_edges()): return true
	return false

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
