extends SceneTree
## The level checker, from the definitions and the dressing alone (no world):
## every stage of every chapter as its family lays it out (floors, crossings
## and spots, services/level_layout.gd), published or not (superseded versions
## included), and a failure names the chapter, the stage and the spot.
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
##    A crossing an open version keeps owned must still be needed: opening it
##    lets one pip finish a stage alone.
##  - Open turns (core/physical/open_turns.gd, 14 and 15): a stage ends when a
##    turn ends with both pips at its goal, its light holding. So no stage may
##    be finished by one pip alone across any number of its own turns while
##    the other does nothing: only a pip that starts at the goal could stand
##    there doing nothing, and the other would still have to reach it. Each
##    stage must be solvable: both pips reach the goal's floor and stand at it
##    with its light able to hold (an over-approximation; the chapter suite's
##    witness, played within the cap, is the proof). Each cap is a whole
##    number from 2 to 20. Owned crossings need a reason the solo probe sees.
##    And both pips must work something (the owner, 2026-11-16): a stage
##    fails if one pip could finish it working every control, lever and pad
##    itself while the other only walks along (level_graph.gd's walker). Give
##    each pip a part only it can reach: floor behind a crossing the other
##    opens, or a pad away from the crossing it holds, so the pip on it cannot
##    walk that crossing too. Published chapters are not on open turns.
##  - Props (content/dressing, kit/props.gd extents): two props standing in
##    each other on a stage. Props against routes, pads, levers, goals and
##    starts, and the camera's view of them, are tests/test_dressing_lint.gd's.
##    Scenery a world builds in code is not dressing and is not covered here.
## The bubbles and the camera's framing need a built world:
## tests/test_level_view.gd. KNOWN lists what fails on purpose, with why; an
## entry that stops failing fails the suite, so the list never goes stale.
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Shots = preload("res://tests/level_tools/stage_shots.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const Props = preload("res://presentation/kit/props.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const PropRules = preload("res://presentation/kit/prop_rules.gd")
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
## Published spots the checker first read once their families were laid out
## (services/level_layout.gd): each is owned by its engine's own rule (only
## the pip whose part it is works the plate, pad or mirror; only the second
## pip rides First Steps' lift), and nothing in its world shows why.
const LAID_OUT_WHY := "published before the ownership rule, owned by its engine's own rule; first read by the checker when its family was laid out (2026-11-15)"
const KNOWN_LAID_OUT := [
	"first-steps@1 a-little-lift crossing little-lift p0",
	"first-steps@1 a-little-lift pad lift-power p1",
	"relay-isles@2 relay pad west-control p1",
	"relay-isles@2 relay pad relay-control p0",
	"relay-isles@2 garden pad west-control p1",
	"relay-isles@2 garden pad relay-control p0",
	"sleeping-lighthouse@2 borrowed-light selector harbour-mirror p0",
	"sleeping-lighthouse@2 borrowed-light pad source-pad p1",
	"sleeping-lighthouse@2 missing-piece selector court-mirror p0",
	"sleeping-lighthouse@2 two-promises selector upper-mirror p1",
	"sleeping-lighthouse@2 two-promises selector south-mirror p0",
	"sleeping-lighthouse@2 after-the-first-bell selector south-selector p0",
	"sleeping-lighthouse@2 a-welcome-left-on selector beacon-upper-mirror p0",
	"sleeping-lighthouse@2 a-welcome-left-on selector beacon-lower-mirror p1",
	"sleeping-lighthouse@2 a-welcome-left-on pad beacon-hold p0",
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
		if not Stages.laid_out(key):
			skipped.append(key)
			_check(false, "%s: its family %s lays out no stages (services/chapter_families.gd \"layout\"), so no level tool reads it" % [key, Index.data(key).family])
			continue
		var started := Time.get_ticks_msec()
		_reach(key)
		_ownership(key)
		_needs_both(key)
		_kept_crossings(key)
		_props(key)
		covered += 1
		print("LEVEL CHECKER: %s in %d ms" % [key, Time.get_ticks_msec() - started])
	_check(covered >= 11, "The checker walks every chapter (%d)" % covered)
	for id: String in KNOWN:
		_check(_found.has(id), "Known failure still fails, or comes off the list: %s (%s)" % [id, KNOWN[id]])
	for id: String in KNOWN_OWNERSHIP:
		_check(_found.has(id), "Known failure still fails, or comes off the list: %s (%s)" % [id, OWNERSHIP_WHY])
	for id: String in KNOWN_LAID_OUT:
		_check(_found.has(id), "Known failure still fails, or comes off the list: %s (%s)" % [id, LAID_OUT_WHY])
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

## A spot that must hold: it fails unless KNOWN (or KNOWN_OWNERSHIP, KNOWN_LAID_OUT) lists its id.
func _expect(ok: bool, id: String, message: String) -> void:
	if not ok:
		_found[id] = true
		var carried := _carried_ownership(id)
		if KNOWN.has(id) or KNOWN_OWNERSHIP.has(id) or KNOWN_LAID_OUT.has(id) or not carried.is_empty():
			print("KNOWN: %s (%s)" % [message, KNOWN.get(id, LAID_OUT_WHY if KNOWN_LAID_OUT.has(id) else OWNERSHIP_WHY if carried.is_empty() else "as %s" % carried)])
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
	var journey := Registry.is_journey(key)
	var open := OpenControls.pinned(Registry.definition(key))
	for item: Dictionary in _stages_of(key):
		if item.checkpoint.is_empty(): continue
		var stage: Dictionary = item.view
		var where := "%s %s" % [key, stage.stage_id]
		var found: Dictionary = _graph(stage).reach(stage, item.checkpoint, journey)
		var ends := _route_ends(stage)
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

## The level graph of a plan's floors and crossings, built once per distinct
## set of them (a chapter's stages usually share one).
var _graphs: Dictionary = {}
## Each chapter's stages (level_stages.gd), read once.
var _stages: Dictionary = {}

func _stages_of(key: String) -> Array:
	if not _stages.has(key): _stages[key] = Stages.stages(key)
	return _stages[key]

func _graph(plan: Dictionary, owned: bool = true) -> RefCounted:
	var floors: Dictionary = {}
	for field: String in ["islands", "bridges", "stairs", "drops", "obstacles", "access_zones"]:
		floors[field] = plan.get(field, []).duplicate(true)
	# The rules pin: on open controls either pip works a control (level_graph.gd).
	if plan.has("simulation_version"): floors.simulation_version = plan.simulation_version
	if not owned:
		for kind: String in ["bridges", "stairs"]:
			for route: Dictionary in floors[kind]: route.erase("owner_slot")
	var id := JSON.stringify(floors)
	if not _graphs.has(id): _graphs[id] = LevelGraph.new(floors)
	return _graphs[id]

## The floors each crossing of `plan` joins, with no owners: the edges a pip
## could step if ownership were no rule at all. Route id -> {floor id: true}.
var _ends: Dictionary = {}

func _route_ends(plan: Dictionary) -> Dictionary:
	var physical: RefCounted = _graph(plan, false)
	if not _ends.has(physical):
		var ends: Dictionary = {}
		for pair: String in physical.build("p0"):
			var sides := pair.split(">")
			for index in range(2):
				if physical.route_bit.has(sides[index]): (ends.get_or_add(sides[index], {}) as Dictionary)[sides[1 - index]] = true
		_ends[physical] = ends
	return _ends[physical]

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
	var journey := Registry.is_journey(key)
	var open := OpenControls.pinned(Registry.definition(key))
	var seen: Dictionary = {}
	var floors: Dictionary = {}
	for item: Dictionary in _stages_of(key):
		var stage: Dictionary = item.view
		var where := "%s %s" % [key, stage.stage_id]
		for island: Dictionary in stage.get("islands", []): floors[str(island.id)] = island
		if item.checkpoint.is_empty():
			_check(false, "%s: no checkpoint to open from (write the chapter's fixtures)" % where)
			continue
		var graph := _graph(stage)
		var found: Dictionary = graph.reach(stage, item.checkpoint, journey)
		for slot: String in found.floors:
			for id: String in found.floors[slot]: seen[id] = true
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
	for id: String in floors:
		_expect(seen.has(id), "%s floor %s" % [key, id], "%s: no stage lets either pip reach the floor %s (%s)" % [key, id, _rect(floors[id].rect_cm)])

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

## On open controls, every stage needs both pips; on open turns, neither pip
## finishes alone, both can reach the goal, and each cap is one a level may
## set (header).
func _needs_both(key: String) -> void:
	var level := Registry.definition(key)
	if not OpenControls.pinned(level): return
	var turns := OpenTurns.pinned(level)
	var journey := Registry.is_journey(key)
	for item: Dictionary in _stages_of(key):
		if item.checkpoint.is_empty(): continue
		var stage: Dictionary = item.view
		var graph := _graph(stage)
		var where := "%s %s" % [key, stage.stage_id]
		if turns:
			_expect(OpenTurns.cap_valid(item.stage), "%s turn cap" % where, "%s: its turn_cap (%s) is not a whole number of turns from %d to %d" % [where, item.stage.get("turn_cap", OpenTurns.DEFAULT_CAP), OpenTurns.MIN_CAP, OpenTurns.MAX_CAP])
			for slot: String in ["p0", "p1"]:
				var other := "p1" if slot == "p0" else "p0"
				_expect(not solo_finish(graph, stage, item.checkpoint, journey, slot), "%s alone %s" % [where, slot], "%s: %s starts at the goal, so %s finishes alone while it does nothing; start it away from the goal" % [where, other, slot])
				_expect(not presses_alone(graph, stage, item.checkpoint, journey, slot), "%s presses alone %s" % [where, slot], "%s: %s can finish it working every control, lever and pad itself while %s only walks; give %s a part only it reaches (floor behind a crossing %s opens, or a pad away from the crossing it holds)" % [where, slot, other, other, slot])
			_expect(solvable(graph, stage, item.checkpoint, journey), "%s solvable" % where, "%s: the two pips can never both stand at the goal %s with its light holding" % [where, stage.get("goal", {}).get("id", "")])
		else:
			_expect(not solo_finish(graph, stage, item.checkpoint, journey), "%s alone" % where, "%s: with the first pip standing still, the second still reaches the goal with it lit; give the first pip a part only it can play" % where)
		# The first turn sees the second pip standing still at its start; on a
		# pad there it would hold it for the first turn.
		var second: Dictionary = item.checkpoint.get("players", {}).get(Shots.goal_slot(stage), {})
		for pad: Dictionary in stage.get("pressure_pads", []):
			_expect(second.is_empty() or not Seven.near(second, pad), "%s pad %s under the second pip" % [where, pad.id], "%s: the second pip starts on the pad %s, so it holds it through the first turn" % [where, pad.id])

## Whether one pip could finish `stage` alone, the other standing still at its
## start. Two turns (the default): the second pip lights the goal itself. Open
## turns (`solo`, either pip): the stage ends with both pips at the goal, so
## the still pip must already start there.
static func solo_finish(graph: RefCounted, stage: Dictionary, checkpoint: Dictionary, journey: bool, solo: String = "") -> bool:
	var live := Shots.goal_slot(stage) if solo.is_empty() else solo
	var still := "p1" if live == "p0" else "p0"
	var goal: Dictionary = stage.get("goal", {})
	if goal.is_empty(): return false
	if not solo.is_empty() and not _starts_at(checkpoint.get("players", {}).get(still, {}), goal): return false
	var found: Dictionary = graph.reach(stage, checkpoint, journey, still)
	return _goal_holds(graph, stage, checkpoint, journey, found, [live])

## Open turns: whether both pips could stand at the goal together with its
## light holding, nobody held still. Both stand at the goal then, so the light
## may count only the pads a pip at the goal could hold. Necessary, not
## enough: the witness proves it.
static func solvable(graph: RefCounted, stage: Dictionary, checkpoint: Dictionary, journey: bool) -> bool:
	var goal: Dictionary = stage.get("goal", {})
	if goal.is_empty(): return false
	var found: Dictionary = graph.reach(stage, checkpoint, journey)
	return _goal_holds(graph, _at_goal(stage), checkpoint, journey, found, ["p0", "p1"])

## Open turns: whether `presser` could finish `stage` working every control,
## lever and pad itself while the other pip only walks (level_graph.gd's
## walker): both reach the goal and stand at it, the presser by the crossings
## it opens for its own walking, and the light can hold. An over-approximation,
## so a stage it clears needs both pips to work something.
static func presses_alone(graph: RefCounted, stage: Dictionary, checkpoint: Dictionary, journey: bool, presser: String) -> bool:
	if stage.get("goal", {}).is_empty(): return false
	var walker := "p1" if presser == "p0" else "p0"
	var found: Dictionary = graph.reach(stage, checkpoint, journey, "", walker)
	var own: Dictionary = found.duplicate()
	own.open = found.own
	var there := _at_goal(stage)
	return _goal_holds(graph, there, checkpoint, journey, found, [walker]) and _goal_holds(graph, there, checkpoint, journey, own, [presser])

## `stage` with only the pads a pip standing at the goal could hold: both
## pips stand at the goal when a stage of open turns ends.
static func _at_goal(stage: Dictionary) -> Dictionary:
	var goal: Dictionary = stage.goal
	var there: Dictionary = stage.duplicate(true)
	there.pressure_pads = stage.get("pressure_pads", []).filter(func(pad: Dictionary) -> bool: return str(pad.get("surface_id", "")) == str(goal.get("surface_id", "")) and Vector2(float(pad.position_cm[0]), float(pad.position_cm[1])).distance_to(Vector2(float(goal.position_cm[0]), float(goal.position_cm[1]))) <= float(int(pad.get("radius_cm", 28)) + int(goal.get("radius_cm", 28))))
	return there

## Whether each pip in `slots` reaches the goal's floor and can stand at it, and
## the goal's light can hold, with what `found` (a reach) opens.
static func _goal_holds(graph: RefCounted, stage: Dictionary, checkpoint: Dictionary, journey: bool, found: Dictionary, slots: Array) -> bool:
	var goal: Dictionary = stage.goal
	var ring := str(stage.get("goal_policy", {}).get("kind", "ring")) == "ring"
	for slot: String in slots:
		if not found.floors[slot].has(str(goal.get("surface_id", ""))): return false
		if ring and not graph.can_stand_at(goal, slot, found.open, journey): return false
	var when: Dictionary = stage.get("goal_policy", {}).get("when", {})
	# Rules 16: an item carried at the goal is carried on the goal's floor (level_graph.gd with_items).
	return when.is_empty() or graph.gate_can_hold(graph.with_items({"when": when, "surface_id": str(goal.get("surface_id", ""))}, found.settable), stage, found.settable, checkpoint.get("mechanisms", {}), journey, found.floors)

## Whether a pip's start (a checkpoint player) stands at `goal`: its floor, within its radius.
static func _starts_at(player: Dictionary, goal: Dictionary) -> bool:
	if player.is_empty() or str(player.get("surface_id", "")) != str(goal.get("surface_id", "")): return false
	return Vector2i(int(player.x), int(player.z)).distance_squared_to(Vector2i(int(goal.position_cm[0]), int(goal.position_cm[1]))) <= int(goal.get("radius_cm", 28)) ** 2

## On open controls, a crossing the level keeps owned must be needed: with it
## open to both pips, some stage could be finished by one pip alone.
func _kept_crossings(key: String) -> void:
	var level := Registry.definition(key)
	if not OpenControls.pinned(level): return
	var turns := OpenTurns.pinned(level)
	var journey := Registry.is_journey(key)
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in level.get(kind, []):
			if not route.has("owner_slot"): continue
			var opened := level.duplicate(true)
			for other: Dictionary in opened.get(kind, []):
				if str(other.id) == str(route.id): other.erase("owner_slot")
			var needed := false
			for item: Dictionary in Stages.stages(key, opened):
				if item.checkpoint.is_empty(): continue
				for solo: String in (["p0", "p1"] if turns else [""]):
					needed = needed or solo_finish(_graph(item.view), item.view, item.checkpoint, journey, solo)
			_expect(needed, "%s kept %s" % [key, route.id], "%s: the %s %s stays %s's only, but open to both pips no stage could be finished by one pip alone; open it" % [key, kind.trim_suffix("s"), route.id, route.owner_slot])

## The probes can fail: Conservatory@1's first stage on open controls, its
## forks on the court both pips share, lets the second pip finish alone; @2's
## balcony does not. On open turns Long Way Home@3's first stage is solvable
## and nobody finishes it alone, but it would be soloable with the second pip
## starting at the window, and unsolvable with a light no selector gives.
func _needs_both_rule() -> void:
	var opened: Dictionary = OpenControls.pin(Registry.definition("conservatory@1").duplicate(true))
	var stage: Dictionary = Stages.stages("conservatory@1", opened)[0]
	_check(solo_finish(_graph(stage.view), stage.view, Stages.starts_checkpoint(opened), true), "On open controls Conservatory@1's first stage can be finished by the second pip alone, so the probe can fail")
	var home := Registry.definition("long-way-home@3")
	var path: Dictionary = _stages_of("long-way-home@3")[0]
	var graph := _graph(path.view)
	var first := str(path.view.get("first_player_slot", "p0"))
	var second := "p1" if first == "p0" else "p0"
	_check(OpenTurns.pinned(home) and solvable(graph, path.view, path.checkpoint, true) and not solo_finish(graph, path.view, path.checkpoint, true, second), "Long Way Home@3's first stage on open turns is solvable and the second pip never finishes it alone")
	var waiting: Dictionary = path.checkpoint.duplicate(true)
	var goal: Dictionary = path.view.goal
	waiting.players[second] = {"x": int(goal.position_cm[0]), "z": int(goal.position_cm[1]), "height": int(goal.get("height_cm", 0)), "surface_id": str(goal.surface_id)}
	_check(solo_finish(graph, path.view, waiting, true, first), "With the second pip starting at the window, the first finishes the stage alone, so the open turns probe can fail")
	var dark: Dictionary = path.view.duplicate(true)
	dark.goal_policy = {"kind": "ring", "when": {"control_id": "path-selector", "value": "nowhere"}}
	_check(not solvable(graph, dark, path.checkpoint, true), "A goal whose light no selector gives is unsolvable, so the solvable probe can fail")
	var later: Dictionary = _stages_of("long-way-home@3")[1]
	var place: Dictionary = later.view.duplicate(true)
	place.goal_policy = {"kind": "ring", "when": {"pad_id": "near-window"}}
	_check(not solvable(_graph(later.view), place, later.checkpoint, true), "A goal lit only while someone holds a pad away from it is unsolvable: both pips stand at the goal")
	# Both pips work something: Long Way Home@2's first stage on open turns
	# lets the first pip turn both selectors while the second only walks over.
	var older: Dictionary = OpenControls.open_crossings(OpenTurns.pin(Registry.definition("long-way-home@2").duplicate(true), {}), [])
	var leave: Dictionary = Stages.stages("long-way-home@2", older)[0]
	_check(presses_alone(_graph(leave.view), leave.view, Stages.starts_checkpoint(older), true, first), "On open turns Long Way Home@2's first stage lets one pip work everything while the other walks, so the both-pips probe can fail")
	_check(not presses_alone(graph, path.view, path.checkpoint, true, first) and not presses_alone(graph, path.view, path.checkpoint, true, second), "Long Way Home@3's first stage needs both pips: the bank gate is the second pip's")
	# A pad counts for the presser's own walking only beside the crossing it
	# holds: Conservatory@2's return shutter moved to the room's west edge
	# lets the pip on it step onto the return and turn the final mirror itself.
	var returns: Dictionary = _stages_of("conservatory@2")[1]
	var beside: Dictionary = returns.view.duplicate(true)
	for pad: Dictionary in beside.pressure_pads:
		if pad.id == "return-shutter": pad.position_cm = [340, 56]
	var lights := _graph(returns.view)
	_check(not presses_alone(lights, returns.view, returns.checkpoint, true, "p0") and presses_alone(lights, beside, returns.checkpoint, true, "p0"), "A pad holds a crossing for the pip on it only when it stands beside that crossing")
	_check(OpenTurns.cap_valid({"turn_cap": 10}) and OpenTurns.cap_valid({"turn_cap": 11}) and not OpenTurns.cap_valid({"turn_cap": 22}) and not OpenTurns.cap_valid({"turn_cap": 1}) and OpenTurns.cap_valid({}), "A cap is a whole number from 2 to 20; a stage with none gets 10")

# --- Props ----------------------------------------------------------------------

func _props(key: String) -> void:
	var data := Dressing.for_key(key)
	if data.get("props", {}).is_empty(): return
	for item: Dictionary in _stages_of(key):
		var where := "%s %s" % [key, item.stage.id]
		var heights := PropRules.heights(item.view)
		var solid: Array = []
		for spec: Dictionary in Props.expand(Dressing.stage_props(data, str(item.stage.id))):
			var piece := PropRules.solid(spec, heights)
			if not piece.is_empty(): solid.append(piece.merged({"spec": spec}))
		for a in range(solid.size()):
			for b in range(a + 1, solid.size()):
				var one: Dictionary = solid[a]
				var two: Dictionary = solid[b]
				if one.high <= two.low + 0.01 or two.high <= one.low + 0.01: continue
				var share := PropRules.share(one, two)
				var id := "%s props %s and %s" % [where, _prop(one.spec), _prop(two.spec)]
				_expect(share <= PropRules.PROP_SHARE, id, "%s: the %s and the %s stand in each other (%d%% of the smaller)" % [where, _prop(one.spec), _prop(two.spec), roundi(share * 100.0)])

## The prop rule on small cases, so it can fail at all.
func _share_rule() -> void:
	var crate := {"rect": Rect2(-0.2, -0.2, 0.4, 0.4), "round": true}
	var inside := {"rect": Rect2(-0.1, -0.1, 0.2, 0.4), "round": false}
	var beside := {"rect": Rect2(0.15, -0.2, 0.4, 0.4), "round": true}
	var apart := {"rect": Rect2(1.0, 1.0, 0.4, 0.4), "round": true}
	_check(PropRules.share(crate, crate) > 0.99 and PropRules.share(crate, inside) > PropRules.PROP_SHARE, "Two props in one place, or one inside another, stand in each other")
	_check(PropRules.share(crate, beside) <= PropRules.PROP_SHARE and PropRules.share(crate, apart) == 0.0, "Props that only touch, or stand apart, pass")

static func _prop(spec: Dictionary) -> String:
	return "%s at %s" % [spec.get("kind", "?"), _cm(spec.get("at", spec.get("from", [0, 0])))]

static func _cm(at: Array) -> String:
	return "(%d, %d) cm" % [int(at[0]), int(at[1])]

static func _rect(r: Array) -> String:
	return "(%d, %d) to (%d, %d) cm" % [int(r[0]), int(r[1]), int(r[2]), int(r[3])]
