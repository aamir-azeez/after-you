extends SceneTree
## The pack art (kit/bundle_art.gd), the one path to a pack's picture: every
## pack in pollen_bundles.json and each currency's first pack pair has its
## picture, the two Pollen packs shown by other names than their keys get the
## pictures of those names, each picture keeps its transparency, is no bigger
## than the largest size a store board draws it at and has mipmaps for the
## small cards, the art fits its box keeping its shape and takes no input,
## an unknown key draws nothing, and a refunded pack fades as one picture.
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const BUNDLES_JSON := "res://content/pollen_bundles.json"
## Every key in store order, then the first pack pairs.
const KEYS := ["pinch", "pouch", "jar", "basket", "handful", "bowl", "crate", "barrel", "pouch_pair", "bowl_pair"]
## The longest side each store board draws a picture at, in a 2340 by 1080
## phone's pixels (Fruits boards 3 and 9): the picture is never bigger.
const LARGEST := {"pinch": 200, "pouch": 270, "jar": 330, "basket": 460, "handful": 270, "bowl": 240, "crate": 280, "barrel": 380, "pouch_pair": 390, "bowl_pair": 380}
## The sizes the game draws the art at (purchases, short-of card, receipt, confirm, store).
const SIDES := [46.0, 52.0, 76.0, 84.0, 104.0]
## Pictures in assets/store/ that are not pack art (the Fruit mark's render).
const NOT_PACKS := ["fruit-rose.png"]

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _run() -> void:
	_pictures()
	await _art()
	print("BUNDLE ART: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _pictures() -> void:
	_check(BundleArt.PICTURES.keys() == KEYS, "Every pack and pair has a picture, in store order: %s" % [BundleArt.PICTURES.keys()])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUNDLES_JSON))
	var sold: Dictionary = parsed.get("bundles", {}) if parsed is Dictionary else {}
	_check(not sold.is_empty(), "The packs are read from %s" % BUNDLES_JSON)
	for key: String in sold: _check(BundleArt.PICTURES.has(key), "The pack %s has its picture" % key)
	_check(BundleArt.path("jar").ends_with("pollen-basket.png") and BundleArt.path("basket").ends_with("pollen-wheelbarrow.png"), "The jar shows the Basket and the basket shows the Wheelbarrow, as their names do")
	_check(BundleArt.first_pack("pollen") == "pouch_pair" and BundleArt.first_pack("fruits") == "bowl_pair" and BundleArt.first_pack("") == "pouch_pair", "Each currency's first pack card shows its pair, and no currency is Pollen")
	var used: Array[String] = []
	for key: String in KEYS:
		var path := BundleArt.path(key)
		used.append(path.get_file())
		_check(path.begins_with(BundleArt.DIR) and ResourceLoader.exists(path), "%s's picture is in %s" % [key, BundleArt.DIR])
		_check(BundleArt.picture(key) is Texture2D, "%s's picture loads" % key)
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if not _check_image(image, key): continue
		_check(maxi(image.get_width(), image.get_height()) <= int(LARGEST[key]), "%s is no bigger than a store board draws it: %s" % [key, image.get_size()])
		var import_text := FileAccess.get_file_as_string(path + ".import")
		_check(import_text.contains("mipmaps/generate=true") and import_text.contains("compress/mode=0"), "%s is imported whole with mipmaps for the small cards" % key)
	for file: String in DirAccess.get_files_at(BundleArt.DIR):
		if file.ends_with(".png"): _check(file in used or file in NOT_PACKS, "%s in %s is used" % [file, BundleArt.DIR])
	_check(BundleArt.path("nothing").is_empty() and BundleArt.picture("nothing") == null, "An unknown pack has no picture")

func _check_image(image: Image, key: String) -> bool:
	if image == null or image.is_empty():
		_check(false, "%s's picture reads" % key)
		return false
	_check(image.detect_alpha() != Image.ALPHA_NONE and image.get_pixel(0, 0).a < 0.05, "%s keeps its transparency" % key)
	return true

func _art() -> void:
	for key: String in KEYS:
		for side: float in SIDES:
			var art: Control = BundleArt.new(key, side)
			_check(art.custom_minimum_size == Vector2(side, side) and art.mouse_filter == Control.MOUSE_FILTER_IGNORE and art.name == "BundleArt", "%s at %d is square at its size and takes no input" % [key, side])
			_check(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and art.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and art.texture != null, "%s at %d keeps its shape inside its box" % [key, side])
			art.free()
	var wide: Control = BundleArt.boxed("bowl_pair", Vector2(250, 128))
	root.add_child(wide)
	await process_frame
	_check(wide.size == Vector2(250, 128) and wide.texture == BundleArt.picture("bowl_pair"), "A pair draws in a box of its own shape")
	wide.queue_free()
	var unknown: Control = BundleArt.new("nothing", 52.0)
	root.add_child(unknown)
	await process_frame
	_check(unknown.texture == null and unknown.is_inside_tree(), "An unknown pack draws nothing and breaks nothing")
	unknown.queue_free()
	var faded: Control = BundleArt.faded("jar", 46.0, 0.55)
	_check(faded.name == "BundleArt" and is_equal_approx(faded.self_modulate.a, 0.55) and faded.modulate == Color.WHITE, "A refunded pack fades as one picture")
	_check(faded.custom_minimum_size == Vector2(46, 46) and faded.texture == BundleArt.picture("jar"), "and keeps its size and picture")
	faded.free()
	await process_frame
