extends RefCounted
## The required-update screen's words and where its Update button goes. Main draws it
## as a card with no Close and no Back (mode "update_gate"), so the player either
## updates or plays solo. Online features show it again while this build is too old;
## solo play, saves, replays already on the phone, Settings, purchase restore and
## identity deletion keep working.

const Copy = preload("res://presentation/player_copy.gd")
const ClientIdentity = preload("res://services/client_identity.gd")
const PLAY_LISTING_URL := "https://play.google.com/store/apps/details?id=com.aamirazeez.afteryou"
const GITHUB_LATEST_URL := "https://github.com/aamir-azeez/after-you/releases/latest"
## The App Store page comes from the private iOS app_config.json (IOS_APP_CONFIG_BASE64),
## because the listing does not exist yet. Only an apps.apple.com https link is used.
const APP_STORE_CONFIG_KEY := "app_store_url"
const APP_STORE_PREFIX := "https://apps.apple.com/"

## Where this channel's newer build is, or "" when there is nowhere to send the player.
## A channel with no target shows no gate (main._update_gate_active).
static func target(channel: String, config: Dictionary) -> String:
	match channel:
		ClientIdentity.PLAY: return PLAY_LISTING_URL
		ClientIdentity.GITHUB: return GITHUB_LATEST_URL
		ClientIdentity.APP_STORE:
			var link: Variant = config.get(APP_STORE_CONFIG_KEY, "")
			if link is String and link.begins_with(APP_STORE_PREFIX) and link.length() <= 200 and not link.contains(" ") and link.length() > APP_STORE_PREFIX.length(): return link
	return ""

static func view(min_version: String) -> Dictionary:
	return {"title": Copy.UPDATE_GATE_TITLE, "body": Copy.UPDATE_GATE_BODY % min_version, "update": Copy.UPDATE_GATE_UPDATE, "solo": Copy.UPDATE_GATE_SOLO}

## One line for places that stay open while gated, such as Together replays.
static func notice(min_version: String) -> String:
	return Copy.UPDATE_GATE_NOTICE % min_version
