extends RefCounted

## Where a weapon's hands go, measured from its own mesh. No `class_name`: [ZeeViewModel] preloads it by path.

const IronSight := preload("zee_iron_sight.gd")

## How far above the body's underside a hand's centre may sit, as a fraction of the gun's length.
const REACH := 0.06

# The two ray-cast spans cost a triangle walk of the whole mesh each; a weapon's art does not change, so a re-equip reuses them.
static var _span_cache: Dictionary = {}


## Grip, fore-end, their axes and the grip radius for [param art] on [param weapon], in [param holder]'s space (grip and fore before the holder's transform).
static func measure(art: ZeeWeaponArt, weapon: Node3D, holder: Node3D) -> Dictionary:
	var forward := art.model_forward.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	var grip := Vector3.ZERO
	var fore := forward * 0.4
	var grip_axis := up
	var fore_axis := forward
	var radius := 0.0
	if weapon != null:
		var box := bounds_in(holder, weapon)
		if box.size != Vector3.ZERO:
			var t_min := INF
			var t_max := -INF
			for i in 8:
				var t := box.get_endpoint(i).dot(forward)
				t_min = minf(t_min, t)
				t_max = maxf(t_max, t)
			var centre := box.get_center()
			var on_axis := centre - forward * centre.dot(forward)
			match art.pose:
				&"melee":
					# Round the handle, a hand's width up from its butt (the origin).
					grip = forward * minf(0.055, (t_max - t_min) * 0.3)
					grip_axis = forward
					radius = minf(box.size.x, box.size.z) * 0.38
				&"thrown":
					grip = centre
					grip_axis = forward
					radius = minf(box.size.x, box.size.z) * 0.4
				_:
					# Under the body: the grip and fore-end are below the bore, so the hands
					# sit a third and a half of the way up from the bottom of the model.
					var low := box.position.y
					var tall := box.size.y
					grip = on_axis + forward * lerpf(t_min, t_max, art.grip_along)
					grip.y = low + tall * art.grip_up
					fore = on_axis + forward * lerpf(t_min, t_max, art.fore_along)
					fore.y = low + tall * art.fore_up
					# A scope on top or a magazine below inflates the bounds' height; the hand
					# takes the body at its own station, never higher than a hand's span.
					var spans := spans_for(art, weapon, holder, forward)
					var under: Dictionary = spans[0]
					if not under.is_empty():
						fore.y = minf(fore.y, float(under.low) + float(under.length) * REACH)
					var rear: Dictionary = spans[1]
					if not rear.is_empty():
						grip.y = minf(grip.y, float(rear.low) + float(rear.length) * REACH * 1.6)
					# A pistol grip rakes: its top is forward of its bottom.
					grip_axis = (up + forward * 0.3).normalized()
					radius = box.size.x * 0.3

	return {"grip": grip, "fore": fore, "grip_axis": grip_axis, "fore_axis": fore_axis, "radius": radius}


## The bounds of every mesh under [param node], in [param space]'s own coordinates.
static func bounds_in(space: Node3D, node: Node) -> AABB:
	var out := AABB()
	var seeded := false
	for mi: MeshInstance3D in meshes(node):
		if mi.mesh == null:
			continue
		var to_space := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != space:
			if walk is Node3D:
				to_space = (walk as Node3D).transform * to_space
			walk = walk.get_parent()
		var b := to_space * mi.mesh.get_aabb()
		out = b if not seeded else out.merge(b)
		seeded = true
	return out


## Every mesh under [param node].
static func meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		out.append(node)

	for child in node.get_children():
		out.append_array(meshes(child))

	return out


static func spans_for(art: ZeeWeaponArt, weapon: Node3D, holder: Node3D, forward: Vector3) -> Array:
	# Not the art's instance id: `HipHold.sized` makes a new art per equip, and that id is reused.
	var key := "%s|%s|%s|%s|%s" % [art.id, art.model_path, holder.transform, forward, art.fore_along]
	if not _span_cache.has(key):
		var tris := IronSight.triangles_of(weapon, holder)
		_span_cache[key] = [IronSight.span(weapon, holder, forward, art.fore_along, tris), IronSight.span(weapon, holder, forward, 0.30, tris)]
	return _span_cache[key]
