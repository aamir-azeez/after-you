extends Node
## The Full Journey store, paywall, purchase, restore and tester-code flow.
##
## Main hosts it as a child. The flow keeps its own state and screens, asks Main
## to navigate through the signals below, and reads Main only through this host
## contract (read at call time, so Main or a test can swap a service):
## - services: purchases, tester_access, config, api
## - screen: mode, running, store_view_generation, application_backgrounded,
##   identity_restart_required, overlay
## - card kit: _card, _label, _paragraph, _button, _style, _screen_shell,
##   _replay_preview_thumb, _toast
## - identity and access rules: _ensure_identity, _relay_identity, _tester_context,
##   _tester_checks_enabled, _tester_active, _load_cached_tester,
##   _hosting_lock_reason, _store_identity_settled, _purchase_session_identity
##
## Cancel rule: every host._card() and host._screen_shell() clears the overlay,
## which bumps host.store_view_generation. Each await here keeps the generation
## it started with and stops if it changed, so a late store or tester answer
## never draws over a screen the player has since opened.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PaidThumbnails = preload("res://presentation/paid_level_thumbnails.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const Purchases = preload("res://services/purchases.gd")
const Save = preload("res://services/local_save.gd")
const CREAM := Color("eceddb")
const GOLD := Color("f1c48a")
## Main's mode while a store card is up, including the locked-hosting page.
const MODE_PAYWALL := "paywall"
const MODE_TESTER_ACCESS := "tester_access"

signal settings_requested
signal chapters_requested
signal rooms_requested
## Enter the Lighthouse after a purchase; Main opens what the chapter card opens.
signal lighthouse_requested
signal google_play_requested

var host: Node
## The current store offering: {"offering_id", "packages"} with the monthly and yearly packages.
var purchase_offer: Dictionary={}
## Store screens opened from Settings return there.
var store_from_settings := false
var tester_action_pending := false
var tester_store_manual := false
var store_configured := false
var restore_requested := false
var store_action_pending := false
var store_action_request := ""
var store_configure_request := ""
var store_read_request := ""
var store_read_views: Dictionary = {}
var store_owner := ""
var store_restore_view := -1

func _init(main: Node = null) -> void:
	host = main

func show_paywall(manual_store: bool = false) -> void:
	host.running=false
	host.mode=MODE_PAYWALL
	tester_store_manual = manual_store
	if not manual_store: store_from_settings = false
	if host._tester_checks_enabled():
		var loading: VBoxContainer = host._card(680)
		loading.add_child(host._label("Checking saved access…",30,CREAM,true))
		_add_store_back(loading)
		var view: int = host.store_view_generation
		await host._load_cached_tester()
		if host.mode != MODE_PAYWALL or view != host.store_view_generation: return
	if host._tester_active() and not manual_store:
		_show_tester_active()
		return
	var card := _full_journey_card()
	if not _play_store_enabled():
		add_store_elsewhere(card)
		_add_store_back(card)
		return
	var key := str(host.config.get("revenuecat_public_key",""))
	if key.is_empty() or not host.purchases.is_available():
		card.add_child(host._paragraph(PlayerCopy.MAIN_FC1F8BAE026C,600))
	else:
		card.add_child(host._paragraph(PlayerCopy.MAIN_DD823B20A782,600))
		_load_store.call_deferred()
	if not key.is_empty() and host.purchases.is_available():
		card.add_child(host._button("Retry store",func(): _load_store(true),false))
		card.add_child(host._button("Restore purchases",restore_purchases,false))
	_add_store_back(card)

func _add_store_back(card: VBoxContainer) -> void:
	var view: int = host.store_view_generation
	var label := "Back to settings" if store_from_settings else "Back to chapters"
	card.add_child(host._back_button(label,func():
		if host.mode == MODE_PAYWALL and view == host.store_view_generation: leave_store(),false))

func leave_store() -> void:
	if host.mode != MODE_PAYWALL: return
	if store_from_settings:
		store_from_settings = false
		settings_requested.emit()
	else: chapters_requested.emit()

func _play_store_enabled() -> bool:
	return Purchases.store_enabled(host.config)

