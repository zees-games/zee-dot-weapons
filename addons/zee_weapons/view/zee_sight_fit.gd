extends RefCounted

## Which sight a weapon aims down and the aim hold that puts it through the eye: the model's own (read off its mesh),
## its marked one, or the built ring and post. No `class_name`: [ZeeViewModel] preloads it by path.

const IronSight := preload("zee_iron_sight.gd")
const OwnSight := preload("zee_own_sight.gd")

## The front sight's glow: a small dot on the post's tip, its size in degrees from the ADS rule `sight_dot`, shown as the aim arrives.
const DOT_COLOR := Color(0.75, 1.0, 0.35)
const DOT_NAME := "SightDot"
const DOT_FADE_FROM := 0.6


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
