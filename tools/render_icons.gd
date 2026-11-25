extends SceneTree
## HUD / catalogue icons from the real models: each glb, whole, three-quarter view, transparent background,
## fitted to a square and saved as <out dir>/<glb stem>.png (128 px by default).
##
##   xvfb-run godot --path . --script tools/render_icons.gd -- <out dir> [--size=128] <glb path>...
##   xvfb-run godot --path . --script tools/render_icons.gd -- <out dir> --list=<text file, one glb path per line>
##
## Paths may be absolute or res://; the glb is read from disk (no import needed), so any pack or game can be rendered from
## this one project. The model's longest horizontal side is turned to run across the picture; nothing else is guessed.
## Nightly finds the files by stem (the source config's `icons` globs), so keep the glb's file name.

const BIG := 512

var vp: SubViewport
var cam: Camera3D
var out := ""
var size := 128


func _initialize() -> void:
	var files := _parse_args()
	if out == "" or files.is_empty():
		push_error("usage: render_icons.gd -- <out dir> [--size=N] [--list=F] <glb>...")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_build_stage()
	await process_frame
	var failed := 0
	for f in files:
		if not await _render(f):
			failed += 1
	quit(1 if failed > 0 else 0)


func _parse_args() -> Array[String]:
	var files: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			size = int(a.substr(7))
		elif a.begins_with("--list="):
			for l in FileAccess.get_file_as_string(a.substr(7)).split("\n", false):
				files.append(l.strip_edges())
		elif out == "":
			out = a
		else:
			files.append(a)
	return files


func _build_stage() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(BIG, BIG)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.68)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.4
	vp.add_child(fill)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true


func _render(f: String) -> bool:
	var model := _load(f)
	if model == null:
		push_error("render_icons: cannot load %s" % f)
		return false
	var holder := Node3D.new()
	vp.add_child(holder)
	holder.add_child(model)
	var box := _aabb(holder)
	if box.size.length() < 0.0001:
		push_error("render_icons: %s has no mesh" % f)
		holder.queue_free()
		return false
	if box.size.z > box.size.x:
		holder.rotation_degrees.y = 90.0
		box = _aabb(holder)
	_frame(box)
	for k in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var name := f.get_file().get_basename()
	img.save_png("%s/%s.png" % [out, name])
	print("ICON ", name)
	holder.queue_free()
	await process_frame
	return true


## Three-quarter view; the ortho size fits the projected box and the camera is shifted so the box sits in the middle.
func _frame(box: AABB) -> void:
	var centre := box.get_center()
	var dir := Vector3(0.45, 0.4, 1.0).normalized()
	cam.global_position = centre + dir * (box.size.length() * 2.0 + 1.0)
	cam.look_at(centre, Vector3.UP)
	var inv := cam.global_transform.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = inv * box.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	cam.size = maxf(hi.x - lo.x, hi.y - lo.y) * 1.12
	cam.global_position += cam.global_transform.basis * Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, 0.0)


func _load(path: String) -> Node3D:
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(abs, state, 0, abs.get_base_dir()) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