## A build without a store points to the Google Play listing and to tester access. An iOS
## App Store build shows neither: no other store, and no code that unlocks paid content.
func add_store_elsewhere(card: VBoxContainer) -> void:
	if PlatformSupport.play_listing_offered(): card.add_child(host._button("Get it on Google Play",func(): google_play_requested.emit()))
	if PlatformSupport.tester_code_offered(): card.add_child(host._button("Tester code",show_tester_access,false))

## Every store state shares this card: the paid chapters on the left, and on
## the right the title and what the subscription pays for. Callers add the
## state's own actions to the returned column.
func _full_journey_card() -> VBoxContainer:
	var card: VBoxContainer = host._card(1120)
	var columns := HBoxContainer.new()
	columns.name = "FullJourneyCard"
	columns.add_theme_constant_override("separation",24)
	card.add_child(columns)
	var gallery := PaidThumbnails.gallery(clampf(host.overlay.size.y-160.0,300.0,560.0))
	gallery.custom_minimum_size.x = 470
	columns.add_child(gallery)
	var column := VBoxContainer.new()
	column.name = "FullJourneyDetails"
	column.add_theme_constant_override("separation",14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(column)
	column.add_child(host._label("Full Journey",32,CREAM,true))
	column.add_child(host._paragraph(PlayerCopy.SUBSCRIPTION_PURPOSE,0))
	column.add_child(host._paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,0))
	if Save.equal(host.config.get("purchase_mode"), "test_store"):
		column.add_child(host._paragraph(PlayerCopy.MAIN_38EAC523F08C,0))
	return column

## The one subscription offer used by the store card and locked hosting: each
## store package with its store price and period, the renewal terms, Restore
## and the privacy policy. Prices always come from the store.
func _add_subscription_choices(card: VBoxContainer) -> void:
	var choices := HBoxContainer.new()
	choices.name = "SubscriptionChoices"
	choices.add_theme_constant_override("separation",12)
	card.add_child(choices)
	for package: Dictionary in purchase_offer.get("packages",[]):
		var option: Button = host._button(_subscription_price_text(package),_buy_full_journey.bind(package))
		option.name = "Subscribe_"+str(package.get("period",""))
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_child(option)
	var terms: Label = host._paragraph(_subscription_terms(),0)
	terms.name = "SubscriptionTerms"
	terms.add_theme_font_size_override("font_size",16)
	card.add_child(terms)
	_add_store_links(card)

func _subscription_terms() -> String:
	match host.config.get("purchase_mode"):
		"test_store": return PlayerCopy.SUBSCRIPTION_TERMS_TEST
		"app_store": return PlayerCopy.SUBSCRIPTION_TERMS_APP_STORE
	return PlayerCopy.SUBSCRIPTION_TERMS_PLAY

static func _subscription_price_text(package: Dictionary) -> String:
	return (PlayerCopy.SUBSCRIPTION_YEARLY if package.get("period") == "year" else PlayerCopy.SUBSCRIPTION_MONTHLY) % str(package.get("price",""))

## Restore, Manage subscription for a subscriber, the privacy policy and, on iOS, the
## Terms of Use that App Review asks every subscription screen to link.
func _add_store_links(card: VBoxContainer) -> void:
	var links := HBoxContainer.new()
	links.name = "StoreLinks"
	links.add_theme_constant_override("separation",12)
	card.add_child(links)
	var buttons: Array[Button] = [host._button("Restore purchases",restore_purchases,false)]
	if _manage_subscription_available():
		buttons.append(host._button(PlayerCopy.SUBSCRIPTION_MANAGE,_open_subscription_management,false))
	if not _privacy_url().is_empty():
		buttons.append(host._button(PlayerCopy.SUBSCRIPTION_PRIVACY,func(): OS.shell_open(_privacy_url()),false))
	if PlatformSupport.is_ios():
		var terms: Button = host._button(PlayerCopy.SUBSCRIPTION_TERMS_OF_USE,func(): OS.shell_open(PlatformSupport.APPLE_TERMS_URL),false)
		terms.name = "TermsOfUse"
		buttons.append(terms)
	for button: Button in buttons:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		links.add_child(button)

func _manage_subscription_available() -> bool:
	return host.config.get("purchase_mode") in ["google_play","app_store"] and not Purchases.subscriptions_url(host.config).is_empty() and host.purchases.has_method("has_subscription") and host.purchases.has_subscription()

