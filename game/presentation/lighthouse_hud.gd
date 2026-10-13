extends RefCounted
## The Sleeping Lighthouse turn HUD for one native engine snapshot: beams,
## holds, the ordered paths, the lens hand-off and the beacon. Shared by the
## solo screen (sleeping-lighthouse@1) and the shared chapter screen playing
## sleeping-lighthouse@2, so both show the same words at the same moment.
## Pure: no node, no state; `stage` is the native stage definition.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")

static func display(state: Dictionary, stage: Dictionary) -> Dictionary:
	var display := state.duplicate()
	var cumulative_holds := int(state.get("simulation_version", Simulation.LEGACY_SIMULATION_VERSION)) == Simulation.CURRENT_SIMULATION_VERSION
	var signals: Dictionary = state.get("receiver_goal", {}).get("signals", {})
	if not signals.is_empty():
		var lit := 0
		for value: Variant in signals.values():
			if value == true: lit += 1
		display.progress_message = "Beams together: %d / %d" % [lit, signals.size()]
		display.objective_display = {"label": PlayerCopy.LIGHTHOUSE_PREVIEW_D286213698F0, "current": lit, "required": signals.size()}
	if str(state.get("role", "")) == "a" and state.has("hold_ticks") and not state.has("sequence") and not state.has("handoff"):
		var required := int(stage.get("source_policy", {}).get("minimum_hold_ticks", Simulation.MIN_HOLD_TICKS))
		if required > 1:
			display.objective_display = {"label": PlayerCopy.LIGHTHOUSE_PREVIEW_7D9E3287C90C, "current": float(state.hold_ticks) / Simulation.TICK_RATE,
				"required": float(required) / Simulation.TICK_RATE, "unit": "seconds",
				"detail": PlayerCopy.LIGHTHOUSE_PREVIEW_DDC41A9DE09F if state.get("can_commit", false) else str(state.get("commit_reason", ""))}
	if state.has("sequence"):
		var sequence: Dictionary = state.sequence
		display.erase("objective_display")
		var phase := str(sequence.get("phase", "off"))
		if cumulative_holds and phase == "second" and display.get("context_action", {}).get("id", "") == "select_path":
			display.context_action = display.context_action.duplicate()
			display.context_action.label = "Action"
		if str(state.get("role", "")) == "a":
			var required: Array = sequence.get("required_ticks", [])
			if sequence.get("broken", false):
				display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_DE83BF374773
			elif phase == "off":
				display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_8BD43A5CB9A6
			elif required.size() == 2:
				var elapsed := int(sequence.get(phase + "_ticks", 0))
				var target := int(required[0 if phase == "first" else 1])
				var next := PlayerCopy.LIGHTHOUSE_PREVIEW_06D97CF8BBB0 if elapsed < target else PlayerCopy.LIGHTHOUSE_PREVIEW_6EB851761E97 if phase == "first" else PlayerCopy.LIGHTHOUSE_PREVIEW_DDC41A9DE09F if state.get("can_commit", false) else PlayerCopy.LIGHTHOUSE_PREVIEW_B7D36B943CC3
				if cumulative_holds and phase == "second" and elapsed >= target and not state.get("can_commit", false):
					next = PlayerCopy.from_canonical(str(state.get("commit_reason", PlayerCopy.LIGHTHOUSE_PREVIEW_06D97CF8BBB0)))
				display.progress_message = "%s path · %.1f / %.1f s\n%s" % [phase.capitalize(), float(elapsed) / Simulation.TICK_RATE, float(target) / Simulation.TICK_RATE, next]
				display.objective_display = {"label": PlayerCopy.LIGHTHOUSE_PREVIEW_3FEAADB6698F % phase.capitalize(), "current": float(elapsed) / Simulation.TICK_RATE, "required": float(target) / Simulation.TICK_RATE, "unit": "seconds", "detail": next}
		else:
			var reached := int(state.get("route_progress", {}).get("step", 0))
			var first_open := phase == "first"
			var second_open := phase == "second"
			var first_hint := PlayerCopy.LIGHTHOUSE_PREVIEW_5BDAA3E15024 if first_open else PlayerCopy.LIGHTHOUSE_PREVIEW_4499AA040CB9 if phase == "off" else PlayerCopy.LIGHTHOUSE_PREVIEW_88C07E403BF7
			if cumulative_holds and not first_open:
				first_hint = PlayerCopy.LIGHTHOUSE_PREVIEW_4499AA040CB9
			var rest_hint := PlayerCopy.LIGHTHOUSE_PREVIEW_D7AE1ED2893C if second_open else PlayerCopy.LIGHTHOUSE_PREVIEW_C2AC8F270DB6
			var milestones := [first_hint, PlayerCopy.LIGHTHOUSE_PREVIEW_C1D7295EFDDA, rest_hint, PlayerCopy.LIGHTHOUSE_PREVIEW_E4B624E028B0, PlayerCopy.LIGHTHOUSE_PREVIEW_4D47D03902BF]
			display.progress_message = milestones[clampi(reached, 0, milestones.size() - 1)]
	if state.has("handoff"):
		display.erase("objective_display")
		var handoff: Dictionary = state.handoff
		var local_role := str(state.get("role", ""))
		var prop: Dictionary = state.get("props", {}).get(handoff.get("prop_id", ""), {})
		if handoff.get("authority", "") == "source":
			display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_E1B989F40743 if local_role == "a" else PlayerCopy.LIGHTHOUSE_PREVIEW_384D841A26F0
		elif handoff.get("authority", "") == "offered":
			if local_role == "a":
				display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_36FD8BD84EAF if state.get("can_commit", false) else PlayerCopy.LIGHTHOUSE_PREVIEW_D92D80808C6B
			else:
				display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_916B79F531D4
		elif prop.get("status", "") == "fitted":
			display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_632EBC193BA2
		else:
			display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_A8E0D7FD415B
	if state.has("beacon"):
		var beacon: Dictionary = state.beacon
		if beacon.get("lit", false):
			display.erase("objective_display")
			display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_B5589046FF13
		elif str(state.get("role", "")) == "a":
			if state.get("can_commit", false):
				display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_287401669977
			else:
				display.progress_message = PlayerCopy.LIGHTHOUSE_PREVIEW_A9FFB8248733
				display.message = str(state.get("commit_reason", stage.hint_a))
		else:
			var lit := 0
			for value: Variant in beacon.get("signals", {}).values():
				if value == true: lit += 1
			var next := PlayerCopy.LIGHTHOUSE_PREVIEW_88274E656354 if beacon.get("ready", false) else PlayerCopy.LIGHTHOUSE_PREVIEW_810A63400300
			if state.get("context_action", {}).get("id", "") == "light_beacon" and state.context_action.get("enabled", false): next = PlayerCopy.LIGHTHOUSE_PREVIEW_ADDFE326F53E
			display.progress_message = "Two lights: %d / 2\n%s" % [lit, next]
			display.objective_display = {"label": PlayerCopy.LIGHTHOUSE_PREVIEW_5968E7393343, "current": lit, "required": 2, "detail": next}
	return display
