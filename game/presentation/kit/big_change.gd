extends RefCounted
## A big change: a piece whose move players should notice wherever it is,
## even off screen. While it moves the view shakes a little (the camera kit,
## presentation/camera_exploration.gd shake()), and a move the player's own
## turn caused (theirs or their memory's, never a replay's) gives the phone a
## short soft buzz through the soundscape's haptics, which the Haptics setting
## turns off. Its sound is the shared sound map's (services/chapter_sound_map.gd),
## never this file's: a cue's pitch must follow the recorded tick, and a world
## only sees the ticks it shows.
##
## A world reports a piece that starts to move with note_big_change(kind, id,
## seconds) (presentation/island_world.gd); the kinds below turn it on.
## Pieces that could join later, each one line here once their world reports
## it: the lift, the well's bucket, ladder and folds, water levels, the sea
## gates (which snap today) and the new pieces' crossings that rise and sink
## (kit/pieces/bridge.gd).
const KINDS := {
	# Island worlds' classic drawbridge (island_world _move_bridge).
	"drawbridge": true,
	# A winch's ramp over moving water (kit/ramp_rules.gd, tide_world).
	"ramp": true,
}
## The shake: its size as a share of the view's height (so it is the same on
## any screen and zoom), how many times a second it sways, and the most it
## lasts however long a move is. It eases in and fades out, mostly up and down
## like something heavy settling.
const SHAKE := {"size": 0.0035, "hz": 11.0, "max_seconds": 1.5, "ease_in": 0.06}
## A move with no length of its own (a drawbridge that eases into place).
const SECONDS := 0.4
## The buzz, short and soft to match the shake.
const HAPTIC_MS := 22

static func is_big(kind: String) -> bool:
	return bool(KINDS.get(kind, false))

## The shake's offset in the camera's plane (x across, y up), as shares of
## the view's height, `age` seconds into a shake `seconds` long. Zero outside it.
static func offset(age: float, seconds: float) -> Vector2:
	if seconds <= 0.0 or age < 0.0 or age >= seconds: return Vector2.ZERO
	var envelope := smoothstep(0.0, float(SHAKE.ease_in), age) * (1.0 - age / seconds)
	var phase := age * float(SHAKE.hz) * TAU
	return Vector2(sin(phase * 1.37 + 1.1) * 0.4, sin(phase)) * float(SHAKE.size) * envelope
