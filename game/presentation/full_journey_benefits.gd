extends RefCounted
## What the Full Journey card says the subscription brings, in the order the
## rules set (POLLEN-RULES.md "Card order"): the chapters first, then the room
## boost, and only then the monthly Pollen. The chapters are two plain lines;
## the boost and the monthly Pollen are the two cream panels of pollen-concepts
## board 3, each with its explainer, and the Pollen panel ends with the ladder.
## The panels show only while the server pays them, and never on a build that
## names no Full Journey Pollen (services/pollen_surfaces.gd, asked by the
## caller). While Fruits show (Fruits board 5a) the monthly gifts are two tiles
## side by side in the same place: the Pollen tile, then the plum Fruit tile
## with the Fruits a month, the step they grow to and, until it is paid, the
## welcome basket. The store card (presentation/store_flow.gd) draws this with
## presentation/kit/benefit_panel.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")

## The monthly grant's ladder, as backend/src/pollen/rates.json "grant" sets it:
## month 1 pays FIRST, each month after pays STEP more, up to TOP.
const GRANT_FIRST := 4500
const GRANT_STEP := 250
const GRANT_TOP := 12000
## The Fruit ladder, as backend/src/pollen/fruits.json "grant" sets it: month 1
## pays FRUIT_FIRST, FRUIT_STEP more every FRUIT_EVERY months, up to FRUIT_TOP,
## and the welcome basket once with the first paid month. The server's own
## values (services/fruit_wallet.gd part's grant) win whenever it sent them.
const FRUIT_FIRST := 15
const FRUIT_STEP := 1
const FRUIT_EVERY := 2
const FRUIT_TOP := 30
const FRUIT_WELCOME := 25
## A monthly gift tile's mark: board 5a draws it bigger, beside two lines.
const TILE_ICON := 44.0
## The ladder line names what this month pays.
const LADDER_MONTH := 12
const SEPARATOR := " · "

## The card's content. `boost`: Pollen earning is on (the room boost pays).
## `grant`: the monthly grant is on. `ladder`: what the server last said for
## this player ({months, next, top}, services/pollen_grant.gd ladder), {} for a
## player who never subscribed. `shown`: the build names Full Journey Pollen.
## `fruits`: null while Fruits do not show; else the Fruit grant the server
## last said for this player (services/fruit_wallet.gd part's grant: {next,
## top, welcome, welcome_paid}), {} for a player it sent none for.
## Returns {intro: the chapter lines, panels: [{name, icon, title, body, ladder?}
## or {name, tiles: [two such panels]}]}.
static func content(boost: bool, grant: bool, ladder: Dictionary = {}, shown: bool = true, fruits: Variant = null) -> Dictionary:
	var panels: Array[Dictionary] = []
	if boost and shown:
		panels.append({"name": "FullJourneyBoost", "icon": "room", "title": PlayerCopy.FULL_JOURNEY_ROOM_BOOST, "body": PlayerCopy.FULL_JOURNEY_ROOM_BOOST_NOTE})
	if boost and grant and shown:
		var top := _top(ladder)
		var first := _first_month(ladder)
		if fruits is Dictionary:
			panels.append({"name": "FullJourneyGifts", "tiles": [pollen_tile(ladder), fruit_tile(fruits, int(ladder.get("months", 0)))]})
		else:
			panels.append({"name": "FullJourneyGrant", "icon": "pollen", "title": (PlayerCopy.FULL_JOURNEY_GRANT_TOP if first >= top else PlayerCopy.FULL_JOURNEY_GRANT) % PollenMoney.grouped(first),
				"body": PlayerCopy.FULL_JOURNEY_GRANT_NOTE % [PollenMoney.grouped(GRANT_STEP), PollenMoney.grouped(top)], "ladder": ladder_line(ladder)})
	return {"intro": PackedStringArray([PlayerCopy.SUBSCRIPTION_PURPOSE, PlayerCopy.COOPERATIVE_HOST_ACCESS]), "panels": panels}