func _open_subscription_management() -> void:
	OS.shell_open(Purchases.subscriptions_url(host.config))

func _privacy_url() -> String:
	var base := str(host.config.get("api_base_url","")).trim_suffix("/")
	return base+"/privacy" if base.begins_with("https://") else ""

func show_store_from_settings() -> void:
	store_from_settings = true
	show_paywall(true)

func show_hosting_locked(chapter_key: String) -> void:
	host.running = false
	host.mode = MODE_PAYWALL
	var descriptor := ChapterRegistry.descriptor(chapter_key)
	var test_store := str(host.config.get("purchase_mode","")) == "test_store"
	var shell: Dictionary = host._screen_shell("Host a room",func(): rooms_requested.emit())
	var body := HBoxContainer.new()
	body.name = "HostingLocked"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",24)
	shell.outer.add_child(body)
	# The chapter picture keeps a steady 16:9 cover crop in rounded corners.
	var picture_area := AspectRatioContainer.new()
	picture_area.ratio = 16.0/9.0
	picture_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture_area.size_flags_stretch_ratio = 1.15
	body.add_child(picture_area)
	var frame: Control = host._replay_preview_thumb(chapter_key,Vector2.ZERO,20)
	frame.get_child(0).name = "HostingLockedHero"
	picture_area.add_child(frame)
	# Details scroll on their own whenever a short screen cannot fit them.
	var details := ScrollContainer.new()
	details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.follow_focus = true
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ControlTheme.touch_scroll(details)
	body.add_child(details)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(column)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style: StyleBoxFlat = host._style(Color("1b443e"),20)
	for edge: String in ["left","top","right","bottom"]: panel_style.set("content_margin_"+edge,26)
	panel.add_theme_stylebox_override("panel",panel_style)
	column.add_child(panel)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation",12)
	panel.add_child(card)
	var title: Label = host._label(str(descriptor.get("title",chapter_key)),32,CREAM,true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(title)
	card.add_child(host._label("Full Journey",22,GOLD))
	# A Test Store build offers no purchase here, so it names none.
	if not test_store: card.add_child(host._paragraph(PlayerCopy.SUBSCRIPTION_PURPOSE,0))
	# "Full Journey is only required for the host. A friend may join by invitation."
	card.add_child(host._paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,0))
	if test_store:
		# This build's purchase cannot unlock hosting, so point to tester access
		# instead of offering a checkout that would not grant it.
		var owned: bool = host._hosting_lock_reason() == Purchases.HOSTING_NEEDS_TESTER_CODE
		card.add_child(host._paragraph(PlayerCopy.HOSTING_NEEDS_TESTER_CODE if owned else PlayerCopy.MAIN_FAD34E850ED9,0))
		if PlatformSupport.tester_code_offered():
			var code: Button = host._button("Tester code",show_tester_access)
			code.name = "HostingLockedTester"
			card.add_child(code)
	elif _play_store_enabled() and host.purchases.is_available() and not purchase_offer.is_empty():
		# Show the real store prices only when the store actually provided them.
		_add_subscription_choices(card)
	else:
		var unlock: Button = host._button("Unlock Full Journey",show_paywall)
		unlock.name = "HostingLockedUnlock"
		card.add_child(unlock)
		card.add_child(host._button("Restore purchases",restore_purchases,false))

func _show_store_offer() -> void:
	if not _play_store_enabled():
		show_paywall(tester_store_manual)
		return
	if host._tester_active() and not tester_store_manual:
		_show_tester_active()
		return
	if host.purchases.has_entitlement():
		_show_full_journey_unlocked()
		return
	var card := _full_journey_card()
	_add_subscription_choices(card)
	_add_store_back(card)

func _show_full_journey_unlocked() -> void:
	if not _play_store_enabled():
		show_paywall(tester_store_manual)
		return
	var card: VBoxContainer = host._card(680)
	card.add_child(host._label("Full Journey unlocked.",34,CREAM,true))
	if Save.equal(host.config.get("purchase_mode"), "test_store"):
		card.add_child(host._paragraph(PlayerCopy.MAIN_FAD34E850ED9,620))
	elif _manage_subscription_available():
		card.add_child(host._paragraph(PlayerCopy.for_platform(PlayerCopy.SUBSCRIPTION_ACTIVE,PlayerCopy.SUBSCRIPTION_ACTIVE_IOS),620))
	card.add_child(host._button("Enter the Lighthouse",func(): lighthouse_requested.emit()))
	_add_store_links(card)
	_add_store_back(card)

