extends Node

## Puts each weapon in a first-person camera and measures what a player sees: where the barrel points, how wide the gun is on
## screen, and where the sight sits at full aim. Works headless (a camera projects without rendering). Add to the tree, then call.

const CHANNEL := "zee.view_measure"

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
func measure(id: StringName, aimed: bool) -> Dictionary:
	var art := ZeeWeaponArtTable.get_art(id)
	if art == null or not art.has_model():
		return {}
	if not view.equip(art).ok:
		return {}
	view.aim(aimed)
	for _i in 60:
		view.advance(0.05)
	var weapon := view.find_child("Weapon", true, false) as Node3D
	if weapon == null:
		return {}
	var size := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mesh in weapon.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var box := m.get_aabb()
		for i in 8:
			var world := m.global_transform * box.get_endpoint(i)
			var local := camera.global_transform.affine_inverse() * world
			local.z = minf(local.z, -0.05)
			var p := camera.unproject_position(camera.global_transform * local)
			lo = lo.min(p)
			hi = hi.max(p)
	var forward := (weapon.global_transform.basis * ZeeWeaponArtTable.get_art(id).model_forward).normalized()
	var out := {
		"id": id,
		"degrees_off": rad_to_deg(forward.angle_to(-camera.global_transform.basis.z)),
		"width": (hi.x - lo.x) / size.x if hi.x > lo.x else 0.0,
		"bbox": Rect2(lo, hi - lo),
		"scoped": view.is_scoped(),
	}
	var pts := view.sight_points()
	if not pts.is_empty():
		var rear := camera.unproject_position(view.global_transform * (pts.rear as Vector3))
		var front := camera.unproject_position(view.global_transform * (pts.front as Vector3))
		out["rear_px"] = rear
		out["front_px"] = front
		out["sight_off_px"] = maxf((rear - size * 0.5).length(), (front - size * 0.5).length())
	return out
