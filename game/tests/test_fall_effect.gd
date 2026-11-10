extends SceneTree
## Falling wear effects (presentation/kit/fall_effect.gd and its shader):
## - the shader and its GDScript mirror agree: the same uniforms by name, type
##   and default, the same instance uniforms, the same hash and fall key, and
##   each random draw read with the same values on both sides; every recipe
##   field is a uniform or a bake field. Headless runs never compile the
##   shader, so this reads its source;
## - the hash is lowbias32 on 32 bit words and each fall draws its own look;
## - every shape is a few triangles round its middle, and a fall of it stays
##   within the item budget;
## - for every shape and every sample recipe (tests/fixtures/fall_samples.gd),
##   and every catalog item that wears a fall: the shared checks
##   (tests/fixtures/fall_checks.gd): in every pip view from every facing,
##   idle and dozing, never inside the pip, clear of a carried seed, inside
##   its bounds, seamless at the loop, one draw call on the pip's clock,
##   still under Reduce motion, its own seed per pip, see-through on the
##   race ghost.
const FallEffect = preload("res://presentation/kit/fall_effect.gd")
const FallChecks = preload("res://tests/fixtures/fall_checks.gd")
const FallSamples = preload("res://tests/fixtures/fall_samples.gd")
const Spirit = preload("res://presentation/spirit_visual.gd")
const Stage = preload("res://presentation/kit/pip_stage.gd")
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Look = preload("res://presentation/spirit_look.gd")

