extends CanvasLayer
## The small "Opening your chapter" card every chapter opens behind.
## A chapter screen builds its world and sets up its turn in one frame, so the
## card is drawn first (two frames) and stays on top, above the scene change,
## until the chapter has drawn its own first frame. Every open is timed; the
## card shows only when this chapter took 300 ms or more to open last time on
## this device, or has not been timed here yet.
##
## The engine draws a frame only when the main thread finishes one, so the bar
## can move only while the main thread is free. Before the scene change,
## prepare() therefore loads the chapter scene on the loader's threads and
## proves the chapter's saved journey on a worker (journey_proofs.gd), while
## the bar follows both parts' real progress, eased and never backwards, with
## a shimmer passing over it. The chapter's own build then finds its scene
## loaded and its save remembered; only that build (its world and first turn,
## node work that must stay on the main thread) still holds one frame, with
## the bar parked near the end.
const ReplayLoadingBar = preload("res://presentation/replay_loading_bar.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const ProofWarmup = preload("res://services/journey_proof_warmup.gd")
const Reaper = preload("res://services/worker_reaper.gd")
## The bar's share for the work before the scene change, where it waits while
## the chapter builds, and the proof's weight against the scene load.
const PREPARED := 0.85
const BUILDING := 0.92
const PROOF_WEIGHT := 2.0
## Real progress arrives in steps (a whole saved stage, a quarter of the
## scene) that can each take seconds on a phone. While none arrives the bar
## creeps toward CREEP_SHARE of what is left before PREPARED, with this time
## constant; the next real step carries it on from there.
const CREEP_SHARE := 0.6
const CREEP_USEC := 2500000.0
## The longest prepare() waits after its work for the bar to catch up.
const CATCH_UP_USEC := 90000
const TITLE := "Opening your chapter"
const SHOW_AFTER_USEC := 300000
const COSTS_PATH := "user://chapter-open-times.json"
const MAX_COSTS_BYTES := 16384
const MAX_COSTS := 64
const LAYER := 90
## Frames a scene change may take before the card gives up waiting for it.
const MAX_WAIT_FRAMES := 600
const CREAM := Color("eceddb")

static var costs_path := COSTS_PATH
static var _costs: Dictionary = {}
static var _costs_from := ""

var key := ""
var shown := false
var _started := 0
var _closed := false
var _bar: VBoxContainer
## A scene requested from the threaded loader and not collected yet.
var _loading := ""
var _proof_thread: Thread
var _proof_run: ProofRun

## Shared with the proof worker: a stop request and its progress.
class ProofRun extends "res://services/stop_request.gd":
	var _total := 0
	var _done := 0
	var _base := 0
	var _calls := 0
	func set_total(total: int) -> void:
		_mutex.lock()
		_total = total
		_mutex.unlock()
	## Called by Proofs.warm before each stage it replays (so the one before
	## it is done), and whether to stop.
	func step() -> bool:
		_mutex.lock()
		_calls += 1
		_done = mini(_base + _calls - 1, _total)
		var value := _stopped
		_mutex.unlock()
		return value
	## A saved generation of steps steps is settled (proven, known or refused).
	func settle(steps: int) -> void:
		_mutex.lock()
		_base = mini(_base + steps, _total)
		_done = _base
		_calls = 0
		_mutex.unlock()
	func fraction() -> float:
		_mutex.lock()
		var value := 1.0 if _total <= 0 else clampf(float(_done) / _total, 0.0, 1.0)
		_mutex.unlock()
		return value



## Whether an open of key is expected to take long enough to show the card.
static func expected_slow(open_key: String) -> bool:
	var cost := last_cost_usec(open_key)
	return cost < 0 or cost >= SHOW_AFTER_USEC

## The last measured open of key on this device, or -1.
static func last_cost_usec(open_key: String) -> int:
	_load_costs()
	return int(_costs.get(open_key, -1))


## Adds the card for an open of open_key under the tree's root, which outlives
## the scene change. Hidden when the open is expected to be quick.
func start(tree: SceneTree, open_key: String, reduced_motion: bool = false) -> void:
	key = open_key
	name = "ChapterLoadingCard"
	layer = LAYER
	shown = expected_slow(key)
	visible = shown
	if shown: _build(reduced_motion)
	tree.root.add_child(self)
	_started = Time.get_ticks_usec()

## Returns once the card is on screen: two frames when it shows, none when
## it does not. Timing starts after it, with the work.
func drawn() -> void:
	if shown and is_inside_tree():
		await get_tree().process_frame
		await get_tree().process_frame
	_started = Time.get_ticks_usec()

## After drawn(), while the card shows: loads scene on the loader's threads
## and proves the saved journey of the solo chapter it opens on a worker,
## keeping the main thread free so the bar moves every frame. Returns once
## both are done (at once when the card is hidden). Anything that fails here
## is simply left to the open itself, which checks and loads as before.
## owner, when given, is the screen this open is for: if it is freed
## meanwhile, the open is over and the card leaves.
func prepare(scene: String, prove_save: bool = true, owner: Object = null) -> void:
	await _prepare(scene, chapters_for_scene(scene) if prove_save else [], owner.get_instance_id() if owner != null else 0)

## change_scene_to_file for the open, using the scene prepare() loaded.
func change_scene(scene: String) -> Error:
	var tree := get_tree()
	if is_instance_valid(_bar): _bar.follow(BUILDING)
	if not _loading.is_empty() and _loading == scene and ResourceLoader.load_threaded_get_status(scene) == ResourceLoader.THREAD_LOAD_LOADED:
		_loading = ""
		var packed := ResourceLoader.load_threaded_get(scene) as PackedScene
		if packed != null: return tree.change_scene_to_packed(packed)
	return tree.change_scene_to_file(scene)

## The solo chapters a scene opens whose saved journey can be proved ahead.
static func chapters_for_scene(scene: String) -> Array:
	var result: Array = []
	if scene.is_empty(): return result
	for chapter: String in Registry.keys():
		if Registry.solo_scene(chapter) != scene or not Proofs._runtime_family(Registry.simulation_script(chapter)): continue
		var path := str(Registry.descriptor(chapter).get("local_path", ""))
		if not path.is_empty(): result.append({"chapter": chapter, "path": path})
	return result

## owner_id: the object whose open this is (0 for none); when it is freed the
## open is over and the card leaves.
func _prepare(scene: String, saves: Array, owner_id: int = 0) -> void:
	if not shown or _closed or not is_inside_tree(): return
	var tree := get_tree()
	if not scene.is_empty() and ResourceLoader.load_threaded_request(scene) == OK: _loading = scene
	var weight := 0.0
	if not saves.is_empty():
		_proof_run = ProofRun.new()
		Reaper.ensure()
		var thread := Thread.new()
		# A static function and private copies: no node crosses to the worker.
		if thread.start(Callable(get_script(), "_prove_saves").bind(saves.duplicate(true), _proof_run)) == OK:
			_proof_thread = thread
			weight = PROOF_WEIGHT
		else:
			_proof_run = null
	var progress: Array = []
	var real := -1.0
	var real_since := Time.get_ticks_usec()
	while not _closed and is_inside_tree():
		var load_part := 1.0
		var loading := false
		if not _loading.is_empty():
			var status := ResourceLoader.load_threaded_get_status(_loading, progress)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				loading = true
				load_part = float(progress[0]) if not progress.is_empty() else 0.0
			elif status != ResourceLoader.THREAD_LOAD_LOADED:
				# The open loads it itself, as before.
				_loading = ""
		var proof_part := 1.0
		if _proof_thread != null:
			proof_part = _proof_run.fraction()
			if not _proof_thread.is_alive():
				_proof_thread.wait_to_finish()
				_proof_thread = null
				_proof_run = null
				proof_part = 1.0
		var now := PREPARED * (load_part + proof_part * weight) / (1.0 + weight)
		if now != real:
			real = now
			real_since = Time.get_ticks_usec()
		if is_instance_valid(_bar): _bar.follow(creeping(real, Time.get_ticks_usec() - real_since))
		# The screen that asked for this open has gone: so has the open.
		if owner_id != 0 and not is_instance_id_valid(owner_id):
			cancel()
			return
		if not loading and _proof_thread == null: break
		await tree.process_frame
	# A few frames for the bar to reach the share it holds while the chapter
	# builds, since that build holds the frame.
	if _closed or not is_inside_tree() or not is_instance_valid(_bar): return
	_bar.follow(BUILDING)
	_bar.hurry = true
	var waited := Time.get_ticks_usec()
	while _bar.shown < BUILDING - 0.03 and Time.get_ticks_usec() - waited < CATCH_UP_USEC and not _closed and is_inside_tree():
		await tree.process_frame

## The bar's share after waited_usec with no new progress beyond real: on
## toward PREPARED, never onto it.
static func creeping(real: float, waited_usec: int) -> float:
	if real >= PREPARED: return real
	return real + (PREPARED - real) * CREEP_SHARE * (1.0 - exp(-maxf(waited_usec, 0) / CREEP_USEC))

## The worker: proves each saved generation of saves (the save, a write in
## progress and its backup, as load_data reads them) through the proofs'
## warm-up, counting replayed stages as progress.
static func _prove_saves(saves: Array, run: ProofRun) -> void:
	var found: Array = []
	var total := 0
	for source: Dictionary in saves:
		for suffix: String in ["", ".tmp", ".backup"]:
			var state: Variant = ProofWarmup._read(str(source.path) + suffix)
			if state == null: continue
			found.append([source, state])
			total += _steps(state)
	run.set_total(total)
	var validators: Dictionary = {}
	for item: Array in found:
		if run.stopped(): return
		var source: Dictionary = item[0]
		var chapter := str(source.chapter)
		if not validators.has(chapter): validators[chapter] = Journey.new(str(source.path), null, chapter)
		Proofs.warm(validators[chapter], item[1], Callable(run, "step"))
		run.settle(_steps(item[1]))

## The stages Proofs.warm may replay for a saved state, plus its first turn.
static func _steps(state: Dictionary) -> int:
	var pairs: Variant = state.get("pairs")
	var first: Variant = state.get("a")
	return (pairs.size() if pairs is Array else 0) + (1 if first is Dictionary and not first.is_empty() else 0)

## Call right after a successful change_scene_to_file: times the open and
## leaves once the new scene has drawn its first frame.
func follow_scene_change(previous: Node) -> void:
	if _closed or not is_inside_tree(): return
	var tree := get_tree()
	var previous_id := previous.get_instance_id() if is_instance_valid(previous) else 0
	var frames := 0
	while is_inside_tree() and frames < MAX_WAIT_FRAMES and (tree.current_scene == null or tree.current_scene.get_instance_id() == previous_id):
		await tree.process_frame
		frames += 1
	if not is_inside_tree(): return
	await _while_building(tree.current_scene)
	if not is_inside_tree(): return
	if is_instance_valid(_bar): _bar.follow(1.0)
	await tree.process_frame
	_finish(frames < MAX_WAIT_FRAMES)

## A chapter screen that builds its world over several frames says so with
## building(); the card stays up (its bar moving) until it is done, never
## longer than BUILD_WAIT_MSEC.
const BUILD_WAIT_MSEC := 15000
func _while_building(screen: Object) -> void:
	var deadline := Time.get_ticks_msec() + BUILD_WAIT_MSEC
	while is_inside_tree() and is_instance_valid(screen) and screen.has_method("building") and screen.building() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

## Runs work behind the card (after it is drawn) and leaves after the next
## frame. For a chapter that builds itself in place, outside a scene change;
## its saved journey is proved first on a worker, as prepare() does.
func run(work: Callable, prove_chapter: String = "") -> void:
	await drawn()
	if _closed: return
	var saves: Array = []
	for source: Dictionary in chapters_for_scene(Registry.solo_scene(prove_chapter)):
		if source.chapter == prove_chapter: saves.append(source)
	var owner_id := work.get_object_id()
	await _prepare("", saves, owner_id)
	if _closed: return
	if owner_id != 0 and not is_instance_id_valid(owner_id):
		cancel()
		return
	work.call()
	if not is_inside_tree(): return
	await _while_building(instance_from_id(owner_id) if owner_id != 0 else null)
	if not is_inside_tree(): return
	if is_instance_valid(_bar): _bar.follow(1.0)
	await get_tree().process_frame
	_finish(true)

## Leaves without recording a time: the open did not happen.
func cancel() -> void:
	_closed = true
	_release()
	if is_inside_tree(): get_parent().remove_child(self)
	queue_free()

func _finish(measured: bool) -> void:
	if _closed: return
	_closed = true
	if measured: _record(key, Time.get_ticks_usec() - _started)
	_release()
	if is_inside_tree(): get_parent().remove_child(self)
	queue_free()

## Never waits: a running proof is asked to stop after its stage and handed
## to the reaper; a finished load is collected so the loader lets it go.
func _release() -> void:
	if _proof_thread != null:
		_proof_run.stop()
		Reaper.adopt(_proof_thread)
		_proof_thread = null
		_proof_run = null
	if not _loading.is_empty():
		if ResourceLoader.load_threaded_get_status(_loading) == ResourceLoader.THREAD_LOAD_LOADED: ResourceLoader.load_threaded_get(_loading)
		_loading = ""


func _build(reduced_motion: bool) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	theme.default_font = body
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", CREAM)
	root.theme = theme
	add_child(root)
	# The same dimming as a chapter card; it also keeps taps off the screen
	# underneath while the chapter opens.
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.10, 0.10, 0.73)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "OpeningCard"
	panel.custom_minimum_size.x = 380
	var style := StyleBoxFlat.new()
	style.bg_color = Color("163c36")
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = Color("54766a")
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	var title := Label.new()
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var heading := FontVariation.new()
	heading.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	title.add_theme_font_override("font", heading)
	title.add_theme_font_size_override("font_size", 28)
	stack.add_child(title)
	var bar := ReplayLoadingBar.new()
	bar.name = "OpeningProgress"
	bar.reduced_motion = reduced_motion
	stack.add_child(bar)
	bar.follow(0.0)
	_bar = bar


static func _load_costs() -> void:
	if _costs_from == costs_path: return
	_costs_from = costs_path
	_costs = {}
	if not FileAccess.file_exists(costs_path): return
	var file := FileAccess.open(costs_path, FileAccess.READ)
	if file == null: return
	if file.get_length() < 1 or file.get_length() > MAX_COSTS_BYTES:
		file.close()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	# Anything unexpected is ignored; the next open writes a fresh record.
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("costs") is Dictionary: return
	for name: Variant in parsed.costs:
		var value: Variant = parsed.costs[name]
		if name is String and (value is int or value is float) and value >= 0 and _costs.size() < MAX_COSTS: _costs[name] = int(value)

static func _record(open_key: String, usec: int) -> void:
	if open_key.is_empty() or usec < 0: return
	_load_costs()
	_costs.erase(open_key)
	_costs[open_key] = usec
	while _costs.size() > MAX_COSTS: _costs.erase(_costs.keys()[0])
	var text := JSON.stringify({"schema_version": 1, "costs": _costs})
	var file := FileAccess.open(costs_path, FileAccess.WRITE)
	if file == null: return
	file.store_string(text)
	file.close()
