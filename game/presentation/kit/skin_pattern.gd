extends RefCounted
## Patterned body skins: flat colour marks on the pip's own head, torso and
## feet, no added geometry (Pollen skins board, 2026-11-12). Every skin is
## data: an art script (presentation/pip_wear/) wears one with a recipe,
##     SkinPattern.wear(look, {"id": "knit", "head": {...}, "body": {...}, "feet": [...]})
## and the two shaders draw it (skin_pattern.gdshaderinc, through
## spirit_face_pattern.gdshader on the head, under the eyes, and
## spirit_body_pattern.gdshader on the torso).
##
## A recipe:
##   id     names it; its head's uniforms and its torso material are made
##          once and shared by every pip wearing it (the torso's through
##          kit/pip_wear_kit.gd cached_material, released at session end)
##   head, body: a surface's marks (SURFACE fields), in the board's surface
##          coordinates: u 0 at the surface's left edge to 1 at its right, v 0
##          at its top to 1 at its bottom, seen straight on. A body with only
##          a base draws with the plain shared material.
##   feet   the two feet's colours, left (the viewer's left) then right; each
##          drawn a shade darker, as a plain pip's feet are
##   drift  the slow drift's reach (u) either way, or 0 for a still skin;
##          it runs a triangle over `loop` seconds of the pip's own clock (the
##          idle card rate), starting and resting at 0, so Reduce motion and a
##          still picture hold it at 0
## A surface's marks (colours are palette Colors):
##   base    its colour
##   fields  [{"points": [Vector2 uv...] (3 to 8), "color", "wander"}]: broad
##           colour fields with softly curved edges (wander: uv)
##   bands   [{"from", "to" (v), "kind" ("zigzag" or "wave"), "period" (u),
##           "amplitude" (v), "color", "edge": accent strip height (v) on the
##           top edge, "edge_color"}]
##   stamps  [{"shape" ("star" or "leaf"), "at": Vector2 uv, "width" (share of
##           the surface's width), "turn" (radians), "color", "back": true
##           for the back of the surface}]; on the head they never draw
##           inside the eyes' safety ovals (SAFE_EYES)
##   seam    {"color", "width" (share of the surface's width)}: a thin line
##           down the back
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const FACE_SHADER = preload("res://presentation/spirit_face_pattern.gdshader")
const BODY_SHADER = preload("res://presentation/spirit_body_pattern.gdshader")

## How many marks each shader takes (skin_pattern.gdshaderinc).
const MAX_FIELDS := 4
const MAX_FIELD_POINTS := 24
const MAX_BANDS := 3
const MAX_STAMPS := 5
## The head's mapping: half width, the height of v 0, the height (metres,
## head space). The board's u, v name the visible front, so 0 to 1 spans
## FRONT_WIDTH of the head's width and FRONT_HEIGHT of its height: the rounded
## sides beyond (u below 0 or above 1) turn away and are not stretched over.
## The torso's visible part runs from y -0.15 to about 0.04 (its top is
## inside the head).
## The crown's unrolling (skin_pattern.gdshaderinc crown_wrap): the front
## face's depth, and the heights the wrap fades in between, so the front face
## keeps the board's mapping and the top carries on from its upper edge. A
## recipe's v runs from 0 at the front's top edge to CROWN_BACK at the back of
## the top.
const CROWN_WRAP := Vector3(Look.HEAD_HALF.z, Look.HEAD_HALF.y * 0.4, Look.HEAD_HALF.y * 0.85)
const FRONT_WIDTH := 0.85
const FRONT_HEIGHT := 0.9
const HEAD_MAP := Vector3(Look.HEAD_HALF.x * FRONT_WIDTH, Look.HEAD_HALF.y * FRONT_HEIGHT, Look.HEAD_HALF.y * 2.0 * FRONT_HEIGHT)
## Where v ends at the back of the crown (the front face's depth twice over,
## in the head's mapping).
const CROWN_BACK := -(Look.HEAD_HALF.y * (1.0 - FRONT_HEIGHT) + Look.HEAD_HALF.z * 2.0) / (Look.HEAD_HALF.y * 2.0 * FRONT_HEIGHT)
const BODY_MAP := Vector3(Look.TORSO_HALF.x, 0.04, 0.19)
## The eyes' safety ovals in face space: each open eye at rest, widened by
## the gaze's reach and a margin of 0.025 of the head's width (the board's
## rule), so no stamp crowds an eye or its cream rim in any reaction.
const SAFE_MARGIN := 0.025 * Look.HEAD_HALF.x * 2.0
const SAFE_EYES := Vector4(Look.EYE_X, Look.EYE_Y, 0.085 + 0.018 + SAFE_MARGIN, 0.098 + 0.009 + SAFE_MARGIN)
## The drift's default loop (seconds) and the face parameter it writes.
const LOOP := 8.0
const DRIFT := &"skin_drift"

