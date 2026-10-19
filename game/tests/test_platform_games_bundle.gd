extends SceneTree
## Cloud save bundle: the join of two copies never loses progress, never lets an older copy win,
## is stable when applied twice, and the encoded slot fits Saved Games by dropping journals only.
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _journal(stages: int, marker: String = "") -> Dictionary:
	var pairs: Array = []
	for index in range(stages): pairs.append({"a": {"mark": marker, "i": index}, "b": {"i": index}})
	return {"version": 1, "generation": stages, "relay": {"pairs": pairs, "a": {}, "draft": {}}}

func _save(settings: Dictionary, completed: Array, replays: Dictionary = {}) -> Dictionary:
	var marks := {}
	for id: String in completed: marks[id] = true
	return {"settings": settings, "completed": marks, "replays": replays, "attempts": {}, "room": {}}

func _run() -> void:
	var phone := Bundle.collect(_save({"sound": false, "haptics": true, "graphics_quality": "high", "turn_notifications": true}, ["first-light"], {"first-light": {"a": {"x": 1}, "b": {}, "draft": {}}}), 100,
		{"relay/one": {"solo": true, "friend": false}, "relay/two": {"solo": false, "friend": false}}, {"relay-journey-v2.json": _journal(2, "phone"), "first-steps-journey-v1.json": _journal(0)})
	_check(phone.settings.values == {"sound": false, "haptics": true}, "Only device-neutral settings travel; graphics and notification switches stay on the phone")
	_check(phone.keepsakes.keys() == ["relay/one"], "Unearned keepsake marks are not carried")
	_check(phone.journals.keys() == ["relay-journey-v2.json"], "A journal with no finished stage is not carried")
	var cloud := Bundle.collect(_save({"sound": true, "haptics": false}, ["long-way-home"]), 50,
		{"relay/one": {"solo": false, "friend": true}, "relay/three": {"solo": true, "friend": false}}, {"relay-journey-v2.json": _journal(3, "cloud"), "high-and-low-journey-v1.json": _journal(1)})
	var merged := Bundle.merge(phone, cloud)
	_check(merged.completed.keys().size() == 2 and merged.completed.has("first-light") and merged.completed.has("long-way-home"), "Completions are the union")
	_check(merged.keepsakes["relay/one"] == {"solo": true, "friend": true} and merged.keepsakes.has("relay/three"), "Keepsake marks only add")
	_check(int(merged.journals["relay-journey-v2.json"].stages) == 3 and merged.journals["relay-journey-v2.json"].envelope.relay.pairs[0].a.mark == "cloud", "The journal with more finished stages wins")
	_check(merged.journals.has("high-and-low-journey-v1.json"), "A chapter only the cloud has is kept")
	_check(merged.settings.values == {"sound": false, "haptics": true} and merged.settings.stamp == 100, "The settings changed last win")
	_check(Bundle.fingerprint(Bundle.merge(cloud, phone)) == Bundle.fingerprint(merged), "Merge is order independent apart from ties")
	_check(Bundle.fingerprint(Bundle.merge(merged, merged)) == Bundle.fingerprint(merged), "Merging a copy with itself changes nothing")
	_check(Bundle.fingerprint(Bundle.merge(merged, cloud)) == Bundle.fingerprint(merged), "Applying the same cloud copy twice changes nothing")
	_check(not Bundle.adds_to(merged, merged) and Bundle.adds_to(merged, phone) and Bundle.adds_to(merged, cloud), "adds_to tells when one side lacks something")
	# Never older over newer: an untouched phone (stamp 0) loses to any real settings change.
	var fresh := Bundle.collect(_save({"sound": true, "haptics": true}, []), 0, {}, {})
	_check(Bundle.merge(fresh, cloud).settings.values == cloud.settings.values, "Defaults on a phone that never synced never overwrite chosen settings")
	var tie := Bundle.merge(Bundle.collect(_save({"sound": true}, []), 7, {}, {"relay-journey-v2.json": _journal(2, "a")}), Bundle.collect(_save({"sound": false}, []), 7, {}, {"relay-journey-v2.json": _journal(2, "b")}))
	_check(tie.settings.values.sound == true and tie.journals["relay-journey-v2.json"].envelope.relay.pairs[0].a.mark == "a", "Exact ties keep the first (this phone's) copy")

	# Encoding.
	var bytes := Bundle.encode(merged)
	_check(bytes.slice(0, 4).get_string_from_ascii() == "AYC1", "Slot bytes start with the format tag")
	var decoded := Bundle.decode(bytes)
	_check(Bundle.fingerprint(decoded) == Bundle.fingerprint(merged), "Encoding round-trips the bundle")
	_check(Bundle.decode(PackedByteArray()) == Bundle.empty(), "An empty slot is an empty bundle")
	_check(Bundle.decode("not a bundle at all".to_utf8_buffer()).is_empty(), "Foreign bytes are refused")
	var corrupt := bytes.duplicate()
	corrupt[10] = corrupt[10] ^ 0xff
	corrupt[11] = corrupt[11] ^ 0xff
	_check(Bundle.decode(corrupt).is_empty() or Bundle.fingerprint(Bundle.decode(corrupt)) == Bundle.fingerprint(merged), "Damaged bytes never decode into different progress")
	var future := merged.duplicate(true)
	future.schema_version = 2
	_check(Bundle.decode(Bundle.encode(future)).is_empty(), "A newer app's bundle is not half read")
	var extra := merged.duplicate(true)
	extra["achievements"] = {}
	_check(Bundle.validated(extra).is_empty(), "Unknown fields make a copy unusable rather than partly read")
	var lying := merged.duplicate(true)
	lying.journals["relay-journey-v2.json"].stages = 9
	_check(Bundle.validated(lying).is_empty(), "A journal's stage count must match its pairs")
	var bad_setting := merged.duplicate(true)
	bad_setting.settings.values["graphics_quality"] = true
	_check(Bundle.validated(bad_setting).is_empty(), "Settings outside the travelling set are refused")
	_check(Bundle.validated({"schema_version": 1}).is_empty(), "A partial copy is refused")

	# Size: journals are dropped, fewest stages first, until the slot fits.
	var big := Bundle.collect(_save({"sound": true}, ["first-light"]), 1, {"relay/one": {"solo": true, "friend": false}}, {})
	var noise := Crypto.new()
	for index in range(4):
		var envelope := _journal(index + 1)
		envelope.relay.pairs[0].a["noise"] = Marshalls.raw_to_base64(noise.generate_random_bytes(1_000_000))
		big.journals["chapter-%d-journey-v1.json" % index] = {"stages": index + 1, "envelope": envelope}
	var packed := Bundle.encode(big)
	var kept := Bundle.decode(packed)
	_check(packed.size() <= Bundle.MAX_BYTES, "An oversized bundle is trimmed to fit a slot")
	_check(kept.completed.has("first-light") and kept.keepsakes.has("relay/one") and kept.settings.values.sound == true, "Completions, keepsakes and settings always fit")
	_check(kept.journals.has("chapter-3-journey-v1.json") and not kept.journals.has("chapter-0-journey-v1.json"), "The journals with the fewest stages go first")

	print("PLATFORM GAMES BUNDLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
