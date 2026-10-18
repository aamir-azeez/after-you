extends Node
## Settings and the screens under it: the Settings list with its toggles and
## links, Graphics (quality and unlimited frame rate), and Licenses with each
## license's text. It also saves the photo prompt preference that a chapter
## room's photo card changes.
##
## Main hosts it as a child. The flow keeps no state: settings live in saves.
## Main keeps _apply_settings, which puts saved settings into Main's world, HUD,
## sound and presence; the flow calls it after each change, so a new setting
## with a runtime effect also needs a line there. The flow asks Main to go Home
## through home_requested, and reads Main only through this host contract (read
## at call time, so Main or a test can swap a service):
## - services: saves, _apply_settings, _play_store_enabled
## - screen: mode, running, overlay, _toast
## - links: notification_flow (show_settings), store_flow
##   (show_store_from_settings, show_tester_access), account_flow (show_account),
##   _open_safety, _open_whats_new_card
## - card kit: _card, _label, _paragraph, _button, _list_button, _back_button,
##   _scroll_list
## Main opens it through show_settings() (the Home cog, the settings_requested
## signals of StoreFlow, AccountFlow and NotificationFlow, Safety's return) and
## routes Android Back on Graphics, Licenses and a license's text.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const LocalSave = preload("res://services/local_save.gd")
const Licenses = preload("res://services/licenses.gd")
const CREAM := Color("eceddb")
## Main's modes on these screens.
const MODE_SETTINGS := "settings"
const MODE_GRAPHICS := "graphics_settings"
const MODE_LICENSES := "licenses"
const MODE_LICENSE_TEXT := "license_text"

signal home_requested

var host: Node

func _init(main: Node = null) -> void:
	host = main

func show_settings() -> void:
	host.running=false
	host.mode=MODE_SETTINGS
	var card: VBoxContainer = host._card()
	card.add_theme_constant_override("separation", 10)
	card.add_child(host._label(PlayerCopy.MAIN_0FEE4C6E23F4,34,CREAM,true))
	var settings_list: VBoxContainer = host._scroll_list(card)
	settings_list.get_parent().custom_minimum_size.y = clampf(host.overlay.size.y-220.0,180.0,420.0)
	var display_links := HBoxContainer.new()
	display_links.add_theme_constant_override("separation",10)
	settings_list.add_child(display_links)
	var display_entries: Array = [["Graphics",show_graphics_settings],["Notifications",host.notification_flow.show_settings]]
	# Subscribers reach Manage subscription and Restore here once Home hides the offer.
	if host._play_store_enabled(): display_entries.append(["Full Journey",host.store_flow.show_store_from_settings])
	for entry: Array in display_entries:
		var link: Button = host._list_button(entry[0],entry[1],false)
		link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		display_links.add_child(link)
	var defaults: Dictionary = LocalSave.defaults().settings
	for entry in [["assistance","Forgiving catches"],["reduced_motion","Reduce motion"],["left_handed",PlayerCopy.MAIN_A1E007823FF0],["sound","Sound"],["haptics","Gentle haptics"],["photo_prompts",PlayerCopy.MAIN_289D745F1246],["share_online_status","Share online status"],["skip_waits","Always skip waits"]]:
		var toggle := CheckButton.new()
		toggle.text=entry[1]
		toggle.mouse_filter = Control.MOUSE_FILTER_PASS
		toggle.button_pressed=bool(host.saves.data.settings.get(entry[0],defaults[entry[0]]))
		toggle.toggled.connect(func(value: bool):
			var next: Dictionary = host.saves.data.settings.duplicate(true)
			next[entry[0]] = value
			if not host.saves.update_values({"settings": next}):
				toggle.set_pressed_no_signal(bool(host.saves.data.settings.get(entry[0], defaults[entry[0]])))
				host._toast(PlayerCopy.MAIN_34B82590B663)
				return
			host._apply_settings())
		settings_list.add_child(toggle)
	var account_group: Array = [["Account & recovery",host.account_flow.show_account]]
	if PlatformSupport.tester_code_offered(): account_group.append(["Tester code",host.store_flow.show_tester_access])
	for group: Array in [account_group,[["Community & privacy",host._open_safety],[PlayerCopy.WHATS_NEW,func(): host._open_whats_new_card()],["Licenses",show_licenses]]]:
		var links := HBoxContainer.new()
		links.add_theme_constant_override("separation",10)
		settings_list.add_child(links)
		for entry: Array in group:
			var link: Button = host._button(entry[0],entry[1],false)
			link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			links.add_child(link)
	card.add_child(host._back_button("Done",home_requested.emit,false))

