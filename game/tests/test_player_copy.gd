extends SceneTree
## Presentation changes must never revise the authored recording contract.
const Copy = preload("res://presentation/player_copy.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const First = preload("res://core/first_steps/stage_catalog.gd")
const Relay = preload("res://core/v2/stage_catalog.gd")
const Lighthouse = preload("res://core/lighthouse/stage_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_check(Canonical.digest(First.definition()) == "72ddc480e0f493c983fb012ce7bfa20a9cb1984ef7263d236c11509a527df85b", "First Steps catalog remains compatible with existing recordings")
	_check(Canonical.digest(Relay.relay_isles()) == "705b79d266c8acb0b94e7c9955579466654d26492455cca4b6ff27f15684b07b", "Relay catalog remains compatible with existing recordings")
	_check(First.initial_checkpoint().checkpoint_hash == "b12ac49480a223783c2d276f7b44e7dcfadcbc5deb86b1483a0e9df1e218fbbd", "First Steps initial checkpoint stays exact")
	_check(Copy.from_canonical("Uncatalogued value") == "Uncatalogued value", "Technical and short values pass through unchanged")
	var catalogs: Array = [First.definition(), Relay.relay_isles()]
	for stage_id: String in Lighthouse.STAGE_IDS:
		catalogs.append(Lighthouse.definition(stage_id))
	for catalog: Dictionary in catalogs:
		var before := Canonical.digest(catalog)
		_check_story(catalog)
		for stage: Dictionary in catalog.get("stages", []):
			_check_story(stage)
		_check(Canonical.digest(catalog) == before, "Reading presentation prose cannot mutate a canonical definition")
	var token_pattern := RegEx.new()
	token_pattern.compile("%(?:[-+0 #]*\\d*(?:\\.\\d+)?)?[sdf]")
	for key: String in Copy.FORMAT_TOKENS:
		var actual: Array[String] = []
		for token: RegExMatch in token_pattern.search_all(Copy.text(key)):
			actual.append(token.get_string())
		_check(actual == Copy.FORMAT_TOKENS[key], "Ordered format placeholders remain valid: " + key)
	print("AFTER YOU PLAYER COPY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_story(value: Dictionary) -> void:
	for field: String in ["hint_a", "hint_b", "completion_message"]:
		if not value.has(field): continue
		var original := str(value[field])
		_check(Copy.CANONICAL_KEYS.has(original), "Canonical prose has a presentation key: " + field)
		_check(Copy.from_canonical(original) == Copy.text(str(Copy.CANONICAL_KEYS[original])), "Display reads editable prose rather than changing the authored definition")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
