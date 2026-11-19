extends RefCounted
## Ending scenes: the short scene a chapter may end with, written as data in
## content/endings/<name>.gd (the descriptor's "ending" names it) and played in
## the chapter's own world with its real pips (presentation/ending_player.gd).
## This file is the timeline only: no nodes, no clock, no randomness.
## compile() turns the steps into keyframes from where the pips stand when the
## scene starts; state(t) is a closed-form function of t, so the scene looks
## the same at any frame rate and a skip is state(duration).
##
## A scene file declares `const DATA := {...}`:
##   "cast":   {"holds": a carried item id (core/physical/carried_items.gd),
##             "fallback": a slot}. The pip carrying it in the final snapshot
##             is "carrier" (else the fallback slot's pip), the other "other".
##   "origin": "pips" (the pips' midpoint) or a world anchor name (a world's
##             ending_anchor(name), when it has one). Every point is metres
##             [x, y, z] from it.
##   "props":  {id: {"shape": box|sphere|cylinder|cone, "size": [x, y, z] for a
##             box, [radius, height] for the others, "color", "at", "shown"
##             (true), "alpha" (1), "glow" (0), "rot": degrees [x, y, z]}}:
##             placeholder props built when the scene starts and freed when it
##             ends, for scenery a world does not have yet.
##   "steps":  in order. Each starts at the cursor; only "wait" moves the
##             cursor on, so the steps between two waits run together.
##     wait:    {"time"}
##     move:    {"who", "to", "time", "ease", "arc": metres of lift at the
##              middle, "carried": true moves the pip without walking}
##     face:    {"who", "toward": a role or a point}
##     pose:    {"who", "face": a spirit_look.gd expression, "for": seconds,
##              "rest": rest|doze|sit, "hop": seconds, "wake", "bump", "cheer",
##              "wobble": {"amp": radians, "rate": per second, "for"},
##              "bob": {"amp": metres, "rate": per second, "for"}}
##     camera:  {"at": a point, or "who": a role, "size": metres of view
##              height, "time", "ease", "orbit": degrees the view turns
##              round the point over the time (a slow circle; it stays turned)};
##              {"home": true, "time", "ease"} glides back to the game's own
##              view (where the camera stood when the scene began, unturned),
##              so the world comes back without a jump;
##              {"who": a role, "track": true, "size", "time", "ease"} glides to
##              that pip and keeps following it through its moves until the
##              next camera step;
##              {"frame": a list of roles or points, "margin": metres round
##              them (1), "time", "ease"} picks the centre and size that fit
##              them all on the screen it plays on, narrow or wide (a role is
##              its pip, feet to leaf, where it stands when the step begins)
##     shake:   {"amount": 1 is a big change's shake (kit/big_change.gd), "for":
##              seconds, at most its max_seconds}: a short sway of the view for
##              a splash or a slam. The Haptics and Reduce motion settings turn
##              it off, as they do a big change's
##     bars:    {"show": true or false, "time", "ease"}: letterbox bars slide in
##              or out (each 10% of the screen's height), for the film feel
##     tint:    {"color": hex, "alpha": 0..1, "time", "ease"}: the screen washes
##              toward a colour (warm glow, cool fog, black to fade out)
##     sound:   {"cue": a fixed cue of services/sound_cues.gd, "variant"}
##     prop:    {"id", "to", "time", "ease", "arc", "show", "alpha",
##              "follow": a role it rides on ("" lets go), "spin": degrees a second}
##     caption: {"text": a PlayerCopy line, "for"}
## Times are seconds. "ease" is "inout" (default), "in", "out", "linear",
## "back" (runs a little past and settles: a landing, a pop into place) or
## "bounce" (drops and bounces to rest: something let fall).
## A prop of shape "model" is a part of a Blender model (kit/models.gd):
##   {"shape": "model", "model": res path, "part": name, "colors": {slot: hex},
##    "scale": 1, "at", "rot", "alpha"}; it needs no "size".
const SoundCues = preload("res://services/sound_cues.gd")
const Motion = preload("res://presentation/kit/motion.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const SpiritIdle = preload("res://presentation/spirit_idle.gd")
const ViewFit = preload("res://presentation/kit/view_fit.gd")
const BigChange = preload("res://presentation/kit/big_change.gd")

const ROLES := ["carrier", "other"]
const SHAPES := ["box", "sphere", "cylinder", "cone", "model"]
const EASES := Motion.EASES
const STEPS := ["wait", "move", "face", "pose", "camera", "sound", "prop", "caption", "bars", "tint", "shake"]
## A prop riding on a pip sits this high over the pip's feet (its carried seed's height).
const FOLLOW_LIFT := 1.06
## A framed camera's margin round what it frames when the step names none, and
## the least view height it ever picks (metres).
const FRAME_MARGIN := 1.0
const FRAME_LEAST := 1.0
## The most a shake may be, as times a big change's.
const SHAKE_MOST := 4.0
## How long a scene may last at most (seconds).
const LONGEST := 40.0

## "" when `data` is a scene this player can play, else what is wrong with it.
static func check(data: Dictionary) -> String:
	var cast: Variant = data.get("cast", {})
	if not cast is Dictionary or str(cast.get("fallback", "")) not in ["p0", "p1"]: return "cast needs a fallback slot"
	var props: Variant = data.get("props", {})
	if not props is Dictionary: return "props must be a dictionary"
	for id: String in props:
		var prop: Variant = props[id]
		if not prop is Dictionary or str(prop.get("shape", "")) not in SHAPES: return "prop %s needs a shape" % id
		if not _point(prop.get("at", [0, 0, 0])) is Vector3: return "prop %s needs a point" % id
		if prop.shape == "model":
			if not ResourceLoader.exists(str(prop.get("model", ""))) or str(prop.get("part", "")).is_empty() or not prop.get("colors", {}) is Dictionary: return "model prop %s needs a model, a part and colours" % id
			continue
		if not prop.get("size") is Array or (prop.size as Array).size() != (3 if prop.shape == "box" else 2): return "prop %s has the wrong size" % id
	var steps: Variant = data.get("steps", [])
	if not steps is Array or (steps as Array).is_empty(): return "a scene needs steps"
	for index in range((steps as Array).size()):
		var problem := _check_step(steps[index], props)
		if not problem.is_empty(): return "step %d: %s" % [index, problem]
	var compiled := compile(data, {"carrier": Vector3.ZERO, "other": Vector3.RIGHT, "origin": Vector3.ZERO, "camera": Vector3.ZERO, "camera_size": 10.0})
	if float(compiled.duration) <= 0.0 or float(compiled.duration) > LONGEST: return "a scene lasts between 0 and %d seconds" % int(LONGEST)
	return ""

static func _check_step(step: Variant, props: Dictionary) -> String:
	if not step is Dictionary or str(step.get("do", "")) not in STEPS: return "unknown step"
	if float(step.get("time", 0.0)) < 0.0 or float(step.get("for", 0.0)) < 0.0: return "times are never negative"
	if str(step.get("ease", "inout")) not in EASES: return "unknown ease"
	if step.has("who") and str(step.who) not in ROLES: return "unknown role %s" % step.who
	match str(step.do):
		"move":
			if not step.has("who") or not _point(step.get("to")) is Vector3: return "a move needs who and to"
		"face":
			if not step.has("who") or not (str(step.get("toward", "")) in ROLES or _point(step.get("toward")) is Vector3): return "a face needs who and toward"
		"pose":
			if not step.has("who"): return "a pose needs who"
			if step.has("face") and not SpiritLook.has(StringName(str(step.face))): return "unknown face %s" % step.face
			if step.has("rest") and not SpiritIdle.has_pose(StringName(str(step.rest))): return "unknown rest %s" % step.rest
		"camera":
			if bool(step.get("home", false)): return ""
			if step.has("frame"):
				if step.has("who") or step.has("at") or step.has("size") or step.has("track"): return "a frame works out its own place and size"
				if not step.frame is Array or (step.frame as Array).is_empty(): return "a frame needs roles or points"
				for item: Variant in step.frame:
					if not (str(item) in ROLES or _point(item) is Vector3): return "a frame takes roles or points"
				if float(step.get("margin", FRAME_MARGIN)) < 0.0: return "a frame's margin is never negative"
				return ""
			if step.has("track") and (not step.track is bool or (step.track and not step.has("who"))): return "a track needs who and track true"
			if not (step.has("who") or _point(step.get("at")) is Vector3) or float(step.get("size", 0.0)) <= 0.0: return "a camera needs a place and a size"
		"sound":
			if not SoundCues.is_fixed(str(step.get("cue", ""))): return "sound %s is not a fixed cue" % step.get("cue", "")
		"prop":
			if not props.has(str(step.get("id", ""))): return "unknown prop %s" % step.get("id", "")
			if step.has("to") and not _point(step.to) is Vector3: return "a prop's to is a point"
			if step.has("follow") and str(step.follow) not in ROLES + [""]: return "unknown follow %s" % step.follow
		"caption":
			if str(step.get("text", "")).is_empty() or float(step.get("for", 0.0)) <= 0.0: return "a caption needs text and for"
		"bars":
			if not step.get("show") is bool: return "bars need show true or false"
		"tint":
			if not Color.html_is_valid(str(step.get("color", ""))) or float(step.get("alpha", -1.0)) < 0.0 or float(step.get("alpha", 0.0)) > 1.0: return "a tint needs a colour and an alpha from 0 to 1"
		"shake":
			var amount := float(step.get("amount", 1.0))
			var length := float(step.get("for", 0.0))
			if amount <= 0.0 or amount > SHAKE_MOST or length <= 0.0 or length > float(BigChange.SHAKE.max_seconds): return "a shake needs an amount up to %d and for up to %.1f s" % [int(SHAKE_MOST), float(BigChange.SHAKE.max_seconds)]
	return ""

## The slot each role plays: {"carrier": slot, "other": slot}. The carrier
## carries the cast's item in `snapshot` (a journey snapshot's
## players[slot].carrying, rules 16), else it is the fallback slot.
static func cast(data: Dictionary, snapshot: Dictionary) -> Dictionary:
	var spec: Dictionary = data.get("cast", {})
	var carrier := str(spec.get("fallback", "p0"))
	var players: Variant = snapshot.get("players", {})
	for slot: String in ["p0", "p1"]:
		var player: Variant = players.get(slot, {}) if players is Dictionary else {}
		if player is Dictionary and not str(spec.get("holds", "")).is_empty() and str(player.get("carrying", "")) == str(spec.get("holds", "")): carrier = slot
	return {"carrier": carrier, "other": "p1" if carrier == "p0" else "p0"}

## The scene as keyframes. `at`: where things stand when it starts, in the
## world's own space: "carrier" and "other" (the pips), "origin" (the scene's
## origin), "camera" (the point the camera looks at), "camera_size" and
## "aspect" (the view's width over its height; 16:9 when not given).
static func compile(data: Dictionary, at: Dictionary) -> Dictionary:
	var origin: Vector3 = at.origin
	var actors := {}
	for role: String in ROLES:
		actors[role] = {"start": at[role], "moves": [], "faces": [], "rests": [], "wobbles": [], "bobs": [], "facings": []}
	var camera := {"start": at.camera, "moves": [], "start_size": float(at.camera_size), "sizes": [], "orbits": [], "shakes": []}
	var aspect := float(at.get("aspect", ViewFit.BASE.x / ViewFit.BASE.y))
	var screen := {"bars": [], "tints": [], "tint_colors": []}
	var props := {}
	for id: String in data.get("props", {}):
		var spec: Dictionary = data.props[id]
		props[id] = {"start": origin + _point(spec.get("at", [0, 0, 0])), "moves": [], "start_alpha": float(spec.get("alpha", 1.0)), "alphas": [],
			"shows": [[-1.0, bool(spec.get("shown", true))]], "spins": []}
	var compiled := {"actors": actors, "camera": camera, "props": props, "screen": screen, "events": [], "captions": [], "duration": 0.0}
	var cursor := 0.0
	var ends := 0.0
	for step: Dictionary in data.get("steps", []):
		var time := float(step.get("time", 0.0))
		var ease := str(step.get("ease", "inout"))
		match str(step.get("do", "")):
			"wait":
				cursor += time
			"move":
				var actor: Dictionary = actors[step.who]
				_append(actor.moves, {"at": cursor, "time": time, "ease": ease, "arc": float(step.get("arc", 0.0)), "to": origin + _point(step.to), "carried": bool(step.get("carried", false))},
					position_of(compiled, str(step.who), cursor))
			"face":
				var toward: Variant = step.toward
				actors[step.who].facings.append({"at": cursor, "toward": toward if str(toward) in ROLES else origin + _point(toward)})
			"pose":
				var actor: Dictionary = actors[step.who]
				if step.has("face"): actor.faces.append({"at": cursor, "until": cursor + float(step.get("for", 1.0)), "face": StringName(str(step.face))})
				if step.has("rest"): actor.rests.append({"at": cursor, "rest": StringName(str(step.rest))})
				for wave: String in ["wobble", "bob"]:
					if step.has(wave): actor[wave + "s"].append({"at": cursor, "until": cursor + float(step[wave].get("for", 1.0)), "amp": float(step[wave].get("amp", 0.0)), "rate": float(step[wave].get("rate", 1.0))})
				for kind: String in ["hop", "wake", "bump", "cheer"]:
					if step.has(kind): compiled.events.append({"at": cursor, "kind": kind, "who": str(step.who), "time": float(step[kind]) if kind == "hop" else 0.0})
			"camera":
				var home := bool(step.get("home", false))
				if step.has("orbit") or home:
					var turned: float = _track(camera.orbits, 0.0, cursor)
					_append(camera.orbits, {"at": cursor, "time": time, "ease": ease, "arc": 0.0, "to": 0.0 if home else turned + float(step.orbit)}, turned)
				var move := {"at": cursor, "time": time, "ease": ease, "arc": 0.0}
				var size: float = float(camera.start_size) if home else float(step.get("size", 0.0))
				if home: move.to = camera.start
				elif step.has("frame"):
					var points: Array = []
					for item: Variant in step.frame:
						if str(item) in ROLES: points.append_array([position_of(compiled, str(item), cursor), position_of(compiled, str(item), cursor) + Vector3.UP * FOLLOW_LIFT])
						else: points.append(origin + _point(item))
					var fitted := frame(points, float(step.get("margin", FRAME_MARGIN)), _track(camera.orbits, 0.0, cursor + time), aspect)
					move.to = fitted.center
					size = fitted.size
				elif bool(step.get("track", false)):
					move.to = Vector3.ZERO
					move.track = str(step.who)
				else: move.to = position_of(compiled, str(step.who), cursor) if step.has("who") else origin + _point(step.at)
				_append(camera.moves, move, camera_center(compiled, cursor))
				_append(camera.sizes, {"at": cursor, "time": time, "ease": ease, "arc": 0.0, "to": size}, _track(camera.sizes, camera.start_size, cursor))
			"shake":
				var length := minf(float(step["for"]), float(BigChange.SHAKE.max_seconds))
				camera.shakes.append({"at": cursor, "for": length, "amount": float(step.get("amount", 1.0))})
				ends = maxf(ends, cursor + length)
			"bars":
				_append(screen.bars, {"at": cursor, "time": time, "ease": ease, "arc": 0.0, "to": 1.0 if bool(step.show) else 0.0}, _track(screen.bars, 0.0, cursor))
			"tint":
				screen.tint_colors.append({"at": cursor, "color": Color(str(step.color))})
				_append(screen.tints, {"at": cursor, "time": time, "ease": ease, "arc": 0.0, "to": float(step.alpha)}, _track(screen.tints, 0.0, cursor))
			"sound":
				compiled.events.append({"at": cursor, "kind": "sound", "cue": str(step.cue), "variant": int(step.get("variant", 0))})
			"prop":
				var prop: Dictionary = props[step.id]
				if step.has("show"): prop.shows.append([cursor, bool(step.show)])
				if step.has("alpha"): _append(prop.alphas, {"at": cursor, "time": time, "ease": ease, "arc": 0.0, "to": float(step.alpha)}, _track(prop.alphas, prop.start_alpha, cursor))
				if step.has("spin"): prop.spins.append([cursor, float(step.spin)])
				if step.has("follow"):
					var rider := str(step.follow)
					_append(prop.moves, {"at": cursor, "time": 0.0, "ease": "linear", "arc": 0.0, "to": Vector3.ZERO, "follow": rider}, prop_position(compiled, str(step.id), cursor))
				if step.has("to"):
					_append(prop.moves, {"at": cursor, "time": time, "ease": ease, "arc": float(step.get("arc", 0.0)), "to": origin + _point(step.to)}, prop_position(compiled, str(step.id), cursor))
			"caption":
				compiled.captions.append({"at": cursor, "until": cursor + float(step.get("for", 1.0)), "text": str(step.text)})
				ends = maxf(ends, cursor + float(step.get("for", 1.0)))
		ends = maxf(ends, cursor + time)
	compiled.duration = maxf(cursor, ends)
	compiled.events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)
	return compiled

