extends RefCounted
## Which build this is: its version and its release channel. Every request carries
## both as `X-AfterYou-Client: <version> <channel>`, so the server can tell an
## outdated build to update (services/app_status.gd) and later refuse one on a route
## it would break. No player identity is involved.
##
## Channels: Google Play builds are "play"; the GitHub tester APK (RevenueCat Test
## Store) and tester-only debug APKs are "github"; App Store builds are "app_store".
## Everything else is "dev" and is never gated: desktop runs (tests, captures, the
## editor) and iOS builds without App Store purchases. An iOS build never names Play
## or GitHub.
##
## Versions are semantic versions without build metadata (0.6.2, 0.6.2-rc.1), read
## the same way as backend/src/app-status.ts; tests/fixtures/update_gate holds the
## vectors both sides check.

const PlatformSupport = preload("res://services/platform_support.gd")
const HEADER := "X-AfterYou-Client"
const PLAY := "play"
const GITHUB := "github"
const APP_STORE := "app_store"
const DEV := "dev"
const MAX_VERSION_LENGTH := 40
const _NUMBER := "(0|[1-9][0-9]{0,3})"

## Tests set these and clear them afterwards. Empty reads the build.
static var override_version := ""
static var override_purchase_mode := ""
static var _mode_loaded := false
static var _mode := ""
static var _pattern: RegEx

static func version() -> String:
	if not override_version.is_empty(): return override_version
	return str(ProjectSettings.get_setting("application/config/version", ""))

## The channel for a platform and app_config.json purchase_mode.
static func channel_for(platform: String, purchase_mode: String) -> String:
	if platform == PlatformSupport.ANDROID:
		if purchase_mode == "google_play": return PLAY
		if purchase_mode in ["test_store", "tester_only"]: return GITHUB
	if platform == PlatformSupport.IOS and purchase_mode == "app_store": return APP_STORE
	return DEV

static func channel() -> String:
	return channel_for(PlatformSupport.platform(), purchase_mode())

## Read once: app_config.json never changes while the app runs.
static func purchase_mode() -> String:
	if not override_purchase_mode.is_empty(): return override_purchase_mode
	if not _mode_loaded:
		_mode_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://app_config.json"))
		_mode = str(parsed.get("purchase_mode", "")) if parsed is Dictionary else ""
	return _mode

## "0.6.2 play", or "" when this build's version is not a valid one (then no header is sent).
static func header_value() -> String:
	var own := version()
	return "" if parse(own).is_empty() else own + " " + channel()

## The header line for one request, or "" when there is none to send.
static func header_line() -> String:
	var value := header_value()
	return "" if value.is_empty() else HEADER + ": " + value

## {"core": [major, minor, patch], "pre": [identifiers]}, or {} for anything else.
static func parse(value: Variant) -> Dictionary:
	if not value is String or value.length() > MAX_VERSION_LENGTH: return {}
	if _pattern == null:
		_pattern = RegEx.create_from_string("^%s\\.%s\\.%s(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$" % [_NUMBER, _NUMBER, _NUMBER])
	var found := _pattern.search(value)
	if found == null: return {}
	var pre: PackedStringArray = PackedStringArray() if found.get_string(4).is_empty() else found.get_string(4).split(".")
	for part: String in pre:
		# A numeric identifier has no leading zeros (semver 9) and stays a safe size.
		if part.is_valid_int() and _digits(part) and ((part.length() > 1 and part.begins_with("0")) or part.length() > 6): return {}
	return {"core": [int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))], "pre": Array(pre)}

static func _digits(part: String) -> bool:
	for character: String in part:
		if character < "0" or character > "9": return false
	return true

## Semantic version precedence of two parsed versions: -1 older, 0 equal, 1 newer.
static func compare_parsed(a: Dictionary, b: Dictionary) -> int:
	for i in range(3):
		if a.core[i] != b.core[i]: return -1 if a.core[i] < b.core[i] else 1
	var ap: Array = a.pre
	var bp: Array = b.pre
	if ap.is_empty() or bp.is_empty():
		if ap.size() == bp.size(): return 0
		return 1 if ap.is_empty() else -1
	for i in range(mini(ap.size(), bp.size())):
		var x: String = ap[i]
		var y: String = bp[i]
		if x == y: continue
		var xn := _digits(x)
		var yn := _digits(y)
		if xn and yn: return -1 if int(x) < int(y) else 1
		if xn != yn: return -1 if xn else 1
		return -1 if x < y else 1
	if ap.size() == bp.size(): return 0
	return -1 if ap.size() < bp.size() else 1

## Compares two version strings; null when either is not a valid version.
static func compare(a: String, b: String) -> Variant:
	var left := parse(a)
	var right := parse(b)
	if left.is_empty() or right.is_empty(): return null
	return compare_parsed(left, right)
