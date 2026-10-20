extends RefCounted

## A gun's sight line, measured from its own mesh, and the iron sight that marks it.
##
## No `class_name`, on purpose: [ZeeViewModel] preloads it by path. A new global class in an
## addon makes every project that links the addon fail until it is re-imported, and a class
## added by an addon pack overlaid at boot is never registered at all.
##
## [b]Why aiming needs a line and not a place.[/b] Aim used to be one hand-written place
## (`aim_offset`) shared by every blaster: the eye level with the middle of the gun's back,
## which drew the pale rear face of the gun across the bottom of the screen. Aiming down
## sights is the eye on a line through two points on top of the gun, a rear sight and a
## front one; centre that line on the screen and the front sight sits on the crosshair and
## the top of the gun runs away below it, whatever the model's shape. So the line is
## measured, per model, like the muzzle.
##
## [b]Measured by casting down onto the mesh, not from its bounds.[/b] The kit's guns are
## low-poly with long faces, so a slice of vertices at a station along the barrel is often
## empty, and the bounds' top is a fin or a drum somewhere else on the gun. A ray straight
## down at a station hits the face that is really there.
##
## [b]Every gun gets the sight built, rather than looking for one in the model.[/b] Not one
## blaster in the kit has a readable iron sight (they are toys: fins and drums), and a sight
## guessed from a bump on the top is a bump the eye cannot line anything up with. The sight
## is the line drawn: a ring round a post at the front, a notch at the rear, both rising from
## the gun's own top to the line, in the colour of the part they stand on.

## How far back along the gun the rear sight stands, from its back end. Behind the grip
## (0.30), where a rear sight is: further back, it was so close to the eye that the notch
## filled the middle of the screen.
const REAR_STATION := 0.35

## How far along the front sight stands: just short of the muzzle, clear of a brake or a tip.
const FRONT_STATION := 0.88

## The ring's radius as a fraction of the gun's width, clamped (model metres).
const RING_OF_WIDTH := 0.40
const RING_MIN := 0.03
const RING_MAX := 0.07

## The ring's angular radius at full aim, which the view model sizes it to: the rifle's ring
## at 0.4 of its width came out at about this and read right beside the reference picture,
## while the second pack's slimmer, real-sized guns drew a ring a third the size at the
## same fraction. Clamped to [constant RING_FIT_MIN] - [constant RING_FIT_MAX] model metres.
const RING_DEGREES := 4.8
const RING_FIT_MIN := 0.02
const RING_FIT_MAX := 0.12


## Measures [param weapon]'s sight line in [param space]'s coordinates (the holder: the
## model's own space). [param forward] is the art's `model_forward`, model +Y is up.
##
## Returns `{}` when there is nothing to measure (no mesh data, a gun pointing up), or:
## `rear` and `front` (the two sight points, on the line), `ring` (radius, from the width
## until [method with_ring] resizes it), `top` (the highest top the line clears), `rear_top` and
## `front_top` (the gun's top under each), `width`, `back` (the gun's back end along the
## line, for keeping the stock in front of the near plane), and `rear_paint` / `front_paint`
## (`{material, uv}` of the face each sight stands on).
## Node names a model gives its own sight line (see [method from_marks]).
const MARK_REAR := "sight_rear"
const MARK_FRONT := "sight_front"


static func measure(weapon: Node, space: Node3D, forward: Vector3) -> Dictionary:
	var f := forward.normalized()
	if f == Vector3.ZERO or absf(f.dot(Vector3.UP)) > 0.5:
		return {}
	var up := Vector3.UP
	var side := up.cross(f).normalized()

	var triangles := _triangles(weapon, space)
	if triangles.is_empty():
		return {}

	var t_min := INF
	var t_max := -INF
	var s_min := INF
	var s_max := -INF
	var y_max := -INF
	for tri: Dictionary in triangles:
		for p: Vector3 in [tri.a, tri.b, tri.c]:
			t_min = minf(t_min, p.dot(f))
			t_max = maxf(t_max, p.dot(f))
			s_min = minf(s_min, p.dot(side))
			s_max = maxf(s_max, p.dot(side))
			y_max = maxf(y_max, p.y)
	var length := t_max - t_min
	var width := s_max - s_min
	if length <= 0.0 or width <= 0.0:
		return {}
	var centre := (s_min + s_max) * 0.5

	var rear := _top_near(triangles, f, side, centre, lerpf(t_min, t_max, REAR_STATION), length, y_max, width)
	var front := _top_near(triangles, f, side, centre, lerpf(t_min, t_max, FRONT_STATION), length, y_max, width)
	if rear.is_empty() or front.is_empty():
		return {}

	# The line clears everything between the two sights: the eye looks along it, and a fin
	# or a drum above it would stand in front of the front sight.
	var top := maxf(rear.y, front.y)
	for i in range(25):
		var t := lerpf(rear.t, front.t, i / 24.0)
		for off: float in [-0.2, 0.0, 0.2]:
			var hit := _top_at(triangles, f, side, centre + off * width, t, y_max)
			if not hit.is_empty():
				top = maxf(top, hit.y)

	var ring := clampf(width * RING_OF_WIDTH, RING_MIN, RING_MAX)
	return with_ring({
		"rear": f * rear.t + side * centre,
		"front": f * front.t + side * centre,
		"back": f * t_min + side * centre,
		"top": top,
		"rear_top": rear.y,
		"front_top": front.y,
		"width": width,
		"rear_paint": {"material": rear.material, "uv": rear.uv},
		"front_paint": {"material": front.material, "uv": front.uv},
	}, ring)