static func _append(segments: Array, segment: Dictionary, from: Variant) -> void:
	segment.from = from
	segments.append(segment)

static func _point(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() != 3: return null
	for part: Variant in value:
		if not (part is int or part is float): return null
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

## Every ease is the shared motion kit's (kit/motion.gd).
static func _eased(ease: String, u: float) -> float:
	return Motion.ease(ease, u)

## The value of a keyframe track at `t`: the newest segment begun by then, from
## where the track stood when it began.
static func _track(segments: Array, start: Variant, t: float) -> Variant:
	var found: Variant = null
	for segment: Dictionary in segments:
		if float(segment.at) > t: break
		found = segment
	if found == null: return start
	return _segment(found, t)

static func _segment(segment: Dictionary, t: float) -> Variant:
	var time := float(segment.time)
	var u := 1.0 if time <= 0.0 else clampf((t - float(segment.at)) / time, 0.0, 1.0)
	var value: Variant = segment.from
	if value is Vector3: value = (value as Vector3).lerp(segment.to, _eased(segment.ease, u)) + Vector3.UP * float(segment.arc) * 4.0 * u * (1.0 - u)
	else: value = lerpf(float(value), float(segment.to), _eased(segment.ease, u))
	return value

static func position_of(compiled: Dictionary, role: String, t: float) -> Vector3:
	var actor: Dictionary = compiled.actors[role]
	return _track(actor.moves, actor.start, t)

## Where the camera looks at `t`: its newest move from where it stood, and a
## tracking move eases onto its pip and then follows it exactly.
static func camera_center(compiled: Dictionary, t: float) -> Vector3:
	var camera: Dictionary = compiled.camera
	var found: Variant = _latest(camera.moves, t)
	if found == null: return camera.start
	if not found.has("track"): return _segment(found, t)
	var time := float(found.time)
	var u := 1.0 if time <= 0.0 else clampf((t - float(found.at)) / time, 0.0, 1.0)
	return (found.from as Vector3).lerp(position_of(compiled, str(found.track), t), _eased(found.ease, u))

## The camera's centre and size (a KEEP_HEIGHT size, before ViewFit grows it)
## that fit `points` with `margin` metres round them in a view turned `orbit`
## degrees, `aspect` wide per unit of height. Once ViewFit has grown the size
## for that screen, the view fits them exactly on its tighter side.
static func frame(points: Array, margin: float, orbit: float, aspect: float) -> Dictionary:
	var axes := view_axes(orbit)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var mean := Vector3.ZERO
	for point: Vector3 in points:
		var flat := Vector2(axes.x.dot(point), axes.y.dot(point))
		low = Vector2(minf(low.x, flat.x), minf(low.y, flat.y))
		high = Vector2(maxf(high.x, flat.x), maxf(high.y, flat.y))
		mean += point / points.size()
	var middle := (low + high) * 0.5
	var center: Vector3 = mean + axes.x * (middle.x - axes.x.dot(mean)) + axes.y * (middle.y - axes.y.dot(mean))
	var span := high - low + Vector2.ONE * margin * 2.0
	var shown := maxf(FRAME_LEAST, maxf(span.y, span.x / maxf(aspect, 0.01)))
	return {"center": center, "size": shown / ViewFit.fit(1.0, aspect)}

## The camera's own axes in a view turned `orbit` degrees: x across the
## screen, y up it (as look_at builds them from ViewFit.CAMERA_FROM).
static func view_axes(orbit: float) -> Basis:
	var back := (Basis(Vector3.UP, deg_to_rad(orbit)) * ViewFit.CAMERA_FROM).normalized()
	var across := Vector3.UP.cross(back).normalized()
	return Basis(across, back.cross(across), back)

## The shake's sway at `t` (kit/big_change.gd offset(): x across, y up, as
## shares of the view's height), zero when none is running.
static func shake_at(compiled: Dictionary, t: float) -> Vector2:
	var found: Variant = _latest(compiled.camera.get("shakes", []), t)
	if found == null: return Vector2.ZERO
	return BigChange.offset(t - float(found.at), float(found["for"])) * float(found.amount)

static func prop_position(compiled: Dictionary, id: String, t: float) -> Vector3:
	var prop: Dictionary = compiled.props[id]
	var found: Variant = null
	for segment: Dictionary in prop.moves:
		if float(segment.at) > t: break
		found = segment
	if found == null: return prop.start
	if found.has("follow"):
		var rider := str(found.follow)
		return found.from if rider.is_empty() else position_of(compiled, rider, t) + Vector3.UP * FOLLOW_LIFT
	return _segment(found, t)

static func _latest(items: Array, t: float) -> Variant:
	var found: Variant = null
	for item: Dictionary in items:
		if float(item.at) > t: break
		found = item
	return found

static func _wave(items: Array, t: float) -> float:
	var found: Variant = _latest(items, t)
	if found == null or t >= float(found.until): return 0.0
	return float(found.amp) * sin(TAU * float(found.rate) * (t - float(found.at)))

## Everything at `t` (clamped to the scene): per role its "position",
## "carried" (moved without walking), "face" (&"" for none), "rest", "lean"
## (Vector3 for set_ride_pose), "facing" (radians, or null to follow its walk);
## the camera's "center", "size", "orbit" and "shake" (shake_at); per prop "position", "shown", "alpha",
## "spin" (radians about y); and the "caption" ("" for none).
static func state(compiled: Dictionary, t: float) -> Dictionary:
	t = clampf(t, 0.0, float(compiled.duration))
	var result := {"actors": {}, "props": {}, "camera": {}, "screen": {}, "caption": ""}
	for role: String in ROLES:
		var actor: Dictionary = compiled.actors[role]
		var face: Variant = _latest(actor.faces, t)
		var rest: Variant = _latest(actor.rests, t)
		var move: Variant = _latest(actor.moves, t)
		var facing: Variant = null
		var toward: Variant = _latest(actor.facings, t)
		if toward != null:
			var here := position_of(compiled, role, t)
			var there: Vector3 = position_of(compiled, str(toward.toward), t) if toward.toward is String else toward.toward
			if Vector2(there.x - here.x, there.z - here.z).length() > 0.01: facing = atan2(there.x - here.x, there.z - here.z)
		var walking: bool = move != null and t < float(move.at) + float(move.time)
		result.actors[role] = {"position": position_of(compiled, role, t) + Vector3.UP * _wave(actor.bobs, t),
			"carried": walking and bool(move.carried), "face": face.face if face != null and t < float(face.until) else &"",
			"rest": rest.rest if rest != null else SpiritIdle.REST, "lean": Vector3(0, 0, _wave(actor.wobbles, t)), "facing": facing}
	result.camera = {"center": camera_center(compiled, t), "size": _track(compiled.camera.sizes, compiled.camera.start_size, t),
		"orbit": _track(compiled.camera.get("orbits", []), 0.0, t), "shake": shake_at(compiled, t)}
	var screen: Dictionary = compiled.get("screen", {})
	var tint: Variant = _latest(screen.get("tint_colors", []), t)
	result.screen = {"bars": _track(screen.get("bars", []), 0.0, t), "tint": tint.color if tint != null else Color.BLACK, "tint_alpha": _track(screen.get("tints", []), 0.0, t)}
	for id: String in compiled.props:
		var prop: Dictionary = compiled.props[id]
		var shown := false
		for change: Array in prop.shows:
			if float(change[0]) <= t: shown = bool(change[1])
		var spin := 0.0
		for index in range(prop.spins.size()):
			var begin := float(prop.spins[index][0])
			if begin > t: break
			var end := t if index + 1 >= prop.spins.size() else minf(t, float(prop.spins[index + 1][0]))
			spin += deg_to_rad(float(prop.spins[index][1])) * (end - begin)
		result.props[id] = {"position": prop_position(compiled, id, t), "shown": shown, "alpha": _track(prop.alphas, prop.start_alpha, t), "spin": spin}
	for caption: Dictionary in compiled.captions:
		if float(caption.at) <= t and t < float(caption.until): result.caption = caption.text
	return result

## The instant events (hops, wakes, bumps, cheers and sounds) after `from` up
## to and including `to`, in order. A scene's events at 0 come with from < 0.
static func events_between(compiled: Dictionary, from: float, to: float) -> Array:
	return compiled.events.filter(func(event: Dictionary) -> bool: return float(event.at) > from and float(event.at) <= to)
