extends RefCounted
## What a platform games service offers After You, whatever the platform. PlatformGames talks
## only to this interface; Android (Play Games), iOS (Game Center), desktop (none) and tests
## (a fake) each provide one. This base class is the "none" provider: nothing is available and
## every call answers at once with a code, so desktop and headless runs do no work.
##
## Every call returns a Dictionary: {"ok": true, ...} or {"ok": false, "code": <short code>}.
## Calls are coroutines (await them); none of them may block a frame.
##
## Codes every provider uses:
##   unavailable    no platform service on this device or build (none, not installed, not configured)
##   signed_out     the player is not signed in
##   cancelled      the player closed the sign-in sheet
##   offline        no network; try again later
##   timeout        the platform did not answer in time
##   not_enabled    the feature exists in the interface but After You does not use it yet
##   failed         anything else (never carries platform text)

## Emitted when the platform reports another signed-in account than before.
signal account_changed

const NONE := "none"
const PLAY_GAMES := "play_games"
const GAME_CENTER := "game_center"

## "none", "play_games" or "game_center": also the server's provider name.
func kind() -> String:
	return NONE

## True when this build and device can talk to the platform at all.
func available() -> bool:
	return false

## Sign-in. Quiet (interactive false) never shows UI; interactive may show the platform's sheet.
## Ok answers carry "signed_in" (bool) and, when signed in, "player_key": a one-way digest of
## the platform account, used only to tell accounts apart on this phone.
func authenticate(_interactive: bool) -> Dictionary:
	return {"ok": false, "code": "unavailable"}

## Proof of the signed-in account for the server: {"ok", "credential": Dictionary}.
## Play Games: a one-time server auth code for web_client_id. Game Center: signed identity data.
func server_credential(_web_client_id: String) -> Dictionary:
	return {"ok": false, "code": "unavailable"}

## The signed-in player's gamer name (Play Games display name, Game Center
## alias): {"ok", "name"}. Asked only when the player picks it as their display
## name, never during sign-in. The game checks the name against its own rules.
func player_name() -> Dictionary:
	return {"ok": false, "code": "unavailable"}

## Saved Games. open gives {"ok", "handle", "data": PackedByteArray} and, when two copies
## disagree, "conflict": {"data": PackedByteArray} (the other copy). resolve answers like open.
func snapshot_open(_name: String) -> Dictionary:
	return {"ok": false, "code": "unavailable"}

func snapshot_commit(_handle: String, _data: PackedByteArray, _description: String) -> Dictionary:
	return {"ok": false, "code": "unavailable"}

func snapshot_resolve(_handle: String, _data: PackedByteArray) -> Dictionary:
	return {"ok": false, "code": "unavailable"}

func snapshot_discard(_handle: String) -> Dictionary:
	return {"ok": false, "code": "unavailable"}

## Achievements and leaderboards: the interface is ready, but After You defines, unlocks and
## shows none yet (owner decision). Every provider answers not_enabled until that changes.
func unlock_achievement(_id: String) -> Dictionary:
	return {"ok": false, "code": "not_enabled"}

func submit_score(_board: String, _score: int) -> Dictionary:
	return {"ok": false, "code": "not_enabled"}
