extends RefCounted
## The single share path for a player's invite link, used by Friends and Home: the Android
## share sheet receives the link plus the friend-<id> code; without it the code is copied.
const ShareCodes = preload("res://services/share_codes.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

static func message(player_id: Variant) -> String:
	var code := ShareCodes.format(ShareCodes.FRIEND, player_id)
	if code.is_empty(): return ""
	return PlayerCopy.INVITE_SHARE_MESSAGE % [ShareCodes.link(ShareCodes.FRIEND, player_id), code]

## share_text(text) -> bool opens a share sheet; clipboard_copy(text) is the fallback.
## Returns false only when player_id is not a valid friend ID.
static func share(player_id: Variant, share_text: Callable = Callable(), clipboard_copy: Callable = Callable()) -> bool:
	var text := message(player_id)
	if text.is_empty(): return false
	var shared: Variant = share_text.call(text) if share_text.is_valid() else android_share(text)
	if shared != true:
		var code := ShareCodes.format(ShareCodes.FRIEND, player_id)
		if clipboard_copy.is_valid(): clipboard_copy.call(code)
		else: DisplayServer.clipboard_set(code)
	return true

static func android_share(text: String) -> bool:
	if text.is_empty() or not OS.has_feature("android") or not Engine.has_singleton("AfterYouAndroid"): return false
	Engine.get_singleton("AfterYouAndroid").share_text(text)
	return true