const SHADER_PATH := "res://presentation/kit/fall_effect.gdshader"
const SCRIPT_PATH := "res://presentation/kit/fall_effect.gd"
## Recipe fields that are not shader uniforms of the same name, and where they go.
const BAKE_FIELDS := ["id", "shape", "size", "colors", "clear", "head_sink", "bounds"]
## The board's budget per item (test_pip_outfit.gd MAX_TRIANGLES), and a shape's.
const MAX_TRIANGLES := 640
const SHAPE_TRIANGLES := 24

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	Outfit.show_unreleased = true
	_sync()
	_hash()
	_recipes()
	_shapes()
	for name: StringName in FallEffect.SHAPES: _fall("shape %s" % name, {"id": "test:%s" % name, "shape": name})
	for name: String in FallSamples.SAMPLES: _fall("sample %s" % name, FallSamples.SAMPLES[name])
	_catalog()
	print("FALL EFFECT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The shader's uniforms: name -> [type, default text or "", instance].
func _uniforms(code: String) -> Dictionary:
	var found := {}
	var pattern := RegEx.create_from_string("(?m)^\\s*(instance\\s+)?uniform\\s+(\\w+)\\s+(\\w+)\\s*(?:=\\s*([^;]+))?;")
	for match: RegExMatch in pattern.search_all(code):
		found[match.get_string(3)] = [match.get_string(2), match.get_string(4).strip_edges(), not match.get_string(1).is_empty()]
	return found

## A GLSL literal (float, vecN(...)) as a Variant, or null.
func _literal(text: String) -> Variant:
	if text.is_valid_float(): return text.to_float()
	var vector := RegEx.create_from_string("^vec([23])\\(([^)]*)\\)$").search(text)
	if vector == null: return null
	var parts := vector.get_string(2).split(",")
	if parts.size() != vector.get_string(1).to_int(): return null
	var values: Array[float] = []
	for part: String in parts: values.append(part.strip_edges().to_float())
	return Vector2(values[0], values[1]) if vector.get_string(1) == "2" else Vector3(values[0], values[1], values[2])

func _same(value: Variant, other: Variant) -> bool:
	if value is float and other is float: return is_equal_approx(value, other) or absf(value - other) < 0.000001
	if value is Vector2 and other is Vector2: return (value as Vector2).distance_to(other) < 0.000001
	if value is Vector3 and other is Vector3: return (value as Vector3).distance_to(other) < 0.000001
	return false

## The shader and the GDScript mirror agree; changing one alone fails here.
func _sync() -> void:
	var code := FileAccess.get_file_as_string(SHADER_PATH)
	var mirror := FileAccess.get_file_as_string(SCRIPT_PATH)
	_check(not code.is_empty() and not mirror.is_empty() and FallEffect.SHADER.resource_path == SHADER_PATH, "The kit draws with its own shader file")
	var shader := _uniforms(code)
	var values := FallEffect.uniforms(FallEffect.recipe({"id": "test:defaults"}))
	var names := {}
	for name: String in shader:
		if not shader[name][2]: names[name] = true
	var keys := {}
	for key: StringName in values: keys[str(key)] = true
	_check(names.keys().size() == keys.keys().size() and names.keys().all(func(name: String) -> bool: return keys.has(name)), "The material sets exactly the shader's uniforms: shader %s, material %s" % [names.keys(), keys.keys()])
	var types := {TYPE_FLOAT: "float", TYPE_VECTOR2: "vec2", TYPE_VECTOR3: "vec3"}
	var wrong: Array[String] = []
	var defaults_off: Array[String] = []
	var no_default: Array[String] = []
	for name: String in names:
		if not keys.has(name): continue
		var value: Variant = values[StringName(name)]
		if types.get(typeof(value), "") != shader[name][0]: wrong.append("%s: %s, %s" % [name, shader[name][0], type_string(typeof(value))])
		var text: String = shader[name][1]
		if text.is_empty():
			no_default.append(name)
			continue
		if not _same(_literal(text), value): defaults_off.append("%s: %s, %s" % [name, text, value])
	_check(wrong.is_empty(), "Each uniform has the shader's type: %s" % [wrong])
	_check(defaults_off.is_empty(), "Each shader default is the recipe's default (DEFAULTS): %s" % [defaults_off])
	no_default.sort()
	_check(no_default == ["head_center", "head_half", "torso_center", "torso_half"], "Only the pip's own shapes have no shader default (the kit always sets them): %s" % [no_default])
	var instances: Array = shader.keys().filter(func(name: String) -> bool: return shader[name][2])
	instances.sort()
	var expected := [str(FallEffect.CLOCK), str(FallEffect.SEED), str(FallEffect.VEIL)]
	expected.sort()
	_check(instances == expected and shader[str(FallEffect.CLOCK)][0] == "float" and shader[str(FallEffect.SEED)][0] == "float", "The instance uniforms are the kit's clock, seed and veil: %s" % [instances])
	var fields: Array = FallEffect.DEFAULTS.keys().filter(func(field: String) -> bool: return not FallEffect.PATH_FIELDS.has(field))
	fields.sort()
	var bake := BAKE_FIELDS.duplicate()
	bake.sort()
	_check(fields == bake and FallEffect.PATH_FIELDS.all(func(field: String) -> bool: return FallEffect.DEFAULTS.has(field) and names.has(field)), "Every recipe field is a shader uniform of its name or a bake field: %s" % [fields])
	var flat := code.replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "")
	var hashing := "x^=x>>16u;x*=%du;x^=x>>15u;x*=%du;x^=x>>16u;" % [FallEffect.HASH[0], FallEffect.HASH[1]]
	_check(flat.contains(hashing), "The shader hashes with the mirror's lowbias32 constants")
	var keying := "mix_word((uint(index)*%du+uint(fall)*%du)^uint(%s))" % [FallEffect.KEY[0], FallEffect.KEY[1], FallEffect.SEED]
	_check(flat.contains(keying), "and keys a fall by the mirror's multipliers and the pip's seed")
	_check(flat.contains("returnfloat(mix_word(key+uint(at))>>8u)/16777216.0;") and mirror.replace(" ", "").contains("float(_mix((key+at)&WORD)>>8)/16777216.0"), "and turns a word into a draw the same way")
	_check(not code.contains("TIME"), "It moves on the pip's clock, never TIME")
	# Each draw is read with the same uniforms on both sides.
	var shader_draws := _draw_uses(_body(code, "void vertex()"), "draw\\(key, (\\d+)\\)", ";", names)
	var mirror_draws := _draw_uses(_body(mirror, "static func fall_shape(") + _body(mirror, "static func fall_place("), "draws\\[(\\d+)\\]", "\n", names)
	var all := range(FallEffect.DRAWS)
	_check(shader_draws.keys().size() == FallEffect.DRAWS and all.all(func(at: int) -> bool: return shader_draws.has(at)), "The shader draws exactly DRAWS values: %s" % [shader_draws.keys()])
	var differ: Array[String] = []
	for at: int in all:
		if shader_draws.get(at, []) != mirror_draws.get(at, ["(not drawn)"]): differ.append("%d: shader %s, mirror %s" % [at, shader_draws.get(at), mirror_draws.get(at)])
	_check(differ.is_empty(), "Each draw takes the same uniforms in the shader and the mirror: %s" % [differ])
	# Every value the path works out takes the same uniforms on both sides.
	var shader_steps := _steps(_body(code, "void vertex()"), ";", "^\\s*(?:\\w+\\s+)?(\\w+)\\s*=[^=]", names)
	var mirror_steps := _steps(_body(mirror, "static func fall_shape(") + "\n" + _body(mirror, "static func fall_place("), "\n", "^\\s*(?:var\\s+)?(\\w+)\\s*(?::\\s*\\w+\\s*)?:?=[^=]", names)
	var unmatched: Array[String] = []
	for target: String in shader_steps:
		if shader_steps[target] != mirror_steps.get(target, []): unmatched.append("%s: shader %s, mirror %s" % [target, shader_steps[target], mirror_steps.get(target, "(none)")])
	for target: String in mirror_steps:
		if not shader_steps.has(target) and not (mirror_steps[target] as Array).is_empty(): unmatched.append("%s: mirror only %s" % [target, mirror_steps[target]])
	_check(unmatched.is_empty() and shader_steps.has("out_to") and shader_steps.has("fade") and shader_steps.has("w"), "Each step of the path takes the same uniforms in the shader and the mirror: %s" % [unmatched])
	var drawn := _steps(_body(code, "void fragment()"), ";", "^\\s*(\\w+)\\s*=[^=]", names)
	var lit := {}
	for target: String in drawn:
		for name: String in drawn[target]: lit[name] = true
	_check(lit.keys() == ["glow"], "The fragment takes only the glow, which the path never needs: %s" % [lit.keys()])

