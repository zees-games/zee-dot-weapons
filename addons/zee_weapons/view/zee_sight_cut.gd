extends RefCounted

## Cuts a see-through hole out of a view model's own meshes along the aim line: a cone from the aimed eye round the aim axis,
## ending short of the front post, so a solid rear sight, ring housing or optic box is looked through, not at.
## No `class_name`: preloaded by path, as zee_own_sight.gd is. Cut meshes are copies; the world model keeps the original.

## Sides of the pyramid that stands in for the cone; it is drawn round the circle, so the hole is never smaller than asked.
const SIDES := 16
## How far short of the front post's back face the cut stops, as a share of its distance from the eye.
const POST_CLEAR := 0.03

const IronSight := preload("zee_iron_sight.gd")

static var _cache: Dictionary = {}


## The cut for an aim hold [param aim] (the holder's transform at full aim): `{eye, axis, tan, stop}` in the holder's space.
## [param degrees] is the hole's angular radius; [param front] the front post (holder space) the hole stops short of, or null.
static func cone(aim: Transform3D, degrees: float, front: Variant = null) -> Dictionary:
	if degrees <= 0.0:
		return {}
	var inv := aim.affine_inverse()
	var eye := inv * Vector3.ZERO
	var axis := (inv.basis * Vector3.FORWARD).normalized()
	var stop := INF
	if front is Vector3:
		stop = ((front as Vector3) - eye).dot(axis) * (1.0 - POST_CLEAR)
	return {"eye": eye, "axis": axis, "tan": tan(deg_to_rad(degrees)), "stop": stop}


## Gives every mesh under [param roots] the cut copy for [param cut] (from [method cone]) in [param space].
## Returns `{removed, near, far}`: triangles touched and the axial range of what was taken away (0 when nothing).
static func apply(roots: Array, space: Node3D, cut: Dictionary) -> Dictionary:
	var out := {"removed": 0, "near": INF, "far": 0.0}
	if cut.is_empty():
		return out
	var planes := _planes(cut)
	for root: Variant in roots:
		if not (root is Node):
			continue
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			var mi := n as MeshInstance3D
			if mi == null or not (mi.mesh is ArrayMesh or mi.mesh is PrimitiveMesh):
				continue
			var to_space := _to_space(mi, space)
			var key := "%d|%s|%s|%s|%s|%s" % [mi.mesh.get_instance_id(), to_space, cut.eye, cut.axis, cut.tan, cut.stop]
			var done: Dictionary = _cache[key] if _cache.has(key) else _cut_mesh(mi.mesh, to_space, planes, cut)
			_cache[key] = done
			if int(done.removed) == 0:
				continue
			out.removed += int(done.removed)
			out.near = minf(out.near, float(done.near))
			out.far = maxf(out.far, float(done.far))
			var overrides: Array[Material] = []
			for s in mi.get_surface_override_material_count():
				overrides.append(mi.get_surface_override_material(s))
			mi.mesh = done.mesh
			for s in mini(overrides.size(), mi.mesh.get_surface_count()):
				mi.set_surface_override_material(s, overrides[s])
	if out.removed == 0:
		out.near = 0.0
	return out


## [param cut] stopped short of the first thing its axis meets in the front part of [param node] (past [param from] of its length
## along the axis): a front post the mesh reading missed. Unchanged when the axis meets nothing there.
static func short_of_front(cut: Dictionary, node: Node, space: Node3D, from: float = 0.55) -> Dictionary:
	if cut.is_empty() or is_finite(float(cut.stop)):
		return cut
	var eye: Vector3 = cut.eye
	var axis: Vector3 = cut.axis
	var triangles := IronSight.triangles_of(node, space)
	var lo := INF
	var hi := -INF
	for tri: Dictionary in triangles:
		for p: Vector3 in [tri.a, tri.b, tri.c]:
			lo = minf(lo, (p - eye).dot(axis))
			hi = maxf(hi, (p - eye).dot(axis))
	var front := lo + (hi - lo) * from
	var nearest := INF
	for tri: Dictionary in triangles:
		var hit: Variant = Geometry3D.segment_intersects_triangle(eye + axis * maxf(front, 0.0), eye + axis * (hi + 1.0), tri.a, tri.b, tri.c)
		if hit != null:
			nearest = minf(nearest, ((hit as Vector3) - eye).dot(axis))
	if is_finite(nearest):
		var out := cut.duplicate()
		out.stop = nearest * (1.0 - POST_CLEAR)
		return out
	return cut


