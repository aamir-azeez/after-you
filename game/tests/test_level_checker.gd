extends SceneTree
## The level checker, from the definitions and the dressing alone (no world):
## every stage of every chapter laid out as floors and crossings, published or
## not (superseded versions included), and a failure names the chapter, the
## stage and the spot.
##  - Reach (tests/level_graph.gd): a floor no stage lets either pip reach;
##    on a stage, a control, lever or pad its owner cannot reach and stand
##    on, and a ring goal its pip cannot reach. The graph over-approximates
##    (a gate counts as open once anything reachable could make it hold), so
##    each failure here is a spot no real play reaches.
##  - Ownership (one-pip access): a crossing, zone or control that only one pip
##    may use, which the other pip can still reach on that stage (an end of the
##    crossing, the zone's floor, the control's floor). One-pip access comes
##    from geography (the pip's own side of a real gap), a control only that
##    pip reaches, or a carried item; never an owner_slot on floor the other
##    pip walks. Published spots are KNOWN_OWNERSHIP: the route barriers
##    (presentation/kit/route_barriers.gd) show their cause instead.
##  - Open controls (core/physical/open_controls.gd, the rules a new level
##    pins): a control, lever or pad may carry no owner_slot at all, and either
##    pip reaching it is enough. Each stage must still need both pips: with the
##    first pip standing still at its start (a memory that does nothing), the
##    second must not be able to reach its goal with the goal's light or
##    switches holding. The graph over-approximates, so a pass is a proof.
##    A later version keeps the crossings and zones an earlier version lists
##    in KNOWN_OWNERSHIP (same stage, same spot): the open rules change
##    controls only, and the route barriers still show those causes.
##  - Props (content/dressing, kit/props.gd extents): two props standing in
##    each other on a stage. Props against routes, pads, levers, goals and
##    starts, and the camera's view of them, are tests/test_dressing_lint.gd's.
##    Scenery a world builds in code is not dressing and is not covered here.
## The bubbles and the camera's framing need a built world:
## tests/test_level_view.gd. KNOWN lists what fails on purpose, with why; an
## entry that stops failing fails the suite, so the list never goes stale.
const Registry = preload("res://services/chapter_registry.gd")
const Families = preload("res://services/chapter_families.gd")
const Index = preload("res://content/chapters/index.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Shots = preload("res://tests/level_tools/stage_shots.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const Props = preload("res://presentation/kit/props.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
## Two props stand in each other when their footprints share more than this
## much of the smaller one's (and their heights meet): touching leaves and a
## lamp beside a crate are fine, one crate inside another is not.
const PROP_SHARE := 0.3
## Known failures: {failure id: why it is left}. Published worlds never change
## to clear one; a new chapter fixes its own.
const KNOWN := {
	"high-and-low@1 upper-path props hedge at (-690, -200) cm and signpost at (-700, 230) cm": "the shore's signpost stands at the hedge's front end on purpose, its post beside the leaves and its boards above them (seen in the 800x360 preview)",
	"high-and-low@1 down-and-around props hedge at (-690, -200) cm and signpost at (-700, 230) cm": "the same signpost and hedge on the second stage",
}
## Published one-pip spots the other pip can reach, each shown by the route
## barriers (a gate, a stair's chain, a zone's rope or a lock) rather than
## rebuilt. A new level fixes its own; an entry that stops failing fails the suite.
const OWNERSHIP_WHY := "published before the ownership rule; the 2026-11-13 block audit found it and the route barriers show its cause"
const KNOWN_OWNERSHIP := [
	"high-and-low@1 upper-path crossing lower-causeway p1",
	"high-and-low@1 upper-path crossing blue-stair p0",
	"high-and-low@1 upper-path lever shore-lever p1",
	"high-and-low@1 upper-path pad lower-switch p1",
	"high-and-low@1 down-and-around crossing lower-causeway p1",
	"high-and-low@1 down-and-around crossing red-passage p1",
	"high-and-low@1 down-and-around crossing blue-stair p0",
	"high-and-low@1 down-and-around pad lower-ledge-switch p0",
	"rolling-home@1 weight-of-a-friend zone upper-lane p0",
	"rolling-home@1 weight-of-a-friend zone lower-lane p1",
	"rolling-home@1 weight-of-a-friend lever middle-lever p0",
	"rolling-home@1 bring-it-home zone upper-lane p0",
	"rolling-home@1 bring-it-home zone lower-lane p1",
	"rolling-home@1 bring-it-home lever home-lever p0",
	"rolling-home@1 bring-it-home lever route-lever p1",
	"a-house-for-two@1 open-the-house crossing workshop-entry p1",
	"a-house-for-two@1 open-the-house crossing loft-stairs p0",
	"a-house-for-two@1 open-the-house lever workshop-lever p1",
	"a-house-for-two@1 the-room-below crossing workshop-entry p1",
	"a-house-for-two@1 the-room-below crossing loft-stairs p0",
	"conservatory@1 a-light-above crossing lower-crossing p1",
	"conservatory@1 a-light-above crossing court-return p1",
	"conservatory@1 a-light-above crossing room-return p1",
	"conservatory@1 a-light-above crossing high-stair p0",
	"conservatory@1 a-light-above selector court-fork p1",
	"conservatory@1 a-light-above selector high-return p1",
	"conservatory@1 a-light-above selector preserved-turn p1",
	"conservatory@1 the-way-light-returns crossing lower-crossing p1",
	"conservatory@1 the-way-light-returns crossing court-return p1",
	"conservatory@1 the-way-light-returns crossing room-return p1",
	"conservatory@1 the-way-light-returns crossing high-stair p0",
	"conservatory@1 the-way-light-returns crossing recovery-stair p0",
	"conservatory@1 the-way-light-returns selector lower-fork p0",
	"conservatory@1 the-way-light-returns selector crossing-return p0",
	"conservatory@1 the-way-light-returns lever return-shutter p1",
	"long-way-home@1 the-path-you-leave crossing court-landing p1",
	"long-way-home@1 the-path-you-leave crossing friend-crossing p0",
	"long-way-home@1 the-path-you-leave crossing drop-garden p1",
	"long-way-home@1 the-path-you-leave crossing near-crossing p1",
	"long-way-home@1 the-path-you-leave crossing garden-arch p1",
	"long-way-home@1 the-path-you-leave crossing recovery-stair p1",
	"long-way-home@1 the-path-you-leave crossing service-up p0",
	"long-way-home@1 the-path-you-leave selector path-selector p1",
	"long-way-home@1 the-path-you-leave selector return-selector p0",
	"long-way-home@1 a-place-beside-you crossing court-landing p1",
	"long-way-home@1 a-place-beside-you crossing friend-crossing p0",
	"long-way-home@1 a-place-beside-you crossing drop-garden p1",
	"long-way-home@1 a-place-beside-you crossing near-crossing p1",
	"long-way-home@1 a-place-beside-you crossing porch-door p1",
	"long-way-home@1 a-place-beside-you crossing garden-arch p1",
	"long-way-home@1 a-place-beside-you crossing garden-door p1",
	"long-way-home@1 a-place-beside-you crossing recovery-stair p1",
	"long-way-home@1 a-place-beside-you crossing service-up p0",
	"long-way-home@1 a-place-beside-you crossing service-down p0",
	"long-way-home@1 a-place-beside-you pad near-window p0",
	"long-way-home@1 a-place-beside-you pad garden-window p0",
	"the-wishing-well@1 go-on-ahead crossing rope-walk-west p0",
	"the-wishing-well@1 go-on-ahead crossing cliff-steps p1",
	"the-wishing-well@1 go-on-ahead crossing long-stair p0",
	"the-wishing-well@1 go-on-ahead zone well-lip p1",
	"the-wishing-well@1 go-on-ahead lever garden-gate p1",
	"the-wishing-well@1 back-for-you crossing rope-walk-east p0",
	"the-wishing-well@1 back-for-you crossing cliff-steps p1",
	"the-wishing-well@1 back-for-you crossing well-ladder p1",
	"the-wishing-well@1 back-for-you zone well-lip p1",
	"the-wishing-well@1 back-for-you lever winch-lever p0",
	"the-wishing-well@1 back-for-you pad tower-step p0",
	"long-way-home@2 the-path-you-leave crossing court-landing p1",
	"long-way-home@2 the-path-you-leave crossing friend-crossing p0",
	"long-way-home@2 the-path-you-leave crossing drop-garden p1",
	"long-way-home@2 the-path-you-leave crossing near-crossing p1",
	"long-way-home@2 the-path-you-leave crossing garden-arch p1",
	"long-way-home@2 the-path-you-leave crossing recovery-stair p1",
	"long-way-home@2 the-path-you-leave crossing service-up p0",
	"long-way-home@2 the-path-you-leave selector path-selector p1",
	"long-way-home@2 the-path-you-leave selector return-selector p0",
	"long-way-home@2 a-place-beside-you crossing court-landing p1",
	"long-way-home@2 a-place-beside-you crossing friend-crossing p0",
	"long-way-home@2 a-place-beside-you crossing drop-garden p1",
	"long-way-home@2 a-place-beside-you crossing near-crossing p1",
	"long-way-home@2 a-place-beside-you crossing porch-door p1",
	"long-way-home@2 a-place-beside-you crossing garden-arch p1",
	"long-way-home@2 a-place-beside-you crossing garden-door p1",
	"long-way-home@2 a-place-beside-you crossing recovery-stair p1",
	"long-way-home@2 a-place-beside-you crossing service-up p0",
	"long-way-home@2 a-place-beside-you crossing service-down p0",
	"long-way-home@2 a-place-beside-you pad near-window p0",
	"long-way-home@2 a-place-beside-you pad garden-window p0",
	"turn-of-the-tide@1 set-the-tide crossing quay-step p1",
	"turn-of-the-tide@1 set-the-tide crossing wheel-step p1",
	"turn-of-the-tide@1 set-the-tide crossing bollard-step p1",
	"turn-of-the-tide@1 set-the-tide crossing boom-jetty p1",
	"turn-of-the-tide@1 set-the-tide crossing sea-gate-in p1",
	"turn-of-the-tide@1 set-the-tide crossing punt-ferry p1",
	"turn-of-the-tide@1 set-the-tide crossing race-stage p1",
	"turn-of-the-tide@1 set-the-tide crossing bar-catwalk p0",
	"turn-of-the-tide@1 set-the-tide crossing punt-post p0",
	"turn-of-the-tide@1 set-the-tide crossing gate-catwalk p0",
	"turn-of-the-tide@1 set-the-tide crossing gate-post p0",
	"turn-of-the-tide@1 set-the-tide crossing boom-post p0",
	"turn-of-the-tide@1 set-the-tide crossing beach-catwalk p0",
	"turn-of-the-tide@1 set-the-tide crossing quay-catwalk p0",
	"turn-of-the-tide@1 set-the-tide crossing mill-ladder p1",
	"turn-of-the-tide@1 set-the-tide crossing boathouse-steps p0",
	"turn-of-the-tide@1 set-the-tide zone spout-lip p0",
	"turn-of-the-tide@1 set-the-tide selector tide p1",
	"turn-of-the-tide@1 set-the-tide selector winch p1",
	"turn-of-the-tide@1 set-the-tide selector lock p0",
	"turn-of-the-tide@1 set-the-tide lever sluice p1",
	"turn-of-the-tide@1 set-the-tide lever line p1",
	"turn-of-the-tide@1 set-the-tide lever gangway p0",
	"turn-of-the-tide@1 slack-water crossing quay-step p1",
	"turn-of-the-tide@1 slack-water crossing wheel-step p1",
	"turn-of-the-tide@1 slack-water crossing bollard-step p1",
	"turn-of-the-tide@1 slack-water crossing boom-jetty p1",
	"turn-of-the-tide@1 slack-water crossing sea-gate-in p1",
	"turn-of-the-tide@1 slack-water crossing punt-ferry p1",
	"turn-of-the-tide@1 slack-water crossing race-stage p1",
	"turn-of-the-tide@1 slack-water crossing bar-catwalk p0",
	"turn-of-the-tide@1 slack-water crossing punt-post p0",
	"turn-of-the-tide@1 slack-water crossing gate-catwalk p0",
	"turn-of-the-tide@1 slack-water crossing gate-post p0",
	"turn-of-the-tide@1 slack-water crossing boom-post p0",
	"turn-of-the-tide@1 slack-water crossing beach-catwalk p0",
	"turn-of-the-tide@1 slack-water crossing quay-catwalk p0",
	"turn-of-the-tide@1 slack-water crossing mill-ladder p1",
	"turn-of-the-tide@1 slack-water crossing boathouse-steps p0",
	"turn-of-the-tide@1 slack-water zone spout-lip p0",
	"turn-of-the-tide@1 slack-water selector tide p1",
	"turn-of-the-tide@1 slack-water selector lock p0",
	"turn-of-the-tide@1 slack-water selector basin p0",
	"turn-of-the-tide@2 set-the-tide crossing quay-step p1",
	"turn-of-the-tide@2 set-the-tide crossing wheel-step p1",
	"turn-of-the-tide@2 set-the-tide crossing bollard-step p1",
	"turn-of-the-tide@2 set-the-tide crossing boom-jetty p1",
	"turn-of-the-tide@2 set-the-tide crossing sea-gate-in p1",
	"turn-of-the-tide@2 set-the-tide crossing punt-ferry p1",
	"turn-of-the-tide@2 set-the-tide crossing race-stage p1",
	"turn-of-the-tide@2 set-the-tide crossing bar-catwalk p0",
	"turn-of-the-tide@2 set-the-tide crossing punt-post p0",
	"turn-of-the-tide@2 set-the-tide crossing gate-catwalk p0",
	"turn-of-the-tide@2 set-the-tide crossing gate-post p0",
	"turn-of-the-tide@2 set-the-tide crossing boom-post p0",
	"turn-of-the-tide@2 set-the-tide crossing beach-catwalk p0",
	"turn-of-the-tide@2 set-the-tide crossing quay-catwalk p0",
	"turn-of-the-tide@2 set-the-tide crossing mill-ladder p1",
	"turn-of-the-tide@2 set-the-tide crossing boathouse-steps p0",
	"turn-of-the-tide@2 set-the-tide zone spout-lip p0",
	"turn-of-the-tide@2 set-the-tide selector tide p1",
	"turn-of-the-tide@2 set-the-tide selector winch p1",
	"turn-of-the-tide@2 set-the-tide selector lock p0",
	"turn-of-the-tide@2 set-the-tide lever sluice p1",
	"turn-of-the-tide@2 set-the-tide lever line p1",
	"turn-of-the-tide@2 set-the-tide lever gangway p0",
	"turn-of-the-tide@2 slack-water crossing quay-step p1",
	"turn-of-the-tide@2 slack-water crossing wheel-step p1",
	"turn-of-the-tide@2 slack-water crossing bollard-step p1",
	"turn-of-the-tide@2 slack-water crossing boom-jetty p1",
	"turn-of-the-tide@2 slack-water crossing sea-gate-in p1",
	"turn-of-the-tide@2 slack-water crossing punt-ferry p1",
	"turn-of-the-tide@2 slack-water crossing race-stage p1",
	"turn-of-the-tide@2 slack-water crossing bar-catwalk p0",
	"turn-of-the-tide@2 slack-water crossing punt-post p0",
	"turn-of-the-tide@2 slack-water crossing gate-catwalk p0",
	"turn-of-the-tide@2 slack-water crossing gate-post p0",
	"turn-of-the-tide@2 slack-water crossing boom-post p0",
	"turn-of-the-tide@2 slack-water crossing beach-catwalk p0",
	"turn-of-the-tide@2 slack-water crossing quay-catwalk p0",
	"turn-of-the-tide@2 slack-water crossing mill-ladder p1",
	"turn-of-the-tide@2 slack-water crossing boathouse-steps p0",
	"turn-of-the-tide@2 slack-water zone spout-lip p0",
	"turn-of-the-tide@2 slack-water selector tide p1",
	"turn-of-the-tide@2 slack-water selector lock p0",
	"turn-of-the-tide@2 slack-water selector basin p0",
]
var checks := 0
var failures := 0
var _found: Dictionary = {}
## Ownership spots the other pip reaches, known or not: proof the rule can fail.
var _owned_seen := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_share_rule()
	var covered := 0
	var skipped: Array[String] = []
	for key: String in Registry.keys():
		if not Stages.floor_chapter(key):
			skipped.append(key)
			_check(Stages.NOT_FLOOR_FAMILIES.has(str(Index.data(key).family)), "%s: a chapter with no floors to check names its family in NOT_FLOOR_FAMILIES" % key)
			continue
		var started := Time.get_ticks_msec()
		_reach(key)
		_ownership(key)
		_needs_both(key)
		_props(key)
		covered += 1
		print("LEVEL CHECKER: %s in %d ms" % [key, Time.get_ticks_msec() - started])
	_check(covered >= 8, "The checker walks every floor chapter (%d)" % covered)
	for family: String in Stages.NOT_FLOOR_FAMILIES:
		_check(Families.row(family).get("cooperative", true) == false, "%s is listed as having no floors, and is no floor family" % family)
	for id: String in KNOWN:
		_check(_found.has(id), "Known failure still fails, or comes off the list: %s (%s)" % [id, KNOWN[id]])
	for id: String in KNOWN_OWNERSHIP:
		_check(_found.has(id), "Known failure still fails, or comes off the list: %s (%s)" % [id, OWNERSHIP_WHY])
	_check(_owned_seen > 50, "The ownership rule meets the published one-pip spots, so it can fail (%d)" % _owned_seen)
	_needs_both_rule()
	print("LEVEL CHECKER: %d chapters, skipped %s" % [covered, skipped])
	print("LEVEL CHECKER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

## A spot that must hold: it fails unless KNOWN (or KNOWN_OWNERSHIP) lists its id.
func _expect(ok: bool, id: String, message: String) -> void:
	if not ok:
		_found[id] = true
		var carried := _carried_ownership(id)
		if KNOWN.has(id) or KNOWN_OWNERSHIP.has(id) or not carried.is_empty():
			print("KNOWN: %s (%s)" % [message, KNOWN.get(id, OWNERSHIP_WHY if carried.is_empty() else "as %s" % carried)])
			ok = true
		else: print("FAILURE ID: %s" % id)
	_check(ok, message)

# --- Ownership ------------------------------------------------------------------

## The earlier version's KNOWN_OWNERSHIP entry a later version's crossing or
## zone spot carries ("" if none): same stage, same spot, same pip.
static func _carried_ownership(id: String) -> String:
	var parts := id.split(" ", false)
	if parts.size() < 4 or parts[2] not in ["crossing", "zone"] or not parts[0].contains("@"): return ""
	var at := parts[0].rfind("@")
	var version := parts[0].substr(at + 1).to_int()
	var rest := " ".join(parts.slice(1))
	for earlier in range(version - 1, 0, -1):
		var known := "%s@%d %s" % [parts[0].substr(0, at), earlier, rest]
		if KNOWN_OWNERSHIP.has(known): return known
	return ""

## Fails each owned crossing, zone and control the other pip can reach on its
## stage: an end of the crossing, the zone's floor, the control's floor.
func _ownership(key: String) -> void:
	var level := Registry.definition(key)
	var journey := Registry.is_journey(key)
	var graph: RefCounted = LevelGraph.new(level)
	# The floors each crossing joins, with no owners: the edges a pip could
	# step if ownership were no rule at all.
	var bare := level.duplicate(true)
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in bare.get(kind, []): route.erase("owner_slot")
	var physical: RefCounted = LevelGraph.new(bare)
	var ends: Dictionary = {}
	for pair: String in physical.build("p0"):
		var sides := pair.split(">")
		for index in range(2):
			if physical.route_bit.has(sides[index]): (ends.get_or_add(sides[index], {}) as Dictionary)[sides[1 - index]] = true
	for item: Dictionary in Stages.stages(key, level):
		if item.checkpoint.is_empty(): continue
		var stage: Dictionary = item.view
		var where := "%s %s" % [key, stage.stage_id]
		var found: Dictionary = graph.reach(stage, item.checkpoint, journey)
		for kind: String in ["bridges", "stairs"]:
			for route: Dictionary in stage.get(kind, []):
				var owner := str(route.get("owner_slot", ""))
				if owner.is_empty(): continue
				var other := "p1" if owner == "p0" else "p0"
				var reached: Array = (ends.get(str(route.id), {}) as Dictionary).keys().filter(func(surface: String) -> bool: return found.floors[other].has(surface))
				_owned(reached.is_empty(), "%s crossing %s %s" % [where, route.id, other], "%s: %s reaches %s, an end of the %s %s that only %s may use; give one-pip access by geography, a control only that pip reaches or a carried item" % [where, other, ", ".join(reached), kind.trim_suffix("s"), route.id, owner])
		for zone: Dictionary in stage.get("access_zones", []):
			var owner := str(zone.get("owner_slot", ""))
			if owner.is_empty(): continue
			var other := "p1" if owner == "p0" else "p0"
			_owned(not found.floors[other].has(str(zone.surface_id)), "%s zone %s %s" % [where, zone.id, other], "%s: %s reaches %s, the floor of the zone %s that only %s may enter" % [where, other, zone.surface_id, zone.id, owner])
		var open := OpenControls.pinned(level)
		for kind: String in ["controls", "levers", "pressure_pads"]:
			for entity: Dictionary in stage.get(kind, []):
				var owner := str(entity.get("owner_slot", ""))
				var surface := _control_floor(stage, entity)
				# Open controls: either pip works it, so an owner would be a lie.
				if open:
					_expect(not entity.has("owner_slot"), "%s %s %s owned" % [where, _kind_name(kind), entity.id], "%s: the %s %s names an owner (%s), but the chapter plays open controls, where either pip works it; put it where only one pip goes instead" % [where, _kind_name(kind), entity.id, owner])
					continue
				if owner.is_empty(): continue
				# A control the checker cannot place on a floor would pass unseen: say so.
				_expect(not surface.is_empty(), "%s %s %s floor" % [where, _kind_name(kind), entity.id], "%s: the %s %s has no surface_id and no island at its height under it, so no one can tell who reaches it" % [where, _kind_name(kind), entity.id])
				if surface.is_empty(): continue
				var other := "p1" if owner == "p0" else "p0"
				_owned(not found.floors[other].has(surface), "%s %s %s %s" % [where, _kind_name(kind), entity.id, other], "%s: %s reaches %s, the floor of the %s %s that only %s may work; put it where only its pip goes" % [where, other, surface, _kind_name(kind), entity.id, owner])

## The floor a control stands on: its own, else the island under it at its height.
static func _control_floor(stage: Dictionary, entity: Dictionary) -> String:
	if entity.has("surface_id"): return str(entity.surface_id)
	var at: Array = entity.get("position_cm", [])
	if at.size() < 2: return ""
	for island: Dictionary in stage.get("islands", []):
		var r: Array = island.rect_cm
		if int(island.get("height_cm", 0)) == int(entity.get("height_cm", 0)) and int(at[0]) >= int(r[0]) and int(at[0]) <= int(r[2]) and int(at[1]) >= int(r[1]) and int(at[1]) <= int(r[3]): return str(island.id)
	return ""

func _owned(ok: bool, id: String, message: String) -> void:
	if not ok: _owned_seen += 1
	_expect(ok, id, message)

# --- Reach ----------------------------------------------------------------------

func _reach(key: String) -> void:
	var level := Registry.definition(key)
	var graph: RefCounted = LevelGraph.new(level)
	var journey := Registry.is_journey(key)
	var seen: Dictionary = {}
	for item: Dictionary in Stages.stages(key, level):
		var stage: Dictionary = item.view
		var where := "%s %s" % [key, stage.stage_id]
		if item.checkpoint.is_empty():
			_check(false, "%s: no checkpoint to open from (write the chapter's fixtures)" % where)
			continue
		var found: Dictionary = graph.reach(stage, item.checkpoint, journey)
		for slot: String in found.floors:
			for id: String in found.floors[slot]: seen[id] = true
		var open := OpenControls.pinned(level)
		for kind: String in ["controls", "levers", "pressure_pads"]:
			for entity: Dictionary in stage.get(kind, []):
				if open: _stand_either(graph, found, entity, where, kind, journey)
				else: _stand(graph, found, entity, str(entity.get("owner_slot", "")), where, kind, journey)
		var goal: Dictionary = stage.get("goal", {})
		if not goal.is_empty():
			if str(stage.get("goal_policy", {}).get("kind", "ring")) == "ring":
				_stand(graph, found, goal, Shots.goal_slot(stage), where, "goal", journey)
			else:
				var surface := str(goal.get("surface_id", ""))
				_expect(found.floors.p0.has(surface) or found.floors.p1.has(surface), "%s goal %s" % [where, goal.id], "%s: neither pip reaches the goal %s's floor %s at %s" % [where, goal.id, surface, _cm(goal.position_cm)])
	for island: Dictionary in level.islands:
		_expect(seen.has(str(island.id)), "%s floor %s" % [key, island.id], "%s: no stage lets either pip reach the floor %s (%s)" % [key, island.id, _rect(island.rect_cm)])

## The pip that works the entity (its owner; a goal's ringer) reaches its
## floor and can stand within its radius. The engines let only the owner work
## a control, lever or pad, so one with no owner fails.
func _stand(graph: RefCounted, found: Dictionary, entity: Dictionary, slot: String, where: String, kind: String, journey: bool) -> void:
	var surface := str(entity.get("surface_id", ""))
	var label := "%s %s" % [_kind_name(kind), entity.id]
	var id := "%s %s" % [where, label]
	if slot.is_empty():
		_expect(false, id, "%s: the %s has no owner, so no pip can work it" % [where, label])
		return
	var reached: bool = found.floors.get(slot, {}).has(surface)
	_expect(reached, id, "%s: %s never reaches the %s on %s at %s" % [where, slot, label, surface, _cm(entity.position_cm)])
	if reached: _expect(graph.can_stand_at(entity, slot, found.open, journey), id + " stand", "%s: %s cannot stand within reach of the %s at %s on %s (at its height)" % [where, slot, label, _cm(entity.position_cm), surface])

## Open controls: some pip reaches the entity's floor and can stand within reach.
func _stand_either(graph: RefCounted, found: Dictionary, entity: Dictionary, where: String, kind: String, journey: bool) -> void:
	var surface := str(entity.get("surface_id", ""))
	var label := "%s %s" % [_kind_name(kind), entity.id]
	var id := "%s %s" % [where, label]
	var reached: Array = ["p0", "p1"].filter(func(slot: String) -> bool: return found.floors.get(slot, {}).has(surface))
	_expect(not reached.is_empty(), id, "%s: no pip ever reaches the %s on %s at %s" % [where, label, surface, _cm(entity.position_cm)])
	if reached.is_empty(): return
	var stands := reached.any(func(slot: String) -> bool: return graph.can_stand_at(entity, slot, found.open, journey))
	_expect(stands, id + " stand", "%s: no pip can stand within reach of the %s at %s on %s (at its height)" % [where, label, _cm(entity.position_cm), surface])

static func _kind_name(kind: String) -> String:
	match kind:
		"controls": return "selector"
		"levers": return "lever"
		"pressure_pads": return "pad"
	return kind

# --- Both pips (open controls) ---------------------------------------------------

## On open controls, every stage needs both pips (header).
func _needs_both(key: String) -> void:
	var level := Registry.definition(key)
	if not OpenControls.pinned(level): return
	var journey := Registry.is_journey(key)
	var graph: RefCounted = LevelGraph.new(level)
	for item: Dictionary in Stages.stages(key, level):
		if item.checkpoint.is_empty(): continue
		var stage: Dictionary = item.view
		var where := "%s %s" % [key, stage.stage_id]
		_expect(not solo_finish(graph, stage, item.checkpoint, journey), "%s alone" % where, "%s: with the first pip standing still, the second still reaches the goal with it lit; give the first pip a part only it can play" % where)

## Whether the second pip could finish `stage` alone, the first standing still.
static func solo_finish(graph: RefCounted, stage: Dictionary, checkpoint: Dictionary, journey: bool) -> bool:
	var first := str(stage.get("first_player_slot", "p0"))
	var second := Shots.goal_slot(stage)
	var found: Dictionary = graph.reach(stage, checkpoint, journey, first)
	var goal: Dictionary = stage.get("goal", {})
	if goal.is_empty() or not found.floors[second].has(str(goal.get("surface_id", "")) ): return false
	if str(stage.get("goal_policy", {}).get("kind", "ring")) == "ring" and not graph.can_stand_at(goal, second, found.open, journey): return false
	var when: Dictionary = stage.get("goal_policy", {}).get("when", {})
	return when.is_empty() or graph.gate_can_hold({"when": when}, stage, found.settable, checkpoint.get("mechanisms", {}), journey, found.floors)

## The probe can fail: Conservatory@1's first stage on open controls, its forks
## on the court both pips share, lets the second pip finish alone; @2's
## balcony does not.
func _needs_both_rule() -> void:
	var opened: Dictionary = OpenControls.pin(Registry.definition("conservatory@1").duplicate(true))
	var stage: Dictionary = Stages.stages("conservatory@1", opened)[0]
	_check(solo_finish(LevelGraph.new(opened), stage.view, Stages.starts_checkpoint(opened), true), "On open controls Conservatory@1's first stage can be finished by the second pip alone, so the probe can fail")
	var balcony := Registry.definition("conservatory@2")
	_check(not solo_finish(LevelGraph.new(balcony), Stages.stages("conservatory@2", balcony)[0].view, Stages.starts_checkpoint(balcony), true), "Conservatory@2's balcony keeps the forks the first pip's, so its first stage needs both")

# --- Props ----------------------------------------------------------------------

func _props(key: String) -> void:
	var data := Dressing.for_key(key)
	if data.get("props", {}).is_empty(): return
	var level := Registry.definition(key)
	var heights: Dictionary = {}
	for island: Dictionary in level.islands: heights[str(island.id)] = float(island.get("height_cm", 0)) / 100.0
	for stage: Dictionary in level.stages:
		var where := "%s %s" % [key, stage.id]
		var solid: Array = []
		for spec: Dictionary in Props.expand(Dressing.stage_props(data, str(stage.id))):
			var extent := Props.extent(spec)
			if bool(extent.flat) or str(spec.get("kind", "")) == "bank": continue
			var base := float(heights.get(str(spec.get("surface", "")), 0.0)) + float(extent.base)
			solid.append({"spec": spec, "rect": extent.rect, "round": _round(spec), "low": base, "high": base + float(extent.height)})
		for a in range(solid.size()):
			for b in range(a + 1, solid.size()):
				var one: Dictionary = solid[a]
				var two: Dictionary = solid[b]
				if one.high <= two.low + 0.01 or two.high <= one.low + 0.01: continue
				var share := _share(one, two)
				var id := "%s props %s and %s" % [where, _prop(one.spec), _prop(two.spec)]
				_expect(share <= PROP_SHARE, id, "%s: the %s and the %s stand in each other (%d%% of the smaller)" % [where, _prop(one.spec), _prop(two.spec), roundi(share * 100.0)])

## The prop rule on small cases, so it can fail at all.
func _share_rule() -> void:
	var crate := {"rect": Rect2(-0.2, -0.2, 0.4, 0.4), "round": true}
	var inside := {"rect": Rect2(-0.1, -0.1, 0.2, 0.4), "round": false}
	var beside := {"rect": Rect2(0.15, -0.2, 0.4, 0.4), "round": true}
	var apart := {"rect": Rect2(1.0, 1.0, 0.4, 0.4), "round": true}
	_check(_share(crate, crate) > 0.99 and _share(crate, inside) > PROP_SHARE, "Two props in one place, or one inside another, stand in each other")
	_check(_share(crate, beside) <= PROP_SHARE and _share(crate, apart) == 0.0, "Props that only touch, or stand apart, pass")

## Round kinds keep a circle footprint; boxes and lines keep their rectangle.
static func _round(spec: Dictionary) -> bool:
	return str(spec.get("kind", "")) not in ["bench", "cottage", "rug", "path", "planter", "boat", "lobster_pot", "shelf", "frame", "fence", "hedge", "wall"]

## How much of the smaller footprint the two share, from 0 to 1 (a circle is
## sampled on a 9 by 9 grid over its square).
static func _share(one: Dictionary, two: Dictionary) -> float:
	var small: Dictionary = one if _area(one) <= _area(two) else two
	var large: Dictionary = two if small == one else one
	if not (small.rect as Rect2).intersects(large.rect): return 0.0
	var inside := 0
	var total := 0
	var rect: Rect2 = small.rect
	for i in range(9):
		for j in range(9):
			var point := rect.position + rect.size * Vector2((float(i) + 0.5) / 9.0, (float(j) + 0.5) / 9.0)
			if not _covers(small, point): continue
			total += 1
			if _covers(large, point): inside += 1
	return float(inside) / float(maxi(total, 1))

static func _covers(item: Dictionary, point: Vector2) -> bool:
	var rect: Rect2 = item.rect
	if not item.round: return rect.has_point(point)
	return point.distance_to(rect.get_center()) <= rect.size.x * 0.5

static func _area(item: Dictionary) -> float:
	var rect: Rect2 = item.rect
	return rect.get_area() * (PI / 4.0 if item.round else 1.0)

static func _prop(spec: Dictionary) -> String:
	return "%s at %s" % [spec.get("kind", "?"), _cm(spec.get("at", spec.get("from", [0, 0])))]

static func _cm(at: Array) -> String:
	return "(%d, %d) cm" % [int(at[0]), int(at[1])]

static func _rect(r: Array) -> String:
	return "(%d, %d) to (%d, %d) cm" % [int(r[0]), int(r[1]), int(r[2]), int(r[3])]
