extends RefCounted

## The sight a model was made with, read off its mesh, so the eye looks over the model's own notch or through its own aperture onto its own post.
## No `class_name`: preloaded by path, as zee_iron_sight.gd is. The mesh is sliced along its centre line and swept from the top down.

const IronSight := preload("zee_iron_sight.gd")

## Where the gun's front part starts, as a fraction of its length: the first thing hit from behind past it is a front post.
const FRONT_FROM := 0.55
## How far past the sight's top a height must see (fraction of length) to be an aperture, not a sloped face.
const SEES_PAST := 0.15
## How far under the rear sight's top an aperture is looked for, and how deep the whole sweep goes (fractions of length).
const APERTURE_DEPTH := 0.15
const SWEEP_DEPTH := 0.35
const STEPS := 700

static var _cache: Dictionary = {}


## [param weapon]'s own sight in [param space]: `{rear, front, back, kind, post, own: true}` on a line along [param forward] at the post's tip
## or the aperture's middle, with `rear` at [param rear_t] along forward; `{}` when the mesh shows no notch, aperture or post.
## [param key] (the model path) caches the measurement, which walks every triangle.
static func measure(weapon: Node, space: Node3D, forward: Vector3, rear_t: float, key: String = "") -> Dictionary:
	var f := forward.normalized()
	if f == Vector3.ZERO or absf(f.dot(Vector3.UP)) > 0.5:
		return {}
	var cache_key := "%s|%s" % [key, f]
	var found: Dictionary = _cache[cache_key] if key != "" and _cache.has(cache_key) else _profile(weapon, space, f)
	if key != "":
		_cache[cache_key] = found
	if found.is_empty():
		return {}
	var side := Vector3.UP.cross(f).normalized()
	var at := side * float(found.s) + Vector3.UP * float(found.y)
	var front_t := float(found.front_t)
	var rear := minf(rear_t, front_t - 0.05)
	return {"rear": at + f * rear, "front": at + f * front_t, "back": at + f * float(found.back_t),
		"kind": found.kind, "post": found.has("post"), "own": true}


## The sweep: `{kind, y, s, front_t, back_t}` in the forward/side/up frame, or `{}`.
static func _profile(weapon: Node, space: Node3D, f: Vector3) -> Dictionary:
	var side := Vector3.UP.cross(f).normalized()
	var triangles := IronSight.triangles_of(weapon, space)
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
	if length <= 0.0:
		return {}
	var centre := (s_min + s_max) * 0.5
	var segments := _slice(triangles, f, side, centre)
	var dy := SWEEP_DEPTH * length / STEPS
	var hits := PackedFloat32Array()
	for i in STEPS:
		hits.append(_first_hit(segments, y_max - dy * (i + 0.5)))
	var top := 0
	while top < STEPS and hits[top] == INF:
		top += 1
	if top == STEPS:
		return {}
	var found := {"s": centre, "back_t": t_min, "front_t": t_max}
	var t0 := hits[top]
	var band := _band(hits, top, t0 + SEES_PAST * length, APERTURE_DEPTH * length / dy)
	# First hit in the front with nothing seen past it below: a post, over a lower notch or rear sight.
	if t0 > t_min + FRONT_FROM * length and band.is_empty():
		found.merge({"kind": "post", "post": true, "y": y_max - dy * (top + 0.5), "front_t": t0}, true)
		return found
	# Otherwise a ring or frame: heights under its top that see well past it, closed below, looked through at the middle.
	if band.is_empty():
		return {}
	var mid := (band[0] + band[1]) * 0.5
	found.merge({"kind": "aperture", "y": y_max - dy * (mid + 0.5), "front_t": t0 if t0 > t_min + FRONT_FROM * length else t_max}, true)
	for j in range(band[0], band[1] + 1):
		if hits[j] != INF:
			# A post filling the ring from its top hides its own tip: no sight picture, so the written aim stands.
			if j == band[0]:
				return {}
			if absf(j - mid) <= (band[1] - band[0]) * 0.25:
				found.merge({"post": true, "y": y_max - dy * (j + 0.5), "front_t": hits[j]}, true)
			break
	return found


## The first run of heights under [param top] whose hit lies past [param past], closed below within [param depth] steps: `[first, last]` or `[]`.
static func _band(hits: PackedFloat32Array, top: int, past: float, depth: float) -> PackedInt32Array:
	var first := -1
	var i := top + 1
	while i < hits.size() and i - top <= depth:
		if hits[i] > past and first < 0:
			first = i
		elif hits[i] <= past and first >= 0:
			return PackedInt32Array([first, i - 1]) if i - 1 - first >= 2 else PackedInt32Array()
		i += 1
	return PackedInt32Array()


## The mesh cut by the vertical plane at [param s] along [param side]: segments `(t1, y1, t2, y2)`.
static func _slice(triangles: Array[Dictionary], f: Vector3, side: Vector3, s: float) -> PackedVector4Array:
	var out := PackedVector4Array()
	for tri: Dictionary in triangles:
		var points: Array[Vector2] = []
		var corners: Array = [tri.a, tri.b, tri.c]
		for k in 3:
			var a: Vector3 = corners[k]
			var b: Vector3 = corners[(k + 1) % 3]
			var sa := a.dot(side) - s
			var sb := b.dot(side) - s
			if sa * sb > 0.0 or sa == sb:
				continue
			var p := a.lerp(b, sa / (sa - sb))
			points.append(Vector2(p.dot(f), p.y))
		if points.size() >= 2 and points[0] != points[1]:
			out.append(Vector4(points[0].x, points[0].y, points[1].x, points[1].y))
	return out


## The nearest-to-the-back point the slice has at height [param y], or INF.
static func _first_hit(segments: PackedVector4Array, y: float) -> float:
	var best := INF
	for seg in segments:
		if (seg.y - y) * (seg.w - y) > 0.0 or seg.y == seg.w:
			continue
		best = minf(best, lerpf(seg.x, seg.z, (y - seg.y) / (seg.w - seg.y)))
	return best
