extends SceneTree
## Load the bundled story through the native validators and Main catalog.
const Catalog = preload("res://services/campaign_catalog.gd")
const Story = preload("res://services/campaign_story.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Main = preload("res://main.gd")
const CONTENT_HASH := "015ace9140afb2d67c9acd47506a8108dd838e98278a9ac479166290e45fef16"
const DEFINITION_HASH := "41ae5d6498f3691774075508fe900bfc1fcc14e82be9035494097fed132fe1c1"
var checks := 0
var failures := 0

func _initialize() -> void:
	var loaded: Array = Catalog.bundled()
	_check(loaded.size() == 1, "Exactly one reviewed shared resource loads through the native story validator")
	if loaded.size() != 1:
		_finish()
		return
	var bundle: Dictionary = loaded[0]
	var narrative := Story.new()
	_check(Protocol.definition_valid(bundle.definition) and narrative.bind(bundle.story,bundle.definition), "Native protocol and narrative independently accept the shared immutable pins")
	var story_body: Dictionary = bundle.story.duplicate(true)
	story_body.erase("content_hash")
	var definition_body: Dictionary = bundle.definition.duplicate(true)
	definition_body.erase("definition_hash")
	_check(Canonical.digest(story_body) == CONTENT_HASH and bundle.story.content_hash == CONTENT_HASH, "Native canonical hashing agrees with the exact approved-copy artifact")
	_check(Canonical.digest(definition_body) == DEFINITION_HASH and bundle.definition.definition_hash == DEFINITION_HASH, "Native canonical hashing agrees with the exact seven-chapter definition")
	var keys: Array[String] = Registry.keys()
	_check(keys.size() == 7 and bundle.definition.chapters.size() == keys.size(), "The shipped sequence contains all seven registered chapters")
	for index in range(keys.size()):
		var pin: Dictionary = bundle.definition.chapters[index]
		var descriptor: Dictionary = Registry.descriptor(keys[index])
		_check(Registry.resolve(pin) == keys[index] and pin.simulation_version == 8 and int(pin.simulation_version) in Registry.supported_rules(keys[index]), "The story chooses the current supported rules without changing authored chapter identity: "+keys[index])
		_check(pin.premium == descriptor.premium and pin.premium == (index >= 3), "The existing free/host-premium boundary is preserved: "+keys[index])
		for phase: String in ["arrival","completion"]:
			_check(narrative.lines(index,phase).size() == 2, "Every reviewed passage retains exactly two mapped utterances")
	_check(narrative.lines(6,"completion")[0].speaker == "p1" and narrative.lines(6,"completion")[1].speaker == "p0", "The final welcome belongs to the physical window keeper p1")
	loaded[0].story.title = "Changed by caller"
	loaded[0].definition.chapters[0].simulation_version = 99
	var fresh: Array = Catalog.bundled()
	_check(fresh.size() == 1 and fresh[0].story.content_hash == CONTENT_HASH and fresh[0].story.title != "Changed by caller" and fresh[0].definition.chapters[0].simulation_version == 8, "Caller edits cannot poison a later catalog load")
	_check(Catalog._validated(loaded[0]).is_empty(), "Changed content with retained hashes fails closed")
	var main := Main.new()
	_check(main.campaign_catalog.is_empty() and main._campaign_pairs().is_empty(), "Production Main does not load the archived narrative")
	main.campaign_catalog = []
	_check(main.campaign_catalog.is_empty() and main._campaign_pairs().is_empty(), "An intentionally injected empty catalog stays empty, with no default fallback")
	main.campaign_catalog = fresh.duplicate(true)
	_check(main._campaign_pairs().is_empty(), "Archived catalog injection cannot enable Story in production")
	main.free()
	_finish()

func _finish() -> void:
	print("Campaign catalog: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