## The text of the function starting at `head` up to the next top-level line.
func _body(source: String, head: String) -> String:
	var from := source.find(head)
	if from < 0: return ""
	var lines := source.substr(from).replace("\r", "").split("\n")
	var kept: Array[String] = [lines[0]]
	for index in range(1, lines.size()):
		var line: String = lines[index]
		if not line.is_empty() and not line.begins_with("\t") and not line.begins_with(" "): break
		kept.append(line)
	return "\n".join(kept)

## Assigned name -> the sorted uniform names its statements read (the
## mirror's "colors" for the two colour uniforms). A local named after a
## uniform is the mirror unpacking it, not a step.
func _steps(body: String, end: String, assign: String, names: Dictionary) -> Dictionary:
	var steps := {}
	var target := RegEx.create_from_string(assign)
	for statement: String in body.split(end):
		var line := statement.strip_edges()
		# The first statement follows the function's head.
		if line.contains("{"): line = line.substr(line.rfind("{") + 1).strip_edges()
		var found := target.search(line)
		if found == null or names.has(found.get_string(1)) or found.get_string(1) == "colors": continue
		var named: Dictionary = {}
		for name: String in steps.get(found.get_string(1), []): named[name] = true
		for name: String in _named(line, names): named[name] = true
		var sorted := named.keys()
		sorted.sort()
		steps[found.get_string(1)] = sorted
	return steps

## The uniform names `text` reads.
func _named(text: String, names: Dictionary) -> Array:
	var named := {}
	for match: RegExMatch in RegEx.create_from_string("[A-Za-z_]\\w*").search_all(text):
		var token := match.get_string()
		if token == "colors":
			named["color_a"] = true
			named["color_b"] = true
		elif names.has(token): named[token] = true
	return named.keys()

## Draw index -> the sorted uniform names (the mirror's "colors" for the two
## colour uniforms) in the statement reading it.
func _draw_uses(body: String, draw: String, end: String, names: Dictionary) -> Dictionary:
	var uses := {}
	var finder := RegEx.create_from_string(draw)
	var word := RegEx.create_from_string("[A-Za-z_]\\w*")
	for statement: String in body.split(end):
		var found := finder.search_all(statement)
		if found.is_empty(): continue
		var named := {}
		for match: RegExMatch in word.search_all(statement):
			var token := match.get_string()
			if token == "colors":
				named["color_a"] = true
				named["color_b"] = true
			elif names.has(token): named[token] = true
		var sorted := named.keys()
		sorted.sort()
		for match: RegExMatch in found: uses[match.get_string(1).to_int()] = sorted
	return uses

func _hash() -> void:
	_check(FallEffect._mix(1) == 1753845952 and FallEffect._mix(123456789) == 2834422664 and FallEffect._mix(0xFFFFFFFF) == 1734902346, "The hash is lowbias32 on 32 bit words, as the shader's uint computes it")
	var first := FallEffect.fall_draws(3, 0, FallEffect.pip_seed(1))
	var inside := first.size() == FallEffect.DRAWS
	for value: float in first: inside = inside and value >= 0.0 and value < 1.0
	_check(inside and first != FallEffect.fall_draws(3, 1, FallEffect.pip_seed(1)) and first != FallEffect.fall_draws(4, 0, FallEffect.pip_seed(1)) and first != FallEffect.fall_draws(3, 0, FallEffect.pip_seed(2)), "Each fall draws its own look, another shape's or another pip's another")
	_check(FallEffect.pip_seed(1) != FallEffect.pip_seed(2) and FallEffect.pip_seed(1) < 65536, "Pips get their own seeds, exact in the shader's float")