func _buy_full_journey(package: Dictionary) -> void:
	if not _play_store_enabled(): return
	# Only a package from the offering on screen can be bought.
	if store_action_pending or host.mode!=MODE_PAYWALL or not package in purchase_offer.get("packages",[]): return
	if not identity_ready():
		host._toast(PlayerCopy.MAIN_5FE98B59E6BA)
		return
	if host.purchases.has_entitlement():
		_show_full_journey_unlocked()
		return
	store_action_pending=true
	var card := _full_journey_card()
	card.add_child(host._paragraph(PlayerCopy.MAIN_8A2FF5596F1C,600))
	store_action_request=host.purchases.purchase(str(package.offering_id),str(package.id))

## The store is set up for the identity Main holds now, and nothing holds that identity.
func identity_ready() -> bool:
	return store_configured and not store_owner.is_empty() and host.api.player_id==store_owner and host._store_identity_settled()

func _load_store(force_refresh: bool = false) -> void:
	if not _play_store_enabled(): return
	if store_action_pending or host.mode != MODE_PAYWALL: return
	_show_store_status(PlayerCopy.MAIN_DD823B20A782)
	store_read_request=""
	var view: int = host.store_view_generation
	if not await host._ensure_identity():
		if host.mode == MODE_PAYWALL and view == host.store_view_generation:
			_show_store_problem(PlayerCopy.MAIN_5FE98B59E6BA)
		return
	if host.mode != MODE_PAYWALL or view != host.store_view_generation: return
	if store_configured:
		if identity_ready():
			_track_store_read(host.purchases.refresh_customer_info_fresh() if force_refresh else host.purchases.refresh_customer_info())
		else: _show_store_problem(PlayerCopy.MAIN_5FE98B59E6BA)
	else:
		configure_purchases(tester_store_manual)

func _track_store_read(id: String) -> void:
	store_read_request=id
	store_read_views[id]=host.store_view_generation

func _accept_store_read(id: String) -> bool:
	# Other customer refreshes retain their existing authoritative UI updates.
	if not store_read_views.has(id): return true
	var view: int=store_read_views[id]
	store_read_views.erase(id)
	if id != store_read_request: return false
	store_read_request=""
	return host.mode == MODE_PAYWALL and view == host.store_view_generation and not store_action_pending

func _show_store_status(message: String) -> void:
	var card := _full_journey_card()
	card.add_child(host._paragraph(message,600))
	card.add_child(host._button("Retry store",func(): _load_store(true),false))
	card.add_child(host._button("Restore purchases",restore_purchases,false))
	_add_store_back(card)

func _show_store_problem(message: String) -> void:
	if host.mode != MODE_PAYWALL: return
	_show_store_status(message if not message.is_empty() else "Store unavailable")

func restore_purchases() -> void:
	if not _play_store_enabled(): return
	if store_action_pending: return
	store_action_pending=true
	var view: int = host.store_view_generation
	store_restore_view=view
	if not await host._ensure_identity():
		store_action_pending=false
		return
	if view!=host.store_view_generation:
		store_action_pending=false
		return
	if store_configured:
		if not identity_ready():
			store_action_pending=false
			return
		store_action_request=host.purchases.restore()
	else:
		restore_requested=true
		configure_purchases(true)

