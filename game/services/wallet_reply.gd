extends RefCounted
## One answered wallet read (GET /v1/pollen) recorded in every store it feeds,
## the same way whichever client made it (services/pollen_client.gd,
## services/wardrobe_client.gd): the wallet (services/pollen_wallet.gd), the
## wardrobe while it is on (services/wardrobe.gd) and the monthly grant
## (services/pollen_grant.gd). Each store checks its own part, so a part that
## cannot be kept never stops the others: the server may have paid a monthly
## instalment inside this very read, and its card must still show.
## A null store is skipped. Returns {wallet, wardrobe}: whether each kept its part.
static func note(server: String, owner: String, data: Variant, wallet: RefCounted, wardrobe: RefCounted, grant: RefCounted) -> Dictionary:
	var kept_wallet: bool = wallet != null and wallet.note_wallet(server, owner, data)
	var kept_wardrobe: bool = wardrobe != null and wardrobe.note_view(server, owner, data)
	if grant != null: grant.note_view(server, owner, data)
	return {"wallet": kept_wallet, "wardrobe": kept_wardrobe}
