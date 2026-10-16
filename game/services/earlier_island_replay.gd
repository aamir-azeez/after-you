extends RefCounted
## Prepares an earlier island's saved replay to play: checks the recording
## against its island and attempt, then builds the simulation that plays it.
##
## It runs on a worker. It reads only the private copies in job
## ({"definition", "attempt", "recording", "version"}) and reports through the
## mutex-backed ReplayLoadProgress, never the live save or a scene node.
const LocalSave = preload("res://services/local_save.gd")
const TurnState = preload("res://services/turn_state.gd")
const Simulation = preload("res://core/simulation.gd")

## {"ok": true, "simulation", "frames"}, or {"ok": false} with an "error" when
## the check failed rather than being cancelled.
static func prepare(job: Dictionary, progress: RefCounted) -> Dictionary:
	var recording: Dictionary=job.recording
	var prior: Dictionary=LocalSave.normalize_attempt(job.attempt).a if recording.get("role") == "b" else {}
	var ticks := clampi(int(recording.duration_ticks),0,Simulation.RECEIVER_TICKS) if Simulation._is_integer(recording.get("duration_ticks")) else 0
	var prior_ticks := clampi(int(prior.duration_ticks),0,Simulation.RECEIVER_TICKS) if Simulation._is_integer(prior.get("duration_ticks")) else 0
	progress.set_total(ticks+2*prior_ticks+2)
	progress.set_phase("checking")
	if progress.cancelled(): return {"ok":false}
	var check: Dictionary=TurnState.review(job.definition,recording,job.attempt,int(job.version),progress)
	if not check.valid: return {"ok":false,"error":check.get("error","")}
	progress.advance()
	progress.set_phase("preparing")
	var prepared := Simulation.new()
	prepared.catch_assistance=bool(recording.get("catch_assistance",true))
	if not prepared.reset(job.definition,prior,str(recording.role),int(recording.simulation_version),progress): return {"ok":false,"error":prepared.error}
	if progress.cancelled(): return {"ok":false}
	var frames := Simulation.expand_recording_inputs(recording)
	progress.advance()
	progress.set_phase("ready")
	return {"ok":true,"simulation":prepared,"frames":frames}
