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
## Versions are semantic versions without build metadata (0.6.2, 0.6.2-rc.1), read by
## the shared services/version_order.gd the same way as backend/src/app-status.ts.

const PlatformSupport = preload("res://services/platform_support.gd")
const VersionOrder = preload("res://services/version_order.gd")
const HEADER := "X-AfterYou-Client"
const PLAY := "play"
const GITHUB := "github"
const APP_STORE := "app_store"
const DEV := "dev"

## Tests set these and clear them afterwards. Empty reads the build.
static var override_version := ""
static var override_purchase_mode := ""
static var _mode_loaded := false
static var _mode := ""

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
	return VersionOrder.parse_release(value)

## Compares two version strings: -1 older, 0 equal, 1 newer; null when either is invalid.
static func compare(a: String, b: String) -> Variant:
	var left := parse(a)
	var right := parse(b)
	if left.is_empty() or right.is_empty(): return null
	return VersionOrder.compare_release(left, right)