## The line a model marks for itself: two nodes named [constant MARK_REAR] and
## [constant MARK_FRONT] (a gun with real sights, modelled; zed-dot-weapons' baked carbine),
## in [param space]. Empty when the model has no marks. The line is used as it is: no ring
## is fitted and no sight is built, because the model's own sights are what the eye lines up.
static func from_marks(weapon: Node, space: Node3D, forward: Vector3) -> Dictionary:
	var rear := weapon.find_child(MARK_REAR, true, false) as Node3D
	var front := weapon.find_child(MARK_FRONT, true, false) as Node3D
	if rear == null or front == null:
		return {}
	var to_space := space.global_transform.affine_inverse()
	var r := to_space * rear.global_transform.origin
	var fr := to_space * front.global_transform.origin
	# The back end, for the eye relief: the furthest point behind the rear mark along forward.
	var f := forward.normalized()
	var back_t := r.dot(f)
	for tri: Dictionary in _triangles(weapon, space):
		for p: Vector3 in [tri.a, tri.b, tri.c]:
			back_t = minf(back_t, p.dot(f))
	return {"rear": r, "front": fr, "back": r + f * (back_t - r.dot(f)), "marked": true}


## [param line] with a ring of radius [param ring] (model metres): the ring's centre is the
## line, standing on the highest top between the sights, so the line's height follows it.
## The view model sizes the ring by how far from the eye it ends up (see [constant RING_DEGREES]).
static func with_ring(line: Dictionary, ring: float) -> Dictionary:
	var out := line.duplicate()
	var height: float = float(line.top) + ring * 0.9
	for key: String in ["rear", "front", "back"]:
		var p: Vector3 = line[key]
		out[key] = Vector3(p.x, height, p.z)
	out["ring"] = ring
	return out