func show_graphics_settings() -> void:
	host.running = false
	host.mode = MODE_GRAPHICS
	var card: VBoxContainer = host._card()
	card.add_child(host._label("Graphics",34,CREAM,true))
	var selected := GraphicsPolicy.normalize(host.saves.data.settings.get("graphics_quality"))
	var group := ButtonGroup.new()
	for quality: String in GraphicsPolicy.QUALITIES:
		var option: Button = host._button(quality.capitalize(),func(): _set_graphics_quality(quality),false)
		option.toggle_mode = true
		option.button_group = group
		option.button_pressed = quality == selected
		option.set_meta("graphics_quality",quality)
		card.add_child(option)
	var unlimited := CheckButton.new()
	unlimited.name = "UnlimitedFrameRate"
	unlimited.text = "Unlimited frame rate"
	unlimited.mouse_filter = Control.MOUSE_FILTER_PASS
	unlimited.button_pressed = GraphicsPolicy.unlimited_frame_rate(host.saves.data.settings)
	unlimited.toggled.connect(func(value: bool): _set_unlimited_frame_rate(value, unlimited))
	card.add_child(unlimited)
	card.add_child(host._paragraph("Plays at your screen's full refresh rate. Uses more battery and can warm your phone.",500))
	card.add_child(host._back_button("Back",show_settings,false))

func _set_graphics_quality(quality: String) -> void:
	if host.mode != MODE_GRAPHICS or quality not in GraphicsPolicy.QUALITIES: return
	var next: Dictionary = host.saves.data.settings.duplicate(true)
	next.graphics_quality = quality
	if not host.saves.update_values({"settings":next}):
		host._toast(PlayerCopy.MAIN_34B82590B663)
		show_graphics_settings()
		return
	host._apply_settings()

func _set_unlimited_frame_rate(value: bool, toggle: CheckButton) -> void:
	if host.mode != MODE_GRAPHICS: return
	var next: Dictionary = host.saves.data.settings.duplicate(true)
	next.unlimited_frame_rate = value
	if not host.saves.update_values({"settings":next}):
		toggle.set_pressed_no_signal(GraphicsPolicy.unlimited_frame_rate(host.saves.data.settings))
		host._toast(PlayerCopy.MAIN_34B82590B663)
		return
	host._apply_settings()

## The photo card's Don't ask again (a chapter room's save_photo_prompt_preference).
func save_photo_prompt_preference(enabled: bool) -> bool:
	var next: Dictionary = host.saves.data.settings.duplicate(true)
	next.photo_prompts = enabled
	return host.saves.update_values({"settings": next})

func show_licenses() -> void:
	host.running=false
	host.mode=MODE_LICENSES
	var card: VBoxContainer = host._card(680)
	card.add_child(host._label("Made with care.",34,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_0A022EF54291,600))
	var list: VBoxContainer = host._scroll_list(card)
	for entry: Dictionary in Licenses.entries():
		list.add_child(host._list_button(str(entry.title),func(): show_license(entry),false))
	card.add_child(host._back_button("Back to settings",show_settings,false))

func show_license(entry: Dictionary) -> void:
	host.mode=MODE_LICENSE_TEXT
	var card: VBoxContainer = host._card(920)
	card.add_child(host._label(str(entry.title),30,CREAM,true))
	var text := RichTextLabel.new()
	text.name="LicenseText"
	text.bbcode_enabled=false
	text.selection_enabled=true
	text.scroll_active=true
	text.custom_minimum_size=Vector2(840,390)
	text.add_theme_font_size_override("normal_font_size",18)
	text.add_theme_color_override("default_color",CREAM)
	text.text=str(entry.text)
	card.add_child(text)
	card.add_child(host._back_button("Back to licenses",show_licenses,false))
