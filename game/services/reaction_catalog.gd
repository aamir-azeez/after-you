extends RefCounted
## The reaction faces, in one place: the end-of-run picker
## (presentation/end_reactions.gd), reactions made during a run
## (presentation/run_reactions.gd), what this phone keeps of either and their
## playback all read this list. Ids are the server's (backend
## src/v2/end-reactions.ts FACES) and never change: rooms, recordings' tracks and
## files keep them. A face's screen reader name is PlayerCopy.END_REACTION_NAMES.
##
## Two kinds of face: the everyday faces (FACES) are everyone's; the pack faces
## belong to reaction packs (PACKS, sold in the Wardrobe; services/face_packs.gd
## says which this player may send now). Any phone draws a friend's pack face.
## A well-formed id this build does not know (a pack added later) draws as
## FALLBACK_FACE and is never sent.
const Look = preload("res://presentation/spirit_look.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

## The picker's order (design 4's order with Knocked out in Normal's place),
## then the heart.
const FACES: Array[String] = ["happy", "squeeze", "surprised", "sad", "annoyed", "angry", "sleepy", "knocked_out", "heart"]
const HEART := "heart"
## The reaction packs by id (backend src/pollen/catalog.json packs), in shelf
## order, each with its faces in picker order.
const PACKS := {"garden_faces": ["heart_eyes", "proud", "wink"], "big_feelings": ["wow", "crying", "dizzy"]}
## Every pack face, in PACKS order.
const PACK_FACES: Array[String] = ["heart_eyes", "proud", "wink", "wow", "crying", "dizzy"]
## What a well-formed face id this build does not know draws as.
const FALLBACK_FACE := "happy"
const ID_PATTERN := "^[a-z0-9_]{1,40}$"
## The spirit expression each face draws (spirit_look.gd); the heart, an icon
## only, draws none.
const EXPRESSIONS := {"happy": Look.HAPPY, "squeeze": Look.SQUEEZE, "surprised": Look.SURPRISED, "sad": Look.SAD,
	"annoyed": Look.ANNOYED, "angry": Look.ANGRY, "sleepy": Look.SLEEPY, "knocked_out": Look.KNOCKED_OUT,
	"heart_eyes": Look.HEART_EYES, "proud": Look.PROUD, "wink": Look.WINK, "wow": Look.WOW, "crying": Look.CRYING, "dizzy": Look.DIZZY}
## The face a spirit makes for the heart while it shows over it: ^ ^ with
## pink cheeks, its own 3D face (the picker and bubbles draw the heart icon).
const HEART_EXPRESSION := Look.JOY

static var _id := RegEx.create_from_string(ID_PATTERN)

## A face this build knows: an everyday face or a pack face.
static func is_face(value: Variant) -> bool:
	return value is String and (value in FACES or value in PACK_FACES)

static func is_pack_face(value: Variant) -> bool:
	return value is String and value in PACK_FACES

## The pack a face belongs to, or "" for an everyday face.
static func pack_of(face: String) -> String:
	for pack: String in PACKS:
		if face in PACKS[pack]: return pack
	return ""

## A face that came from elsewhere (a friend's turn, a newer server) as this
## build draws it: a known face as it is, any other well-formed id as
## FALLBACK_FACE, anything else "".
static func shown_face(value: Variant) -> String:
	if is_face(value): return value
	return FALLBACK_FACE if value is String and _id.search(value) != null else ""

## The expression a face draws, or &"" for the heart.
static func expression(face: String) -> StringName:
	return EXPRESSIONS.get(face, &"")

## The expression a spirit makes for a face: its own, or HEART_EXPRESSION.
static func spirit_expression(face: String) -> StringName:
	return HEART_EXPRESSION if face == HEART else expression(face)

static func face_name(face: String) -> String:
	return str(PlayerCopy.END_REACTION_NAMES.get(face, ""))

static func pack_name(pack: String) -> String:
	return str(PlayerCopy.FACE_PACK_NAMES.get(pack, ""))