func _recipes() -> void:
	var made := FallEffect.recipe({"id": "test:recipe", "shape": &"star", "count": 4})
	_check(made.shape == &"star" and made.count == 4 and made.loop == FallEffect.DEFAULTS.loop and made.size() == FallEffect.DEFAULTS.size(), "A recipe takes its own fields over the defaults")
	_check(FallEffect.DEFAULTS.id == "" and FallEffect.recipe({"id": "test:recipe"}).id == "test:recipe", "and names its own shared mesh and material")
	var one := FallEffect.mesh(made)
	_check(one == FallEffect.mesh(FallEffect.recipe({"id": "test:recipe", "shape": &"star", "count": 4})) and FallEffect.material(made) == FallEffect.material(made), "baked once per recipe and shared")
	var other := FallEffect.recipe({"id": "test:recipe", "shape": &"leaf", "count": 4, "glow": 0.9})
	_check(FallEffect.mesh(other) != one and FallEffect.material(other) != FallEffect.material(made), "and a recipe copied under the same id with other values gets its own")

## Each shape: a few triangles round its middle, inside its half sizes, every
## index in range; count of them stays within the item budget.
func _shapes() -> void:
	var size := Vector3(0.06, 0.006, 0.04)
	for name: StringName in FallEffect.SHAPES:
		var one := FallEffect.shape(name, size)
		var vertices: PackedVector3Array = one.vertices
		var indices: PackedInt32Array = one.indices
		var normals: PackedVector3Array = one.normals
		var spread := true
		for vertex: Vector3 in vertices: spread = spread and absf(vertex.x) <= size.x + 0.0001 and absf(vertex.z) <= size.z + 0.0001 and vertex.y >= -0.0001 and vertex.y <= size.y + 0.0001
		var valid := indices.size() % 3 == 0 and normals.size() == vertices.size()
		for index: int in indices: valid = valid and index >= 0 and index < vertices.size()
		_check(valid and vertices.size() >= 3 and indices.size() / 3 <= SHAPE_TRIANGLES, "%s is a few triangles: %d" % [name, indices.size() / 3])
		_check(spread, "%s lies round its middle within its half sizes" % name)
		var made := FallEffect.recipe({"id": "test:%s" % name, "shape": name})
		var mesh := FallEffect.mesh(made)
		var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		_check(mesh.get_surface_count() == 1 and mesh.get_faces().size() / 3 == int(made.count) * indices.size() / 3 and mesh.get_faces().size() / 3 <= MAX_TRIANGLES and roundi(uvs[uvs.size() - 1].x) == int(made.count) - 1, "a fall of %s is one surface of %d copies, each with its index" % [name, made.count])

## The shared checks for one recipe on a pip that wears it.
func _fall(label: String, overrides: Dictionary) -> void:
	var made := FallEffect.recipe(overrides)
	var staged := func(color: Color) -> Node3D:
		var pip := Stage.pip(color, {})
		FallChecks.dress(pip, overrides)
		return pip
	FallChecks.path(self, _check, label, made, staged, {}, false)
	FallChecks.node(_check, label, made, func() -> Node3D:
		var spirit: Node3D = Spirit.new(Look.PEACH)
		root.add_child(spirit)
		spirit.advance_motion(Vector3.ZERO, 0.001, false)
		FallChecks.dress(spirit, overrides)
		return spirit)

## Every catalog item that wears a fall gets the shared checks, so a new
## falling skin is covered without a line here.
func _catalog() -> void:
	var worn := 0
	for id: String in Catalog.ids():
		var outfit := Outfit.of(id, true)
		var probe := Stage.pip(Look.PEACH, outfit)
		var found := FallChecks.falls(probe)
		var made: Dictionary = found[0].get_meta(FallEffect.RECIPE_META) if not found.is_empty() else {}
		probe.free()
		if made.is_empty(): continue
		worn += 1
		FallChecks.path(self, _check, id, made, func(color: Color) -> Node3D: return Stage.pip(color, outfit), outfit, false)
		FallChecks.node(_check, id, made, func() -> Node3D:
			var spirit: Node3D = Spirit.new(Look.PEACH)
			root.add_child(spirit)
			spirit.advance_motion(Vector3.ZERO, 0.001, false)
			spirit.wear(outfit)
			return spirit)
	_check(worn >= 1, "The catalog's falling skins are found: %d" % worn)
