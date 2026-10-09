extends RefCounted
## Bundled static gameplay images for every selectable chapter.
const ChapterRegistry = preload("res://services/chapter_registry.gd")

const SLEEPING_LIGHTHOUSE := "sleeping-lighthouse"
const SOLO_ONLY_KEYS := [SLEEPING_LIGHTHOUSE]
const LEGACY_KEYS := [
	"legacy-rising-together",
	"legacy-across-the-blue",
	"legacy-lantern-crossing",
	"legacy-two-beats",
	"legacy-after-you",
]
const THUMBNAILS := {
	"first-steps@1": "res://assets/chapter_thumbnails/first-steps.png",
	"legacy-first-light": "res://assets/chapter_thumbnails/legacy-first-light.png",
	"legacy-long-way-home": "res://assets/chapter_thumbnails/legacy-long-way-home.png",
	"legacy-patient-garden": "res://assets/chapter_thumbnails/legacy-patient-garden.png",
	"sleeping-lighthouse": "res://assets/paid_levels/sleeping-lighthouse.png",
	"relay-isles@2": "res://assets/chapter_thumbnails/relay-isles.png",
	"high-and-low@1": "res://assets/chapter_thumbnails/high-and-low.png",
	"rolling-home@1": "res://assets/paid_levels/rolling-home.png",
	"a-house-for-two@1": "res://assets/paid_levels/a-house-for-two.png",
	"conservatory@1": "res://assets/paid_levels/conservatory.png",
	"long-way-home@1": "res://assets/paid_levels/long-way-home.png",
	"legacy-rising-together": "res://assets/paid_levels/legacy-rising-together.png",
	"legacy-across-the-blue": "res://assets/paid_levels/legacy-across-the-blue.png",
	"legacy-lantern-crossing": "res://assets/paid_levels/legacy-lantern-crossing.png",
	"legacy-two-beats": "res://assets/paid_levels/legacy-two-beats.png",
	"legacy-after-you": "res://assets/paid_levels/legacy-after-you.png",
}

static func keys() -> Array[String]:
	var result: Array[String] = []
	result.append(ChapterRegistry.FIRST_STEPS)
	result.append(SLEEPING_LIGHTHOUSE)
	result.append(ChapterRegistry.RELAY)
	for key: String in ChapterRegistry.keys():
		if key not in result:
			result.append(key)
	result.append_array(["legacy-first-light", "legacy-long-way-home", "legacy-patient-garden"])
	result.append_array(LEGACY_KEYS)
	return result

static func path(key: String) -> String:
	return str(THUMBNAILS.get(key, ""))

static func texture(key: String) -> Texture2D:
	var resource_path := path(key)
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		return null
	return load(resource_path) as Texture2D

static func entry(key: String) -> Dictionary:
	var resource_path := path(key)
	if resource_path.is_empty():
		return {}
	return {"key": key, "texture": resource_path, "solo_only": key in SOLO_ONLY_KEYS}
