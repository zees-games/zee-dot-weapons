extends RefCounted

## Which sight a weapon aims down and the aim hold that puts it through the eye: the model's own (read off its mesh),
## its marked one, or the built ring and post. No `class_name`: [ZeeViewModel] preloads it by path.

const IronSight := preload("zee_iron_sight.gd")
const OwnSight := preload("zee_own_sight.gd")
const Cut := preload("zee_sight_cut.gd")

## The front sight's glow: a small dot on the post's tip, its size in degrees from the ADS rule `sight_dot`, shown as the aim arrives.
const DOT_COLOR := Color(0.75, 1.0, 0.35)
const DOT_NAME := "SightDot"
const DOT_FADE_FROM := 0.6
const RED_DOT_NAME := "RedDot"
const RETICLE_NAME := "Reticle"
## The red dot's lens: a faint tint, and the thin rim round it as a share of the window's radius.
const LENS_COLOR := Color(0.55, 0.85, 1.0, 0.035)
const RIM_COLOR := Color(0.06, 0.06, 0.07)
const RIM_SHARE := 0.07


## `{line, aim, sight}` for [param art] on [param weapon] under [param holder] (`sight` a node to add under the holder, or
## null), or `{}` when the weapon aims at its written hold. [param near] is the camera's near plane plus its margin.
static func fit(art: ZeeWeaponArt, weapon: Node3D, holder: Node3D, dressed_line: Dictionary, near: float, dot_degrees: float) -> Dictionary:
	if not (art.iron_sight or art.sight_own) or not art.aim_enabled or art.aim_scoped or weapon == null:
		return {}
	var basis := art.orientation().scaled(Vector3.ONE * art.view_scale)
	var line := {}
	if art.sight_own:
		# The rear point stays where the written hold had it, so the eye keeps its distance from the gun.
		var written := basis.inverse() * (Vector3(0.0, 0.0, -art.aim_eye_relief) - art.aim_offset)
		line = OwnSight.measure(weapon, holder, art.model_forward, written.dot(art.model_forward.normalized()), art.model_path)
	var built := false
	if line.is_empty():
		if not art.iron_sight:
			return {}
		line = IronSight.from_marks(weapon, holder, art.model_forward)
		if not line.is_empty():
			line.merge(dressed_line, true)
		else:
			line = IronSight.measure(weapon, holder, art.model_forward)
			built = true
	if line.is_empty():
		return {}
	# The eye stands back far enough to keep the gun's back end past the near plane (a clip plane slices).
	var behind := maxf(0.0, (basis * (line.back as Vector3)).z - (basis * (line.rear as Vector3)).z)
	var relief := maxf(art.aim_eye_relief, behind + near)
	# The ring is sized to how far out it ends up, so a toy blaster and a real-sized rifle read alike.
	var span := absf((basis * (line.front as Vector3)).z - (basis * (line.rear as Vector3)).z)
	var sight: Node3D = null
	if built:
		var ring := (relief + span) * tan(deg_to_rad(IronSight.RING_DEGREES)) / art.view_scale
		line = IronSight.with_ring(line, clampf(ring, IronSight.RING_FIT_MIN, IronSight.RING_FIT_MAX))
		sight = IronSight.build(line, art.model_forward)
	elif line.get("post", false) and dot_degrees > 0.0:
		sight = _dot(line, art.model_forward, (relief + span) * tan(deg_to_rad(dot_degrees)) / art.view_scale)
	return {"line": line, "aim": Transform3D(basis, Vector3(0.0, 0.0, -relief) - basis * (line.rear as Vector3)), "sight": sight}


