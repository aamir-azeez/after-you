extends RefCounted
## Descriptor for the Paper boat cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "paper_boat",
	"slot": "hat",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_PAPER_BOAT,
	"art": "res://presentation/pip_wear/paper_boat.gd",
	"code": 200,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
	## Its raised end hangs out past the head on the side the views turn away.
	"wide": true,
	## The leaf comes out of the boat itself: it rises from inside the hull up
	## through the sail's middle and pokes out of the top, its root at this
	## point (head space) while the boat is worn (kit/wear_fit.gd). Where it
	## passes through the paper it may clip.
	"leaf_mode": "sits_on_top",
	"leaf_at": Vector3(0.194, 0.478, -0.025),
	"leaf_max": "tall",
}
