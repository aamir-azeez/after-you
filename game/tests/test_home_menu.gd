extends SceneTree
## Home's menu component (presentation/home_menu.gd) and the shared colour tokens
## (presentation/ui_tokens.gd): layout A at phone sizes, under cutout insets and
## with the What's new tip, the Play button's icon slot, and nothing per frame;
## and the Wardrobe row, shown only while the server has the wardrobe on, with
## the player's own pip as a still picture for its icon, beside the Pollen chip;
## and Main's Pollen routes: Pollen from play opened from the Pollen store goes
## back to the store, or where the store's own Back goes when it cannot open.
const FriendPlayIcon = preload("res://presentation/friend_play_icon.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const HomeMenu = preload("res://presentation/home_menu.gd")
const HomeStage = preload("res://presentation/home_stage.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const EmptyState = preload("res://presentation/empty_state.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const WardrobeFlow = preload("res://presentation/wardrobe_flow.gd")
const PollenStoreFlow = preload("res://presentation/pollen_store_flow.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")

## Stands in for the Wardrobe: whether it is on, and where it was opened from.
class WardrobeStub:
	extends WardrobeFlow
	var on := false
	var opened: Array[String] = []
	func available() -> bool: return on
	func show_wardrobe(from: String = "settings") -> void: opened.append(from)

## Stands in for the Pollen store: whether it can open, and how often it did.
class StoreStub:
	extends PollenStoreFlow
	var on := true
	var opened := 0
	func available() -> bool: return on
	func show_store() -> void: opened += 1

## 1560x720 is a 2340x1080 phone (and a 1560x720 one); 1600x720 is what an
## 800x360 window gets from the canvas_items/expand stretch; 1280x960 a tablet.
const SIZES := [Vector2i(1560, 720), Vector2i(1600, 720), Vector2i(1280, 720), Vector2i(1280, 960)]
## Cutout insets (left, top, right, bottom) in viewport units.
const INSETS := [Vector4.ZERO, Vector4(96, 0, 0, 0), Vector4(0, 0, 96, 0), Vector4(64, 18, 48, 24)]

## Stands in for a drawn icon that follows the Play button's hover and press.
class FollowIcon:
	extends Control
	var followed: BaseButton
	func attach_to(button: BaseButton) -> void:
		followed = button

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_tokens()
	var path := "user://home-menu-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var viewport := SubViewport.new()
	viewport.size = SIZES[0]
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Storage.new(path)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await _frames()
	for size: Vector2i in SIZES:
		viewport.size = size
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		for insets: Vector4 in INSETS:
			var safe := Rect2(insets.x, insets.y, size.x - insets.x - insets.z, size.y - insets.y - insets.w)
			app._apply_safe_area(safe)
			for unseen: bool in [false, true]:
				app._whats_new_unseen = unseen
				app._show_home()
				await _frames()
				_check_layout(app, screen, safe, unseen, "%s insets %s tip %s" % [size, insets, unseen])
		app._apply_safe_area(screen)
	app._whats_new_unseen = false
	app._show_home()
	await _frames()
	await _test_tip_clears(app)
	await _test_icon_slot(app)
	await _test_actions(app)
	await _test_wardrobe_row(app)
	await _test_pollen_routes(app)
	viewport.free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU HOME MENU: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _frames() -> void:
	for frame in range(4): await process_frame

## One name per colour: every alias reads the shared token.
func _test_tokens() -> void:
	_check(ControlTheme.INK == UiTokens.INK and ControlTheme.CREAM == UiTokens.CREAM and ControlTheme.CHOICE_DISABLED == UiTokens.DISABLED_TEXT, "Control theme colours are the shared tokens")
	_check(Main.INK == UiTokens.INK and Main.CREAM == UiTokens.CREAM and Main.MINT == UiTokens.MINT and Main.MUTED == UiTokens.MUTED, "Main's colours are the shared tokens")
	_check(EmptyState.CREAM == UiTokens.CREAM and EmptyState.MUTED == UiTokens.SOFT, "Empty state colours are the shared tokens")
	_check(HomeStage.PAGE_FILL == UiTokens.PAGE_FILL and HomeStage.PAGE_BORDER == UiTokens.PAGE_BORDER and HomeStage.KeepsakeCard.TOGETHER_LIT == UiTokens.TOGETHER, "Home stage colours are the shared tokens")
	# The values players have always seen.
	_check(UiTokens.INK == Color("193d39") and UiTokens.CREAM == Color("eceddb") and UiTokens.MINT == Color("a6d9c4") and UiTokens.MUTED == Color("9dbeb4") and UiTokens.SOFT == Color("afc6be") and UiTokens.SECONDARY == Color("254b45") and UiTokens.SECONDARY_BORDER == Color("54766a") and UiTokens.SELECTED == Color("3a6b5f"), "Token values keep the existing palette")
	_check(UiTokens.HOME_STAGE_LEFT <= UiTokens.HOME_PANEL_WIDTH, "The camera stage starts at or under the panel's edge")

func _menu(app: Node) -> Control:
	return app.overlay.find_child("HomeMenu", true, false) as Control

func _check_layout(app: Node, screen: Rect2, safe: Rect2, unseen: bool, context: String) -> void:
	var menu := _menu(app)
	_check(menu != null and menu.get_script() == HomeMenu and menu.get_parent() == app.overlay, "Home's menu is one component in the overlay: " + context)
	if menu == null: return
	_check(app.overlay.get_child(0) == app.home_stage_view, "The island stage stays under the menu: " + context)
	var offer: Button = app.overlay.get_node_or_null("HomeFullJourney")
	_check(offer != null and offer == menu.journey_offer, "Full Journey stays a direct child of the overlay: " + context)
	var order: Array[Button] = [menu.play_button, menu.solo_button, menu.friends_button, menu.replays_button, menu.invite_button, menu.whats_new_button]
	var names := ["HomePlay", "HomeSolo", "HomeFriends", "HomeReplays", "HomeInvite", "HomeWhatsNew"]
	# The Wardrobe row joins the column under Replays while the server has the wardrobe on.
	if menu.wardrobe_button.visible:
		order.insert(4, menu.wardrobe_button)
		names.insert(4, "HomeWardrobe")
	for index in range(order.size()):
		_check(order[index] != null and order[index].name == names[index] and order[index].is_visible_in_tree(), "Home shows %s: %s" % [names[index], context])
	_check(menu.play_button.text == "Play with your friend" and menu.solo_button.text == "Play Solo" and menu.friends_button.text == "Friends" and menu.replays_button.text == "Replays" and menu.invite_button.text == PlayerCopy.HOME_INVITE and menu.whats_new_button.text == PlayerCopy.WHATS_NEW, "Labels are the existing words: " + context)
	_check(menu.settings_button.name == "HomeSettings" and menu.settings_button.text.is_empty() and menu.settings_button.accessibility_name == "Settings", "Settings is the labelled cog: " + context)
	var panel_end := safe.position.x + UiTokens.HOME_PANEL_WIDTH
	var targets: Array[Button] = order.duplicate()
	targets.append(menu.settings_button)
	for index in range(targets.size()):
		var rect := targets[index].get_global_rect()
		_check(safe.encloses(rect) and rect.end.x <= panel_end and rect.position.x >= safe.position.x, "%s sits in the panel and the safe area: %s %s" % [targets[index].name, rect, context])
		_check(rect.size.y >= 48.0 and rect.size.x >= 48.0, "%s keeps a full touch target: %s" % [targets[index].name, context])
		for other in range(index + 1, targets.size()):
			_check(not rect.intersects(targets[other].get_global_rect()), "%s and %s do not overlap: %s" % [targets[index].name, targets[other].name, context])
	for index in range(order.size() - 1):
		_check(order[index].get_global_rect().end.y <= order[index + 1].get_global_rect().position.y + 0.5, "%s comes above %s: %s" % [order[index].name, order[index + 1].name, context])
	var cog: Rect2 = menu.settings_button.get_global_rect()
	var pill: Rect2 = menu.whats_new_button.get_global_rect()
	_check(absf(cog.get_center().y - pill.get_center().y) <= 1.0 and cog.position.x > pill.end.x, "What's new and the cog share the bottom row, the cog at its right: " + context)
	_check(absf(cog.end.x - (panel_end - HomeMenu.RIGHT)) <= 1.0 and absf(menu.invite_button.get_global_rect().end.x - cog.end.x) <= 1.0, "The column and the bottom row end together: " + context)
	_check(safe.end.y - cog.end.y <= 40.0, "The bottom row sits at the foot of the panel: " + context)
	# Rows: icon, label and a chevron; Play is the one cream pill.
	for row: Button in [menu.solo_button, menu.friends_button, menu.replays_button, menu.invite_button]:
		var chevron := row.get_node_or_null("Chevron") as TextureRect
		_check(row.icon != null and chevron != null and chevron.mouse_filter == Control.MOUSE_FILTER_IGNORE and row.get_global_rect().encloses(chevron.get_global_rect()), "%s has its icon and chevron: %s" % [row.name, context])
		_check((row.get_theme_stylebox("hover") as StyleBoxFlat).bg_color.a < 0.2 and row.get_theme_color("font_hover_color") == UiTokens.CREAM, "%s keeps cream text on a faint hover: %s" % [row.name, context])
	_check((menu.play_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == UiTokens.CREAM, "Play with your friend is cream: " + context)
	_check((menu.invite_button.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left > 0 and (menu.invite_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a == 0.0, "Invite is the outlined pill: " + context)
	# Wordmark and line over the column; no eyebrow.
	var wordmark := menu.find_child("HomeWordmark", true, false) as Label
	var subtitle := menu.find_child("HomeSubtitle", true, false) as Label
	_check(wordmark != null and wordmark.text == "After\nYou" and subtitle != null and subtitle.text == PlayerCopy.MAIN_6A7ECC3FD1B9, "The wordmark and its line head the panel: " + context)
	if wordmark != null and subtitle != null:
		_check(safe.encloses(wordmark.get_global_rect()) and (wordmark.get_parent() as Control).get_global_rect().end.y <= subtitle.get_global_rect().position.y + 1.0 and subtitle.get_global_rect().end.y <= menu.play_button.get_global_rect().position.y, "Wordmark, line, then Play, top to bottom: " + context)
		_check(subtitle.get_line_count() == 2 and subtitle.get_visible_line_count() == 2, "The line reads as two lines: " + context)
	for label: Label in app.overlay.find_children("*", "Label", true, false):
		_check(not label.text.contains("TWO DIFFERENT TIMES"), "The eyebrow is gone: " + context)
	# The panel colours the screen from its left edge, under a cutout too.
	var backdrop := menu.find_child("HomePanel", true, false) as Control
	_check(backdrop != null and backdrop.get_global_rect().is_equal_approx(screen), "The panel's backdrop covers the screen to its edges: " + context)
	_check(not (backdrop is PanelContainer) and backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The backdrop is drawn, never a box or a tap target: " + context)
	# The What's new tip sits above its button, on screen, clear of Invite.
	var tip := menu.whats_new_button.get_node_or_null("WhatsNewTip") as Control
	_check((tip != null) == unseen, "The tip shows only while the notes are unseen: " + context)
	if tip != null:
		var tip_rect := tip.get_global_rect()
		_check(safe.encloses(tip_rect) and tip_rect.end.x <= panel_end and not tip_rect.intersects(menu.invite_button.get_global_rect()) and not tip_rect.intersects(cog), "The tip sits on screen in the panel, clear of Invite and the cog: %s %s" % [tip_rect, context])
		# Beside What's new it needs no room of its own, so the column stays put.
		_check(tip_rect.position.x >= pill.end.x and absf(tip_rect.get_center().y - pill.get_center().y) <= 1.0 and not menu.find_child("HomeTipRoom", true, false).visible, "The tip sits beside What's new, level with it: " + context)
		var dot := menu.whats_new_button.get_node_or_null("WhatsNewDot") as Control
		_check(dot != null and dot.get_global_rect().get_center().x < pill.position.x + 48.0, "The dot sits on the gift icon: " + context)
		_check(tip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The tip never takes a tap: " + context)
	# Over the island: Explore at the top left, Full Journey at the top right.
	var stage: Control = app.home_stage_view
	var explore: Button = stage._explore_button
	var explore_rect := explore.get_global_rect()
	_check(explore.icon != null and explore_rect.size.y >= 48.0 and explore_rect.position.x >= panel_end and safe.encloses(explore_rect), "Explore has its compass, right of the panel: " + context)
	if offer.visible:
		var offer_rect := offer.get_global_rect()
		_check(absf(offer_rect.end.x - (safe.end.x - 32.0)) <= 1.0 and absf(offer_rect.position.y - (safe.position.y + 32.0)) <= 1.0 and offer_rect.size.y >= 48.0 and offer.icon != null, "Full Journey sits top right with its arrow: " + context)
		_check(not offer_rect.intersects(explore_rect), "Full Journey keeps clear of Explore: " + context)
	# Every keepsake status reads on one line, with room to spare for a phone's
	# finer text scale, so the box stays low over the island.
	var status: Label = stage._keepsake_status
	var status_font := status.get_theme_font("font")
	for line: String in stage._keepsake_layer.every_line():
		_check(status_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, HomeStage.STATUS_SIZE).x * 1.03 <= stage._keepsake_controls.custom_minimum_size.x, "The keepsake status fits one line: %s %s (%.0f in %.0f)" % [line, context, status_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, HomeStage.STATUS_SIZE).x, stage._keepsake_controls.custom_minimum_size.x])
	_check(not menu.is_processing() and not menu.is_physics_processing(), "The menu does no per-frame work: " + context)
	_check(not stage._allowed(menu.play_button.get_global_rect().get_center()) and not stage._allowed(Vector2(panel_end - 4.0, safe.get_center().y)), "Presses on the panel never start a camera gesture: " + context)

## The Play button's slot takes a drawn icon later; the label moves for it.
func _test_icon_slot(app: Node) -> void:
	var menu := _menu(app)
	var play: Button = menu.play_button
	var slot := play.get_node_or_null("HomePlayIcon") as Control
	_check(slot != null and slot == menu.play_icon_slot and menu.has_play_icon() and slot.get_child_count() == 1 and slot.get_child(0).get_script() == FriendPlayIcon, "Home puts the friend icon in Play's HomePlayIcon slot")
	# The rest checks the slot itself, starting empty.
	menu.set_play_icon(null)
	await _frames()
	_check(slot != null and slot.mouse_filter == Control.MOUSE_FILTER_IGNORE and play.get_global_rect().encloses(slot.get_global_rect()) and slot.size == HomeMenu.PLAY_ICON_SIZE, "The slot sits inside the pill and never takes a tap")
	var empty_left := play.get_theme_stylebox("normal").content_margin_left
	_check(is_equal_approx(empty_left, HomeMenu.PLAY_TEXT_INSET), "With no icon the label starts near the pill's edge")
	var icon := ColorRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.set_play_icon(icon)
	await _frames()
	var left := HomeMenu.PLAY_ICON_LEFT + HomeMenu.PLAY_ICON_SIZE.x + HomeMenu.PLAY_ICON_GAP
	_check(menu.has_play_icon() and icon.get_parent() == slot and icon.get_global_rect().is_equal_approx(slot.get_global_rect()) and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "A dropped icon fills the slot and passes presses to Play")
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_check(is_equal_approx(play.get_theme_stylebox(state).content_margin_left, left), "With an icon the label starts after it (%s)" % state)
	var font := play.get_theme_font("font")
	var words := font.get_string_size(play.text, HORIZONTAL_ALIGNMENT_LEFT, -1, play.get_theme_font_size("font_size")).x
	_check(left + words + play.get_theme_stylebox("normal").content_margin_right <= play.size.x, "The label still fits beside the icon")
	play.text = PlayerCopy.HUB_OPENING
	await _frames()
	_check(icon.get_parent() == slot and play.get_global_rect().encloses(icon.get_global_rect()), "The icon stays while Play reads Opening…")
	play.text = "Play with your friend"
	menu.set_play_icon(null)
	await _frames()
	_check(not menu.has_play_icon() and slot.get_child_count() == 0 and is_equal_approx(play.get_theme_stylebox("normal").content_margin_left, HomeMenu.PLAY_TEXT_INSET), "Emptying the slot puts the label back")
	# An icon that follows its button is handed the Play button.
	var follower := FollowIcon.new()
	menu.set_play_icon(follower)
	await _frames()
	_check(follower.followed == play and follower.get_parent() == slot, "set_play_icon hands a following icon the Play button")
	menu.set_play_icon(null)
	await _frames()
	# An icon added straight into the slot is picked up too.
	var direct := Control.new()
	slot.add_child(direct)
	await _frames()
	_check(is_equal_approx(play.get_theme_stylebox("normal").content_margin_left, left), "An icon added to the slot directly moves the label too")
	menu.set_play_icon(null)
	await _frames()

## Each action still reaches Main's own handler.
func _test_actions(app: Node) -> void:
	var menu := _menu(app)
	var calls: Array[String] = []
	var probe := HomeMenu.new()
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.overlay.add_child(holder)
	holder.add_child(probe)
	var actions := {}
	for key: String in ["solo", "friends", "replays", "invite", "whats_new", "settings", "full_journey"]:
		actions[key] = func() -> void: calls.append(key)
	actions["play"] = func(button: Button) -> void: calls.append("play:" + str(button.name))
	probe.build(actions, HomeStage.heading_font())
	for button: Button in [probe.play_button, probe.solo_button, probe.friends_button, probe.replays_button, probe.invite_button, probe.whats_new_button, probe.settings_button, probe.journey_offer]:
		button.pressed.emit()
	_check(calls == ["play:HomePlay", "solo", "friends", "replays", "invite", "whats_new", "settings", "full_journey"], "Every control calls its own action once: %s" % [calls])
	_check(probe.journey_offer.get_parent() == holder, "Full Journey joins the menu's own parent")
	_check(probe.header_actions() == [probe.journey_offer, probe.pollen_slot, probe.settings_button, probe.whats_new_button], "The stage leaves Full Journey, the Pollen chip, Settings and What's new to their own input")
	_check(probe.pollen_slot.get_parent() == holder and not probe.pollen_slot.visible, "The Pollen chip's slot joins the menu's parent, empty and hidden until a chip comes")
	holder.free()
	_check(is_instance_valid(menu), "Home's own menu is untouched by the probe")

## The Wardrobe row: hidden while the server has the wardrobe off, shown (with
## its still pip, inside the panel) once it is on, opening the Wardrobe from
## Home; Home free for a card decides whether the pip's tap may open it.
func _test_wardrobe_row(app: Node) -> void:
	var real: Node = app.wardrobe_flow
	var stub := WardrobeStub.new(app)
	app.wardrobe_flow = stub
	app._show_home()
	await _frames()
	var menu := _menu(app)
	_check(not menu.wardrobe_button.visible, "The Wardrobe row is hidden while the server has the wardrobe off")
	app._open_wardrobe_from_home()
	_check(stub.opened.is_empty() and not app._open_wardrobe_from_pip(), "Nothing opens the Wardrobe from Home while it is off")
	stub.on = true
	# Every size, cutout and tip again with the row showing: it fits, stays in the panel and the safe area.
	var viewport := app.get_parent() as SubViewport
	var first := viewport.size
	for size: Vector2i in SIZES:
		viewport.size = size
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		for insets: Vector4 in INSETS:
			var safe := Rect2(insets.x, insets.y, size.x - insets.x - insets.z, size.y - insets.y - insets.w)
			app._apply_safe_area(safe)
			for unseen: bool in [false, true]:
				app._whats_new_unseen = unseen
				app._show_home()
				await _frames()
				_check(_menu(app).wardrobe_button.visible, "The Wardrobe row shows at %s insets %s" % [size, insets])
				_check_layout(app, screen, safe, unseen, "with the Wardrobe row, %s insets %s tip %s" % [size, insets, unseen])
		app._apply_safe_area(screen)
	viewport.size = first
	app._whats_new_unseen = false
	app._show_home()
	await _frames()
	menu = _menu(app)
	var pip: Control = menu.wardrobe_button.find_child("HomeWardrobePip", true, false)
	_check(menu.wardrobe_button.visible and pip != null and pip.still and pip.own, "Once it is on the row shows, with the player's own pip as a still picture")
	_check(menu.wardrobe_button.get_parent() == menu.replays_button.get_parent() and menu.wardrobe_button.get_index() == menu.replays_button.get_index() + 1, "It sits under Replays in the same column")
	var column := menu.find_child("HomeMenuMargin", true, false) as Control
	_check(column.get_combined_minimum_size().y <= menu.size.y + 0.5, "The column still fits the screen with the row")
	_check(Rect2(Vector2.ZERO, Vector2(UiTokens.HOME_PANEL_WIDTH, menu.size.y)).encloses(Rect2(menu.wardrobe_button.global_position - menu.global_position, menu.wardrobe_button.size)), "The row stays inside the panel")
	# The Pollen chip and the Wardrobe row show together, each in its own place.
	menu.set_pollen_chip(PollenChip.make(24000, true))
	await _frames()
	var chip_rect: Rect2 = (menu.pollen_slot.get_child(0) as Control).get_global_rect()
	var journey: Rect2 = menu.journey_offer.get_global_rect()
	_check(menu.wardrobe_button.visible and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(chip_rect) and (not menu.journey_offer.visible or chip_rect.end.x <= journey.position.x) and not chip_rect.intersects(menu.wardrobe_button.get_global_rect()) and chip_rect.position.x >= UiTokens.HOME_PANEL_WIDTH, "The Pollen chip sits left of Full Journey, clear of the panel and its Wardrobe row: %s" % chip_rect)
	menu.set_pollen_chip(null)
	menu.wardrobe_button.pressed.emit()
	_check(stub.opened == ["home"], "The row opens the Wardrobe from Home: " + str(stub.opened))
	_check(app._open_wardrobe_from_pip() and stub.opened == ["home", "home"], "A tap on your pip opens it while Home is free")
	var modal := preload("res://presentation/in_game_modal.gd").open(app.ui, "ProbeCard", "Probe")
	await _frames()
	_check(not app._open_wardrobe_from_pip() and stub.opened.size() == 2, "Never over a card: the pip's tap is left to the greeting")
	app._open_wardrobe_from_home()
	_check(stub.opened.size() == 2, "The row never opens it over a card either")
	modal.close()
	await _frames()
	stub.on = false
	app._refresh_home_wardrobe()
	_check(not menu.wardrobe_button.visible, "Off again: the row hides")
	app.wardrobe_flow = real
	stub.free()
	app._show_home()
	await _frames()

## Main's Pollen routes (main.gd _host_pollen_play_flow, _back_to_wardrobe):
## Back from Pollen from play opened from the Pollen store goes back to the
## store; when the store cannot open now, where the store's Back goes (the
## Wardrobe as it opened, or Home while the Wardrobe is off).
func _test_pollen_routes(app: Node) -> void:
	var real_store: Node = app.pollen_store_flow
	var real_wardrobe: Node = app.wardrobe_flow
	var store := StoreStub.new(app)
	var wardrobe := WardrobeStub.new(app)
	app.pollen_store_flow = store
	app.wardrobe_flow = wardrobe
	var play: Node = app.pollen_play_flow
	play.return_to = "store"
	play.back_requested.emit()
	_check(store.opened == 1 and wardrobe.opened.is_empty(), "Back from Pollen from play opened from the store goes back to the store")
	store.on = false
	wardrobe.on = true
	wardrobe.return_to = "home"
	play.back_requested.emit()
	_check(store.opened == 1 and wardrobe.opened == ["home"], "With the store shut now, Back goes to the Wardrobe as it opened: " + str(wardrobe.opened))
	wardrobe.on = false
	play.back_requested.emit()
	await _frames()
	_check(app.mode == "home" and _menu(app) != null, "And Home while the Wardrobe is off too")
	_check(app.show_pollen_from_play() == play.is_open(), "The store learns whether Pollen from play opened")
	play.return_to = "home"
	app.pollen_store_flow = real_store
	app.wardrobe_flow = real_wardrobe
	store.free()
	wardrobe.free()
	app._show_home()
	await _frames()

## Opening the card takes the dot and tip away, and the bottom row's rule returns.
func _test_tip_clears(app: Node) -> void:
	app._whats_new_unseen = true
	app._show_home()
	await _frames()
	var menu := _menu(app)
	var pill: Button = menu.whats_new_button
	var rule := menu.find_child("HomeBottomRule", true, false) as Control
	_check(pill.get_node_or_null("WhatsNewTip") != null and not rule.visible, "The tip beside What's new covers the bottom row's rule")
	app._open_whats_new_from_home()
	await _frames()
	_check(pill.get_node_or_null("WhatsNewTip") == null and pill.get_node_or_null("WhatsNewDot") == null and rule.visible and not menu.find_child("HomeTipRoom", true, false).visible, "Opening the card clears the marks and brings the rule back")
	if is_instance_valid(app._whats_new_card): app._whats_new_card.close(false)
	await _frames()
	app._whats_new_unseen = false
	app._show_home()
	await _frames()
