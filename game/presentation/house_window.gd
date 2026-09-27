extends RefCounted
## The same open shutter/window assembly can decorate a house or a goal.
## It carries no interaction, navigation or completion state of its own.

static func build(host: Variant, parent: Node3D, rear: Vector3, width: float, frame: Color, glass: Color, cream: Color) -> Dictionary:
	var pane: MeshInstance3D = host.box(Vector3(width-0.12,0.60,0.025),glass,rear+Vector3(0,0.80,0.035),parent)
	host.box(Vector3(width+0.10,0.065,0.24),frame,rear+Vector3(0,0.45,0.03),parent)
	for side: int in [-1,1]:
		host.box(Vector3(0.055,0.70,0.08),frame,rear+Vector3(side*width*0.5,0.80,0.06),parent)
	host.box(Vector3(width,0.055,0.08),frame,rear+Vector3(0,1.15,0.06),parent)
	host.box(Vector3(0.04,0.66,0.04),frame,rear+Vector3(0,0.80,0.06),parent)
	var shutters: Array[Node3D] = []
	for side: int in [-1,1]:
		var shutter := Node3D.new()
		shutter.position = rear+Vector3(side*width*0.5,0.80,0.10)
		shutter.set_meta("side",side)
		parent.add_child(shutter)
		host.box(Vector3(width*0.46,0.64,0.065),Color("628c7a"),Vector3(-side*width*0.23,0,0),shutter)
		for y: float in [-0.18,0.18]:
			host.box(Vector3(width*0.40,0.045,0.028),cream,Vector3(-side*width*0.23,y,0.04),shutter)
		shutters.append(shutter)
	return {"pane":pane,"shutters":shutters}

static func present(host: Variant, window: Dictionary, lit: bool, color: Color) -> void:
	host._glow(window.pane,color,0.65 if lit else 0.0)
	for shutter: Node3D in window.shutters:
		shutter.rotation.y = -float(shutter.get_meta("side"))*2.25 if lit else 0.0
