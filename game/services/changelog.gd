extends RefCounted
## Release notes that ship with the app, from content/changelog.json (newest first).
## scripts/release-notes.ps1 prints the GitHub release text from the same file.
## Each version has a few one-line highlights, each with an icon, that every build
## shows on the What's new card, and paragraphs for the GitHub release text. A paragraph may name the builds it belongs to ("channels") and
## may carry iOS wording ("ios_text"; empty hides it on iOS). Any file that breaks
## the rules below loads as no entries, so a screen shows nothing rather than a
## broken list.
const PlatformSupport = preload("res://services/platform_support.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const VersionOrder = preload("res://services/version_order.gd")

const PATH := "res://content/changelog.json"
const SCHEMA_VERSION := 1
const MAX_ENTRIES := 12
const MAX_PARAGRAPHS := 8
const MAX_PARAGRAPH_CHARS := 700
const MAX_FILE_BYTES := 65536
const MAX_HIGHLIGHTS := 4
const MAX_HIGHLIGHT_CHARS := 60
## Icons a highlight can use: assets/ui/whats_new/<name>.svg.
const ICONS := ["spark", "leaf", "tap", "link", "sun", "people", "home", "bell", "play", "picture", "star", "key"]
## Every version's full notes. iOS builds don't link here: the GitHub pages talk
## about the Android APK.
const RELEASES_URL := "https://github.com/aamir-azeez/after-you/releases"
## Top-level key in user://journey.json: the newest version whose notes were opened.
const SAVE_KEY := "last_seen_version"

const PLAY := "play"
const GITHUB := "github"
const APP_STORE := "app_store"
const CHANNELS := [PLAY, GITHUB, APP_STORE]

static func releases_link_offered() -> bool:
	return not PlatformSupport.is_ios()

static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

## Which build this is. iOS is always the App Store build; elsewhere Google Play
## builds are "play" and the Test Store and tester APKs are "github".
static func channel(config: Dictionary) -> String:
	if PlatformSupport.is_ios() or config.get("purchase_mode") == "app_store": return APP_STORE
	return PLAY if config.get("purchase_mode") == "google_play" else GITHUB

## Entries for one build: [{"version", "date", "highlights": [{"icon", "text"}],
## "paragraphs": [String]}], newest first.
static func load_entries(build_channel: String, path: String = PATH) -> Array:
	if not FileAccess.file_exists(path): return []
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or bytes.size() > MAX_FILE_BYTES: return []
	return for_channel(parse(bytes.get_string_from_utf8()), build_channel)

## The validated entries of a changelog file, or [] when any rule is broken.
static func parse(text: String) -> Array:
	var parser := JSON.new()
	if parser.parse(text) != OK: return []
	var root: Variant = parser.data
	if not root is Dictionary or not _exact_keys(root, ["schema_version", "entries"], []): return []
	if not _whole_number(root.schema_version) or int(root.schema_version) != SCHEMA_VERSION: return []
	var entries: Variant = root.entries
	if not entries is Array or entries.is_empty() or entries.size() > MAX_ENTRIES: return []
	var previous := ""
	for entry: Variant in entries:
		if not _valid_entry(entry): return []
		if not previous.is_empty() and VersionOrder.compare(entry.version, previous) >= 0: return []
		previous = entry.version
	return entries.duplicate(true)

## Keeps the paragraphs meant for this build, in this platform's wording.
static func for_channel(entries: Array, build_channel: String) -> Array:
	var result: Array = []
	for entry: Dictionary in entries:
		var texts: Array[String] = []
		for paragraph: Dictionary in entry.paragraphs:
			if paragraph.has("channels") and build_channel not in paragraph.channels: continue
			var text := PlayerCopy.for_platform(paragraph.text, str(paragraph.get("ios_text", paragraph.text)))
			if not text.is_empty(): texts.append(text)
		if not texts.is_empty():
			result.append({"version": entry.version, "date": entry.date, "highlights": entry.highlights.duplicate(true), "paragraphs": texts})
	return result

## What to do at launch, from the saved key and whether a save existed before it:
## {"unseen": this version's notes wait to be opened, "remember": record the
## current version as already seen}.
static func decide(saved: Variant, save_existed: bool, read_only: bool, current: String) -> Dictionary:
	var result := {"unseen": false, "remember": false}
	if read_only or not VersionOrder.valid(current): return result
	if VersionOrder.valid(saved):
		var order := VersionOrder.compare(saved, current)
		if order < 0: result.unseen = true
		elif order > 0: result.remember = true
	elif save_existed:
		# A save made before the key existed: an update, so the notes are new.
		result.unseen = true
	else:
		result.remember = true
	return result

static func _valid_entry(entry: Variant) -> bool:
	if not entry is Dictionary or not _exact_keys(entry, ["version", "date", "highlights", "paragraphs"], []): return false
	if not VersionOrder.valid(entry.version) or not entry.date is String: return false
	var date := RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
	if date.search(entry.date) == null: return false
	var highlights: Variant = entry.highlights
	if not highlights is Array or highlights.is_empty() or highlights.size() > MAX_HIGHLIGHTS: return false
	for highlight: Variant in highlights:
		if not highlight is Dictionary or not _exact_keys(highlight, ["icon", "text"], []): return false
		if not highlight.icon is String or highlight.icon not in ICONS: return false
		var line: Variant = highlight.text
		if not _plain_text(line) or line.is_empty() or line.length() > MAX_HIGHLIGHT_CHARS: return false
	var paragraphs: Variant = entry.paragraphs
	if not paragraphs is Array or paragraphs.is_empty() or paragraphs.size() > MAX_PARAGRAPHS: return false
	for paragraph: Variant in paragraphs:
		if not paragraph is Dictionary or not _exact_keys(paragraph, ["text"], ["channels", "ios_text"]): return false
		if not _plain_text(paragraph.text) or paragraph.text.is_empty(): return false
		if paragraph.has("ios_text") and not _plain_text(paragraph.ios_text): return false
		if paragraph.has("channels"):
			var channels: Variant = paragraph.channels
			if not channels is Array or channels.is_empty(): return false
			var seen := {}
			for value: Variant in channels:
				if not value is String or value not in CHANNELS or seen.has(value): return false
				seen[value] = true
	return true

static func _plain_text(value: Variant) -> bool:
	return value is String and value.length() <= MAX_PARAGRAPH_CHARS and not "\n" in value and value.strip_edges() == value

static func _exact_keys(value: Dictionary, required: Array, optional: Array) -> bool:
	for key: Variant in required:
		if not value.has(key): return false
	for key: Variant in value:
		if key not in required and key not in optional: return false
	return true

static func _whole_number(value: Variant) -> bool:
	return (value is int) or (value is float and value == floorf(value))
