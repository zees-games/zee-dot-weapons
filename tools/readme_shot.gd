extends Node3D

## A studio render of each weapon for the README (tools/gen_readme.sh): neutral backdrop, three-light rig, 3/4 angle, MSAA.
## Models and ids come from tools/readme.cfg and weapons/*.tres (--ids narrows). Not headless (black frame): GPU box.
##   godot --path . res://tools/readme_shot.tscn -- --out /abs/dir [--ids a,b] [--width 1280] [--height 720]

const CFG := "res://tools/readme.cfg"

var _cfg := ConfigFile.new()
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ""
	var ids := PackedStringArray()
	var width := 1280
	var height := 720
	for i in args.size():
		var nxt := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--out": out = nxt
			"--ids": ids = nxt.split(",", false)
			"--width": width = int(nxt)
			"--height": height = int(nxt)
	if _cfg.load(CFG) != OK:
		push_error("readme_shot: cannot read %s" % CFG)
		get_tree().quit(2)
		return
	if out == "":
		push_error("readme_shot: --out <dir> is required")
		get_tree().quit(2)
		return
	if ids.is_empty():
		ids = _ids_from_defs()
	DirAccess.make_dir_recursive_absolute(out)

	var ss := int(_cfg.get_value("shot", "supersample", 2))
	_build_stage(Vector2i(width * ss, height * ss))
	var failed := 0
	for id in ids:
		var model := _model(id)
		if model == null:
			push_error("readme_shot: no model for %s" % id)
			failed += 1
			continue
		_hide(model, String(_opt(id, "hide", "")))
		_pose(model, id)
		for f in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.resize(width, height, Image.INTERPOLATE_LANCZOS)
		var path := out.path_join("%s.png" % id)
		if img.save_png(path) != OK:
			failed += 1
		print("READMESHOT %s %s" % [id, path])
		_pivot.get_child(0).queue_free()
		await get_tree().process_frame
	get_tree().quit(1 if failed > 0 else 0)


func _ids_from_defs() -> PackedStringArray:
	var found := PackedStringArray()
	for f in DirAccess.get_files_at("res://weapons"):
		if f.ends_with(".tres") and not f.get_basename() in PackedStringArray(_cfg.get_value("shot", "skip", [])):
			found.append(f.get_basename())
	found.sort()
	return found


## Drops the model's nodes whose names match any comma-separated glob in `patterns`
## ([pose] "<id>.hide" or [shot] hide), before framing so they don't count toward the bounds.
func _hide(root: Node, patterns: String) -> void:
	if patterns.strip_edges() == "":
		return
	var globs := patterns.split(",", false)
	var doomed: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var hit := false
		for g in globs:
			if n != root and String(n.name).match(g.strip_edges()):
				hit = true
				break
		if hit:
			doomed.append(n)
		else:
			stack.append_array(n.get_children())
	for n in doomed:
		n.get_parent().remove_child(n)
		n.free()


## The weapon's model, by the pack's own art call or by a file pattern.
func _model(id: String) -> Node3D:
	var script_path := String(_cfg.get_value("shot", "model_script", ""))
	if script_path != "":
		var art: Variant = load(script_path)
		var arg: Variant = StringName(id) if bool(_cfg.get_value("shot", "string_name_ids", true)) else id
		var n: Variant = art.call(String(_cfg.get_value("shot", "model_method", "instantiate")), arg)
		return n as Node3D
	var glob := String(_cfg.get_value("shot", "model_glob", ""))
	var packed := load(glob.replace("{id}", id)) as PackedScene
	return packed.instantiate() as Node3D if packed != null else null


func _build_stage(size: Vector2i) -> void:
	_vp = SubViewport.new()
	_vp.size = size
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)

	# Backdrop: a soft radial grey, drawn as the 3D background (BG_CANVAS).
	var grad := Gradient.new()
	grad.set_color(0, Color(String(_cfg.get_value("look", "backdrop_center", "#6b7077"))))
	grad.set_color(1, Color(String(_cfg.get_value("look", "backdrop_edge", "#26282c"))))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.15, 1.1)
	tex.width = 512
	tex.height = 288
	var back := TextureRect.new()
	back.texture = tex
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.position = Vector2.ZERO
	back.size = Vector2(size)
	_vp.add_child(back)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.78, 0.80, 0.84)
	sky_mat.sky_horizon_color = Color(0.62, 0.63, 0.66)
	sky_mat.ground_horizon_color = Color(0.40, 0.40, 0.42)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.13)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = 0
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(_cfg.get_value("look", "ambient", 0.55))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(_cfg.get_value("look", "exposure", 1.0))
	env.ssao_enabled = true
	env.ssao_radius = 0.25
	env.ssao_intensity = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	# Key (upper front left, soft shadows), fill (right, low), rim (behind, picks the silhouette off the backdrop).
	_light(Vector3(-38, -32, 0), float(_cfg.get_value("look", "key", 2.2)), Color(1.0, 0.97, 0.92), true)
	_light(Vector3(-12, 62, 0), float(_cfg.get_value("look", "fill", 0.7)), Color(0.88, 0.92, 1.0), false)
	_light(Vector3(-28, 168, 0), float(_cfg.get_value("look", "rim", 1.8)), Color(1.0, 1.0, 1.0), false)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = float(_cfg.get_value("shot", "fov", 24.0))
	_cam.near = 0.01
	_vp.add_child(_cam)
	_cam.current = true


