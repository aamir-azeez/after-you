extends RefCounted
## One answered wallet read (GET /v1/pollen) recorded in every store it feeds,
## the same way whichever client made it (services/pollen_client.gd,
## services/wardrobe_client.gd): the wallet (services/pollen_wallet.gd), the
## wardrobe while it is on (services/wardrobe.gd), the monthly grant
## (services/pollen_grant.gd), the Fruits (services/fruit_wallet.gd) and the
## duel energy meter (services/duel_energy.gd). Each
## store checks its own part, so a part that cannot be kept never stops the
## others: the server may have paid a monthly instalment inside this very read,
## and its card must still show.
## A null store is skipped. Returns {wallet, wardrobe, fruits}: whether each kept its part.
static func note(server: String, owner: String, data: Variant, wallet: RefCounted, wardrobe: RefCounted, grant: RefCounted, fruits: RefCounted, energy: RefCounted) -> Dictionary:
	var kept_wallet: bool = wallet != null and wallet.note_wallet(server, owner, data)
	var kept_wardrobe: bool = wardrobe != null and wardrobe.note_view(server, owner, data)
	if grant != null: grant.note_view(server, owner, data)
	var kept_fruits: bool = fruits != null and fruits.note_view(server, owner, data)
	if energy != null: energy.note_view(server, owner, data)
	return {"wallet": kept_wallet, "wardrobe": kept_wardrobe, "fruits": kept_fruits}

## One confirmed spend (POST /v1/pollen/spend) recorded the same way in every
## store it feeds: the pieces bought (wardrobe), the Pollen balance (`balance`,
## always Pollen, a convert's Pollen included) and, for a Fruit spend, the Fruit
## balance, the Sunshine turns left and a refill's energy meter. A null store is skipped.
static func note_spend(server: String, owner: String, receipt: Variant, wallet: RefCounted, wardrobe: RefCounted, fruits: RefCounted, energy: RefCounted) -> void:
	if not receipt is Dictionary: return
	if wardrobe != null: wardrobe.note_spend(server, owner, receipt)
	if wallet != null: wallet.note_balance(server, owner, receipt.get("balance"))
	if fruits != null: fruits.note_spend(server, owner, receipt)
	if energy != null: energy.note_spend(server, owner, receipt)

## A duel start or join reply (services/duels_client.gd, the friend and public
## routes alike): the requesting player's energy meter after the spend.
static func note_duel(server: String, owner: String, data: Variant, energy: RefCounted) -> void:
	if energy != null: energy.note_duel(server, owner, data)