## Rays from [param cut]'s eye inside its cone ([param share] of its radius, [param rings] rings of [param per_ring]) that hit a triangle
## of [param node]'s meshes before the stop: 0 when the sight is seen through. A suite's check on the drawn meshes, not the cut.
static func occluders(node: Node, space: Node3D, cut: Dictionary, share: float = 0.9, rings: int = 4, per_ring: int = 12) -> int:
	if cut.is_empty():
		return 0
	var eye: Vector3 = cut.eye
	var axis: Vector3 = cut.axis
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var reach: float = float(cut.stop) if is_finite(float(cut.stop)) else 10.0
	var triangles := IronSight.triangles_of(node, space)
	var hits := 0
	for r in rings + 1:
		var t: float = float(cut.tan) * share * r / rings
		for k in (1 if r == 0 else per_ring):
			var phi := TAU * k / per_ring
			var dir := (axis + (u * cos(phi) + v * sin(phi)) * t).normalized()
			var to := eye + dir * reach / dir.dot(axis)
			for tri: Dictionary in triangles:
				if Geometry3D.segment_intersects_triangle(eye, to, tri.a, tri.b, tri.c) != null:
					hits += 1
					break
	return hits


## The region as planes `[normal, d]` in space coordinates: a point p is inside when every `normal.dot(p) - d <= 0`.
static func _planes(cut: Dictionary) -> Array:
	var eye: Vector3 = cut.eye
	var axis: Vector3 = cut.axis
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	# The pyramid's sides sit outside the circle: its inner radius is the cone's at every depth.
	var t: float = float(cut.tan) / cos(PI / SIDES)
	var planes: Array = []
	for k in SIDES:
		var phi := TAU * k / SIDES
		var n := u * cos(phi) + v * sin(phi) - axis * t
		planes.append([n, n.dot(eye)])
	planes.append([-axis, -axis.dot(eye)])
	if is_finite(float(cut.stop)):
		planes.append([axis, axis.dot(eye) + float(cut.stop)])
	return planes


static func _to_space(mi: Node, space: Node3D) -> Transform3D:
	var to_space := Transform3D.IDENTITY
	var walk: Node = mi
	while walk != null and walk != space:
		if walk is Node3D:
			to_space = (walk as Node3D).transform * to_space
		walk = walk.get_parent()
	return to_space


## `{mesh, removed, near, far}`: [param mesh] with the region taken out of each triangle surface; the mesh itself when nothing is.
static func _cut_mesh(mesh: Mesh, to_space: Transform3D, planes: Array, cut: Dictionary) -> Dictionary:
	var result := ArrayMesh.new()
	var removed := 0
	var near := INF
	var far := 0.0
	var eye: Vector3 = cut.eye
	var axis: Vector3 = cut.axis
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var plain: bool = mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES \
			or arrays[Mesh.ARRAY_BONES] != null or mesh.get_blend_shape_count() > 0
		var cut_surface: Array = [] if plain else _cut_surface(arrays, to_space, planes)
		if cut_surface.is_empty():
			result.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays)
		else:
			removed += int(cut_surface[1])
			for p: Vector3 in cut_surface[2]:
				var d := (p - eye).dot(axis)
				near = minf(near, d)
				far = maxf(far, d)
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cut_surface[0])
		result.surface_set_material(s, mesh.surface_get_material(s))
	if removed == 0:
		return {"mesh": mesh, "removed": 0, "near": 0.0, "far": 0.0}
	return {"mesh": result, "removed": removed, "near": near, "far": far}