const DEFAULTS := {"id": "", "head": {}, "body": {}, "feet": [], "drift": 0.0, "loop": LOOP}
const SURFACE := {"base": Color.WHITE, "fields": [], "bands": [], "stamps": [], "seam": {}}
const SHAPES := {"star": 1.0, "leaf": 2.0}
const KINDS := {"zigzag": 1.0, "wave": 2.0}

## Dresses the pip `look` dresses in the skin `overrides` names (a recipe).
static func wear(look: RefCounted, overrides: Dictionary) -> void:
	var made := recipe(overrides)
	look.set_face(FACE_SHADER, head_uniforms(made))
	var body: Dictionary = made.body
	look.set_material(look.torso(), body_material(made))
	var feet: Array = made.feet
	var all_feet: Array[Node3D] = look.feet()
	for index in range(all_feet.size()):
		var color: Color = feet[index] if index < feet.size() else body.base
		look.set_material(look.foot_mesh(all_feet[index]), Primitives.shared_material(color.darkened(Look.FOOT_SHADE), 0.9))
	var reach: float = made.drift
	if reach <= 0.0: return
	var loop: float = made.loop
	look.animate(func(worn: RefCounted, seconds: float) -> void: worn.set_face_parameter(DRIFT, drift(reach, loop, seconds)))

## The head's uniforms, worked out once per recipe (plain values, no GPU
## resource).
static func head_uniforms(made: Dictionary) -> Dictionary:
	var key := "%s:%d" % [made.id, made.hash()]
	if not _heads.has(key): _heads[key] = uniforms(made.head, HEAD_MAP, true)
	return _heads[key]

static var _heads: Dictionary = {}

## DEFAULTS with `overrides` over them, each surface filled in from SURFACE.
## An unknown field, or no id, is an error (the defaults stand in).
static func recipe(overrides: Dictionary) -> Dictionary:
	var made := DEFAULTS.duplicate(true)
	for field: String in overrides:
		if DEFAULTS.has(field): made[field] = overrides[field]
		else: push_error("Skin recipe field '%s' is not one of DEFAULTS" % field)
	if str(made.id).is_empty(): push_error("A skin recipe needs an id")
	for part: String in ["head", "body"]:
		var surface := SURFACE.duplicate(true)
		surface.merge(made[part], true)
		made[part] = surface
	return made

## The slow drift at `seconds`: a triangle from 0 out to `reach`, back
## through 0 to -reach and home over `loop` seconds.
static func drift(reach: float, loop: float, seconds: float) -> float:
	var phase := fposmod(seconds / loop, 1.0)
	if phase < 0.25: return reach * phase * 4.0
	if phase < 0.75: return reach * (2.0 - phase * 4.0)
	return reach * (phase * 4.0 - 4.0)

## The torso's material: shared by every pip wearing the skin.
static func body_material(made: Dictionary) -> Material:
	var body: Dictionary = made.body
	if (body.fields as Array).is_empty() and (body.bands as Array).is_empty() and (body.stamps as Array).is_empty() and (body.seam as Dictionary).is_empty():
		return Primitives.shared_material(body.base, 0.9)
	return Kit.cached_material("skin:%s:body" % made.id, func() -> Material:
		var shading := ShaderMaterial.new()
		shading.shader = BODY_SHADER
		var values := uniforms(body, BODY_MAP, false)
		for key: StringName in values: shading.set_shader_parameter(key, values[key])
		return shading)

