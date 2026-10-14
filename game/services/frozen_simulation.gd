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
## Everything else (players, mechanisms) changes each tick and is copied. A
## nested engine (the partner's turn replaying beside a second turn) is only
## ever stepped, never exported, so it is left out.
const SHARED := ["level", "stage", "_checkpoint", "_prior", "_prior_frames"]
const APPEND_ONLY := ["_actions", "_checks"]

static func of(simulation: RefCounted) -> RefCounted:
	var copy: RefCounted = simulation.get_script().new()
	for property: Dictionary in simulation.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var name: String = property.name
		var value: Variant = simulation.get(name)
		if value is Object: continue
		if name in APPEND_ONLY and value is Array:
			var entries: Array = value.duplicate()
			if not entries.is_empty() and entries[-1] is Dictionary: entries[-1] = entries[-1].duplicate(true)
			value = entries
		elif name not in SHARED and (value is Dictionary or value is Array):
			value = value.duplicate(true)
		copy.set(name, value)
	return copy