## The Pollen tile beside the Fruit tile (board 5a): "4,500 Pollen a month",
## then how it grows; at the top step the title says so and nothing grows.
static func pollen_tile(ladder: Dictionary = {}) -> Dictionary:
	var top := _top(ladder)
	var first := _first_month(ladder)
	if first >= top: return {"name": "FullJourneyGrant", "icon": "pollen", "icon_size": TILE_ICON, "title": PlayerCopy.FULL_JOURNEY_GRANT_TOP % PollenMoney.grouped(top), "body": ""}
	return {"name": "FullJourneyGrant", "icon": "pollen", "icon_size": TILE_ICON, "title": PlayerCopy.FULL_JOURNEY_POLLEN_TILE % PollenMoney.grouped(first),
		"body": PlayerCopy.FULL_JOURNEY_POLLEN_TILE_NOTE % [PollenMoney.grouped(GRANT_STEP), PollenMoney.grouped(top)]}

## The Fruit tile (board 5a): "15 Fruits a month", the step it grows to and,
## until the player was paid it, the welcome basket: in month 1, or with the
## next month for a player the ladder already counted months for (`months`).
## `grant` is the server's Fruit grant for this player ({} before it sent one: month 1's values).
static func fruit_tile(grant: Dictionary, months: int = 0) -> Dictionary:
	var top := int(grant.get("top", 0)) if int(grant.get("top", 0)) > 0 else FRUIT_TOP
	var next := mini(int(grant.get("next", 0)) if int(grant.get("next", 0)) > 0 else FRUIT_FIRST, top)
	var welcome := int(grant.get("welcome", FRUIT_WELCOME))
	var tile := {"name": "FullJourneyFruits", "icon": CurrencyMark.FRUITS, "icon_size": TILE_ICON, "title": PlayerCopy.FULL_JOURNEY_FRUIT_TILE % PollenMoney.grouped(next), "body": PlayerCopy.FULL_JOURNEY_FRUIT_TILE_NOTE % PollenMoney.grouped(top)}
	if welcome > 0 and not bool(grant.get("welcome_paid", false)):
		tile.body = (PlayerCopy.FULL_JOURNEY_FRUIT_TILE_WELCOME_NEXT if months > 0 else PlayerCopy.FULL_JOURNEY_FRUIT_TILE_WELCOME) % [PollenMoney.grouped(top), PollenMoney.grouped(welcome)]
		tile["rich"] = true
	elif next >= top:
		tile.title = PlayerCopy.FULL_JOURNEY_FRUIT_TILE_TOP % PollenMoney.grouped(top)
		tile.body = ""
	return tile

## What month `month` of the Fruit ladder pays (backend/src/pollen/fruits.ts fruitInstalment).
static func fruit_instalment(month: int, top: int = FRUIT_TOP) -> int:
	return mini(FRUIT_FIRST + FRUIT_STEP * floori((maxi(1, month) - 1) / float(FRUIT_EVERY)), top)

## "Next month: 4,750 · By month 12: 7,250 · Top step: 12,000": what the month
## after the first pays, month 12 while it is still ahead, and the top step.
## A returning subscriber picks up at their own step (the server's next).
static func ladder_line(ladder: Dictionary = {}) -> String:
	var top := _top(ladder)
	var first := _first_month(ladder)
	var month := int(ladder.get("months", 0)) + 1
	var parts := PackedStringArray()
	if first < top: parts.append(PlayerCopy.FULL_JOURNEY_LADDER_NEXT % PollenMoney.grouped(mini(first + GRANT_STEP, top)))
	if month + 1 < LADDER_MONTH: parts.append(PlayerCopy.FULL_JOURNEY_LADDER_BY % [LADDER_MONTH, PollenMoney.grouped(instalment(LADDER_MONTH, top))])
	parts.append(PlayerCopy.FULL_JOURNEY_LADDER_TOP % PollenMoney.grouped(top))
	return SEPARATOR.join(parts)

## What the player's first month back pays: the server's step, else month 1.
static func _first_month(ladder: Dictionary) -> int:
	var next := int(ladder.get("next", 0))
	return mini(next, _top(ladder)) if next > 0 else GRANT_FIRST

## What month `month` of the ladder pays (backend/src/pollen/grant.ts instalmentAmount).
static func instalment(month: int, top: int = GRANT_TOP) -> int:
	return mini(GRANT_FIRST + GRANT_STEP * (maxi(1, month) - 1), top)

static func _top(ladder: Dictionary) -> int:
	var top := int(ladder.get("top", 0))
	return top if top > 0 else GRANT_TOP
