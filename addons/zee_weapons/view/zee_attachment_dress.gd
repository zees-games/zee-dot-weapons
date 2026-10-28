extends RefCounted

## Puts a fitting's models on a gun's sockets, in the view model and the world model alike. No `class_name`: both preload it by path.
## The state it returns is a Dictionary: `parts` and `hidden` (nodes to undo), `reach` (the muzzle's end along the gun's forward),
## `scoped` and `zoom` (an optic's), and `line` (`rear` and `front` through an optic's glass, in the gun's space).


## Draws [param art]'s own extra models (its `attachments` rows) on [param parent].
static func art_parts(art: ZeeWeaponArt, parent: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for entry in art.attachments:
		var part := ZeeModelCache.instantiate(str(entry.get("path", "")))
		if part == null:
			continue
		var turn: Vector3 = entry.get("rotation", Vector3.ZERO)
		parent.add_child(part)
		part.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(turn.x), deg_to_rad(turn.y), deg_to_rad(turn.z))), entry.get("offset", Vector3.ZERO))
		out.append(part)
	return out


## Replaces [param before] with [param fitting]'s models on [param weapon]'s sockets; a mount with no socket or no art draws nothing.
static func apply(weapon: Node3D, fitting: DotWeaponFitting, forward: Vector3, before: Dictionary) -> Dictionary:
	clear(before)
	var out := {"parts": [], "hidden": [], "reach": 0.0, "scoped": false, "zoom": 0.0, "line": {}}
	if weapon == null or fitting == null:
		return out
	var f := forward.normalized()
	for mount in fitting.mounts():
		var entry := ZeeAttachmentArt.of(fitting.attachment_on(mount))
		var socket := weapon.find_child(String(ZeeAttachmentArt.socket_name(mount)), true, false) as Node3D
		var part := ZeeModelCache.instantiate(str(entry.get("path", ""))) if socket != null else null
		if part == null:
			continue
		socket.add_child(part)
		out.parts.append(part)
		for hide: StringName in entry.get("hides", []):
			var node := weapon.find_child(String(hide), true, false) as Node3D
			if node != null:
				node.visible = false
				out.hidden.append(node)
		if mount == DotWeaponAttachment.MOUNT_MUZZLE:
			out.reach = _far_end(_bounds(part, weapon), f)
		var aim: StringName = entry.get("aim", &"")
		var glass := _glass_of(part)
		if aim != &"" and glass != null:
			var box := _bounds(glass, weapon)
			var middle := box.get_center()
			middle -= f * middle.dot(f)
			out.line = {"rear": middle + f * _near_end(box, f), "front": middle + f * _far_end(box, f)}
			out.scoped = aim == &"scoped"
			out.zoom = float(entry.get("zoom", 0.0))
	return out


## Frees what [method apply] added and shows what it hid.
static func clear(state: Dictionary) -> void:
	for node: Node in state.get("parts", []):
		if is_instance_valid(node):
			node.queue_free()
	for node: Node3D in state.get("hidden", []):
		if is_instance_valid(node):
			node.visible = true


static func _glass_of(root: Node) -> MeshInstance3D:
	for child in root.find_children("*_glass", "MeshInstance3D", true, false):
		return child as MeshInstance3D
	return null


## The bounds of [param node]'s meshes in [param space]'s local space, walking the parents' own transforms (no tree needed).
static func _bounds(node: Node, space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh: MeshInstance3D in meshes:
		var to_space := Transform3D.IDENTITY
		var up: Node = mesh
		while up != null and up != space:
			if up is Node3D:
				to_space = (up as Node3D).transform * to_space
			up = up.get_parent()
		var local := mesh.get_aabb()
		for i in 8:
			var p := to_space * local.get_endpoint(i)
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	return box


static func _far_end(box: AABB, f: Vector3) -> float:
	var t := -INF
	for i in 8:
		t = maxf(t, box.get_endpoint(i).dot(f))
	return t


static func _near_end(box: AABB, f: Vector3) -> float:
	var t := INF
	for i in 8:
		t = minf(t, box.get_endpoint(i).dot(f))
	return t