## The sight itself: a node of meshes in the same space the line was measured in.
static func build(line: Dictionary, forward: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Sight"
	if line.is_empty():
		return root
	var f := forward.normalized()
	var up := Vector3.UP
	var side := up.cross(f).normalized()
	var r: float = line.ring
	var rear: Vector3 = line.rear
	var front: Vector3 = line.front
	var front_drop: float = front.y - float(line.front_top)

	# Front: a post from the gun's top to the line, its tip on the line, inside a ring on a
	# foot. Thin enough that the post reads as a point and the ring as a circle round it.
	var st := _begin()
	var post_w := r * 0.28
	var post_h := front_drop + post_w * 0.5
	_box(st, front + up * (post_w * 0.5 - post_h * 0.5), side, up, f,
		Vector3(post_w, post_h, post_w * 1.2), line.front_paint.uv)
	var foot_h := maxf(front_drop - r * 0.7, r * 0.15)
	_box(st, front - up * (front_drop - foot_h * 0.5), side, up, f,
		Vector3(r * 1.5, foot_h, r * 0.6), line.front_paint.uv)
	var segments := 16
	var tube := r * 0.24
	for i in segments:
		var a := TAU * (i + 0.5) / segments
		var radial := side * cos(a) + up * sin(a)
		var tangent := side * -sin(a) + up * cos(a)
		_box(st, front + radial * (r - tube * 0.5), tangent, radial, f,
			Vector3(TAU * r / segments * 1.08, tube, r * 0.45), line.front_paint.uv)
	root.add_child(_commit(st, "Front", line.front_paint.material))

	# Rear: a low notch, its ears' tops below the line. The rear sight is half the front's
	# distance from the eye, so anything on the line there is twice the size on the screen:
	# ears up to the line hid the bottom of the ring and filled the middle of the screen. Kept
	# low, it sits under the ring like a real rear sight seen past the front, and the front
	# post rises out of its notch.
	st = _begin()
	var notch := r * 0.9
	var ear_w := r * 0.5
	var ear_top := rear.y - r * 0.5
	var notch_bottom := rear.y - r * 0.85
	var base_bottom := minf(float(line.rear_top), notch_bottom - r * 0.1)
	_box(st, rear + up * ((base_bottom + notch_bottom) * 0.5 - rear.y), side, up, f,
		Vector3(notch + ear_w * 2.0, notch_bottom - base_bottom, r * 0.8), line.rear_paint.uv)
	for s: float in [-1.0, 1.0]:
		var c := rear + side * s * (notch * 0.5 + ear_w * 0.5)
		c.y = (notch_bottom + ear_top) * 0.5
		_box(st, c, side, up, f, Vector3(ear_w, ear_top - notch_bottom, r * 0.8), line.rear_paint.uv)
	root.add_child(_commit(st, "Rear", line.rear_paint.material))
	return root


# --- Measuring --------------------------------------------------------------

## Every triangle under [param node], in [param space], with its surface's material and the
## mean of its corners' UVs (the kit paints with one colour atlas, so a face's UVs sit in one
## swatch).
static func _triangles(node: Node, space: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_space := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != space:
			if walk is Node3D:
				to_space = (walk as Node3D).transform * to_space
			walk = walk.get_parent()
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_INDEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var material := mi.get_active_material(s)
			var count := index.size() if not index.is_empty() else verts.size()
			for i in range(0, count - 2, 3):
				var ia := index[i] if not index.is_empty() else i
				var ib := index[i + 1] if not index.is_empty() else i + 1
				var ic := index[i + 2] if not index.is_empty() else i + 2
				var uv := Vector2.ZERO
				if uvs.size() == verts.size():
					uv = (uvs[ia] + uvs[ib] + uvs[ic]) / 3.0
				out.append({
					"a": to_space * verts[ia], "b": to_space * verts[ib], "c": to_space * verts[ic],
					"material": material, "uv": uv,
				})
	return out


## The highest face straight down at (lateral [param s], along [param t]), or `{}`.
static func _top_at(triangles: Array[Dictionary], f: Vector3, side: Vector3, s: float, t: float, y_max: float) -> Dictionary:
	var from := f * t + side * s + Vector3.UP * (y_max + 1.0)
	var best := {}
	for tri: Dictionary in triangles:
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, tri.a, tri.b, tri.c)
		if hit == null:
			continue
		var y: float = (hit as Vector3).y
		if best.is_empty() or y > best.y:
			best = {"y": y, "t": t, "material": tri.material, "uv": tri.uv}
	return best


## [method _top_at] at the station, or the nearest station a few centimetres either side that
## has a face under it (a gap between two parts of the model), and failing that the same a
## little to either side of the centre line (a gun whose middle is a gap, like a tank and a
## barrel side by side). The hit's lateral place is returned as `s`.
static func _top_near(triangles: Array[Dictionary], f: Vector3, side: Vector3, s: float, t: float, length: float, y_max: float, width: float) -> Dictionary:
	for lateral: float in [0.0, -0.12, 0.12, -0.25, 0.25]:
		for k in range(9):
			var shift := length * 0.015 * ceilf(k / 2.0) * (1.0 if k % 2 == 1 else -1.0)
			var hit := _top_at(triangles, f, side, s + lateral * width, t + shift, y_max)
			if not hit.is_empty():
				return hit
	return {}


# --- Building ---------------------------------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(st: SurfaceTool, name: String, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	if material != null:
		mi.mesh.surface_set_material(0, material)
	return mi


## A box at [param c] with axes [param x], [param y], [param z] and full [param size], every
## corner on [param uv] so it takes the one colour of the swatch under it.
static func _box(st: SurfaceTool, c: Vector3, x: Vector3, y: Vector3, z: Vector3, size: Vector3, uv: Vector2) -> void:
	var ax := [x.normalized() * size.x * 0.5, y.normalized() * size.y * 0.5, z.normalized() * size.z * 0.5]
	# Each face: its outward normal axis and two in-plane axes with a × b = n, so
	# (-a-b, -a+b, +a+b, +a-b) runs clockwise seen from outside, Godot's front face.
	for i in 3:
		for sgn: float in [1.0, -1.0]:
			var n: Vector3 = ax[i] * sgn
			var a: Vector3 = ax[(i + 1) % 3]
			var b: Vector3 = ax[(i + 2) % 3]
			if a.cross(b).dot(n) < 0.0:
				b = -b
			var centre := c + n
			var corners := [centre - a - b, centre - a + b, centre + a + b, centre + a - b]
			var normal := n.normalized()
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(normal)
				st.set_uv(uv)
				st.add_vertex(corners[k])
