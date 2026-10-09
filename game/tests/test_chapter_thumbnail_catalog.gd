extends SceneTree

const Catalog = preload("res://services/chapter_thumbnail_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")

func _initialize() -> void:
	var expected: Array[String] = [Registry.FIRST_STEPS, "sleeping-lighthouse", Registry.RELAY]
	for key: String in Registry.keys():
		if key not in expected:
			expected.append(key)
	expected.append_array(["legacy-first-light", "legacy-long-way-home", "legacy-patient-garden", "legacy-rising-together", "legacy-across-the-blue", "legacy-lantern-crossing", "legacy-two-beats", "legacy-after-you"])
	var found := Catalog.keys()
	assert(found == expected, "Thumbnail catalog covers Lighthouse, all registry chapters, and the selectable earlier islands")
	assert(Catalog.entry("unknown-chapter").is_empty(), "Unknown chapters have no thumbnail entry")
	assert(Catalog.entry("sleeping-lighthouse").solo_only, "Sleeping Lighthouse is cataloged as solo-only")
	for key: String in expected:
		var item := Catalog.entry(key)
		assert(not item.is_empty(), "Entry exists: " + key)
		assert(ResourceLoader.exists(item.texture), "Image is bundled: " + key)
		var image: Texture2D = Catalog.texture(key)
		assert(image != null, "Image loads: " + key)
		if image == null:
			continue
		var size := image.get_size()
		assert(size.x >= 640 and size.y >= 360 and is_equal_approx(size.x / size.y, 16.0 / 9.0), "Image is at least 640x360 and 16:9: " + key)
	print("CHAPTER THUMBNAIL CATALOG: %d chapters" % expected.size())
	quit(0)