func purchase_completed(id: String, operation: String, payload: Dictionary) -> void:
	if not _play_store_enabled(): return
	if operation in ["get_customer_info","get_offerings"] and not _accept_store_read(id): return
	if operation=="configure":
		if id!=store_configure_request or id.is_empty(): return
		store_configure_request=""
		if host.api.player_id!=store_owner or host.identity_restart_required: return
		store_configured=true
		if restore_requested:
			restore_requested=false
			if store_restore_view!=host.store_view_generation or not identity_ready():
				store_action_pending=false
				return
			store_action_request=host.purchases.restore()
		elif host.mode==MODE_PAYWALL:
			if identity_ready() and host.purchases.has_entitlement(): _show_full_journey_unlocked()
			else: _track_store_read(host.purchases.fetch_offerings())
	elif operation=="get_offerings":
		if host.mode!=MODE_PAYWALL or store_action_pending or not identity_ready():
			return
		if host.purchases.has_entitlement():
			_show_full_journey_unlocked()
			return
		purchase_offer=Purchases.select_subscription_offer(payload,host.config)
		if purchase_offer.is_empty():
			_show_store_problem(PlayerCopy.MAIN_A986D201176A)
			return
		_show_store_offer()
	elif operation=="get_customer_info":
		if host.mode==MODE_PAYWALL and not store_action_pending and identity_ready():
			if host.purchases.has_entitlement(): _show_full_journey_unlocked()
			else: _track_store_read(host.purchases.fetch_offerings())
	elif operation in ["purchase_package","restore_purchases"]:
		if id!=store_action_request or id.is_empty(): return
		store_action_request=""
		store_action_pending=false
		if not identity_ready(): return
		host._toast("Full Journey unlocked." if host.purchases.has_entitlement() else PlayerCopy.MAIN_FF5EB2A130CC)
		if host.mode==MODE_PAYWALL:
			if host.purchases.has_entitlement(): _show_full_journey_unlocked()
			elif not purchase_offer.is_empty(): _show_store_offer()
			else: show_paywall(tester_store_manual)

func purchase_failed(id: String,operation: String,_code: String,message: String,cancelled: bool) -> void:
	if operation in ["get_customer_info","get_offerings"] and not _accept_store_read(id): return
	if operation=="configure":
		if id!=store_configure_request or id.is_empty(): return
		store_configure_request=""
		if not store_action_request.is_empty(): return
		store_action_pending=false
		restore_requested=false
	elif operation in ["purchase_package","restore_purchases"]:
		if id!=store_action_request or id.is_empty(): return
		store_action_request=""
		store_action_pending=false
	if operation in ["purchase_package","restore_purchases","configure"]:
		if host.mode==MODE_PAYWALL and not purchase_offer.is_empty() and identity_ready(): _show_store_offer()
	if host.mode == MODE_PAYWALL and not store_action_pending and (operation in ["configure","get_customer_info","get_offerings"] or purchase_offer.is_empty()):
		_show_store_problem(PlayerCopy.MAIN_B621C76A2638 if cancelled else message)
	host._toast(PlayerCopy.MAIN_B621C76A2638 if cancelled else message)

func configure_purchases(manual_store: bool = false) -> void:
	if host.purchases is Purchases and host._purchase_session_identity():
		host.purchases.bind_session(host.api.player_id, host.api.device_token)
	if host._tester_checks_enabled():
		var context: String = host._tester_context()
		await host._load_cached_tester()
		if context.is_empty() or context != host._tester_context() or _tester_cache_checking(): return
		if host._tester_active() and not manual_store: return
	if not _play_store_enabled() or host.identity_restart_required or not store_configure_request.is_empty():
		return
	var key := str(host.config.get("revenuecat_public_key",""))
	if not key.is_empty() and not host.api.player_id.is_empty() and not store_configured:
		store_owner=host.api.player_id
		store_configure_request=host.purchases.configure_store(key,host.api.player_id,str(host.config.get("purchase_mode","")))

func _tester_cache_checking() -> bool:
	return is_instance_valid(host.tester_access) and host.tester_access.cache_checking

func show_tester_access() -> void:
	host.running = false
	host.mode = MODE_TESTER_ACCESS
	var card: VBoxContainer = host._card(700)
	card.add_child(host._label("Tester access",32,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_BA73581A5C04,620))
	card.add_child(host._back_button("Back to settings",func(): settings_requested.emit(),false))
	var view: int = host.store_view_generation
	if not await host._ensure_identity():
		if host.mode == MODE_TESTER_ACCESS and view == host.store_view_generation: _tester_form(PlayerCopy.for_platform(PlayerCopy.MAIN_B39BBA0B04B0,PlayerCopy.MAIN_B39BBA0B04B0_IOS))
		return
	await host._load_cached_tester()
	if host.mode != MODE_TESTER_ACCESS or view != host.store_view_generation: return
	if host._tester_active(): _show_tester_active()
	else: _tester_form()

