extends Node3D

## Shared meshes and materials of ZeeShotFx, built once; split out for file size.

## Materials shared by every carrier's effects, built once.
static var _tracer_material: StandardMaterial3D = null
static var _beam_material: StandardMaterial3D = null
static var _flash_material: StandardMaterial3D = null
static var _spark_material: StandardMaterial3D = null
static var _puff_material: StandardMaterial3D = null
static var _hit_material: StandardMaterial3D = null
static var _petal_material: StandardMaterial3D = null
static var _mist_material: StandardMaterial3D = null
static var _mark_material: StandardMaterial3D = null
static var _brass_material: StandardMaterial3D = null
static var _hull_material: StandardMaterial3D = null
static var _shell_mesh: CylinderMesh = null
static var _streak: BoxMesh = null
static var _quad: QuadMesh = null
static var _soft: GradientTexture2D = null


static func _streak_mesh() -> BoxMesh:
	if _streak == null:
		_streak = BoxMesh.new()
		_streak.size = Vector3.ONE
	return _streak


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## A white disc fading to nothing at its edge, made once.
static func _soft_disc() -> GradientTexture2D:
	if _soft == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.75))
		_soft = GradientTexture2D.new()
		_soft.gradient = gradient
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func _glow(colour: Color, billboard: bool, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = colour
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		# A quad with no texture is a square, and a square of light reads as a rendering
		# fault rather than as a flash. The soft disc is what makes it a glow.
		m.albedo_texture = _soft_disc()
	m.no_depth_test = false
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Without it a billboard ignores its node's scale, and every flash, spark and puff
		# is drawn one metre across whatever size it was given.
		m.billboard_keep_scale = true
	return m


static func _tracer_mat() -> StandardMaterial3D:
	if _tracer_material == null:
		_tracer_material = _glow(Color(1.0, 0.86, 0.52, 0.95), false, true)
	return _tracer_material


static func _shell_mesh_unit() -> CylinderMesh:
	if _shell_mesh == null:
		_shell_mesh = CylinderMesh.new()
		_shell_mesh.top_radius = 0.5
		_shell_mesh.bottom_radius = 0.5
		_shell_mesh.height = 1.0
		_shell_mesh.radial_segments = 6
		_shell_mesh.rings = 0
	return _shell_mesh


## Brass: lit, a little metallic, and a touch emissive so it still reads in shade.
static func _brass_mat() -> StandardMaterial3D:
	if _brass_material == null:
		_brass_material = StandardMaterial3D.new()
		_brass_material.albedo_color = Color(0.85, 0.62, 0.22)
		_brass_material.metallic = 0.6
		_brass_material.roughness = 0.35
		_brass_material.emission_enabled = true
		_brass_material.emission = Color(0.5, 0.33, 0.1)
		_brass_material.emission_energy_multiplier = 0.6
	return _brass_material


static func _hull_mat() -> StandardMaterial3D:
	if _hull_material == null:
		_hull_material = StandardMaterial3D.new()
		_hull_material.albedo_color = Color(0.75, 0.12, 0.1)
		_hull_material.roughness = 0.6
		_hull_material.emission_enabled = true
		_hull_material.emission = Color(0.5, 0.06, 0.05)
		_hull_material.emission_energy_multiplier = 0.5
	return _hull_material


static func _beam_mat() -> StandardMaterial3D:
	if _beam_material == null:
		_beam_material = _glow(Color(0.45, 0.85, 1.0, 0.9), false, true)
	return _beam_material


static func _flash_mat() -> StandardMaterial3D:
	if _flash_material == null:
		_flash_material = _glow(Color(1.0, 0.74, 0.32, 1.0), true, true)
		# The flash sits a few centimetres past the muzzle, inside the depth the barrel
		# has already written in first person. Tested against it, half the flash is cut
		# off by the gun that made it.
		_flash_material.no_depth_test = true
		_flash_material.render_priority = 1
	return _flash_material


static func _spark_mat() -> StandardMaterial3D:
	if _spark_material == null:
		_spark_material = _glow(Color(1.0, 0.9, 0.6, 1.0), true, true)
	return _spark_material


static func _puff_mat() -> StandardMaterial3D:
	if _puff_material == null:
		# Darker and warmer than the pale grey it was: grey dust on a grey wall was invisible on
		# every frame of the contact sheet after the spark had gone.
		_puff_material = _glow(Color(0.36, 0.32, 0.27, 0.8), true, false)
	return _puff_material


## The flash's petals: additive like the flash and, like it, drawn over the barrel that made it.
static func _petal_mat() -> StandardMaterial3D:
	if _petal_material == null:
		_petal_material = _glow(Color(1.0, 0.62, 0.22, 0.95), false, true)
		_petal_material.albedo_texture = _soft_disc()
		_petal_material.no_depth_test = true
		_petal_material.render_priority = 1
	return _petal_material


static func _hit_mat() -> StandardMaterial3D:
	if _hit_material == null:
		_hit_material = _glow(Color(0.85, 0.05, 0.04, 0.95), true, false)
	return _hit_material


static func _mist_mat() -> StandardMaterial3D:
	if _mist_material == null:
		_mist_material = _glow(Color(0.45, 0.02, 0.03, 0.6), true, false)
	return _mist_material


## A soft dark disc laid on the surface, not a billboard. Mixed, not added: added black is
## nothing at all.
static func _mark_mat() -> StandardMaterial3D:
	if _mark_material == null:
		_mark_material = _glow(Color(0.05, 0.045, 0.04, 0.85), false, false)
		_mark_material.albedo_texture = _soft_disc()
		# Drawn over the surface it sits on, a few millimetres off it: without the offset it
		# flickers in and out of the wall (z-fighting), and depth-tested it still hides behind
		# whatever stands in front of the wall.
		_mark_material.render_priority = -1
	return _mark_material
