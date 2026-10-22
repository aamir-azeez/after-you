extends RefCounted
## The reaction faces, in one place: the end-of-run picker
## (presentation/end_reactions.gd), reactions made during a run
## (presentation/run_reactions.gd), what this phone keeps of either and their
## playback all read this list. Ids are the server's (backend
## src/v2/end-reactions.ts FACES) and never change: rooms, recordings' tracks and
## files keep them. A face's screen reader name is PlayerCopy.END_REACTION_NAMES.
const Look = preload("res://presentation/spirit_look.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

## The picker's order (design 4's order with Knocked out in Normal's place),
## then the heart.
const FACES: Array[String] = ["happy", "squeeze", "surprised", "sad", "annoyed", "angry", "sleepy", "knocked_out", "heart"]
const HEART := "heart"
## The spirit expression each face draws (spirit_look.gd); the heart, an icon
## only, draws none.
const EXPRESSIONS := {"happy": Look.HAPPY, "squeeze": Look.SQUEEZE, "surprised": Look.SURPRISED, "sad": Look.SAD,
	"annoyed": Look.ANNOYED, "angry": Look.ANGRY, "sleepy": Look.SLEEPY, "knocked_out": Look.KNOCKED_OUT}
## The face a spirit makes for the heart while it shows over it: ^ ^ with
## pink cheeks, its own 3D face (the picker and bubbles draw the heart icon).
const HEART_EXPRESSION := Look.JOY

static func is_face(value: Variant) -> bool:
	return value is String and value in FACES

## The expression a face draws, or &"" for the heart.
static func expression(face: String) -> StringName:
	return EXPRESSIONS.get(face, &"")

## The expression a spirit makes for a face: its own, or HEART_EXPRESSION.
static func spirit_expression(face: String) -> StringName:
	return HEART_EXPRESSION if face == HEART else expression(face)

static func face_name(face: String) -> String:
	return str(PlayerCopy.END_REACTION_NAMES.get(face, ""))
