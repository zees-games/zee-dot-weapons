class_name ZeeWeaponPreview
extends Node

## A weapon's model rendered once into a smooth texture (MSAA, transparent) for a menu card, cached per id. Add it to
## the tree; a weapon with no model returns null so the caller keeps its sprite.

## Texture size in pixels; set before the first [method texture] call.
@export var size := Vector2i(512, 256)
@export var msaa: Viewport.MSAA = Viewport.MSAA_4X

var _textures: Dictionary = {}


## The cached picture of [param id]'s model, or null when it has no art.
func texture(id: StringName) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var art := ZeeWeaponArtTable.get_art(id)
	var made: Texture2D = null
	if art != null and art.model_path != "":
		made = _build(art)
	_textures[id] = made
	return made


## How many ids have been resolved, null results included.
func cached_count() -> int:
	return _textures.size()


func _build(art: ZeeWeaponArt) -> Texture2D:
	var model := ZeeModelCache.instantiate(art.model_path)
	if model == null:
		return null
	var port := SubViewport.new()
	port.size = size
	port.transparent_bg = true
	port.own_world_3d = true
	port.msaa_3d = msaa
	port.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(port)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	port.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	port.add_child(sun)

	var forward := art.model_forward.normalized()
	if forward.is_equal_approx(Vector3.LEFT):
		model.basis = Basis(Vector3.UP, PI)
	elif not forward.is_equal_approx(Vector3.RIGHT):
		model.basis = Basis(Quaternion(forward, Vector3.RIGHT))
	port.add_child(model)
	var box := Transform3D(model.basis, Vector3.ZERO) * ZeeModelCache.bounds(art.model_path)
	model.position = -box.get_center()

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = maxf(box.size.x, box.size.y * float(size.x) / float(size.y)) * 1.08
	camera.position = Vector3(0, 0, 10)
	port.add_child(camera)
	camera.current = true
	return port.get_texture()
