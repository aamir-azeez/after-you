extends SceneTree
## About this chapter's letter (presentation/letter/letter_view.gd) at the size
## of a 6-inch phone's canvas (1600 x 720) and the iPhone Duo's outer screen
## (1280 x 880): the closed envelope first, the letter out after a tap with
## its Back tag, a long letter scrolling under the title, emphasis leaning and
## underlined, and reduced motion showing the letter at once.
const LetterView = preload("res://presentation/letter/letter_view.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Actions = preload("res://presentation/action_buttons.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const StampArt = preload("res://presentation/letter/stamp_art.gd")
const SCREENS := {"phone": Vector2(1600, 720), "duo outer": Vector2(1280, 880)}
## The letter with *knew* in it, and one that fits without scrolling. The
## long letter is that one written out three times.
const ITALIC_KEY := "long-way-home@3"
const SHORT_KEY := "turn-of-the-tide@1"
var checks := 0
var failures := 0
var _backs := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	for screen: String in SCREENS:
		await _closed_then_open(screen, SCREENS[screen])
	await _reduced_motion()
	_pen_has_every_letter()
	_every_stamp_draws()
	print("AFTER YOU LETTER VIEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _view(letter: Dictionary, area: Vector2, reduced: bool) -> Control:
	var holder := Control.new()
	holder.size = area
	root.add_child(holder)
	var view := LetterView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(view)
	view.configure("Chapter", letter, ThemeDB.fallback_font, reduced, Actions.create("back", func() -> void: _backs += 1))
	await process_frame
	await process_frame
	return view

func _closed_then_open(screen: String, area: Vector2) -> void:
	var long := Registry.letter(SHORT_KEY)
	long.body = " ".join([long.body, long.body, long.body])
	var view := await _view(long, area, false)
	var stage: Control = view.envelope.get_parent()
	_check(view.envelope.visible and not view.envelope.side_back and not view.scroll.visible and not view.back_button.visible, "Closed first: the envelope's front, no letter, no tag (%s)" % screen)
	_check(Rect2(Vector2.ZERO, stage.size).encloses(Rect2(view.envelope.position, view.envelope.size)), "The closed envelope fits the card (%s)" % screen)
	view.envelope.pressed.emit()
	var guard := 0
	while not view.back_button.visible and guard < 600:
		await process_frame
		guard += 1
	_check(view.opened and view.scroll.visible and view.back_button.visible and view.envelope.side_back and view.envelope.flap == 1.0, "A tap turns it over, opens it and brings the letter out with its tag (%s)" % screen)
	var card: Control = view.get_node("LetterCard")
	_check(Rect2(Vector2.ZERO, area).encloses(card.get_rect()), "The card stays on screen (%s): %s" % [screen, card.get_rect()])
	_check(view.body.line_count() >= 4 and view.body.size.x >= 560.0, "The letter's words wrap across a wide sheet (%s): %d lines, %.0f wide" % [screen, view.body.line_count(), view.body.size.x])
	_check(view.scroll.get_v_scroll_bar().visible and view.scroll.get_v_scroll_bar().max_value > view.scroll.size.y, "A long letter scrolls under the title (%s)" % screen)
	var tag_before: Vector2 = view.back_button.global_position
	view.scroll.scroll_vertical = 200
	await process_frame
	_check(view.scroll.scroll_vertical > 0 and view.back_button.global_position == tag_before, "The tag stays put while the letter scrolls (%s)" % screen)
	_check(Rect2(Vector2.ZERO, stage.size).encloses(view.back_button.get_rect()), "The tag sits inside the card (%s)" % screen)
	view.back_button.pressed.emit()
	_check(_backs == 1, "The tag is the room's Back (%s)" % screen)
	_backs = 0
	view.get_parent().queue_free()
	await process_frame
	var short := await _view(Registry.letter(SHORT_KEY), area, true)
	_check(not short.scroll.get_v_scroll_bar().visible and short.scroll.get_v_scroll_bar().max_value <= short.scroll.size.y, "A letter that fits shows no scroll bar (%s)" % screen)
	short.get_parent().queue_free()
	await process_frame

func _reduced_motion() -> void:
	var view := await _view(Registry.letter(ITALIC_KEY), SCREENS.phone, true)
	_check(view.opened and view.scroll.visible and view.back_button.visible, "Reduced motion shows the letter at once")
	var leaning: Array = view.body.placed().filter(func(item: Dictionary) -> bool: return item.emphasis)
	_check(leaning.size() == 1 and leaning[0].text == "knew", "Only *knew* leans and is underlined: " + str(leaning))
	_check(not view.body.placed().any(func(item: Dictionary) -> bool: return str(item.text).contains("*")), "No asterisk is drawn")
	view.get_parent().queue_free()
	await process_frame

## Every character of every chapter's letter and envelope is in the pen subset.
func _pen_has_every_letter() -> void:
	var missing := ""
	for key: String in Registry.keys():
		var letter := Registry.letter(key)
		var words := "%s %s %s %s %s" % [letter.greeting, letter.body, letter.signoff, " ".join(letter.address), PlayerCopy.LETTER_TO]
		for i in range(words.length()):
			var character := words[i]
			if character != "*" and not LetterView.PEN.has_char(character.unicode_at(0)) and not missing.contains(character): missing += character
	_check(missing.is_empty(), "The pen hand has every character the letters use: missing '%s'" % missing)

## Every stamp kind, used or waiting for a level, draws at its size.
func _every_stamp_draws() -> void:
	for kind: String in StampArt.KINDS:
		var stamp := StampArt.texture(kind, 2.0, Color("f0e9d8"))
		_check(stamp != null and stamp.get_size() == StampArt.SIZE * 2.0, "The %s stamp draws" % kind)
