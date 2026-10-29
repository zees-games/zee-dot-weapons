extends RefCounted

## The built gloved hand, the sleeve stretch and the flat material of [ZeeViewArms]. No `class_name`: it preloads this by path.

## The radius of the cylinder a fist closes round.
const GRIP_RADIUS := 0.017


## A gloved fist closed round a cylinder of [constant GRIP_RADIUS] along +Y, at the origin.
## The forearm leaves along +Z and the back of the hand faces +X; the index finger is the +Y
## end, so a pistol grip's top and a fore-end's muzzle end are +Y.
##
## [b]Boxes, merged into one mesh.[/b] Twelve boxes in a ring are a blocky fist in the
## world's own blocky style, built in code with no model to license; one surface is one draw.
static var _glove_cache: ArrayMesh = null

static func mesh() -> ArrayMesh:
	if _glove_cache != null:
		return _glove_cache

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := GRIP_RADIUS
	var add := func(size: Vector3, at: Vector3, turn_y: float = 0.0, turn_x: float = 0.0) -> void:
		var box := BoxMesh.new()
		box.size = size
		var basis := Basis(Vector3.UP, deg_to_rad(turn_y)) * Basis(Vector3.RIGHT, deg_to_rad(turn_x))
		st.append_from(box, 0, Transform3D(basis, at))

	# A core inside the ring: hidden by whatever the hand holds, and what an empty fist shows
	# instead of a hole straight through it.
	add.call(Vector3(r * 1.6, 0.078, r * 1.6), Vector3.ZERO)
	# The back of the hand: a slab on the +X side running back to the wrist.
	add.call(Vector3(0.026, 0.084, 0.085), Vector3(r + 0.016, 0.0, 0.03))
	# The heel of the palm, filling between the back and the wrist on the near side.
	add.call(Vector3(0.03, 0.07, 0.04), Vector3(r * 0.4, -0.004, r + 0.026))
	# Four fingers as one band in three segments, wrapping from the knuckles (+X) round the
	# far side (-Z) to the palm side (-X). Each segment is turned to its place on the ring.
	var ring := r + 0.012
	# Overlapping, so no light shows between them at the outside of the ring.
	for step: Array in [[20.0, 0.04], [62.0, 0.04], [104.0, 0.04], [146.0, 0.038], [186.0, 0.03]]:
		var phi: float = step[0]
		var at := Vector3(cos(deg_to_rad(phi)) * ring, 0.0, -sin(deg_to_rad(phi)) * ring)
		add.call(Vector3(0.022, 0.08, float(step[1])), at, phi)
	# Knuckle ridge.
	add.call(Vector3(0.016, 0.086, 0.02), Vector3(r + 0.03, 0.0, -0.006))
	# The thumb, from the heel round the near side (+Z) to the far (-X), at the index end.
	for step: Array in [[-40.0, 0.036], [-90.0, 0.036], [-140.0, 0.03]]:
		var phi: float = step[0]
		var at := Vector3(cos(deg_to_rad(phi)) * ring, 0.028, -sin(deg_to_rad(phi)) * ring)
		add.call(Vector3(0.021, 0.022, float(step[1])), at, phi)
	# No wrist here: the cuff is a tube from the heel of the palm toward the real shoulder, so
	# a hand turned on its wrist bends there instead of carrying a box out sideways.

	st.generate_normals()
	_glove_cache = st.commit()
	return _glove_cache


## Stretches a unit cylinder (height 1 along Y, radius 0.5) between [param from] and [param to].
static func tube(node: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	var along := to - from
	var length := along.length()
	if length < 0.001:
		node.visible = false
		return
	node.visible = true
	var y := along / length
	var side := y.cross(Vector3.BACK)
	if side.length() < 0.01:
		side = y.cross(Vector3.RIGHT)
	side = side.normalized()
	var depth := side.cross(y).normalized()
	# The cylinder's top (+Y, the wider end) at the shoulder.
	node.transform = Transform3D(Basis(side * width, y * length, depth * width), (from + to) * 0.5)


static func flat(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	return m
