class_name AfterYouBeamField
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Pure cardinal optics. Coordinates are integer centimetres: north is -Z.
## Field: {schema_version:1,bounds_cm:[minX,minZ,maxX,maxZ],emitters:[],
## mirrors:[],receivers:[],blockers:[]}. Every entity has a unique id,
## position_cm:[x,z] strictly inside bounds, and enabled:bool. Emitters add
## direction:north|east|south|west; mirrors add orientation:slash|backslash.
## Optional overrides: {known_id:{enabled:bool,orientation:<mirror only>}}.
## Emitters and intersecting beams are nonblocking. Disabled optics are absent.
## Only these typed optics affect rays; character or collision state is not an
## input. No scene, filesystem, wall clock, physics, random or network access.

const MAX_EMITTERS := 8
const MAX_MIRRORS := 32
const MAX_ENTITIES := 64
const MAX_COORD := 1000000
const DIRECTIONS := ["north", "east", "south", "west"]
const COLLECTIONS := {"emitters": "emitter", "mirrors": "mirror", "receivers": "receiver", "blockers": "blocker"}

static func evaluate(field: Variant, overrides: Variant = {}) -> Dictionary:
	var checked := _validate(field, overrides)
	if not checked.valid:
		return _failure(checked.error)
	var segments: Array = []
	var signals: Dictionary = {}
	var sources: Dictionary = {}
	var terminations: Array = []
	var entities: Array = checked.entities
	for entity: Dictionary in entities:
		if entity.kind == "receiver":
			signals[entity.id] = false
			sources[entity.id] = []
	for entity: Dictionary in entities:
		if entity.kind == "emitter":
			terminations.append(_trace(entity, checked.bounds, entities, segments, signals, sources))
	return {"valid": true, "error": "", "segments": segments, "signals": signals, "sources": sources, "terminations": terminations}

static func _trace(emitter: Dictionary, bounds: Array, entities: Array, segments: Array, signals: Dictionary, sources: Dictionary) -> Dictionary:
	var origin: Vector2i = emitter.position
	var direction: String = emitter.direction
	if not emitter.enabled:
		return _termination(emitter.id, "disabled", origin, "")
	var visited: Dictionary = {}
	# Four possible incoming directions per mirror plus a terminating segment.
	# The visited-state test normally stops first; this is a hard output bound.
	for _step in range(4 * MAX_MIRRORS + 1):
		var endpoint := _boundary(origin, direction, bounds)
		var distance := _distance(origin, endpoint, direction)
		var hit: Dictionary = {}
		for candidate: Dictionary in entities:
			if not candidate.enabled or candidate.kind == "emitter":
				continue
			var proposed := _distance(origin, candidate.position, direction)
			if proposed > 0 and proposed < distance:
				distance = proposed
				endpoint = candidate.position
				hit = candidate
		segments.append({"emitter_id": emitter.id, "from_cm": _coords(origin), "to_cm": _coords(endpoint), "direction": direction, "hit_id": str(hit.get("id", "")), "hit_kind": str(hit.get("kind", "bounds"))})
		if hit.is_empty():
			return _termination(emitter.id, "bounds", endpoint, "")
		if hit.kind == "receiver":
			signals[hit.id] = true
			sources[hit.id].append(emitter.id)
			return _termination(emitter.id, "receiver", endpoint, hit.id)
		if hit.kind == "blocker":
			return _termination(emitter.id, "blocker", endpoint, hit.id)
		var state := str(hit.id) + ":" + direction
		if visited.has(state):
			return _termination(emitter.id, "loop", endpoint, hit.id)
		visited[state] = true
		direction = _reflected(direction, hit.orientation)
		origin = endpoint
	return _termination(emitter.id, "limit", origin, "")