func _light(rot_deg: Vector3, energy: float, color: Color, shadow: bool) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_energy = energy
	l.light_color = color
	l.shadow_enabled = shadow
	l.light_angular_distance = 2.0
	l.directional_shadow_max_distance = 6.0
	_vp.add_child(l)


func _opt(id: String, key: String, fallback: Variant) -> Variant:
	return _cfg.get_value("pose", "%s.%s" % [id, key], _cfg.get_value("shot", key, fallback))


## Lay the model on its side, muzzle (or head) to the left, turned toward the camera, then frame it.
func _pose(model: Node3D, id: String) -> void:
	_pivot.rotation = Vector3.ZERO
	var holder := Node3D.new()
	_pivot.add_child(holder)
	holder.add_child(model)

	# Base orientation: a gun's contract is muzzle toward -Z; a melee weapon or grenade standing on +Y
	# (its local bounds tallest in Y) is laid down head to the left. tools/readme.cfg [pose] overrides per id.
	var local := _aabb(model, model.global_transform.affine_inverse())
	var base := Vector3(0, -90, 0)
	if local.size.y > local.size.z * 1.2 and local.size.y > local.size.x:
		base = Vector3(0, 0, 90)
	holder.rotation_degrees = _cfg.get_value("pose", id + ".base", base)
	_pivot.rotation_degrees = Vector3(float(_opt(id, "tilt", 0.0)), float(_opt(id, "yaw", 28.0)), float(_opt(id, "roll", 0.0)))

	# Centre the model's world bounds on the origin, then frame its actual silhouette: every vertex is
	# projected, the camera backed off until they all sit inside `fill` of the frame, and the model slid
	# so the projected outline (not its bounding box) is centred. Twice, as sliding changes the fit.
	var box := _aabb(_pivot, Transform3D.IDENTITY)
	holder.position -= _pivot.global_transform.basis.inverse() * box.get_center()
	var elev := deg_to_rad(float(_opt(id, "elevation", 12.0)))
	var dir := Vector3(0, sin(elev), cos(elev))
	var fill := float(_opt(id, "fill", 0.84))
	var aspect := float(_vp.size.x) / float(_vp.size.y)
	var tan_v := tan(deg_to_rad(_cam.fov) * 0.5)
	var tan_h := tan_v * aspect
	var basis := Basis.looking_at(-dir, Vector3.UP)
	var d := 1.0
	for pass_i in 3:
		var pts := _points(_pivot)
		var lo := 0.02
		var hi := 50.0
		for i in 40:
			d = (lo + hi) * 0.5
			var inv := Transform3D(basis, dir * d).affine_inverse()
			var fits := true
			for p in pts:
				var q: Vector3 = inv * p
				var depth := -q.z
				if depth <= 0.0 or absf(q.x) / depth > tan_h * fill or absf(q.y) / depth > tan_v * fill:
					fits = false
					break
			if fits:
				hi = d
			else:
				lo = d
		d = hi
		if pass_i == 2:
			break
		# Screen-space extent of the outline at this distance; move the model so it is centred.
		var inv2 := Transform3D(basis, dir * d).affine_inverse()
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in pts:
			var q: Vector3 = inv2 * p
			var s := Vector2(q.x, q.y) / -q.z
			mn = mn.min(s)
			mx = mx.max(s)
		var c := (mn + mx) * 0.5 * d
		var shift := basis * Vector3(c.x, c.y, 0.0)
		holder.position -= _pivot.global_transform.basis.inverse() * shift
	_cam.global_transform = Transform3D(basis, dir * d)


## World positions of the visible meshes' vertices (at most ~4000 per mesh, evenly strided).
func _points(root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 4000)
			for i in range(0, verts.size(), step):
				out.append(xf * verts[i])
	if out.is_empty():
		var b := _aabb(root, Transform3D.IDENTITY)
		for c in 8:
			out.append(b.get_endpoint(c))
	return out


## Bounds of every visible mesh under [param root], in the space [param to] maps world into.
func _aabb(root: Node, to: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b := mi.get_aabb()
		var xf := to * mi.global_transform
		for c in 8:
			var p: Vector3 = xf * b.get_endpoint(c)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out
