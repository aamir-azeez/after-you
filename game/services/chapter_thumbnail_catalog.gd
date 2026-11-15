extends RefCounted
## Bundled static gameplay images for every selectable chapter.
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")

const SLEEPING_LIGHTHOUSE := "sleeping-lighthouse"
## Images for entries that are not registered chapters. A registered chapter
## names its image in its descriptor ("thumbnail").
const OTHER_THUMBNAILS := {
	"sleeping-lighthouse": "res://assets/paid_levels/sleeping-lighthouse.png",
}

static func keys() -> Array[String]:
	var result: Array[String] = []
	result.append(ChapterRegistry.FIRST_STEPS)
	result.append(SLEEPING_LIGHTHOUSE)
	result.append(ChapterRegistry.RELAY)
	for key: String in ChapterRegistry.keys():
		if key not in result:
			result.append(key)
	return result

static func path(key: String) -> String:
	var chapter := Index.data(key)
	return str(chapter.thumbnail) if not chapter.is_empty() else str(OTHER_THUMBNAILS.get(key, ""))

## Whether key has a bundled picture, without loading it.
static func has_picture(key: String) -> bool:
	var resource_path := path(key)
	return not resource_path.is_empty() and ResourceLoader.exists(resource_path)

static func texture(key: String) -> Texture2D:
	if not has_picture(key):
		return null
	return load(path(key)) as Texture2D

static func entry(key: String) -> Dictionary:
	var resource_path := path(key)
	if resource_path.is_empty():
		return {}
	return {"key": key, "texture": resource_path}
