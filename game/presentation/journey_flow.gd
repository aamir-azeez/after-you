extends Node
## Play Solo's pages: the Chapters page (the chapter picker, with its Hard
## chip) and the Earlier islands list, and which chapter a picked card opens.
## It also answers which chapters the player can open next, for Home's idle
## warm ups (GL programs, worlds and the page's pictures).
##
## Main hosts it as a child. The flow keeps only the page it has open (the
## picker, the Hard chip's state and the Full Journey access the page was drawn
## with). Opening a chapter stays with Main, which the Replays flow, the room
## hub and tester access share. The flow reads Main only through this host
## contract (read at call time, so Main or a test can swap a service or
## override an entry point):
## - services: saves, levels, title_font, hard_states, _chapter_marks,
##   _full_journey_access, _paid_content_hidden
## - screen: mode, running, ui, overlay, _screen_shell, _card, _scroll_list,
##   _button, _back_button, _label, _paragraph, _toast, _show_home
## - chapter opens: _open_premium_chapter,
##   _open_chapter_preview, _start_practice (an earlier island)
## Main opens it through show_journey() (Home's Play Solo, StoreFlow's and
## RoomHubFlow's journey requests, the update screen's Play Solo and an earlier
## island's Back) and refreshes it through refresh_marks() and access_changed().
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const ChapterThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const PaidThumbnails = preload("res://presentation/paid_level_thumbnails.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const CREAM := UiTokens.CREAM
## Main's modes on these pages.
const MODE_JOURNEY := "journey"
const MODE_EARLIER_ISLANDS := "earlier_islands"

var host: Node
## The Chapters page's picker while it is drawn.
var picker: ChapterPicker
## Play Solo's Hard chip (services/hard_mode.gd), kept for the session.
var hard := false
## Full Journey access the open chapter grid was drawn with.
var _grid_access_drawn := false

func _init(main: Node = null) -> void:
	host = main

func show_journey() -> void:
	host.running = false
	host.mode = MODE_JOURNEY
	var shell: Dictionary = host._screen_shell("Your journey",host._show_home)
	var outer: VBoxContainer = shell.outer
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",10)
	var chapters_tab: Button = host._button("Chapters",show_journey,false)
	chapters_tab.disabled = true
	ControlTheme.selected_tab(chapters_tab)
	tabs.add_child(chapters_tab)
	var earlier: Button = host._button("Earlier islands",show_earlier_islands,false)
	ControlTheme.plain_tab(earlier)
	tabs.add_child(earlier)
	# Hard: the whole chapter in one go (services/hard_mode.gd).
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(spacer)
	var hard_chip := HardModeView.chip(hard)
	hard_chip.toggled.connect(func(on: bool):
		hard = on
		show_journey())
	tabs.add_child(hard_chip)
	outer.add_child(tabs)
	var chapter_picker := ChapterPicker.new()
	chapter_picker.heading_font = host.title_font
	chapter_picker.available_width = func() -> float: return host.ui.size.x-44.0
	chapter_picker.hard_mode = HardMode.SOLO
	chapter_picker.hard_states = host.hard_states()
	outer.add_child(chapter_picker)
	shell.margin.resized.connect(chapter_picker.refit)
	# The picker puts every free chapter first, each part in registry order.
	var owned: bool = host._full_journey_access()
	_grid_access_drawn = owned
	chapter_picker.set_entries(entries(owned,hard),ChapterPicker.picture_for(host.ui.size.x))
	chapter_picker.chosen.connect(open_solo_chapter)
	picker = chapter_picker
	refresh_marks()

## Runs a Play Solo card's play button: the chapter's solo scene, through the
## premium gate when the chapter is premium.
func open_solo_chapter(key: String) -> void:
	if hard and host.mode == MODE_JOURNEY:
		_open_hard_chapter(key)
		return
	if not own_solo_card(key): return
	if ChapterRegistry.descriptor(key).premium: host._open_premium_chapter(ChapterRegistry.open_scene(key))
	else: host._open_chapter_preview(ChapterRegistry.open_scene(key))

## Every chapter with a solo screen has its own Solo card.
static func own_solo_card(key: String) -> bool:
	return not ChapterRegistry.solo_scene(key).is_empty()

## A solo hard run of the chapter, once it is finished (services/hard_mode.gd).
func _open_hard_chapter(key: String) -> void:
	if not HardMode.unlocked(host._chapter_marks(), key):
		host._toast(PlayerCopy.HARD_LOCKED_TOAST)
		return
	var request := {"chapter_key": key, "kind": "play"}
	if ChapterRegistry.descriptor(key).premium: host._open_premium_chapter(ChapterRegistry.solo_scene(key), {}, request)
	else: host._open_chapter_preview(ChapterRegistry.solo_scene(key), {}, request)

## The Chapters page's cards, as given to its picker (which shows free ones
## first): every chapter with its own Solo card, in registry order.
## With hard on: only chapters with hard runs, each locked until finished.
## A build that sells nothing lists the free chapters alone (Main._paid_content_hidden).
func entries(owned: bool, hard_on: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in ChapterRegistry.offered_keys():
		if own_solo_card(key): result.append(ChapterPicker.entry(key))
	if host._paid_content_hidden(): result = result.filter(func(item: Dictionary) -> bool: return not item.premium)
	for item: Dictionary in result: item.locked = item.premium and not owned
	return HardMode.picker_entries(result, host._chapter_marks()) if hard_on else result

## The Chapters page's pictures in its card order, which the thumbnail shelf
## loads ahead while Home is idle.
func thumbnail_paths() -> Array[String]:
	var paths: Array[String] = []
	for item: Dictionary in ChapterPicker.shown_order(entries(host._full_journey_access())):
		paths.append(ChapterThumbnailCatalog.path(str(item.key)))
	return paths

## The chapter the player most likely opens next: the first card the Chapters
## page shows, in its order, that is open to them and not yet finished solo;
## "" once every one is.
func next_solo_chapter() -> String:
	var marks: Dictionary = host._chapter_marks()
	for item: Dictionary in ChapterPicker.shown_order(entries(host._full_journey_access())):
		if not bool(item.locked) and not bool(marks.get(str(item.mark), {}).get("solo", false)): return str(item.key)
	return ""

## Every chapter the player can open from the Chapters page now, the one they
## most likely open next first (services/world_prewarm.gd).
func openable_chapters() -> Array[String]:
	var result: Array[String] = []
	var next := next_solo_chapter()
	if not next.is_empty(): result.append(next)
	for item: Dictionary in ChapterPicker.shown_order(entries(host._full_journey_access())):
		if not bool(item.locked) and not str(item.key) in result: result.append(str(item.key))
	return result

func refresh_marks() -> void:
	if host.mode != MODE_JOURNEY or not is_instance_valid(picker): return
	picker.refresh_marks(host._chapter_marks())

func show_earlier_islands() -> void:
	host.running=false
	host.mode=MODE_EARLIER_ISLANDS
	_grid_access_drawn = host._full_journey_access()
	var card: VBoxContainer = host._card(800)
	card.add_child(host._label("Earlier islands.",34,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_042C89C38B20,710))
	# A build that sells nothing lists the free islands alone, which fit without a scroll.
	var free_only: bool = host._paid_content_hidden()
	var list: VBoxContainer = host._scroll_list(card,not free_only)
	if not free_only: list.get_parent().custom_minimum_size.y = 340
	for index in range(host.levels.size()):
		var level: Dictionary=host.levels[index]
		if free_only and bool(level.get("premium",false)): continue
		var locked: bool = index>=3 and not host._full_journey_access()
		var complete: bool = host.saves.data.completed.has(level.id)
		var text := "%02d  %s%s%s" % [index+1,level.title,"  ·  Full Journey" if locked else "","  ✓" if complete else ""]
		var button: Button = host._button(text,func(): host._start_practice(index),false)
		button.custom_minimum_size.y=65
		button.mouse_filter=Control.MOUSE_FILTER_PASS
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size",18)
		if index>=3:
			var actions := VBoxContainer.new()
			actions.add_child(button)
			list.add_child(PaidThumbnails.row("legacy-"+str(level.id),actions,false))
		else:
			list.add_child(button)
	card.add_child(host._back_button("Back to chapters",show_journey,false))

## The store's customer information changed while a page is open
## (Main._customer_info_changed): the page is drawn again only when Full
## Journey access differs from what it was drawn with, after any tap in progress.
func access_changed() -> void:
	if host._full_journey_access() == _grid_access_drawn: return
	await TouchInput.redraw_when_released(host.overlay,func() -> bool: return host.mode in [MODE_JOURNEY,MODE_EARLIER_ISLANDS] and host._full_journey_access() != _grid_access_drawn,
		func() -> void:
			if host.mode==MODE_JOURNEY: show_journey()
			else: show_earlier_islands())
