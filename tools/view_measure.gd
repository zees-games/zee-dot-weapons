extends Node

## Puts each weapon in a first-person camera and measures what a player sees: which way the barrel runs on the screen,
## how far the gun is canted, how wide it is, and where the sight sits at full aim. Works headless (a camera projects
## without rendering). Add to the tree, then call.

var camera: Camera3D = null
var view: ZeeViewModel = null


## Builds the camera and view model; [param rules] may be null (the art table's own hip).
func build(rules: ZeeAdsRules, fov: float = 90.0) -> void:
	camera = Camera3D.new()
	camera.fov = fov
	add_child(camera)
	camera.make_current()
	view = ZeeViewModel.new()
	view.arm_skin = "res://assets/arms/Textures/texture-c.png"
	view.ads_rules = rules
	camera.add_child(view)


## Equips [param id] and settles it at the hip or at full aim. Returns {} when the weapon has no model.
## [param hold] overrides the hip for tuning: "rotation" replaces view_rotation, "offset" is added to view_offset.
func measure(id: StringName, aimed: bool, hold: Dictionary = {}, sprint: bool = false) -> Dictionary:
	var art := ZeeWeaponArtTable.get_art(id)
	if art == null or not art.has_model():
		return {}
	if not hold.is_empty():
		art = art.duplicate() as ZeeWeaponArt
		art.view_rotation = hold.get("rotation", art.view_rotation)
		art.view_offset += hold.get("offset", Vector3.ZERO)
	if not view.equip(art).ok:
		return {}
	view.aim(aimed)
	view.set_sprinting(sprint)
	for _i in 60:
		view.advance(0.05)
	var weapon := view.weapon_node()
	if weapon == null:
		return {}
	var size := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var world_box := AABB()
	var first := true
	for mesh in weapon.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var box := m.global_transform * m.get_aabb()
		world_box = box if first else world_box.merge(box)
		first = false
		for i in 8:
			var local := camera.global_transform.affine_inverse() * box.get_endpoint(i)
			local.z = minf(local.z, -camera.near)
			var p := camera.unproject_position(camera.global_transform * local)
			lo = lo.min(p)
			hi = hi.max(p)
	# What is on the screen, not what a corner behind the near plane would project to.
	lo = lo.clamp(Vector2.ZERO, size)
	hi = hi.clamp(Vector2.ZERO, size)
	var basis := weapon.global_transform.basis.orthonormalized()
	var forward := (basis * art.model_forward).normalized()
	var up := (basis * _model_up(art.model_forward)).normalized()
	var centre := world_box.get_center()
	var out := {
		"id": id,
		"degrees_off": rad_to_deg(forward.angle_to(-camera.global_transform.basis.z)),
		"width": (hi.x - lo.x) / size.x if hi.x > lo.x else 0.0,
		"bbox": Rect2(lo, hi - lo),
		"scoped": view.is_scoped(),
		"centre_px": camera.unproject_position(centre),
		# The barrel as drawn: degrees off straight up the screen, positive leaning toward the middle.
		"screen_lean": _screen_angle(centre, forward, size),
		# The cant as drawn: the weapon's top off straight up the screen, positive leaning toward the middle.
		"screen_cant": _screen_angle(centre, up, size),
	}
	var model_box := ZeeModelCache.bounds(art.model_path)
	if model_box.size != Vector3.ZERO and art.model_forward.is_equal_approx(Vector3.FORWARD):
		var muzzle := view.muzzle_transform().origin
		var zero := view.hip_zero()
		var aim_point := camera.global_transform * Vector3(0.0, 0.0, -zero)
		var bore := weapon.global_transform.basis * art.model_forward
		# How far the barrel points off the screen-centre point at the zero range (degrees), lens included.
		out["bore_deg"] = rad_to_deg(bore.angle_to(aim_point - muzzle)) if zero > 0.0 else -1.0
		var mid := model_box.get_center()
		var back := weapon.global_transform * Vector3(mid.x, mid.y, model_box.end.z)
		var tip := weapon.global_transform * Vector3(mid.x, mid.y, model_box.position.z)
		out["length"] = _drawn_length(back, tip, size) / size.y
	var pts := view.sight_points()
	if not pts.is_empty():
		var rear := camera.unproject_position(view.global_transform * (pts.rear as Vector3))
		var front := camera.unproject_position(view.global_transform * (pts.front as Vector3))
		out["rear_px"] = rear
		out["front_px"] = front
		out["sight_off_px"] = maxf((rear - size * 0.5).length(), (front - size * 0.5).length())
	return out


## The weapon's own top: +Y for a blaster (points -Z), +Z for one standing on its handle along +Y.
static func _model_up(model_forward: Vector3) -> Vector3:
	return Vector3.BACK if absf(model_forward.y) > 0.5 else Vector3.UP


## Degrees between straight up the screen and the short segment from [param from] along [param dir], as drawn.
## Positive leans toward the screen's middle, signed by which half [param from] is in.
func _screen_angle(from: Vector3, dir: Vector3, size: Vector2) -> float:
	var a := camera.unproject_position(from)
	var b := camera.unproject_position(from + dir * 0.05)
	var v := b - a
	if v.length() < 0.001:
		return 90.0
	var deg := rad_to_deg(atan2(v.x, -v.y))
	return -deg if a.x >= size.x * 0.5 else deg


## The length on screen (pixels) of the segment [param a]-[param b] in world space, cut to the frame.
func _drawn_length(a: Vector3, b: Vector3, size: Vector2) -> float:
	var to_cam := camera.global_transform.affine_inverse()
	var la := to_cam * a
	var lb := to_cam * b
	la.z = minf(la.z, -camera.near)
	lb.z = minf(lb.z, -camera.near)
	var p := camera.unproject_position(camera.global_transform * la)
	var q := camera.unproject_position(camera.global_transform * lb)
	var d := q - p
	var t0 := 0.0
	var t1 := 1.0
	for edge in [[-d.x, p.x], [d.x, size.x - p.x], [-d.y, p.y], [d.y, size.y - p.y]]:
		var dp: float = edge[0]
		var room: float = edge[1]
		if absf(dp) < 0.000001:
			if room < 0.0:
				return 0.0
			continue
		var t := room / dp
		if dp < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	return d.length() * (t1 - t0) if t1 > t0 else 0.0