## A glowing dot of [param radius] (model metres) just behind the post's tip on [param line], its top on the line.
static func _dot(line: Dictionary, forward: Vector3, radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "OwnSight"
	var dot := MeshInstance3D.new()
	dot.name = DOT_NAME
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	dot.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(DOT_COLOR, 0.0)
	dot.material_override = material
	dot.position = (line.front as Vector3) - forward.normalized() * radius * 1.2 - Vector3.UP * radius
	dot.visible = false
	root.add_child(dot)
	return root


## Cuts the see-through hole of [method cone_for] out of [param roots]; a red-dot sight returns its dot, lens and rim to add under the holder, else null.
static func cut(art: ZeeWeaponArt, rules: ZeeAdsRules, roots: Array, holder: Node3D, aim: Transform3D, line: Dictionary) -> Node3D:
	var cone := cone_for(art, rules, roots, holder, aim, line)
	if cone.is_empty():
		return null
	var done := Cut.apply(roots, holder, cone)
	if not cone.red:
		return null
	var relief := art.aim_eye_relief / maxf(art.view_scale, 0.01)
	return _red_dot(cone, float(done.far) if int(done.removed) > 0 else relief, _red(art, rules))


## The hole along the aim hold [param aim] in the holder's space (zee_sight_cut.gd's cone plus `red`): `sight_cut` degrees stopping
## short of the front post ([param line]'s, else the first thing on the axis in the gun's front part); a red dot's wider window runs through.
static func cone_for(art: ZeeWeaponArt, rules: ZeeAdsRules, roots: Array, holder: Node3D, aim: Transform3D, line: Dictionary) -> Dictionary:
	if art == null or not art.aim_enabled or art.aim_scoped or roots.is_empty() or roots[0] == null:
		return {}
	var red := _red(art, rules)
	var is_red := art.sight_red_dot or bool(red.on)
	var degrees: float = float(red.window) if is_red else (rules.sight_cut_for(art.id) if rules != null else float(ZeeAdsRules.SPECS["sight_cut"]["default"]))
	var cone := Cut.cone(aim, degrees, line.front if line.get("post", false) and not is_red else null)
	if not is_red:
		cone = Cut.short_of_front(cone, roots[0], holder)
	if not cone.is_empty():
		cone.red = is_red
	return cone


static func _red(art: ZeeWeaponArt, rules: ZeeAdsRules) -> Dictionary:
	return (rules if rules != null else ZeeAdsRules.new()).red_dot_for(art.id)


## The dot, its lens and rim at [param depth] along [param cone]'s axis; [method track] keeps the dot on the axis from wherever the eye is.
static func _red_dot(cone: Dictionary, depth: float, red: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = RED_DOT_NAME
	var axis: Vector3 = cone.axis
	var centre: Vector3 = (cone.eye as Vector3) + axis * depth
	var window := depth * float(cone.tan)
	root.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), centre)
	root.set_meta(&"axis", axis)
	root.set_meta(&"window", window)
	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	var disc := CylinderMesh.new()
	disc.top_radius = window
	disc.bottom_radius = window
	disc.height = window * 0.01
	disc.radial_segments = 32
	disc.rings = 1
	disc.cap_bottom = false
	lens.mesh = disc
	lens.material_override = _flat(LENS_COLOR, true)
	root.add_child(lens)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var ring := TorusMesh.new()
	ring.inner_radius = window
	ring.outer_radius = window * (1.0 + RIM_SHARE)
	ring.rings = 48
	ring.ring_segments = 6
	rim.mesh = ring
	rim.material_override = _flat(RIM_COLOR, false)
	root.add_child(rim)
	var dot := MeshInstance3D.new()
	dot.name = RETICLE_NAME
	var sphere := SphereMesh.new()
	sphere.radius = depth * tan(deg_to_rad(float(red.size)))
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	dot.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = (red.color as Color) * maxf(1.0, float(red.brightness) * 0.25)
	glow.albedo_color.a = 1.0
	glow.no_depth_test = true
	glow.render_priority = Material.RENDER_PRIORITY_MAX
	dot.material_override = glow
	dot.set_meta(&"glow", float(red.brightness))
	root.add_child(dot)
	return root


static func _flat(color: Color, see_through: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	material.disable_receive_shadows = true
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Keeps a red dot under [param sight] on its axis as seen from [param eye] (holder space), as a collimated sight does,
## and hides it once that leaves the window; 0 brightness hides it for good.
static func track(sight: Node3D, eye: Vector3) -> void:
	var red := red_of(sight)
	if red == null:
		return
	var dot := red.get_node(RETICLE_NAME) as Node3D
	var local := red.transform.affine_inverse() * eye
	# In the root's frame the axis is +Y and the window is the plane y = 0: the dot is the eye's foot on it.
	dot.position = Vector3(local.x, 0.0, local.z)
	dot.visible = float(dot.get_meta(&"glow", 0.0)) > 0.0 and Vector2(local.x, local.z).length() < float(red.get_meta(&"window", 0.0))


## The red-dot root [param sight] is or holds, else null. By its meta, not its name: added beside the last gun's
## (queue_free'd, still in the tree) it is renamed.
static func red_of(sight: Node3D) -> Node3D:
	if sight == null or sight.has_meta(&"window"):
		return sight
	for child in sight.get_children():
		if child is Node3D and child.has_meta(&"window"):
			return child
	return null


## Shows the dot under [param sight] by the aim fraction [param f]: none at the hip, full at the eye.
static func fade(sight: Node3D, f: float) -> void:
	var dot := sight.get_node_or_null(DOT_NAME) as MeshInstance3D
	if dot == null:
		return
	var alpha := clampf((f - DOT_FADE_FROM) / (1.0 - DOT_FADE_FROM), 0.0, 1.0)
	dot.visible = alpha > 0.0
	(dot.material_override as StandardMaterial3D).albedo_color.a = alpha


## Sharpens a view material's textures at a grazing angle (a sight's top seen edge-on), keeping its filter's kind.
static func sharpen(material: BaseMaterial3D) -> void:
	match material.texture_filter:
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
