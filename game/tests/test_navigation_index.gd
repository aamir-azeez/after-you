extends SceneTree
## core/cooperative/navigation.gd answers every support query the same with
## its per-definition index as by testing every surface. For every registered
## chapter on the physical runtime: every point of a grid over its surfaces
## (and just past their edges, where a point lies on a rect's border), at each
## surface's height and between, for both spirits, with every route closed,
## every route open, and alternate routes open. Also: one index per digest,
## shared (only for a level with enough surfaces to gain from it), and the
## engines' cached digest equals a fresh one.
const Registry = preload("res://services/chapter_registry.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const STEP_CM := 23
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
	var levels := 0
	for key: String in Registry.keys():
		var engine: Script = Registry.simulation_script(key)
		if engine.resource_path != "res://core/journey/simulation.gd" and engine.resource_path != "res://core/cooperative/simulation.gd": continue
		var level := Registry.definition(key)
		var digest := Canonical.digest(level)
		var surfaces: Array = level.get("islands", []) + level.get("bridges", []) + level.get("stairs", [])
		var shared := Navigation.index_for(level, digest)
		_check(Navigation.index_for(level, digest) == shared, key + ": one index per definition digest")
		_check(shared.is_empty() == (surfaces.size() < Navigation.INDEX_FROM_SURFACES), key + ": indexed only from %d surfaces (%d)" % [Navigation.INDEX_FROM_SURFACES, surfaces.size()])
		# Every chapter's index answers alike, whether or not its engines use it.
		var cells := Navigation._build_index(level)
		var heights: Dictionary = {0: true}
		var low := Vector2i(1 << 30, 1 << 30)
		var high := -low
		for surface: Dictionary in surfaces:
			for field: String in ["height_cm", "from_height_cm", "to_height_cm"]:
				if surface.has(field):
					heights[int(surface[field])] = true
					heights[int(surface[field]) + 3] = true
			var r: Array = surface.rect_cm
			low = Vector2i(mini(low.x, int(r[0])), mini(low.y, int(r[1])))
			high = Vector2i(maxi(high.x, int(r[2])), maxi(high.y, int(r[3])))
		var route_sets: Array = [{}, {}, {}]
		var index := 0
		for surface: Dictionary in level.get("bridges", []) + level.get("stairs", []):
			route_sets[1][surface.id] = true
			if index % 2 == 0: route_sets[2][surface.id] = true
			index += 1
		var points: Array = []
		for x in range(low.x - 30, high.x + 31, STEP_CM):
			for z in range(low.y - 30, high.y + 31, STEP_CM): points.append(Vector2i(x, z))
		# Every rect's corners and edges exactly, where inside() counts the border.
		for surface: Dictionary in surfaces:
			var r: Array = surface.rect_cm
			for x: int in [int(r[0]), int(r[2]), int(r[0]) - 1, int(r[2]) + 1]:
				for z: int in [int(r[1]), int(r[3]), int(r[1]) - 1, int(r[3]) + 1]: points.append(Vector2i(x, z))
		var same := true
		var where := ""
		var tested := 0
		for routes: Dictionary in route_sets:
			for slot: String in ["p0", "p1"]:
				for height: int in heights:
					var previous := {"height": height}
					for point: Vector2i in points:
						var plain := Navigation._support(level, routes, point, slot, previous)
						var indexed := Navigation._support(level, routes, point, slot, previous, 2, cells)
						tested += 1
						if plain != indexed and same:
							same = false
							where = "%s %s h%d routes %d: %s vs %s" % [str(point), slot, height, routes.size(), str(plain), str(indexed)]
		_check(same, "%s: the index answers every support query as testing every surface (%d queries) %s" % [key, tested, where])
		# Whole moves too: at() with and without the index, one cm either way.
		var moves_same := true
		for routes: Dictionary in route_sets:
			for point: Vector2i in points.slice(0, mini(points.size(), 400)):
				var previous := {"x": point.x, "z": point.y, "height": 0}
				if Navigation.at(level, routes, {}, previous, point.x + 1, point.y, "p1", 12) != Navigation.at(level, routes, {}, previous, point.x + 1, point.y, "p1", 12, true, cells): moves_same = false
		_check(moves_same, key + ": at() moves the same with the index")
		levels += 1
	_check(levels >= 8, "Every physical chapter was checked (%d)" % levels)
	# The engines' cached digest is the definition's digest, at every check.
	for key: String in [Registry.TURN_OF_THE_TIDE, Registry.WISHING_WELL]:
		var engine: Script = Registry.simulation_script(key)
		var level := Registry.definition(key)
		var sim: RefCounted = engine.new()
		var checkpoint := Registry.initial_checkpoint(key)
		var stage_id := str(level.stages[0].id)
		sim._reset_trusted(level, stage_id, checkpoint, {}, "a")
		sim.step({"move_x": 1.0, "move_z": 0.0, "interact": false})
		_check(sim._level_digest() == Canonical.digest(sim.level) and sim._level_digest() == Canonical.digest(level), key + ": the engine's cached digest is its definition's digest")
	print("NAVIGATION INDEX: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
