extends "res://tests/test_purchase_session.gd"

var startup_host: Node

class StartupHost extends Node:
	const Facade = preload("res://services/purchases.gd")
	var provider: RefCounted
	var configuration: Dictionary
	var owner_id: String
	var token: String
	var customer_payload: Dictionary
	var service: Node
	var follower: Node
	var configure_id := ""
	var follower_configure_id := ""
	var offer_id := ""
	var reply_before_attachment := false
	var early_reply_observed := false
	var pending_before_attachment := false
	var completed_ids: Array[String] = []
	var failed_ids: Array[String] = []

	func _ready() -> void:
		# Match Main._ready: construct Purchases, then add it during startup readiness.
		# Only provider/configuration are synthetic; facade and broker are real.
		service = Facade.new()
		service._configuration = configuration.duplicate(true)
		service.native_factory = func(): return provider
		add_child(service)
		service.completed.connect(func(id, _operation, _payload): completed_ids.append(id))
		service.failed.connect(func(id, _operation, _code, _message, _cancelled): failed_ids.append(id))
		service.bind_session(owner_id,token)
		configure_id = service.configure_store(configuration.revenuecat_public_key,owner_id,configuration.purchase_mode)
		follower = Facade.new()
		follower._configuration = configuration.duplicate(true)
		follower.native_factory = func(): return provider
		add_child(follower)
		follower.completed.connect(func(id, _operation, _payload): completed_ids.append(id))
		follower.bind_session(owner_id,token)
		follower_configure_id = follower.configure_store(configuration.revenuecat_public_key,owner_id,configuration.purchase_mode)
		var broker: Node = service._session
		reply_before_attachment = not broker.is_inside_tree()
		provider.answer(provider.calls[0],customer_payload)
		early_reply_observed = broker._configured
		offer_id = service.fetch_offerings()
		if broker._writes.has(offer_id):
			pending_before_attachment = not broker.is_inside_tree() and broker.is_processing()
			broker._writes[offer_id].deadline = 0

func _initialize() -> void:
	# Deliberately install before root enters the tree. Deferred _run fixtures add
	# their facades after startup and cannot exercise a busy root during _ready.
	native = Native.new()
	startup_host = StartupHost.new()
	startup_host.provider = native
	startup_host.configuration = CONFIG
	startup_host.owner_id = OWNER
	startup_host.token = TOKEN
	startup_host.customer_payload = _payload(false)
	root.add_child(startup_host)
	_run.call_deferred()

func _run() -> void:
	for frame in range(3): await process_frame
	var broker: Node = startup_host.service._session
	_check(is_instance_valid(broker) and broker.is_inside_tree(), "Startup Purchases attaches its shared broker to the SceneTree")
	_check(native.is_connected("request_result",broker._result) and native.is_connected("request_error",broker._error), "Startup broker connects native result and error callbacks")
	_check(native.count("configure") == 1 and startup_host.follower._session == broker, "Two startup facades share one broker and one native configuration")
	_check(startup_host.reply_before_attachment and startup_host.early_reply_observed, "The broker receives a native reply before its deferred tree attachment")
	_check(startup_host.completed_ids.has(startup_host.configure_id) and startup_host.completed_ids.has(startup_host.follower_configure_id), "An early configuration reply reaches both startup facades")
	_check(startup_host.pending_before_attachment, "A missing offer callback has an active deadline before broker readiness")
	# Let the real tree process the deadline. Calling broker._process manually
	# would hide either an orphan broker or _ready disabling pending processing.
	_check(startup_host.failed_ids.size() == 1 and startup_host.failed_ids[0] == startup_host.offer_id and not broker._writes.has(startup_host.offer_id), "Broker readiness preserves pending timeout processing and settles the lost offer exactly once")
	startup_host.free()
	if is_instance_valid(broker): broker.free()
	Session._shared = null

	# Control: the earlier test helper's late-injection lifecycle already works.
	native.calls.clear()
	var late := _facade()
	root.add_child(late)
	late.bind_session(OWNER,TOKEN)
	var replies: Array[String] = []
	late.completed.connect(func(id, _operation, _payload): replies.append(id))
	var late_id: String = late.configure_store(CONFIG.revenuecat_public_key,OWNER,CONFIG.purchase_mode)
	if not native.calls.is_empty(): native.answer(native.calls[-1],_payload(false))
	for frame in range(3): await process_frame
	_check(late._session.is_inside_tree() and replies.has(late_id), "The late-injected control attaches and receives its configuration reply")
	late.free()
	Session.suspend_shared(true)
	await process_frame
	print("PURCHASE SESSION STARTUP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
