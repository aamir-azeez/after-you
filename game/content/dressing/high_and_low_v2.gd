extends RefCounted
## High and Low, version 2: version 1's meadow, with the shore's hedge ending
## short of the signpost, so the two no longer stand in each other.

const V1 = preload("res://content/dressing/high_and_low.gd")

const DATA := {
	"look": V1.DATA.look,
	"tag": V1.DATA.tag,
	"barrier": V1.DATA.barrier,
	"ground": V1.DATA.ground,
	"stairs": V1.DATA.stairs,
	"cables": V1.DATA.cables,
	"lever": V1.DATA.lever,
	"selector": V1.DATA.selector,
	"pad": V1.DATA.pad,
	"goal": V1.DATA.goal,
	"lift": V1.DATA.lift,
	"deck": V1.DATA.deck,
	"raft": V1.DATA.raft,
	"ladder": V1.DATA.ladder,
	"fog": V1.DATA.fog,
	"spillway": V1.DATA.spillway,
	"carried_item": V1.DATA.carried_item,
	"current": V1.DATA.current,
	"seabed": V1.DATA.seabed,
	"bridges": V1.DATA.bridges,
	"props": {"*": V1.SHORE_BACK + [{"kind": "hedge", "from": [-690, -200], "to": [-690, 170], "surface": "shore", "y": 12}] + V1.REST},
}
