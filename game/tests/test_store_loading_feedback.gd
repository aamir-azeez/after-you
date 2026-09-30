extends "res://tests/test_purchase_session.gd"

const LOADING_OFFER := "Loading the current offer in the store…"
const NO_OFFER := "There is no offer available at the moment from the store."
const OFFER_BUTTON := "Unlock Full Journey · $4.99"

func _run() -> void:
	root.size = Vector2i(1280,720)
	native = Native.new()
	Session.suspend_shared(true)
	var app: Node = await _screen()
	app._show_paywall()
	await _settle_store_ui()
	_check(native.count("configure") == 1 and _store_label(app,LOADING_OFFER), "A nonbuyer paywall starts with one pending native configuration")
	var request: Dictionary = native.calls[-1]
	native.request_error.emit(request.id,request.operation,"offline","Store setup could not complete.",false)
	await _settle_store_ui()
	_store_problem(app,"Store setup could not complete.","Failed configuration")
	_press_store_retry(app)
	_check(native.calls[-1].operation == "configure" and native.count("configure") == 2 and _store_label(app,LOADING_OFFER), "Retry replaces the configuration error with loading and starts a new configuration")
	native.answer(native.calls[-1],_payload(false))
	await _settle_store_ui()
	_check(app._store_identity_ready() and native.calls[-1].operation == "get_offerings", "A real nonbuyer configuration callback requests offerings through the shared broker")
	native.answer(native.calls[-1],_lifetime_offer())
	await _settle_store_ui()
	_check(_store_button(app,OFFER_BUTTON) != null and not _store_label(app,LOADING_OFFER) and not app.purchases.has_entitlement(), "A real lifetime offering replaces loading with its price without granting access")

	app._show_paywall()
	await _settle_store_ui()
	_check(native.calls[-1].operation == "get_offerings", "Reopening a nonbuyer paywall requests the current offering")
	request = native.calls[-1]
	native.request_error.emit(request.id,request.operation,"store_unavailable","The store offer is unavailable. Try again.",false)
	await _settle_store_ui()
	_store_problem(app,"The store offer is unavailable. Try again.","Rejected offering")
	_press_store_retry(app)
	_check(native.calls[-1].operation == "get_customer_info" and _store_label(app,LOADING_OFFER), "Retry replaces the offer error with loading and starts a fresh customer read")
	request = native.calls[-1]
	native.request_error.emit(request.id,request.operation,"offline","Store access could not be refreshed.",false)
	await _settle_store_ui()
	_store_problem(app,"Store access could not be refreshed.","Rejected customer read")

	_press_store_retry(app)
	native.answer(native.calls[-1],_payload(false))
	await _settle_store_ui()
	_check(native.calls[-1].operation == "get_offerings", "Successful retry of customer information resumes offer loading")
	native.answer(native.calls[-1],{"schema_version":1,"mode":"google_play","current_id":"journey","offerings":[]})
	await _settle_store_ui()
	_store_problem(app,NO_OFFER,"Empty offering")
	_check(_store_button(app,OFFER_BUTTON) == null and app.purchase_package.is_empty(), "An empty offer removes the stale purchase package and price")

	_press_store_retry(app)
	_check(_store_label(app,LOADING_OFFER) and not _store_label(app,NO_OFFER), "Retry clears the empty-offer message while the fresh request is pending")
	native.answer(native.calls[-1],_payload(false))
	await _settle_store_ui()
	native.answer(native.calls[-1],_lifetime_offer())
	await _settle_store_ui()
	_check(_store_button(app,OFFER_BUTTON) != null and not _store_label(app,LOADING_OFFER) and not _store_label(app,NO_OFFER), "A recovered offer shows its price and clears prior loading and error feedback")
	_check(native.count("purchase_package") == 0 and native.count("restore_purchases") == 0 and not app.purchases.has_entitlement(), "Viewing and retrying store offers never issues a purchase, restore, or unlock")
	await _superseded_store_callbacks(app)
	app.queue_free()
	await _settle_store_ui()
	Session.suspend_shared(true)
	Review.forget_shared()
	await process_frame
	for path: String in files:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("STORE LOADING FEEDBACK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _superseded_store_callbacks(app: Node) -> void:
	app._load_store(true)
	var first_read: Dictionary = native.calls[-1]
	_press_store_retry(app)
	var current_read: Dictionary = native.calls[-1]
	await _settle_store_ui()
	_check(first_read.id != current_read.id and current_read.operation == "get_customer_info" and _store_label(app,LOADING_OFFER), "Overlapping Retry keeps loading visible when the superseded customer read fails asynchronously")
	native.answer(current_read,_payload(false))
	await _settle_store_ui()
	var old_offer: Dictionary = native.calls[-1]
	_check(old_offer.operation == "get_offerings", "The current retry continues from its customer read to an offering request")
	_press_store_retry(app)
	native.answer(native.calls[-1],_payload(false))
	await _settle_store_ui()
	var current_offer: Dictionary = native.calls[-1]
	_check(current_offer.operation == "get_offerings" and current_offer.id != old_offer.id, "Retry can supersede an outstanding offering request")
	native.answer(current_offer,_lifetime_offer())
	await _settle_store_ui()
	native.request_error.emit(old_offer.id,old_offer.operation,"offline","Obsolete offer failed.",false)
	await _settle_store_ui()
	_check(_store_button(app,OFFER_BUTTON) != null and not _store_label(app,"Obsolete offer failed."), "An older offering failure cannot replace the current successful offer")

	app._show_paywall()
	await _settle_store_ui()
	old_offer=native.calls[-1]
	_press_store_retry(app)
	var unlocked := _payload(true)
	unlocked.request_date_ms=2000
	native.answer(native.calls[-1],unlocked)
	await _settle_store_ui()
	_check(app.purchases.has_entitlement() and _store_label(app,"Full Journey unlocked."), "The current authoritative customer read can unlock while an older offering is outstanding")
	native.request_error.emit(old_offer.id,old_offer.operation,"offline","Obsolete offer failed after unlock.",false)
	await _settle_store_ui()
	_check(app.purchases.has_entitlement() and _store_label(app,"Full Journey unlocked.") and not _store_label(app,"Obsolete offer failed after unlock."), "An older offering failure cannot replace the unlocked view or alter entitlement")
	_check(native.count("purchase_package") == 0 and native.count("restore_purchases") == 0, "Superseded store reads issue no purchase or restore action")

func _lifetime_offer() -> Dictionary:
	return {"schema_version":1,"mode":"google_play","current_id":"journey","offerings":[
		{"id":"journey","packages":[{"id":"lifetime","type":"LIFETIME","product_id":Purchases.PLAY_PRODUCT,"price":"$4.99"}]}]}

func _settle_store_ui() -> void:
	for frame in range(3): await process_frame

func _press_store_retry(app: Node) -> void:
	var retry := _store_button(app,"Retry store")
	_check(retry != null and not retry.disabled, "Store feedback keeps Retry available")
	if retry != null: retry.pressed.emit()

func _store_problem(app: Node, message: String, description: String) -> void:
	_check(_store_label(app,message) and not _store_label(app,LOADING_OFFER), "%s replaces loading with persistent feedback inside the store card" % description)
	_check(_store_button(app,"Retry store") != null and _store_button(app,"Restore purchases") != null and _store_button(app,"Back to chapters") != null, "%s preserves Retry, Restore, and Back controls" % description)

func _store_label(app: Node, value: String) -> bool:
	for label: Label in app.overlay.find_children("*","Label",true,false):
		if label.text == value: return true
	return false

func _store_button(app: Node, value: String) -> Button:
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text == value: return button
	return null
