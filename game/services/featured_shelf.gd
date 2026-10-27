extends RefCounted
## "Featured this week" (POLLEN-RULES.md "The shop"): six catalogue items that
## change every Monday 00:00 UTC. Pure: the same week and items give the same
## shelf on every phone, and featuring changes nothing about what can be bought.
##
## - 3 Common slots and 2 Uncommon slots walk through their tier.
## - 1 top slot follows a fixed 6-week cycle: Rare, Epic, Rare, Special, Rare,
##   Epic. Each time a tier comes round, the next item of that tier shows, so
##   with the planned catalogue (12 Common, 8 Uncommon, 6 Rare, 4 Epic,
##   4 Special) each Common and Uncommon is featured every 4 weeks, each Rare
##   and Epic every 12 and each Special every 24.
## - Each tier's order is fixed and shuffled once: items sort by the SHA-256 of
##   "featured-v1|" + id, so a new item takes its place without moving others
##   more than it must.
## - A tier with fewer items than slots shows each item once; an empty tier
##   leaves its slots empty.
## Weeks are counted as the server counts them (backend/src/pollen/week.ts).
const COMMON_SLOTS := 3
const UNCOMMON_SLOTS := 2
const TOP_CYCLE: Array[String] = ["rare", "epic", "rare", "special", "rare", "epic"]
## Monday 5 January 1970, 00:00 UTC: week 0.
const FIRST_MONDAY_MS := 345_600_000
const WEEK_MS := 604_800_000
const SALT := "featured-v1|"

## Whole weeks since the first Monday of 1970 (never below 0).
static func week_index(unix_ms: int) -> int:
	return maxi(0, floori(float(unix_ms - FIRST_MONDAY_MS) / float(WEEK_MS)))

## This week's index on this phone's clock.
static func this_week() -> int:
	return week_index(int(Time.get_unix_time_from_system() * 1000.0))

## A tier's items in their fixed shuffled order.
static func order(ids: Array) -> Array:
	var keyed: Array = []
	for id: Variant in ids:
		if id is String and not keyed.any(func(entry: Array) -> bool: return entry[1] == id): keyed.append([(SALT + id).sha256_text(), id])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return keyed.map(func(entry: Array) -> String: return entry[1])

## How many weeks before `week` the cycle gave the top slot to `tier`.
static func top_turns_before(week: int, tier: String) -> int:
	var per_cycle := TOP_CYCLE.count(tier)
	var turns := floori(float(week) / float(TOP_CYCLE.size())) * per_cycle
	for index in range(week % TOP_CYCLE.size()):
		if TOP_CYCLE[index] == tier: turns += 1
	return turns

## The shelf for `week`: up to 6 entries {id, tier, top}, Commons first, then
## Uncommons, then the top slot. `by_tier`: tier name -> item ids on sale.
static func shelf(week: int, by_tier: Dictionary) -> Array:
	var result: Array = []
	var at := maxi(0, week)
	for row: Array in [["common", COMMON_SLOTS], ["uncommon", UNCOMMON_SLOTS]]:
		var items := order(by_tier.get(row[0], []))
		for index in range(mini(row[1], items.size())):
			result.append({"id": items[(at * row[1] + index) % items.size()], "tier": row[0], "top": false})
	var top: String = TOP_CYCLE[at % TOP_CYCLE.size()]
	var tops := order(by_tier.get(top, []))
	if not tops.is_empty(): result.append({"id": tops[top_turns_before(at, top) % tops.size()], "tier": top, "top": true})
	return result
