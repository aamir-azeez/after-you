extends RefCounted
## One answer to "which platform is this" for every screen and service.
## Android and iOS are both phones: display safe areas, touch wording, haptics and
## store-gated paid chapters. Desktop builds are development stand-ins for the Android app,
## so they keep its wording; the suite and the store captures run there.

const ANDROID := "android"
const IOS := "ios"
const DESKTOP := "desktop"
## Apple's standard licence agreement, linked from the iOS paywall as the Terms of Use.
const APPLE_TERMS_URL := "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

## Tests set this to ANDROID, IOS or DESKTOP and clear it afterwards. Empty reads the build.
static var override_platform := ""

static func platform() -> String:
	if not override_platform.is_empty(): return override_platform
	if OS.has_feature("android"): return ANDROID
	if OS.has_feature("ios"): return IOS
	return DESKTOP

static func is_ios() -> bool:
	return platform() == IOS

static func is_phone() -> bool:
	return platform() in [ANDROID, IOS]

## Paid chapters wait for a tester grant or a store purchase on a phone, even when no
## store is configured. Only desktop development builds open them directly.
static func store_gated() -> bool:
	return is_phone()

## A shared code that unlocks paid content is not allowed in an App Store build
## (guideline 3.1.1). iOS debug builds keep it for testing; every other build is unchanged.
static func tester_code_offered() -> bool:
	return tester_code_offered_for(OS.is_debug_build() and not override_release)

## Tests set this to check what a release build shows while running a debug build.
static var override_release := false

static func tester_code_offered_for(debug_build: bool) -> bool:
	return not is_ios() or debug_build

## The "Get it on Google Play" link only makes sense outside iOS.
static func play_listing_offered() -> bool:
	return not is_ios()
