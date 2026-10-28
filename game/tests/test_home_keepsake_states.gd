extends SceneTree
## Home's keepsake states as a table (services/home_keepsake_states.gd): base
## from either chapter mark or a Hard mark, Together from the friend mark or the
## together Hard mark, each Hard mark alone, Together Hard without solo Hard,
## together Hard switched off, both version pairs and the Lighthouse's split
## keys, the Lantern Line in both builds, the started and next outlines, and
## the counts in every build.
const States = preload("res://services/home_keepsake_states.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const HardMode = preload("res://services/hard_mode.gd")
const ChapterCompletion = preload("res://presentation/chapter_completion.gd")
const ORDER := ["first-steps", "relay-isles", "high-and-low", "the-wishing-well", "turn-of-the-tide", "earlier", "sleeping-lighthouse", "rolling-home", "a-house-for-two", "conservatory", "long-way-home"]
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_entries()
	_check_chapter_rules()
	_check_versions()
	_check_outlines()
	_check_lantern_line()
	_check_counts()
	print("HOME KEEPSAKE STATES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Earned ledger marks: {place id: [solo, friend]}.
func _earned(marks: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in marks: result.append({"id": id, "solo": marks[id][0], "friend": marks[id][1]})
	return result

func _places(level: String) -> Array:
	return States.entries()[ORDER.find(level)].places

## Every stage of a chapter marked.
func _cleared(level: String, solo: bool, friend: bool, into: Dictionary = {}) -> Dictionary:
	for id: String in _places(level): into[id] = [solo, friend]
	return into

func _item(result: Dictionary, level: String) -> Dictionary:
	return result.items[ORDER.find(level)]

func _state(marks: Dictionary, hard: Dictionary = {}, together_hard: bool = true, free_only: bool = false) -> Dictionary:
	return States.states(States.entries(free_only), _earned(marks), hard, together_hard)

func _check_entries() -> void:
	var entries := States.entries()
	_check(entries.map(func(entry: Dictionary) -> String: return entry.id) == ORDER, "Home order: the free chapters, the Lantern Line, then the Full Journey chapters: %s" % [entries.map(func(entry: Dictionary) -> String: return entry.id)])
	var free := States.entries(true)
	_check(free.map(func(entry: Dictionary) -> String: return entry.id) == ORDER.slice(0, 6), "A build that sells nothing stands the five free chapters and the Lantern Line")
	_check(free[5].places.size() == 3 and free[5].free_places == entries[5].free_places and entries[5].places.size() == 8, "The free build's Lantern Line has the three free islands' lanterns")
	_check(entries[5].free_places == ["earlier/first-light", "earlier/long-way-home", "earlier/patient-garden"], "The free islands are First Light, Long Way Home and Patient Garden")
	var keys := {}
	for entry: Dictionary in entries: keys[entry.id] = entry.key
	_check(keys["sleeping-lighthouse"] == "sleeping-lighthouse@2" and keys["turn-of-the-tide"] == "turn-of-the-tide@2" and keys["long-way-home"] == "long-way-home@2", "A keepsake lives on its chapter's offered version: %s" % [keys])
	for entry: Dictionary in entries:
		_check(entry.keepsake.has("builder") and ResourceLoader.exists(str(entry.keepsake.builder)), "Keepsake %s names a builder" % entry.id)
		_check(entry.hard == (entry.id != "earlier"), "Every chapter has Hard; the Lantern Line has none: " + entry.id)
		_check(entry.together == (entry.id != "sleeping-lighthouse" or Catalog.lighthouse_together()), "Every keepsake has a together upgrade where a friend can play: " + entry.id)
	_check(States.entries() == entries, "Entries are worked out once and kept")

func _check_chapter_rules() -> void:
	var none := _state({})
	_check(none.items.all(func(item: Dictionary) -> bool: return not item.base and not item.together and not item.hard and not item.top), "Nothing earned, nothing shows")
	_check(_item(none, "first-steps").look == "next" and none.items.filter(func(item: Dictionary) -> bool: return item.look == "next").size() == 1 and none.items.slice(1).all(func(item: Dictionary) -> bool: return item.look == "none"), "Only the first keepsake in Home order is the next outline")
	# The keepsake ledger's chapter marks are ChapterCompletion's: every stage in one mode.
	var solo := _state(_cleared("first-steps", true, false))
	var expected := ChapterCompletion.chapters(_earned(_cleared("first-steps", true, false)))
	_check(expected["first-steps@1"].solo and _item(solo, "first-steps").base and not _item(solo, "first-steps").together and _item(solo, "first-steps").look == "keepsake", "Cleared solo shows the base alone")
	_check(_item(solo, "relay-isles").look == "next", "The next outline moves on to the first chapter with no marks")
	var friend := _state(_cleared("relay-isles", false, true))
	_check(_item(friend, "relay-isles").base and _item(friend, "relay-isles").together and not _item(friend, "relay-isles").hard, "Cleared with a friend shows base and Together")
	var both := _state(_cleared("relay-isles", true, true))
	_check(_item(both, "relay-isles").base and _item(both, "relay-isles").together, "Cleared both ways: base and Together, the old gold plinth")
	var hard_only := _state({}, {"high-and-low@1": {"solo": true, "together": false}})
	var steps := _item(hard_only, "high-and-low")
	_check(steps.base and steps.hard and not steps.together and not steps.top, "A solo Hard mark alone shows the base and the footing")
	var top_only := _state({}, {"high-and-low@1": {"solo": false, "together": true}})
	steps = _item(top_only, "high-and-low")
	_check(steps.base and steps.together and steps.top and not steps.hard, "Together Hard without solo Hard: base, Together and the gold top, no footing")
	var off := _state({}, {"high-and-low@1": {"solo": false, "together": true}}, false)
	_check(_item(off, "high-and-low").top and off.upgrades == [1, 21], "An earned gold top still shows with together Hard off, and is not counted: %s" % [off.upgrades])
	var partial := _cleared("conservatory", true, false)
	partial[_places("conservatory")[0]] = [true, true]
	var glass := _item(_state(partial), "conservatory")
	_check(glass.base and not glass.together and glass.stages == [[true, true], [true, false]], "Cleared solo with one stage done together: base, and the stage's friend mark kept for the card")

func _check_versions() -> void:
	# Hard marks of an earlier version and of the offered one meet in one keepsake.
	var tide := _state({}, {"turn-of-the-tide@1": {"solo": true, "together": false}, "turn-of-the-tide@2": {"solo": false, "together": true}})
	_check(_item(tide, "turn-of-the-tide").hard and _item(tide, "turn-of-the-tide").top, "Both Tide versions' Hard marks join")
	var way := _state(_cleared("long-way-home", true, false), {"long-way-home@1": {"solo": true, "together": false}})
	_check(_item(way, "long-way-home").base and _item(way, "long-way-home").hard, "Long Way Home's places and its @1 Hard mark join")
	# The Lighthouse keeps its stages under @1 and its Hard marks under @2.
	var light_places := _places("sleeping-lighthouse")
	_check(light_places.size() == 6 and light_places.all(func(id: String) -> bool: return Catalog.by_id(id).chapter_key == Catalog.LIGHTHOUSE), "The Lighthouse's six stages are its @1 places")
	var light := _state(_cleared("sleeping-lighthouse", true, false), {"sleeping-lighthouse@2": {"solo": true, "together": true}})
	var item := _item(light, "sleeping-lighthouse")
	_check(item.base and item.hard and item.top and item.together == Catalog.lighthouse_together(), "The Lighthouse's stages and its @2 Hard marks join")
	_check(_item(_state({}, {"nowhere@1": {"solo": true, "together": true}, "earlier@1": {"solo": true, "together": true}}), "earlier").base == false, "Hard marks of unknown chapters, or the earlier islands, show nothing")

func _check_outlines() -> void:
	var first: String = _places("the-wishing-well")[0]
	var started := _state({first: [true, false]})
	var well := _item(started, "the-wishing-well")
	_check(well.look == "started" and not well.base and well.stages == [[true, false], [false, false]], "One stage done shows the started outline with its dot")
	_check(_item(started, "first-steps").look == "next" and _item(started, "relay-isles").look == "none", "The next outline is the first keepsake with no marks at all")
	var friend_stage := _item(_state({first: [false, true]}), "the-wishing-well")
	_check(friend_stage.look == "started" and friend_stage.stages[0] == [false, true], "A stage done together lights its dot in mint")
	var every_started := {}
	for level: String in ORDER:
		if level != "earlier": every_started[_places(level)[0]] = [true, false]
	var all_started := _state(every_started)
	_check(all_started.items.filter(func(item: Dictionary) -> bool: return item.look == "started").size() == 10 and _item(all_started, "earlier").look == "next", "Ten chapters started: ten outlines, and the Lantern Line is next")

func _check_lantern_line() -> void:
	var marks := {}
	var rows: Array = States.entries()[5].places
	for index in range(5): marks[rows[index]] = [true, false]
	var lit := _item(_state(marks), "earlier")
	_check(lit.base and lit.lit == 5 and not lit.together and not lit.hard and not lit.top, "Five islands cleared: the Lantern Line with five lanterns lit")
	marks[rows[0]] = [true, true]
	marks[rows[1]] = [false, true]
	_check(not _item(_state(marks), "earlier").together, "Two of the free islands with a friend is not enough")
	marks[rows[2]] = [false, true]
	_check(_item(_state(marks), "earlier").together, "The three free islands with a friend add the mint flags")
	var free := _state(marks, {}, true, true)
	_check(_item(free, "earlier").together and _item(free, "earlier").lit == 3, "The same rule in a build that sells nothing, with its three lanterns")
	var paid_only := {rows[6]: [true, true]}
	var paid_item := _item(_state(paid_only), "earlier")
	_check(paid_item.base and paid_item.lit == 1 and not paid_item.together, "A paid island lights its own lantern")
	_check(not _item(_state(paid_only, {}, true, true), "earlier").base, "In a build that sells nothing a paid island lights nothing")

func _check_counts() -> void:
	var everything := {}
	var hard := {}
	for entry: Dictionary in States.entries():
		_cleared(entry.id, true, true, everything)
		if entry.hard: hard[entry.key] = {"solo": true, "together": true}
	var together := 11 if Catalog.lighthouse_together() else 10
	for build: Array in [[false, true, 11, together + 20, 10], [false, false, 11, together + 10, 10], [true, true, 6, 16, 5], [true, false, 6, 11, 5]]:
		var result := _state(everything, hard, build[1], build[0])
		_check(result.keepsakes == [build[2], build[2]] and result.upgrades == [build[3], build[3]] and result.hard == [build[4], build[4]] and result.hard_open,
			"Everything earned, free_only %s, together Hard %s: %s %s %s" % [build[0], build[1], result.keepsakes, result.upgrades, result.hard])
		var nothing := _state({}, {}, build[1], build[0])
		_check(nothing.keepsakes == [0, build[2]] and nothing.upgrades == [0, build[3]] and nothing.hard == [0, build[4]] and not nothing.hard_open, "Nothing earned counts nothing: %s" % [nothing.upgrades])
	# While the Lighthouse @2 is unreleased it has no together play, so neither
	# Together nor Together Hard can be earned there: 29 and 20.
	var held: Array = []
	for entry: Dictionary in States.entries():
		var copy := entry.duplicate()
		if copy.id == "sleeping-lighthouse":
			copy.together = false
			copy.friendly = copy.friendly.map(func(_value: bool) -> bool: return false)
		held.append(copy)
	_check(States.states(held, _earned(everything), hard, true).upgrades == [29, 29] and States.states(held, _earned(everything), hard, false).upgrades == [20, 20], "With the Lighthouse's together play held back the upgrades are 29 and 20")
	var light := States.states(held, _earned(_cleared("sleeping-lighthouse", true, true)), {"sleeping-lighthouse@2": {"solo": false, "together": true}}, true)
	_check(not light.items[6].together and light.upgrades[0] == 0, "A together mark where no friend can play neither shows Together nor counts")
	# The board's part-way player: 9 keepsakes, 11 upgrades.
	var part := {}
	for level: String in ["first-steps", "relay-isles", "the-wishing-well", "sleeping-lighthouse", "a-house-for-two"]: _cleared(level, true, true, part)
	for level: String in ["high-and-low", "turn-of-the-tide", "rolling-home"]: _cleared(level, true, false, part)
	part[_places("conservatory")[0]] = [true, false]
	var rows: Array = States.entries()[5].places
	for index in range(5): part[rows[index]] = [true, false]
	var part_hard := {"first-steps@1": {"solo": true, "together": true}, "high-and-low@1": {"solo": true, "together": false}, "the-wishing-well@1": {"solo": true, "together": false}, "sleeping-lighthouse@2": {"solo": true, "together": true}}
	var board := _state(part, part_hard)
	_check(board.keepsakes == [9, 11] and board.upgrades == [11 if Catalog.lighthouse_together() else 10, together + 20] and board.hard == [4, 10], "The part-way player: %s %s %s" % [board.keepsakes, board.upgrades, board.hard])
	_check(_item(board, "conservatory").look == "started" and _item(board, "long-way-home").look == "next", "with the Glasshouse started and the Signpost next")
