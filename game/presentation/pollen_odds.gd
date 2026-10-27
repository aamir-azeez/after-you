extends RefCounted
## The Help note that publishes the bloom odds (POLLEN-RULES.md "Lucky blooms"
## and "Item blooms"), shown as a Settings About row while the server pays
## Pollen (presentation/settings_rows.gd). The item odds are added only while
## the server says item blooms drop. Never next to a shop offer.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")

static func text(item_blooms: bool) -> String:
	var parts := PackedStringArray([PlayerCopy.POLLEN_ODDS])
	if item_blooms: parts.append(PlayerCopy.POLLEN_ODDS_ITEMS)
	parts.append(PlayerCopy.POLLEN_ODDS_PAID)
	return " ".join(parts)

## Whether the note shows: Pollen is on for the signed-in player (`scope` is
## {server, owner}) and this build shows Pollen at all.
static func shown(scope: Dictionary, paid_hidden: bool, store: RefCounted = null) -> bool:
	if paid_hidden or scope.is_empty(): return false
	return (store if store != null else PollenWallet.shared()).enabled(str(scope.server), str(scope.owner))

## The note's words for the signed-in player.
static func note(scope: Dictionary, store: RefCounted = null) -> String:
	var wallet: RefCounted = store if store != null else PollenWallet.shared()
	return text(not scope.is_empty() and wallet.item_blooms(str(scope.server), str(scope.owner)))
