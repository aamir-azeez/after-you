extends RefCounted
## A still copy of a live turn's engine, for a worker to export while the turn
## keeps playing on the main thread. RelayJourney's periodic draft save uses
## it: exporting a turn digests the whole recording, which grows every tick,
## so on the main thread it became a hitch once a second that kept growing.
## Taking the copy costs about the same at the end of a turn as at its start.
##
## Every engine sets the SHARED fields only when a turn is set up, each to its
## own deep copy, and never changes them in place afterwards, so the copy reads
## them alongside the live engine. The two lists that grow through a turn only
## ever append, and only their newest entry changes (the moves list counts
## another tick on its last entry); setting up a turn starts new lists. So the
## copy takes those lists' earlier entries as they are and copies the newest.
## Everything else (players, mechanisms) changes each tick and is copied. An
## engine held inside another is copied the same way: the sleeping-lighthouse@2
## facade keeps its whole turn in the engine it drives (_inner), and that
## engine's state hash reads the partner's replay beside a second turn too.
## Other objects are left out: no engine exports through one.
const SHARED := ["level", "stage", "_checkpoint", "_prior", "_prior_frames"]
const APPEND_ONLY := ["_actions", "_checks"]
const MAX_DEPTH := 3

static func of(simulation: RefCounted, depth: int = 0) -> RefCounted:
	var copy: RefCounted = simulation.get_script().new()
	for property: Dictionary in simulation.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var name: String = property.name
		var value: Variant = simulation.get(name)
		if value is Object:
			if not value is RefCounted or value.get_script() == null or depth >= MAX_DEPTH or not _plain(value.get_script()): continue
			value = of(value, depth + 1)
		elif name in APPEND_ONLY and value is Array:
			var entries: Array = value.duplicate()
			if not entries.is_empty() and entries[-1] is Dictionary: entries[-1] = entries[-1].duplicate(true)
			value = entries
		elif name not in SHARED and (value is Dictionary or value is Array):
			value = value.duplicate(true)
		copy.set(name, value)
	return copy

## An engine script whose instances need no arguments to make.
static func _plain(script: Script) -> bool:
	for method: Dictionary in script.get_script_method_list():
		if method.name == "_init" and method.args.size() > method.default_args.size(): return false
	return true
