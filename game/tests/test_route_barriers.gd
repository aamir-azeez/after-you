extends SceneTree
## The route barriers (presentation/kit/route_barriers.gd) and the refusal
## finder that wiggles them (presentation/barrier_refusals.gd):
##  - the rules on small made-up stages: an owner gate opens for its owner on
##    the crossing or near its end, and stays open while both pips stand there;
##    a closed stair shows its chain; a zone's rope drops near its owner; a
##    push into each of them is found, and nothing else is;
##  - every fixture turn of every floor chapter, as played and as the memory:
##    no spirit ever walks through a shut gate, a stair's chain or a zone's
##    rope while it shows, and the memory's pushes are the ones its own turn
##    found (so a push rattles the same live, as the memory and in a replay);
##  - every gate of every floor chapter's stages is a short, upright gate
##    straight across its crossing's mouth, no wider than the way it lands on,
##    and no gate meets another gate or a zone's rope, shut or open;
##  - the sound map plays a rattle and a clunk named by what was pushed.
const Registry = preload("res://services/chapter_registry.gd")
const Golden = preload("res://tests/golden_support.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const RouteBarriers = preload("res://presentation/kit/route_barriers.gd")
const BarrierRefusals = preload("res://presentation/barrier_refusals.gd")
const ChapterSoundMap = preload("res://services/chapter_sound_map.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const PropStyles = preload("res://content/dressing/prop_styles.gd")
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

func _run() -> void:
	for style: String in PropStyles.SLOTS.barrier:
		_check(RouteBarriers.EDGE_LOOKS.has(StringName(str(PropStyles.SLOTS.barrier[style].edge))), "The barrier style %s names a zone edge look" % style)
	_rules()
	_shapes()
	_refusals()
	_sounds()
	var played := 0
	for key: String in Registry.keys():
		if not Registry.is_cooperative(key): continue
		played += _fixtures(key)
	_check(played >= 12, "Every floor chapter's fixture turns were walked (%d stages)" % played)
	print("ROUTE BARRIERS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# --- Rules on a made-up stage ------------------------------------------------------

## Two islands joined by a bridge p1 owns, a stair to a ledge (closed until a
## lever), and a zone p0 owns on the east island.
static func _view() -> Dictionary:
	return {
		"islands": [{"id": "west", "rect_cm": [-300, -100, 0, 100], "height_cm": 0}, {"id": "east", "rect_cm": [200, -100, 500, 100], "height_cm": 0}, {"id": "ledge", "rect_cm": [-300, 260, 0, 400], "height_cm": 64}],
		"bridges": [{"id": "plank", "rect_cm": [0, -32, 200, 32], "height_cm": 0, "from_surface": "west", "to_surface": "east", "owner_slot": "p1"}],
		"stairs": [{"id": "steps", "rect_cm": [-200, 100, -136, 260], "axis": "z", "from_height_cm": 0, "to_height_cm": 64}],
		"access_zones": [{"id": "bed", "rect_cm": [300, -60, 420, 60], "surface_id": "east", "owner_slot": "p0"}],
		"levers": [{"id": "pull", "position_cm": [-250, -60], "surface_id": "west", "radius_cm": 40, "owner_slot": "p0"}],
	}

static func _player(x: int, z: int, surface: String, height: int = 0) -> Dictionary:
	return {"x": x, "z": z, "height": height, "surface_id": surface}

static func _mouth(layout: Dictionary, route: String, end: int) -> Dictionary:
	for mouth: Dictionary in layout.mouths:
		if mouth.route == route and int(mouth.end) == end: return mouth
	return {}

func _rules() -> void:
	var view := _view()
	var layout := RouteBarriers.layout(view)
	var west := _mouth(layout, "plank", 0)
	var east := _mouth(layout, "plank", 1)
	_check(not west.is_empty() and not east.is_empty() and west.owner == "p1", "An owned bridge gets an owner gate at both ends it lands on")
	_check(not _mouth(layout, "steps", 0).is_empty() and not _mouth(layout, "steps", 1).is_empty() and _mouth(layout, "steps", 0).stair_gate, "A stair gets a stair gate at its foot and head")
	_check(layout.spans.size() >= 4, "An access zone in the middle of its island is edged on all four sides (%d stretches)" % layout.spans.size())
	_check(layout.locks.size() == 1 and layout.locks[0].id == "pull", "An owned lever gets a lock")
	var skipped := RouteBarriers.layout(view, {"steps": "drawn by the world"})
	_check(_mouth(skipped, "steps", 0).is_empty(), "A skipped stair gets no stair gate")
	var far := {"bridges": {"plank": true, "steps": false}, "players": {"p0": _player(-250, 0, "west"), "p1": _player(450, 80, "east")}}
	var masks := RouteBarriers.masks_of(layout, far)
	_check(masks[west.slot] & RouteBarriers.SHUT and not masks[west.slot] & RouteBarriers.OPEN, "An owner gate is shut while its owner is far away")
	_check(masks[_mouth(layout, "steps", 0).slot] & RouteBarriers.CHAIN, "A closed stair shows its chain")
	var on := far.duplicate(true)
	on.players.p1 = _player(100, 0, "plank")
	masks = RouteBarriers.masks_of(layout, on)
	_check(masks[west.slot] & RouteBarriers.OPEN and masks[east.slot] & RouteBarriers.OPEN, "Both ends open while the owner is on the crossing")
	var both := far.duplicate(true)
	both.players.p1 = _player(-40, 0, "west")
	both.players.p0 = _player(-30, 10, "west")
	masks = RouteBarriers.masks_of(layout, both)
	_check(masks[west.slot] & RouteBarriers.OPEN and masks[east.slot] & RouteBarriers.SHUT, "With both pips at one end the owner wins: that end opens, the far end stays shut")
	var closed := far.duplicate(true)
	closed.bridges.plank = false
	masks = RouteBarriers.masks_of(layout, closed)
	_check(masks[west.slot] == 0, "A closed owned bridge shows no gate (its missing deck shows it)")
	var open_stair := far.duplicate(true)
	open_stair.bridges.steps = true
	_check(RouteBarriers.masks_of(layout, open_stair)[_mouth(layout, "steps", 0).slot] == 0, "An open unowned stair's chain is gone")
	var rope_near := false
	var rope_far := true
	var at_bed := far.duplicate(true)
	at_bed.players.p0 = _player(360, 0, "east")
	masks = RouteBarriers.masks_of(layout, at_bed)
	for span: Dictionary in layout.spans:
		if not masks[span.slot] & RouteBarriers.ROPE: rope_near = true
	masks = RouteBarriers.masks_of(layout, far)
	for span: Dictionary in layout.spans:
		if not masks[span.slot] & RouteBarriers.ROPE: rope_far = false
	_check(rope_near and rope_far, "A zone's rope drops near its owner and stands everywhere while the owner is away")
	var locked := far.duplicate(true)
	locked.players.p1 = _player(-240, -50, "west")
	_check(RouteBarriers.masks_of(layout, locked)[layout.locks[0].slot] == RouteBarriers.PADLOCK and RouteBarriers.masks_of(layout, far)[layout.locks[0].slot] == 0, "A lock shows while the other pip stands at the control, and only then")
	# Refusals: a push one step past a spirit's reach.
	var routes := {"plank": true, "steps": false}
	var at_edge := _player(-12, 0, "west")
	_check(RouteBarriers.refusal(view, routes, at_edge, "p0", Vector2.RIGHT, 12, 8).get("kind") == RouteBarriers.OWNER, "A push onto a crossing the other pip owns is an owner refusal")
	_check(RouteBarriers.refusal(view, routes, at_edge, "p1", Vector2.RIGHT, 12, 8).is_empty(), "Its owner is never refused")
	_check(RouteBarriers.refusal(view, routes, at_edge, "p0", Vector2.LEFT, 12, 8).is_empty(), "A push away from it finds nothing")
	routes.plank = false
	_check(RouteBarriers.refusal(view, routes, at_edge, "p0", Vector2.RIGHT, 12, 8).is_empty(), "A closed bridge is a gap, not a barrier")
	_check(RouteBarriers.refusal(view, routes, _player(-168, 88, "west"), "p1", Vector2(0, 1), 12, 8).get("kind") == RouteBarriers.STAIR, "A push onto a closed stair is a stair refusal")
	_check(RouteBarriers.refusal(view, routes, _player(290, 0, "east"), "p1", Vector2.RIGHT, 12, 8).get("kind") == RouteBarriers.ZONE, "A push into a zone the other pip owns is a zone refusal")
	_check(RouteBarriers.refusal(view, routes, _player(290, 0, "east"), "p0", Vector2.RIGHT, 12, 8).is_empty(), "A zone's owner walks in")

# --- Gate shapes ------------------------------------------------------------------

## A short, wide crossing (Slack Water's sea gates are 64 cm long and 128 cm
## wide), then every stage of every floor chapter.
func _shapes() -> void:
	var short := {
		"islands": [{"id": "west", "rect_cm": [-300, -100, 0, 100], "height_cm": 0}, {"id": "east", "rect_cm": [64, -100, 300, 100], "height_cm": 0}],
		"bridges": [{"id": "sluice", "rect_cm": [0, -64, 64, 64], "height_cm": 0, "owner_slot": "p0"}],
	}
	var problems := _gate_problems(short, "a short wide bridge")
	_check(problems.is_empty(), "The gates at both ends of a short wide bridge stand straight across it and never meet: %s" % [problems])
	var stages := 0
	for key: String in Registry.keys():
		if not Registry.is_cooperative(key): continue
		for entry: Dictionary in Stages.stages(key):
			stages += 1
			problems = _gate_problems(entry.view, "%s stage %d" % [key, int(entry.index) + 1])
			_check(problems.is_empty(), "%s stage %d: every gate is straight across its mouth and meets no other barrier: %s" % [key, int(entry.index) + 1, problems])
	_check(stages >= 12, "Every floor chapter's stages were measured (%d)" % stages)

## What is wrong with `view`'s gates: a leaf not square to the way through or
## wider than the way it lands on, two gates (posts, shut or open leaves) on
## one floor meeting, a gate crossing a zone's rope.
static func _gate_problems(view: Dictionary, where: String) -> Array:
	var problems: Array = []
	var layout := RouteBarriers.layout(view)
	var floors := RouteBarriers.floors_of(view)
	var parts: Array = []
	for mouth: Dictionary in layout.mouths:
		var along := Vector2(mouth.along)
		var across := Vector2(along.y, -along.x)
		var at := Vector2(mouth.at.x, mouth.at.z)
		var name := "%s end %d" % [mouth.route, mouth.end]
		for share: float in [-0.95, 0.0, 0.95]:
			if RouteBarriers._floor_at(floors, at - along * RouteBarriers.LANDING_REACH + across * float(mouth.half) * share, mouth.at.y, mouth.route).is_empty(): problems.append("%s is wider than the way it lands on" % name)
		var mine: Array = []
		for side: float in [-1.0, 1.0]:
			var post := RouteBarriers.post_of(mouth, side)
			mine.append(Rect2(post - Vector2.ONE * RouteBarriers.POST * 0.5, Vector2.ONE * RouteBarriers.POST))
		if not str(mouth.owner).is_empty():
			var width := 0.0
			for leaf: Dictionary in RouteBarriers.leaves(mouth, RouteBarriers.SHUT):
				var run := Vector2(leaf.run.x, leaf.run.z)
				if absf(run.dot(along)) > 0.001 or absf(leaf.run.y) > 0.001: problems.append("%s leans off square" % name)
				width += float(leaf.length)
			if width > float(mouth.half) * 2.0 + 0.001: problems.append("%s is %.2f m wide on a %.2f m way" % [name, width, float(mouth.half) * 2.0])
			mine.append_array(RouteBarriers.leaf_rects(mouth, RouteBarriers.SHUT | RouteBarriers.OPEN))
		parts.append({"name": name, "y": float(mouth.at.y), "rects": mine})
	for i in range(parts.size()):
		for j in range(i + 1, parts.size()):
			if absf(float(parts[i].y) - float(parts[j].y)) > 0.05: continue
			for a: Rect2 in parts[i].rects:
				for b: Rect2 in parts[j].rects:
					if a.grow(-0.002).intersects(b.grow(-0.002)) and not problems.has("%s meets %s" % [parts[i].name, parts[j].name]): problems.append("%s meets %s" % [parts[i].name, parts[j].name])
	for span: Dictionary in layout.spans:
		var low := Vector2(minf(span.a.x, span.b.x), minf(span.a.z, span.b.z))
		var line := Rect2(low, Vector2(maxf(span.a.x, span.b.x), maxf(span.a.z, span.b.z)) - low).grow(0.025)
		for part: Dictionary in parts:
			if absf(float(part.y) - float(span.a.y)) > 0.05: continue
			if part.rects.any(func(r: Rect2) -> bool: return r.intersects(line)): problems.append("%s crosses the rope of zone %s" % [part.name, span.zone])
	return problems.map(func(p: String) -> String: return "%s: %s" % [where, p])

# --- The refusal finder --------------------------------------------------------------

func _refusals() -> void:
	# A made-up turn: p0 live pushes east into p1's crossing for 40 ticks,
	# standing still; then lets go; then pushes again.
	var finder := BarrierRefusals.new()
	finder._definition = {"id": "made-up-level", "stages": [_view().merged({"id": "made-up", "version": 1}, true)]}
	finder._stage("made-up")
	_check(not finder._layout.is_empty(), "The finder lays out a made-up stage")
	var still := {"stage_id": "made-up", "tick": 0, "active_slot": "p0", "bridges": {"plank": true}, "players": {"p0": _player(-12, 0, "west"), "p1": _player(450, 80, "east")}}
	finder._remember(still)
	var events: Array = []
	for tick in range(1, 80):
		var state := still.duplicate(true)
		state.tick = tick
		var input := {"move_x": 1.0, "move_z": 0.0, "interact": false} if tick < 45 or tick > 50 else {"move_x": 0.0, "move_z": 0.0, "interact": false}
		finder.annotate(state, input)
		for event: Dictionary in state.get("refused", []): events.append([tick, event.id])
	_check(events == [[1, "plank"], [1 + BarrierRefusals.REPEAT_TICKS, "plank"], [51, "plank"]], "A held push rattles at once, again every %d ticks, and anew after letting go: %s" % [BarrierRefusals.REPEAT_TICKS, events])
	# Standing at the other pip's lever clunks once on arrival and on a press.
	var clunks: Array = []
	var at_lever := still.duplicate(true)
	at_lever.players.p1 = _player(-250, -60, "west")
	at_lever.active_slot = "p1"
	for tick in range(80, 90):
		var state := at_lever.duplicate(true)
		state.tick = tick
		finder.annotate(state, {"move_x": 0.0, "move_z": 0.0, "interact": tick == 85})
		for event: Dictionary in state.get("locked", []): clunks.append(tick)
	_check(clunks == [80, 85], "A lock clunks on arrival and on a press, not every tick: %s" % [clunks])

# --- Sounds ----------------------------------------------------------------------

func _sounds() -> void:
	_check(SoundCues.CUES.has("barrier_rattle") and SoundCues.CUES.has("control_locked"), "The rattle and the clunk are cues")
	var key := "high-and-low@1"
	var state := {"role": "a", "first_player_slot": "p0", "events": [], "players": {}, "refused": [{"slot": "p0", "kind": RouteBarriers.OWNER, "id": "blue-stair", "push": Vector2.RIGHT}], "locked": [{"slot": "p1", "kind": RouteBarriers.LOCK, "id": "shore-lever"}]}
	var cues := ChapterSoundMap.cues(key, state, {})
	_check(cues.cues == ["barrier_rattle", "control_locked"] and cues.sources == ["rattle:blue-stair:a|rattle", "locked:shore-lever:b|locked"], "A push and a lock play named cues: %s" % [cues])

# --- Fixtures ---------------------------------------------------------------------

func _chain(key: String) -> Array:
	for name: String in ReplayGolden.CHAINS.get(key, {}):
		var spec: Dictionary = ReplayGolden.CHAINS[key][name]
		if spec.has("stages"): return spec.stages
	for name: String in ReplayGolden.CHAINS.get(key, {}):
		var spec: Dictionary = ReplayGolden.CHAINS[key][name]
		if not spec.has("bundle") or not str(spec.get("entry", "")).is_empty(): continue
		var bundle := Golden.fixture(spec.bundle)
		if not bundle.get("pairs") is Array or not bundle.get("checkpoints") is Array or bundle.checkpoints.size() != bundle.pairs.size() + 1: continue
		var stages: Array = []
		for index in range(bundle.pairs.size()): stages.append([bundle.pairs[index].a, bundle.pairs[index].b, bundle.checkpoints[index + 1]])
		return stages
	return []

## Plays each stage's fixture turns: no spirit crosses a shown barrier, and the
## memory's pushes in the second turn are the first turn's own. Returns the
## stages walked.
func _fixtures(key: String) -> int:
	var stages := _chain(key)
	if stages.is_empty(): return 0
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var checkpoint := Registry.initial_checkpoint(key)
	var walked := 0
	for index in range(stages.size()):
		var files: Array = stages[index]
		var a: Dictionary = files[0] if files[0] is Dictionary else Golden.fixture(files[0])
		var b: Dictionary = files[1] if files[1] is Dictionary else Golden.fixture(files[1])
		var where := "%s stage %d" % [key, index + 1]
		var view := CooperativeCatalog.stage_definition(level, str(a.stage_id))
		var layout := RouteBarriers.layout(view)
		_check(int(layout.slots) <= RouteBarriers.MAX_SLOTS, "%s: the barriers fit the shader's %d slots (%d)" % [where, RouteBarriers.MAX_SLOTS, layout.slots])
		var found: Dictionary = {}
		for turn: Array in [[a, {}], [b, a]]:
			var sim: RefCounted = engine.new()
			sim.catch_assistance = bool(turn[0].get("catch_assistance", true))
			if not Registry.reset_simulation(sim, key, level, str(turn[0].stage_id), checkpoint, turn[1], str(turn[0].role), turn[0]):
				_check(false, "%s: the %s turn resets (%s)" % [where, turn[0].role, sim.error])
				continue
			var finder := BarrierRefusals.new()
			var start: Dictionary = sim.snapshot()
			finder.begin(key, level, start, turn[1] if not turn[1].is_empty() else null)
			var before := start
			var crossed := ""
			for input: Dictionary in engine.expand_recording_inputs(turn[0]):
				var state: Dictionary = sim.step(input)
				finder.annotate(state, input)
				for event: Dictionary in state.get("refused", []):
					var slot := str(event.slot)
					var mine := str(turn[0].role) == "a" or slot != str(state.first_player_slot)
					var record: Array = found.get_or_add("live" if mine else "memory", [])
					# A stair the second pip opened can differ for the memory (barrier_refusals.gd).
					if str(event.kind) != RouteBarriers.STAIR: record.append([int(state.tick), slot, str(event.id)])
				if crossed.is_empty(): crossed = _crossing(layout, before, state)
				before = state
			_check(crossed.is_empty(), "%s %s turn: no spirit walks through a shown barrier %s" % [where, turn[0].role, crossed])
		var live: Array = found.get("live", [])
		var memory: Array = found.get("memory", [])
		var first: Array = live.filter(func(event: Array) -> bool: return event[1] == str(view.get("first_player_slot", "p0")))
		_check(memory == first, "%s: the memory's pushes are its own turn's (%s, %s)" % [where, first, memory])
		walked += 1
		checkpoint = files[2] if files[2] is Dictionary else Golden.fixture(files[2])
	return walked

## The first barrier shown at `before` that a spirit's step to `after` crosses
## ("" when none): a shut gate's line, a stair's chain or a zone's rope.
static func _crossing(layout: Dictionary, before: Dictionary, after: Dictionary) -> String:
	var masks := RouteBarriers.masks_of(layout, before)
	for slot: Variant in after.get("players", {}):
		var from: Variant = before.get("players", {}).get(slot)
		var to: Variant = after.players[slot]
		if not from is Dictionary or not to is Dictionary: continue
		var a := Vector2(float(from.x), float(from.z)) / 100.0
		var b := Vector2(float(to.x), float(to.z)) / 100.0
		if a.is_equal_approx(b): continue
		for mouth: Dictionary in layout.mouths:
			if not masks[mouth.slot] & (RouteBarriers.SHUT | RouteBarriers.CHAIN): continue
			var at := Vector2(mouth.at.x, mouth.at.z)
			var across := Vector2(mouth.along.y, -mouth.along.x) * float(mouth.half)
			if absf(float(from.get("height", 0)) - mouth.at.y * 100.0) > RouteBarriers.NEAR_HEIGHT_CM: continue
			if Geometry2D.segment_intersects_segment(a, b, at - across, at + across) != null: return "(%s at the %s gate of %s)" % [slot, "%s" % mouth.get("floor", ""), mouth.route]
		for span: Dictionary in layout.spans:
			if not masks[span.slot] & RouteBarriers.ROPE: continue
			if absf(float(from.get("height", 0)) - span.a.y * 100.0) > RouteBarriers.NEAR_HEIGHT_CM: continue
			if Geometry2D.segment_intersects_segment(a, b, Vector2(span.a.x, span.a.z), Vector2(span.b.x, span.b.z)) != null: return "(%s over the rope of %s)" % [slot, span.zone]
	return ""
