extends "res://tests/test_comfort_rules.gd"
## Worst-size legal physical8 proof, generated through the native engine.

func _run() -> void:
	var level := Catalog.definition("high-and-low")
	var checkpoint := Catalog.initial_checkpoint(level)
	var pairs: Array = []
	var checkpoints: Array = [checkpoint]
	for stage: Dictionary in level.stages:
		var a := Physical.new()
		_check(a.reset(level,stage.id,checkpoint,{},"a",8),"Dense source admits exact8")
		for frame: Dictionary in Physical.expand_recording_inputs(_fixture("cooperative/"+stage.id+"-a")):
			_dense_step(a,frame)
		while not a.finished: _dense_step(a,{})
		_check(a.tick == 900 and a.can_commit(),"Dense source remains actually ready at tick900")
		var first: Dictionary = a.export_recording()
		_check(first.actions.size() == 900,"Every source tick is an independently encoded legal action")
		var b := Physical.new()
		_check(b.reset(level,stage.id,checkpoint,first,"b",8),"Dense receiver admits independent full source")
		var route := Physical.expand_recording_inputs(_fixture("cooperative/"+stage.id+"-b"))
		for frame: Dictionary in route.slice(0,route.size()-1): _dense_step(b,frame)
		while not b.finished and b.tick < 1199: _dense_step(b,{})
		_dense_step(b,{"interact":true})
		_check(b.complete and b.tick == 1200,"Receiver rings the real goal on its final grace tick")
		var second: Dictionary = b.export_recording()
		_check(second.actions.size() == 1200 and second.replay_checks.size() == 40,"Receiver exports all1200 actions and40 regular checks")
		var derived := Physical.derive_checkpoint(level,checkpoint,first,second)
		_check(derived.valid,"Native verifier accepts the full dense pair")
		if not derived.valid: break
		checkpoint = derived.checkpoint
		pairs.append({"a":first,"b":second}); checkpoints.append(checkpoint)
	if pairs.size() == 2:
		var packet := {"base_revision":4,"branch":1,"idempotency_key":"comfort8-dense-receiver","recording":pairs[1].b,"checkpoint":checkpoint}
		var nodes := _node_count(packet)
		_check(nodes > 24000 and nodes < 32000,"Actual full proof exceeds old24k envelope but fits bounded32k comfort envelope")
		_check(JSON.stringify(packet).to_utf8_buffer().size() <= 327680,"Actual full proof remains inside unchanged request byte limit")
		_check(JSON.stringify(checkpoint).to_utf8_buffer().size() <= 229376 and _node_count(checkpoint) < 24000,"Checkpoint alone preserves retained byte/node limits")
		for pair: Dictionary in pairs:
			for record: Dictionary in [pair.a,pair.b]:
				_check(JSON.stringify(record).to_utf8_buffer().size() <= 65536,"Dense recording fits explicit physical8 recording limit")
		if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args():
			var path := "res://tests/fixtures/comfort8/dense-physical.json"
			_check(not FileAccess.file_exists(path),"Dense evidence is written only to a new fixture")
			if failures == 0:
				DirAccess.make_dir_recursive_absolute("res://tests/fixtures/comfort8")
				var file := FileAccess.open(path,FileAccess.WRITE)
				file.store_string(JSON.stringify({"pairs":pairs,"checkpoints":checkpoints,"packet":packet},"\t")+"\n"); file.close()
		print("COMFORT8 DENSE: %d nodes / %d bytes" % [nodes,JSON.stringify(packet).to_utf8_buffer().size()])
	print("AFTER YOU COMFORT BOUNDS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _dense_step(sim: RefCounted, input: Dictionary) -> void:
	var frame := input.duplicate(true)
	# ±1% on an unused axis quantizes distinctly but rounds to zero centimetres.
	# The other axis retains exactly its original integer-centimetre movement.
	var axis := "move_z" if float(frame.get("move_z",0)) == 0 else "move_x"
	if float(frame.get(axis,0)) != 0:
		_check(false,"Dense witness must not rewrite an authored diagonal input")
		return
	frame[axis] = 0.01 if sim.tick % 2 == 0 else -0.01
	sim.step(frame)

func _node_count(value: Variant) -> int:
	var count := 1
	if value is Dictionary:
		for child: Variant in value.values(): count += _node_count(child)
	elif value is Array:
		for child: Variant in value: count += _node_count(child)
	return count
