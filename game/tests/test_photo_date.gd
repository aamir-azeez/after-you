extends SceneTree
## The handwritten capture date on the polaroid: format, the bundled pen font and its notice.
const PhotoDate = preload("res://presentation/photo_date.gd")
const Polaroid = preload("res://presentation/photo_polaroid_card.gd")
const Catalog = preload("res://services/licenses.gd")
const FONT_PATH := "res://assets/fonts/pen-date.ttf"
## 2026-10-15 12:00:00 UTC.
const NOON := 1792065600
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for pair: Array in [[1, "1st"], [2, "2nd"], [3, "3rd"], [4, "4th"], [10, "10th"], [11, "11th"], [12, "12th"], [13, "13th"], [14, "14th"], [21, "21st"], [22, "22nd"], [23, "23rd"], [24, "24th"], [30, "30th"], [31, "31st"]]:
		_check(PhotoDate.ordinal(pair[0]) == pair[1], "Ordinal day %d reads %s" % pair)
	_check(PhotoDate.format(NOON, 0) == "15th Oct '26", "The approved short form: 15th Oct '26")
	_check(PhotoDate.format(NOON, 13 * 60) == "16th Oct '26" and PhotoDate.format(NOON, -13 * 60) == "14th Oct '26", "The date is the player's local date for the capture time")
	_check(PhotoDate.format(1767225599, 0) == "31st Dec '25" and PhotoDate.format(1767225600, 0) == "1st Jan '26", "Year end and start, with the two-digit year after an apostrophe")
	_check(PhotoDate.format(1704067200 + 2 * 86400 + 3600, 0) == "3rd Jan '24", "A leading zero year keeps two digits")
	_check(PhotoDate.format(0, 0).is_empty() and PhotoDate.local(0).is_empty(), "No capture time writes no date")
	var months := []
	for month: int in 12:
		months.append(PhotoDate.format(1767225600 + (month * 31 + 1) * 86400, 0).split(" ")[1])
	_check(months == PhotoDate.MONTHS, "Every month uses its short English name")
	await _card_dates()
	_font_and_notice()
	print("After You photo date: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _jpeg() -> PackedByteArray:
	var image := Image.create(24, 24, false, Image.FORMAT_RGB8)
	image.fill(Color(0.4, 0.6, 0.5))
	return image.save_jpg_to_buffer(0.8)

func _card_dates() -> void:
	var stage := Control.new()
	stage.size = Vector2(1560, 720)
	root.add_child(stage)
	var empty: Control = Polaroid.new()
	stage.add_child(empty)
	empty.build("Before", "")
	empty.show_photo(PackedByteArray(), false, NOON)
	_check(empty.date_label == null and empty.paper.find_child("PolaroidDate", true, false) == null, "The empty polaroid before a photo has no date")
	var old: Control = Polaroid.new()
	stage.add_child(old)
	old.build("Older photo", "")
	_check(old.show_photo(_jpeg(), false, 0) and old.date_label == null, "A photo kept before capture times existed shows no date")
	var dated: Control = Polaroid.new()
	stage.add_child(dated)
	dated.build("Dated", "")
	_check(dated.show_photo(_jpeg(), false, NOON), "A dated photo shows")
	var label: Label = dated.date_label
	_check(label != null and label.get_parent() == dated.paper and label.text == PhotoDate.local(NOON), "One date label sits on the tilted paper, in local time")
	_check(label.get_theme_font("font").resource_path == FONT_PATH and label.get_theme_font_size("font_size") == Polaroid.DATE_SIZE and label.get_theme_color("font_color") == Color("5b5246"), "The date uses the pen font, its size and ink")
	var strip_top := Polaroid.PHOTO_INSET + Polaroid.PHOTO_SIDE
	_check(label.position.y == strip_top and label.size == Vector2(Polaroid.PAPER_SIZE.x, Polaroid.PAPER_SIZE.y - strip_top) and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "The date is centred on the bottom strip")
	_check(not label.is_processing() and dated.paper.get_children().filter(func(child: Node) -> bool: return child is Label).size() == 1, "The date is a single still label")
	stage.queue_free()
	await process_frame

func _font_and_notice() -> void:
	var size := FileAccess.get_file_as_bytes(FONT_PATH).size()
	_check(size > 1000 and size < 32 * 1024, "The pen font is subset to a few KB (%d bytes)" % size)
	var font: FontFile = load(FONT_PATH)
	var missing := ""
	for character: String in PhotoDate.CHARACTERS:
		if not font.has_char(character.unicode_at(0)): missing += character
	_check(missing.is_empty(), "The subset keeps every character a date uses: missing '%s'" % missing)
	_check(not font.has_char("x".unicode_at(0)) and not font.has_char("Q".unicode_at(0)) and not font.has_char(0xAC00), "Characters a date never uses are dropped")
	var entry: Array = Catalog.entries().filter(func(item: Dictionary) -> bool: return item.title == "After You Date Pen font (from Nanum Pen Script)")
	_check(entry.size() == 1 and entry[0].text.contains("SIL OPEN FONT LICENSE Version 1.1"), "The pen font's OFL is in the licence catalog")
	_check(not font.get_font_name().to_lower().contains("nanum") and font.get_font_name() == "After You Date Pen", "The subset is renamed, as the OFL's reserved Nanum names require")
