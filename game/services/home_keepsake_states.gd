extends RefCounted
## Home's keepsakes: one per card on the Chapters page (each chapter, plus one
## Lantern Line for the earlier islands), and how far each has come. A view
## over records the game already keeps, never an award source: the keepsake
## ledger's per-stage solo and friend marks (services/home_keepsakes.gd) and the
## Hard marks (services/hard_mode.gd). Nothing here is saved, and nothing else
## decides a state. Pure and static.
##
## A chapter is joined to its marks by its level id (the part of its key before
## "@"), so every version of a chapter, and the Sleeping Lighthouse's split keys
## (stages under @1, Hard marks under @2), meet in one keepsake. Per keepsake:
##   base      the chapter cleared solo or with a friend (every stage in one
##             mode, as the chapter picker's tick), or either Hard mark
##   together  cleared with a friend, or the together Hard mark
##   hard      the solo Hard mark
##   top       the together Hard mark (shown even while the server has
##             together Hard switched off; then not counted)
##   stages    [solo, friend] per stage, for the started outline's dots
##   look      "keepsake" (base earned), "started" (stage marks only), "next"
##             (the first keepsake in Home order with no marks at all) or "none"
## The Lantern Line has a base (any earlier island marked; each lantern lights
## for its own island) and a together upgrade (the free islands all done with
## a friend, the same rule in every build). It has no Hard.
const Index = preload("res://content/chapters/index.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const HardMode = preload("res://services/hard_mode.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const EARLIER := "earlier"
## The Lantern Line, in the same shape as a chapter descriptor's home_keepsake
## (content/chapters/index.gd), since the earlier islands have no descriptor.
const EARLIER_KEEPSAKE := {
	"builder": "res://presentation/keepsakes/lantern_line.gd",
	"island": "right",
	"slot": [0.8, 2.0],
	"copy": {
		"name": PlayerCopy.KEEPSAKE_LANTERN_LINE_NAME,
		"action": PlayerCopy.KEEPSAKE_LANTERN_LINE_ACTION,
		"together": PlayerCopy.KEEPSAKE_LANTERN_LINE_TOGETHER,
	},
	"sounds": {"base": "waypoint", "together": "garden_opened"},
}
const LOOKS := ["keepsake", "started", "next", "none"]

static var _entries: Dictionary = {}

## The keepsakes Home stands, in Home order: the free chapters in chapter
## order, the Lantern Line, then the Full Journey chapters. `free_only` (a build
## that sells nothing) keeps the free ones, and the free islands' lanterns.
## Each: {"id": level id, "key": the chapter key holding its home_keepsake ("" for
## the Lantern Line), "keepsake": that field, "title": the chapter's title,
## "paid", "places": its keepsake ledger place ids, "friendly": whether each
## place has a together variant, "free_places" (the Lantern Line's free
## islands), "together": a friend can play it, "hard": it has Hard plays}.
## Worked out once per build kind; read-only.
static func entries(free_only: bool = false) -> Array:
	if _entries.has(free_only): return _entries[free_only]
	var free: Array = []
	var paid: Array = []
	var seen: Dictionary = {}
	for chapter: String in Catalog.CHAPTERS:
		var level := chapter.get_slice("@", 0)
		if seen.has(level): continue
		var key := keepsake_key(level)
		var places := _places(level)
		if key.is_empty() or places.is_empty(): continue
		seen[level] = true
		var is_paid := Catalog.paid(Catalog.by_id(places[0]))
		if free_only and is_paid: continue
		var keepsake: Dictionary = Index.data(key).home_keepsake
		(paid if is_paid else free).append({"id": level, "key": key, "keepsake": keepsake, "title": str(Registry.descriptor(key).get("title", "")),
			"paid": is_paid, "places": places, "free_places": [], "friendly": _friendly(places),
			"together": _friendly(places).has(true), "hard": HardMode.eligible(key)})
	var earlier_places: Array = []
	var free_islands: Array = []
	for item: Dictionary in Catalog.all():
		if item.family != EARLIER: continue
		if not Catalog.paid(item): free_islands.append(item.id)
		if not free_only or not Catalog.paid(item): earlier_places.append(item.id)
	var result: Array = free
	result.append({"id": EARLIER, "key": "", "keepsake": EARLIER_KEEPSAKE, "title": PlayerCopy.KEEPSAKE_LANTERN_LINE_NAME, "paid": false,
		"places": earlier_places, "free_places": free_islands, "friendly": _friendly(earlier_places), "together": true, "hard": false})
	result.append_array(paid)
	for entry: Dictionary in result: entry.make_read_only()
	result.make_read_only()
	_entries[free_only] = result
	return result

## The registered chapter whose descriptor holds a level id's home_keepsake
## (its offered version), or "".
static func keepsake_key(level: String) -> String:
	return str(Index.home_keepsake(level).get("key", ""))

## Whether each place has a together variant.
static func _friendly(places: Array) -> Array:
	return places.map(func(id: String) -> bool: return bool(Catalog.by_id(id).get("friend_available", true)))

## The ledger's places of a level id, in stage order.
static func _places(level: String) -> Array:
	var result: Array = []
	for item: Dictionary in Catalog.all():
		if item.family == level: result.append(item.id)
	return result

## The state of every entry and the counts. `earned` holds the ledger's marks
## ({"id", "solo", "friend"} per place, HomeKeepsakes.earned_descriptors());
## `hard` is HardMode.marks(); `together_hard` is whether the server hosts
## together Hard rooms. Returns {"items": [per entry, in entries' order: {"id",
## "base", "together", "hard", "top", "stages", "lit", "look"}], "keepsakes":
## [earned, total], "upgrades": [earned, total], "hard": [earned, total],
## "hard_open": whether any Hard play is open}.
static func states(entries_list: Array, earned: Array, hard: Dictionary, together_hard: bool) -> Dictionary:
	var marks: Dictionary = {}
	for item: Variant in earned:
		if item is Dictionary: marks[str(item.get("id", ""))] = item
	var hard_by_level: Dictionary = {}
	for key: Variant in hard:
		var mark: Variant = hard[key]
		if not key is String or not mark is Dictionary: continue
		var level := str(key).get_slice("@", 0)
		var had: Dictionary = hard_by_level.get(level, {"solo": false, "together": false})
		hard_by_level[level] = {"solo": had.solo or mark.get("solo") == true, "together": had.together or mark.get("together") == true}
	var items: Array = []
	var counts := {"keepsakes": [0, 0], "upgrades": [0, 0], "hard": [0, 0]}
	var hard_open := false
	var next_found := false
	for entry: Dictionary in entries_list:
		var stages: Array = []
		var any_stage := false
		var all_solo: bool = not entry.places.is_empty()
		var all_friend: bool = not entry.places.is_empty()
		for index in range(entry.places.size()):
			var id: String = entry.places[index]
			var mark: Dictionary = marks.get(id, {})
			var friend_ok: bool = entry.together and entry.friendly[index]
			var solo: bool = mark.get("solo", false) == true
			var friend: bool = friend_ok and mark.get("friend", false) == true
			stages.append([solo, friend])
			any_stage = any_stage or solo or friend
			all_solo = all_solo and solo
			all_friend = all_friend and friend
		var item := {"id": entry.id, "base": false, "together": false, "hard": false, "top": false, "stages": stages, "lit": 0, "look": "none"}
		if entry.id == EARLIER:
			for stage: Array in stages: item.lit += int(stage[0] or stage[1])
			item.base = item.lit > 0
			item.together = not entry.free_places.is_empty() and entry.free_places.all(func(id: String) -> bool: return marks.get(id, {}).get("friend", false) == true)
		else:
			var hard_mark: Dictionary = hard_by_level.get(entry.id, {}) if entry.hard else {}
			item.hard = hard_mark.get("solo", false)
			item.top = hard_mark.get("together", false)
			item.base = all_solo or all_friend or item.hard or item.top
			item.together = entry.together and (all_friend or item.top)
		if item.base: item.look = "keepsake"
		elif any_stage: item.look = "started"
		elif not next_found:
			item.look = "next"
			next_found = true
		items.append(item)
		counts.keepsakes[1] += 1
		counts.keepsakes[0] += int(item.base)
		var top_counts: bool = entry.hard and entry.together and together_hard
		counts.upgrades[1] += int(entry.together) + int(entry.hard) + int(top_counts)
		counts.upgrades[0] += int(item.together and entry.together) + int(item.hard) + int(item.top and top_counts)
		if entry.hard:
			counts.hard[1] += 1
			counts.hard[0] += int(item.hard)
			hard_open = hard_open or item.base
	counts.upgrades[0] = mini(counts.upgrades[0], counts.upgrades[1])
	return {"items": items, "keepsakes": counts.keepsakes, "upgrades": counts.upgrades, "hard": counts.hard, "hard_open": hard_open}