## A surface's shader uniforms, by name (skin_pattern.gdshaderinc). `eyes`:
## the head, whose stamps keep out of the eyes' safety ovals.
static func uniforms(surface: Dictionary, map: Vector3, eyes: bool) -> Dictionary:
	var values := {&"surface_map": map, &"pattern_base": _raw(surface.base), &"safe_eyes": SAFE_EYES if eyes else Vector4.ZERO, &"skin_drift": 0.0, &"crown_wrap": CROWN_WRAP if eyes else Vector3.ZERO}
	var points := PackedVector2Array()
	var info := PackedVector4Array()
	var field_colors := PackedVector3Array()
	for field: Dictionary in surface.fields:
		var corners: Array = field.points
		if info.size() >= MAX_FIELDS or points.size() + corners.size() > MAX_FIELD_POINTS or corners.size() < 3 or corners.size() > 8:
			push_error("A skin field does not fit the shader (at most %d fields, %d points, 3 to 8 each)" % [MAX_FIELDS, MAX_FIELD_POINTS])
			continue
		info.append(Vector4(points.size(), corners.size(), float(field.get("wander", 0.0)), 0))
		for corner: Vector2 in corners: points.append(corner)
		field_colors.append(_raw(field.color))
	values[&"field_points"] = _padded2(points, MAX_FIELD_POINTS)
	values[&"field_info"] = _padded4(info, MAX_FIELDS)
	values[&"field_color"] = _padded3(field_colors, MAX_FIELDS)
	var rows := PackedVector4Array()
	var styles := PackedVector4Array()
	var band_colors := PackedVector3Array()
	var edge_colors := PackedVector3Array()
	for band: Dictionary in surface.bands:
		if rows.size() >= MAX_BANDS:
			push_error("A skin has more than %d bands" % MAX_BANDS)
			break
		rows.append(Vector4(band.from, band.to, band.get("period", 1.0), band.get("amplitude", 0.0)))
		styles.append(Vector4(KINDS.get(str(band.get("kind", "wave")), 2.0), band.get("edge", 0.0), 0, 0))
		band_colors.append(_raw(band.color))
		edge_colors.append(_raw(band.get("edge_color", band.color)))
	values[&"band_rows"] = _padded4(rows, MAX_BANDS)
	values[&"band_style"] = _padded4(styles, MAX_BANDS)
	values[&"band_color"] = _padded3(band_colors, MAX_BANDS)
	values[&"band_edge_color"] = _padded3(edge_colors, MAX_BANDS)
	var at := PackedVector4Array()
	var stamp_styles := PackedVector4Array()
	var stamp_colors := PackedVector3Array()
	for stamp: Dictionary in surface.stamps:
		if at.size() >= MAX_STAMPS:
			push_error("A skin has more than %d stamps" % MAX_STAMPS)
			break
		var spot: Vector2 = stamp.at
		at.append(Vector4((spot.x - 0.5) * 2.0 * map.x, map.y - spot.y * map.z, float(stamp.width) * map.x, float(stamp.get("turn", 0.0))))
		stamp_styles.append(Vector4(SHAPES.get(str(stamp.shape), 1.0), -1.0 if stamp.get("back", false) else 1.0, 0, 0))
		stamp_colors.append(_raw(stamp.color))
	values[&"stamp_at"] = _padded4(at, MAX_STAMPS)
	values[&"stamp_style"] = _padded4(stamp_styles, MAX_STAMPS)
	values[&"stamp_color"] = _padded3(stamp_colors, MAX_STAMPS)
	var seam: Dictionary = surface.seam
	values[&"seam_half"] = float(seam.get("width", 0.0)) * map.x if not seam.is_empty() else 0.0
	values[&"seam_color"] = _raw(seam.get("color", surface.base))
	return values

## A palette colour as the shaders take it: its values as they are, like
## baked vertex colours (kit/fall_effect.gd's colours too); converting it to
## linear first draws it a whole gamma too dark.
static func _raw(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)

static func _padded2(values: PackedVector2Array, size: int) -> PackedVector2Array:
	var out := values.duplicate()
	out.resize(size)
	return out

static func _padded3(values: PackedVector3Array, size: int) -> PackedVector3Array:
	var out := values.duplicate()
	out.resize(size)
	return out

static func _padded4(values: PackedVector4Array, size: int) -> PackedVector4Array:
	var out := values.duplicate()
	out.resize(size)
	return out
