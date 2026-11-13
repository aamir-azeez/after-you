extends SceneTree
## "Featured this week" (services/featured_shelf.gd):
## - weeks start Monday 00:00 UTC, as the server counts them;
## - 3 Commons, 2 Uncommons and a top slot cycling Rare, Epic, Rare, Special,
##   Rare, Epic;
## - with the planned catalogue each Common and Uncommon shows every 4 weeks,
##   each Rare and Epic every 12 and each Special every 24;
## - a tier's order is fixed, a short tier shows each item once and an empty
##   tier leaves its slot empty;
## - the server's featured item takes the top slot when the shelf sells it,
##   without showing twice; anything else leaves the built-in shelf exactly.
const Shelf = preload("res://services/featured_shelf.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

static func _ids(prefix: String, count: int) -> Array:
	var out: Array = []
	for index in range(count): out.append("%s_%02d" % [prefix, index])
	return out

func _run() -> void:
	# Monday 26 October 2026 00:00 UTC, and the second before it.
	var monday := 1792972800000
	_check(Shelf.week_index(monday) == Shelf.week_index(monday - 1000) + 1, "A week starts on Monday at 00:00 UTC")
	_check(Shelf.week_index(monday + 6 * 86400000 + 86399000) == Shelf.week_index(monday), "Sunday night is still the same week")
	_check(Shelf.week_index(Shelf.FIRST_MONDAY_MS) == 0 and Shelf.week_index(0) == 0, "Week 0 is the first Monday of 1970, and nothing counts below it")
	var catalogue := {"common": _ids("c", 12), "uncommon": _ids("u", 8), "rare": _ids("r", 6), "epic": _ids("e", 4), "special": _ids("s", 4)}
	var tiers: Array = []
	var seen := {}
	for week in range(48):
		var shelf := Shelf.shelf(week, catalogue)
		_check(shelf.size() == 6, "Week %d has six items" % week)
		var ids: Array = shelf.map(func(slot: Dictionary) -> String: return slot.id)
		var unique := {}
		for id: String in ids: unique[id] = true
		_check(unique.size() == 6, "Week %d shows six different items" % week)
		_check(shelf.slice(0, 3).all(func(slot: Dictionary) -> bool: return slot.tier == "common") and shelf.slice(3, 5).all(func(slot: Dictionary) -> bool: return slot.tier == "uncommon") and shelf[5].top, "Week %d: three Commons, two Uncommons, then the top slot" % week)
		tiers.append(shelf[5].tier)
		for id: String in ids: (seen.get_or_add(id, []) as Array).append(week)
	_check(tiers.slice(0, 6) == ["rare", "epic", "rare", "special", "rare", "epic"] and tiers.slice(6, 12) == tiers.slice(0, 6), "The top slot cycles Rare, Epic, Rare, Special, Rare, Epic")
	for row: Array in [["c", 12, 4], ["u", 8, 4], ["r", 6, 12], ["e", 4, 12], ["s", 4, 24]]:
		for id: String in _ids(row[0], row[1]):
			var weeks: Array = seen.get(id, [])
			var gaps := range(1, weeks.size()).map(func(i: int) -> int: return weeks[i] - weeks[i - 1])
			_check(not weeks.is_empty() and gaps.all(func(gap: int) -> bool: return gap == row[2]), "%s is featured every %d weeks (%s)" % [id, row[2], str(weeks)])
	_check(Shelf.order(["b", "a", "c"]) == Shelf.order(["c", "b", "a"]), "A tier's order does not depend on the order items come in")
	_check(Shelf.shelf(5, catalogue) == Shelf.shelf(5, catalogue), "The same week shows the same shelf")
	var launch := {"common": ["daisy", "seashell"], "uncommon": ["straw_hat"], "rare": ["tide"], "epic": ["lantern"], "special": ["lighthouse_lamp"]}
	var small := Shelf.shelf(3, launch)
	_check(small.map(func(slot: Dictionary) -> String: return slot.id).size() == 4 and small[3].id == "lighthouse_lamp", "A short tier shows each of its items once, and week 3's top slot holds the Special")
	_check(Shelf.shelf(1, {"common": ["daisy"]}).size() == 1, "An empty tier leaves its slots empty")
	_check(Shelf.shelf(0, {}).is_empty(), "No items, no shelf")
	_server_pick(catalogue)
	print("AFTER YOU FEATURED SHELF: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _server_pick(catalogue: Dictionary) -> void:
	for week in range(12):
		var built_in := Shelf.shelf(week, catalogue)
		for missing: String in ["", "nothing", "fruit_hood"]: _check(Shelf.shelf(week, catalogue, missing) == built_in, "Week %d: a featured id the shelf does not sell (%s) leaves the built-in shelf" % [week, missing])
		var pick := Shelf.shelf(week, catalogue, "u_05")
		var ids: Array = pick.map(func(slot: Dictionary) -> String: return slot.id)
		_check(pick.size() == 6 and pick[5] == {"id": "u_05", "tier": "uncommon", "top": true} and ids.count("u_05") == 1, "Week %d: the featured Uncommon takes the top slot, once: %s" % [week, ids])
		_check(pick.slice(0, 3) == built_in.slice(0, 3) and pick.slice(3, 5).all(func(slot: Dictionary) -> bool: return slot.tier == "uncommon" and slot.id != "u_05"), "Week %d: the Commons stay and two other Uncommons fill their slots" % week)
		var top := Shelf.shelf(week, catalogue, str(built_in[5].id))
		_check(top == built_in, "Week %d: featuring this week's own top item changes nothing" % week)
	var tiny := Shelf.shelf(0, {"common": ["daisy"]}, "daisy")
	_check(tiny == [{"id": "daisy", "tier": "common", "top": true}], "A featured item that was the shelf's only Common stands alone in the top slot")