## `[arrays, removed, points]` for one surface (non-indexed, every attribute interpolated), or `[]` when nothing is inside.
static func _cut_surface(arrays: Array, to_space: Transform3D, planes: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := index.size() if not index.is_empty() else verts.size()
	var world := PackedVector3Array()
	world.resize(verts.size())
	for i in verts.size():
		world[i] = to_space * verts[i]
	var corners := PackedInt32Array()
	var bary: Array[Vector3] = []
	var removed := 0
	var points: Array[Vector3] = []
	var corner := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	for i in range(0, count - 2, 3):
		var ids := PackedInt32Array([index[i], index[i + 1], index[i + 2]] if not index.is_empty() else [i, i + 1, i + 2])
		var p: Array[Vector3] = [world[ids[0]], world[ids[1]], world[ids[2]]]
		var outside := _outside_any(p, planes)
		var pieces: Array = []
		var poly: Array[Vector3] = [corner[0], corner[1], corner[2]]
		if not outside:
			for plane: Array in planes:
				var split := _split(poly, p, plane[0], plane[1])
				if not (split[0] as Array).is_empty():
					pieces.append(split[0])
				poly = split[1]
				if poly.is_empty():
					break
		if outside or poly.is_empty():
			pieces = [[corner[0], corner[1], corner[2]]]
		else:
			removed += 1
			for b: Vector3 in poly:
				points.append(p[0] * b.x + p[1] * b.y + p[2] * b.z)
		for piece: Array in pieces:
			for k in range(1, piece.size() - 1):
				for b: Vector3 in [piece[0], piece[k], piece[k + 1]]:
					corners.append_array(ids)
					bary.append(b)
	if removed == 0:
		return []
	return [_build(arrays, corners, bary), removed, points]


## Whether every corner of [param p] is outside one of [param planes]: the triangle misses the region.
static func _outside_any(p: Array[Vector3], planes: Array) -> bool:
	for plane: Array in planes:
		var n: Vector3 = plane[0]
		var d: float = plane[1]
		if n.dot(p[0]) > d and n.dot(p[1]) > d and n.dot(p[2]) > d:
			return true
	return false


## Splits a convex polygon of barycentrics on [param p] by a plane: `[outside, inside]`.
static func _split(poly: Array[Vector3], p: Array[Vector3], n: Vector3, d: float) -> Array:
	var outside: Array[Vector3] = []
	var inside: Array[Vector3] = []
	var size := poly.size()
	for k in size:
		var a := poly[k]
		var b := poly[(k + 1) % size]
		var fa := n.dot(p[0] * a.x + p[1] * a.y + p[2] * a.z) - d
		var fb := n.dot(p[0] * b.x + p[1] * b.y + p[2] * b.z) - d
		if fa > 0.0:
			outside.append(a)
		else:
			inside.append(a)
		if (fa > 0.0) != (fb > 0.0):
			var c := a.lerp(b, fa / (fa - fb))
			outside.append(c)
			inside.append(c)
	var none: Array[Vector3] = []
	return [outside if outside.size() >= 3 else none, inside if inside.size() >= 3 else none]


## Non-indexed arrays: entry i is corners[3i..3i+2] (the source triangle) weighted by bary[i].
static func _build(arrays: Array, corners: PackedInt32Array, bary: Array[Vector3]) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR, Mesh.ARRAY_TANGENT]:
		var src: Variant = arrays[slot]
		if src == null:
			continue
		match slot:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				var a: PackedVector3Array = src
				var o := PackedVector3Array()
				for i in bary.size():
					var b := bary[i]
					var v := a[corners[3 * i]] * b.x + a[corners[3 * i + 1]] * b.y + a[corners[3 * i + 2]] * b.z
					o.append(v.normalized() if slot == Mesh.ARRAY_NORMAL and v != Vector3.ZERO else v)
				out[slot] = o
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				var a2: PackedVector2Array = src
				var o2 := PackedVector2Array()
				for i in bary.size():
					var b := bary[i]
					o2.append(a2[corners[3 * i]] * b.x + a2[corners[3 * i + 1]] * b.y + a2[corners[3 * i + 2]] * b.z)
				out[slot] = o2
			Mesh.ARRAY_COLOR:
				var c: PackedColorArray = src
				var oc := PackedColorArray()
				for i in bary.size():
					var b := bary[i]
					oc.append(c[corners[3 * i]] * b.x + c[corners[3 * i + 1]] * b.y + c[corners[3 * i + 2]] * b.z)
				out[slot] = oc
			Mesh.ARRAY_TANGENT:
				var t: PackedFloat32Array = src
				var ot := PackedFloat32Array()
				for i in bary.size():
					var b := bary[i]
					for k in 4:
						ot.append(t[4 * corners[3 * i] + k] * b.x + t[4 * corners[3 * i + 1] + k] * b.y + t[4 * corners[3 * i + 2] + k] * b.z)
				out[slot] = ot
	return out