static func _validate(field: Variant, overrides: Variant) -> Dictionary:
	if not field is Dictionary or not _exact_keys(field, ["schema_version", "bounds_cm", "emitters", "mirrors", "receivers", "blockers"]):
		return {"valid": false, "error": PlayerCopy.BEAM_FIELD_D1D0A898DA7F}
	if not _integer(field.schema_version) or field.schema_version != 1:
		return {"valid": false, "error": PlayerCopy.BEAM_FIELD_0A335806E9B1}
	if not field.bounds_cm is Array or field.bounds_cm.size() != 4:
		return {"valid": false, "error": PlayerCopy.BEAM_FIELD_CA3D5F9CF1A7}
	var bounds: Array = []
	for value: Variant in field.bounds_cm:
		if not _integer(value) or absf(float(value)) > MAX_COORD:
			return {"valid": false, "error": PlayerCopy.BEAM_FIELD_77E1FAF2AC55}
		bounds.append(int(value))
	if bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
		return {"valid": false, "error": PlayerCopy.BEAM_FIELD_D0BFB53373EA}
	var entities: Array = []
	var by_id: Dictionary = {}
	var positions: Dictionary = {}
	for collection: String in COLLECTIONS:
		if not field[collection] is Array or field[collection].size() > MAX_ENTITIES:
			return {"valid": false, "error": PlayerCopy.BEAM_FIELD_0440EF189328}
		if (collection == "emitters" and field[collection].size() > MAX_EMITTERS) or (collection == "mirrors" and field[collection].size() > MAX_MIRRORS):
			return {"valid": false, "error": PlayerCopy.BEAM_FIELD_DB64D854E918}
		var kind: String = COLLECTIONS[collection]
		for value: Variant in field[collection]:
			var keys: Array = ["id", "position_cm", "enabled"]
			if kind == "emitter":
				keys.append("direction")
			elif kind == "mirror":
				keys.append("orientation")
			if not value is Dictionary or not _exact_keys(value, keys) or not _id(value.get("id")) or not value.enabled is bool:
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_20EE8A8BC954}
			if by_id.has(value.id):
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_7EA321242B76}
			if not value.position_cm is Array or value.position_cm.size() != 2 or not _integer(value.position_cm[0]) or not _integer(value.position_cm[1]):
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_1DD95DF05F20}
			if value.position_cm[0] <= bounds[0] or value.position_cm[0] >= bounds[2] or value.position_cm[1] <= bounds[1] or value.position_cm[1] >= bounds[3]:
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_CE0804510CBF}
			var position := Vector2i(int(value.position_cm[0]), int(value.position_cm[1]))
			if positions.has(position):
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_C68BAC8BA7A0}
			if kind == "emitter" and value.direction not in DIRECTIONS:
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_3CB4D3182E03}
			if kind == "mirror" and value.orientation not in ["slash", "backslash"]:
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_9517CDD989CB}
			var entity := {"id": str(value.id), "kind": kind, "position": position, "enabled": bool(value.enabled)}
			if kind == "emitter":
				entity["direction"] = str(value.direction)
			elif kind == "mirror":
				entity["orientation"] = str(value.orientation)
			entities.append(entity)
			by_id[value.id] = entity
			positions[position] = value.id
			if entities.size() > MAX_ENTITIES:
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_B901A58744E0}
	if not overrides is Dictionary or overrides.size() > MAX_ENTITIES:
		return {"valid": false, "error": PlayerCopy.BEAM_FIELD_040A3B136A0E}
	for id: Variant in overrides:
		if not id is String or not by_id.has(id) or not overrides[id] is Dictionary:
			return {"valid": false, "error": PlayerCopy.BEAM_FIELD_9D3F80045721}
		var entity: Dictionary = by_id[id]
		var state: Dictionary = overrides[id]
		for key: Variant in state:
			if key == "enabled" and state[key] is bool:
				entity.enabled = state[key]
			elif key == "orientation" and entity.kind == "mirror" and state[key] in ["slash", "backslash"]:
				entity.orientation = state[key]
			else:
				return {"valid": false, "error": PlayerCopy.BEAM_FIELD_2BA97C2AA40E}
	entities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return {"valid": true, "error": "", "bounds": bounds, "entities": entities}

static func _reflected(direction: String, orientation: String) -> String:
	var index := DIRECTIONS.find(direction)
	var mapped: Array = [1, 0, 3, 2] if orientation == "slash" else [3, 2, 1, 0]
	return DIRECTIONS[mapped[index]]

static func _distance(origin: Vector2i, target: Vector2i, direction: String) -> int:
	match direction:
		"north": return origin.y - target.y if origin.x == target.x else -1
		"east": return target.x - origin.x if origin.y == target.y else -1
		"south": return target.y - origin.y if origin.x == target.x else -1
		_: return origin.x - target.x if origin.y == target.y else -1

static func _boundary(origin: Vector2i, direction: String, bounds: Array) -> Vector2i:
	match direction:
		"north": return Vector2i(origin.x, int(bounds[1]))
		"east": return Vector2i(int(bounds[2]), origin.y)
		"south": return Vector2i(origin.x, int(bounds[3]))
		_: return Vector2i(int(bounds[0]), origin.y)

static func _coords(position: Vector2i) -> Array:
	return [position.x, position.y]

static func _termination(emitter_id: String, reason: String, position: Vector2i, entity_id: String) -> Dictionary:
	return {"emitter_id": emitter_id, "reason": reason, "at_cm": _coords(position), "entity_id": entity_id}

static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "error": reason, "segments": [], "signals": {}, "sources": {}, "terminations": []}

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if key not in expected:
			return false
	return true

static func _id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))