func _tester_form(message: String = "") -> void:
	host.mode = MODE_TESTER_ACCESS
	var card: VBoxContainer = host._card(700)
	card.add_child(host._label("Tester code",32,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_A44444872701,620))
	if not message.is_empty(): card.add_child(host._paragraph(message,620))
	var field := LineEdit.new()
	field.name = "TesterCode"
	field.placeholder_text = "Tester code"
	field.secret = true
	field.max_length = 128
	field.custom_minimum_size.y = 52
	card.add_child(field)
	var submit: Button = host._button("Redeem tester code",func(): _submit_tester_code(field))
	submit.disabled = not host._relay_identity().ready or tester_action_pending
	card.add_child(submit)
	var restore: Button = host._button("Restore tester access",_restore_tester_access,false)
	restore.disabled = not host._relay_identity().ready or tester_action_pending
	card.add_child(restore)
	card.add_child(host._paragraph(PlayerCopy.MAIN_2E2A18416368,620))
	card.add_child(host._back_button("Back to settings",func(): settings_requested.emit(),false))

func _show_tester_active() -> void:
	host.mode = MODE_TESTER_ACCESS
	var card: VBoxContainer = host._card(700)
	card.add_child(host._label("Tester access active",32,CREAM,true))
	card.add_child(host._back_button("Back to chapters",func(): chapters_requested.emit()))
	if _play_store_enabled(): card.add_child(host._button("Store purchases",show_store_from_settings,false))
	elif PlatformSupport.play_listing_offered(): card.add_child(host._button("Get it on Google Play",func(): google_play_requested.emit(),false))
	card.add_child(host._back_button("Back to settings",func(): settings_requested.emit(),false))

func _submit_tester_code(field: LineEdit) -> void:
	if tester_action_pending or not is_instance_valid(field) or not host._relay_identity().ready: return
	var code := field.text
	field.clear()
	await _request_tester_access(code, false)

func _restore_tester_access() -> void:
	await _request_tester_access("", true)

func _request_tester_access(code: String, restoring: bool) -> void:
	if tester_action_pending or not host._relay_identity().ready: return
	tester_action_pending = true
	var context: String = host._tester_context()
	var card: VBoxContainer = host._card(700)
	card.add_child(host._label("Restoring tester access…" if restoring else "Checking tester code…",30,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_C7E8A28B2803,620))
	card.add_child(host._back_button("Back to settings",func(): settings_requested.emit(),false))
	var view: int = host.store_view_generation
	var result: Dictionary = await host.tester_access.restore(host.api.base_url, host.api.player_id) if restoring else await host.tester_access.redeem(host.api.base_url, host.api.player_id, code)
	code = ""
	tester_action_pending = false
	if context != host._tester_context(): return
	if result.get("ok", false) and host.purchases is Purchases: host.purchases.invalidate_session_reads()
	host.tester_access.note_cache_checked(context, host.api.base_url, host.api.player_id, host.api.device_token)
	if host.application_backgrounded or host.mode != MODE_TESTER_ACCESS: return
	if view != host.store_view_generation:
		_refresh_tester_screen_if_idle()
		return
	if result.get("ok",false) and result.get("granted",false) and result.get("durable",false) and host._tester_active():
		_show_tester_active()
	elif result.get("ok",false) and not result.get("granted",false):
		_tester_form(PlayerCopy.MAIN_B7C7E85171CD)
	else:
		_tester_form(PlayerCopy.MAIN_85B232C00485)

func resume_purchase_access() -> void:
	if host._tester_checks_enabled(): await host._load_cached_tester()
	if host.application_backgrounded or _tester_cache_checking(): return
	_refresh_tester_screen_if_idle()
	if host._tester_active(): return
	if not store_configured:
		if host._relay_identity().ready and not store_action_pending:
			configure_purchases()
		return
	if host.purchases is Purchases and host.purchases.needs_review_verification() and identity_ready():
		host.purchases.refresh_customer_info()

func _refresh_tester_screen_if_idle() -> void:
	if host.mode != MODE_TESTER_ACCESS or tester_action_pending or host.application_backgrounded: return
	if host._tester_active(): _show_tester_active()
	else: _tester_form()
