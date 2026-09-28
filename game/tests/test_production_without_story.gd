extends "res://tests/test_main_story.gd"
## Production Main stays closed to Story even when old journals/content exist.
const ReleaseCatalog = preload("res://services/campaign_catalog.gd")
const Local = preload("res://services/local_save.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const LegacyLevels = preload("res://core/levels.gd")

class ProductionMain extends UiMain:
	var owner_preparations := 0
	func _ready() -> void:
		super._ready()
		world.free()
		world = IslandWorld.new()
		add_child(world)
		world.set_process(false)
		levels = LegacyLevels.all_levels()
		current_level = levels[0]
	func _prepare_campaign_owner() -> bool:
		owner_preparations += 1
		return super._prepare_campaign_owner()

func _run() -> void:
	_catalog_and_export()
	_make_story_fixture()
	await _fresh_navigation()
	await _retained_navigation(false)
	await _retained_navigation(true)
	print("Production without Story: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _catalog_and_export() -> void:
	_check(not ReleaseCatalog.PRODUCTION_ENABLED,"Production has no Story feature switch controlled by saves or capabilities")
	var app := MainSource.new()
	_check(app.campaign_catalog.is_empty() and not app._campaign_visible(),"Constructing Main loads no narrative catalog and exposes no Story entry")
	app.campaign_catalog = ReleaseCatalog.bundled()
	_check(not app.campaign_catalog.is_empty() and app._campaign_pairs().is_empty() and not app._campaign_visible(),"Even exact archived content cannot enable production Story")
	var definitions := ReleaseCatalog.compatibility_definitions()
	_check(definitions.size() == 1 and Canonical.same(definitions[0],app.campaign_catalog[0].definition),"Compatibility retains the exact old definition without its dialogue")
	_check(not definitions[0].has("title") and not definitions[0].has("summary") and definitions[0].story.size() == 3,"Compatibility contains only immutable references")
	var export_config := ConfigFile.new()
	_check(export_config.load("res://export_presets.cfg") == OK,"Android export configuration is readable")
	var excluded := str(export_config.get_value("preset.0","exclude_filter",""))
	_check("content/campaigns/*" in excluded and "tests/*" in excluded and "content/compatibility" not in excluded,"Android excludes the narrative and tests while retaining compatibility metadata")
	app.free()

func _production_ui(c: Dictionary) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var app := ProductionMain.new()
	app.harness = c.h
	app.api = c.h
	app.saves.data = Local.defaults()
	app.saves.data.settings.sound = false
	app.relay_session = c.online
	app.campaign_owner = c.owner
	app.campaign_catalog = [{"definition":fixture.definition.duplicate(true),"story":story_content.duplicate(true)}]
	viewport.add_child(app)
	c.owner._leave_ready = app._campaign_leave_ready
	return {"app":app,"viewport":viewport}

func _fresh_navigation() -> void:
	var h := UiHarness.new()
	root.add_child(h)
	var online := Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	var c := {"h":h,"online":online,"owner":owner}
	c.merge(_production_ui(c))
	var before: Dictionary = h.store.saved.duplicate(true)
	var calls: int = h.calls.size()
	_check(c.app._prepare_campaign_owner() and owner.runtime_archived(),"Production retains a passive ownership classifier")
	_check(c.app._campaign_depart_for_ordinary(),"A fresh ordinary profile is not blocked by an empty Story catalog")
	c.app._show_journey()
	_check(_button(c.app.overlay,"Story") == null and _button(c.app.overlay,"Earlier islands") != null,"Chapter picker keeps ordinary chapters without a Story row")
	await _blocked_routes(c)
	_check(h.calls.size() == calls and Canonical.same(before,h.store.saved),"Fresh production navigation performs no Story request or journal write")
	await _dispose_production(c)

func _retained_navigation(corrupt: bool) -> void:
	# Build an actual formerly accepted owner/cache using finite synthetic replies.
	var old := await _make()
	old.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await old.owner.refresh() and await old.owner.select_current() and old.owner.adopt_selected(),"Retained save includes an actual published and cached later Story chapter")
	var online := Online.new(old.h,old.h.identity,old.h.store)
	var owner := Owner.new(online,old.h.identity,[fixture.definition],old.h.leave_ready,old.h.store)
	var c := {"h":old.h,"online":online,"owner":owner,"anchor":old.anchor,"target":old.target}
	if corrupt:
		c.h.store.saved[_journal(c.anchor)] = {"retained_unfamiliar_story":true}
	c.merge(_production_ui(c))
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	c.app._prepare_campaign_owner()
	_check(c.online.coordinator == null and not is_instance_valid(c.app.relay_child),"Old Story ownership never auto-restores a playable child")
	c.app._show_journey()
	_check(_button(c.app.overlay,"Story") == null,"A retained Story save cannot restore the removed menu")
	await _blocked_routes(c)
	_check(not c.app._production_replay_room_allowed({"family":"chapter","room_id":c.target}),"A cached later Story chapter is held even when its control journal is damaged")
	if not corrupt:
		_check(not c.app._production_replay_room_allowed({"family":"chapter","room_id":c.anchor}),"An old Story anchor is excluded from ordinary shared replay selection")
		_check(c.app._production_replay_room_allowed({"family":"chapter","room_id":"OOOOOOOOOOOOOOOOOOOOOO"}),"A separate ordinary chapter replay remains available")
	_check(c.app._production_replay_room_allowed({"family":"legacy","room_id":"OOOOOOOOOOOOOOOOOOOOOO"}),"Legacy replays do not depend on Story compatibility state")
	var preparations: int = c.app.owner_preparations
	await c.app._start_practice(0)
	_check(c.app.mode == "ready" and not c.app.room_play and c.app.owner_preparations == preparations,"Local practice bypasses old Story restoration, including corrupt journals")
	_check(c.h.calls.size() == calls and Canonical.same(before,c.h.store.saved),"Old Story journals, accepted evidence and pending state remain unchanged")
	await _dispose_production(c)

func _blocked_routes(c: Dictionary) -> void:
	var app: Node = c.app
	app._show_journey()
	await app._show_story()
	app._draw_story_lobby()
	_check(app.mode == "journey","Direct Story lobby entry cannot change the production screen")
	for action: String in ["create","join","retry","refresh","terminal","open","resume","current"]:
		app.mode = "story_lobby"
		await app._story_lobby_action(action,Protocol.key(fixture.definition),"0123456789ABCDEF0123")
	_check(not app._campaign_action_busy and app._story_replay_rows().is_empty(),"All old Story lobby actions remain inert")
	app._show_journey()
	app._show_story_replays()
	app._draw_story_replay_chapters()
	await app._open_story_replay_chapter({})
	await app._story_child_action("progress",null)
	await app._story_child_action("recover",null)
	app._story_history(0,"arrival",null)
	app._show_story_access()
	app._show_story_store()
	_check(not await app._story_open_bound({}) and not app._enter_story_child(),"Saved ownership cannot directly resume Story gameplay")
	_check(app.mode == "journey" and not is_instance_valid(app.relay_child) and not is_instance_valid(app.campaign_flow),"Replay, history and access routes create no Story presentation")
	await app._show_paywall(false,{"obsolete_story_return":true})
	_check(app.mode == "paywall" and app._story_store_return.is_empty() and _button(app.overlay,"Return to Story") == null and _button(app.overlay,"Back to chapters") != null,"Ordinary purchases remain reachable without a Story return route")
	app._leave_store()
	_check(app.mode == "journey","Store Back returns to ordinary chapters")

func _dispose_production(c: Dictionary) -> void:
	c.viewport.queue_free()
	await process_frame
	await process_frame
	c.h.free()
