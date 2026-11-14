extends RefCounted
## The face cosmetics, in one table (content/cosmetics/index.gd reads ROWS
## beside its descriptor files): the single reaction faces, the resting faces
## and the two extra reaction slots. Same fields as a descriptor
## (content/cosmetics/index.gd); a row needs no art script because the face
## shader draws every face from its recipe (presentation/spirit_look.gd eye(),
## keyed by the same id).
##
## - Reaction faces (slot "reaction"): owned, never worn. A face's id is its
##   reaction id everywhere (rooms, recordings' tracks, backend
##   src/v2/end-reactions.ts SINGLE_FACES and PACK_FACES) and its spirit
##   expression. "moving": the face moves on the pip's face clock.
## - Resting faces (slot "rest_face"): worn like a hat; the pip shows it in
##   place of the Normal face. Classic, the face every pip has, is wearing none.
## - Reaction slots (slot "reaction_slot"): each one owned opens one more of
##   the six slots past the four free ones (services/reaction_slots.gd).
## Codes take the 400s block, in this order (tests/fixtures/cosmetic_codes.json).
const PlayerCopy = preload("res://presentation/player_copy.gd")

const ROWS := [
	{"id": "aww", "code": 400, "slot": "reaction", "tier": "face_common", "name": PlayerCopy.FACE_AWW, "art": ""},
	{"id": "shy", "code": 401, "slot": "reaction", "tier": "face_common", "name": PlayerCopy.FACE_SHY, "art": ""},
	{"id": "huh", "code": 402, "slot": "reaction", "tier": "face_common", "name": PlayerCopy.FACE_HUH, "art": ""},
	{"id": "please", "code": 403, "slot": "reaction", "tier": "face_uncommon", "name": PlayerCopy.FACE_PLEASE, "art": ""},
	{"id": "touched", "code": 404, "slot": "reaction", "tier": "face_uncommon", "name": PlayerCopy.FACE_TOUCHED, "art": ""},
	{"id": "lucky", "code": 405, "slot": "reaction", "tier": "face_uncommon", "name": PlayerCopy.FACE_LUCKY, "art": ""},
	{"id": "giggle", "code": 406, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_GIGGLE, "art": "", "moving": true},
	{"id": "curious", "code": 407, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_CURIOUS, "art": "", "moving": true},
	{"id": "nervous", "code": 408, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_NERVOUS, "art": "", "moving": true},
	{"id": "drowsy", "code": 409, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_DROWSY, "art": "", "moving": true},
	{"id": "gasp", "code": 410, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_GASP, "art": "", "moving": true},
	{"id": "peekaboo", "code": 411, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_PEEKABOO, "art": "", "moving": true},
	{"id": "yay", "code": 412, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_YAY, "art": "", "moving": true},
	{"id": "smitten", "code": 413, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_SMITTEN, "art": "", "moving": true},
	{"id": "starry", "code": 414, "slot": "reaction", "tier": "face_rare", "name": PlayerCopy.FACE_STARRY, "art": "", "moving": true},
	{"id": "flower", "code": 415, "slot": "reaction", "tier": "face_epic", "name": PlayerCopy.FACE_FLOWER, "art": "", "moving": true},
	# The pack faces, sold one at a time; a pack's owner owns its three already.
	{"id": "heart_eyes", "code": 416, "slot": "reaction", "tier": "face_uncommon", "name": PlayerCopy.FACE_HEART_EYES, "art": ""},
	{"id": "proud", "code": 417, "slot": "reaction", "tier": "face_common", "name": PlayerCopy.FACE_PROUD, "art": ""},
	{"id": "wink", "code": 418, "slot": "reaction", "tier": "face_common", "name": PlayerCopy.FACE_WINK, "art": ""},
	{"id": "wow", "code": 419, "slot": "reaction", "tier": "face_uncommon", "name": PlayerCopy.FACE_WOW, "art": ""},
	{"id": "crying", "code": 420, "slot": "reaction", "tier": "face_uncommon", "name": PlayerCopy.FACE_CRYING, "art": ""},
	{"id": "dizzy", "code": 421, "slot": "reaction", "tier": "face_uncommon", "name": PlayerCopy.FACE_DIZZY, "art": ""},
	# Resting faces, on the hat tiers.
	{"id": "rest_button", "code": 422, "slot": "rest_face", "tier": "common", "name": PlayerCopy.REST_FACE_BUTTON, "art": ""},
	{"id": "rest_bean", "code": 423, "slot": "rest_face", "tier": "common", "name": PlayerCopy.REST_FACE_BEAN, "art": ""},
	{"id": "rest_round", "code": 424, "slot": "rest_face", "tier": "uncommon", "name": PlayerCopy.REST_FACE_ROUND, "art": ""},
	{"id": "rest_wide", "code": 425, "slot": "rest_face", "tier": "uncommon", "name": PlayerCopy.REST_FACE_WIDE, "art": ""},
	{"id": "rest_sprout", "code": 426, "slot": "rest_face", "tier": "uncommon", "name": PlayerCopy.REST_FACE_SPROUT, "art": ""},
	# The two reaction slots past the four free ones.
	{"id": "reaction_slot_5", "code": 427, "slot": "reaction_slot", "tier": "reaction_slot", "name": PlayerCopy.REACTION_SLOT_FIFTH, "art": ""},
	{"id": "reaction_slot_6", "code": 428, "slot": "reaction_slot", "tier": "reaction_slot", "name": PlayerCopy.REACTION_SLOT_SIXTH, "art": ""},
]
