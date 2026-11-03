class_name ZeeViewOverlay
extends Node

## Draws the view model's layer a second time, from a camera of its own in a transparent SubViewport, composited under the HUD.
## That pass has no world in it, so a wall the player stands against cannot hide the gun; only a SubViewport has a depth buffer of its own on every renderer, the web build included.

var _canvas: CanvasLayer
var _rect: TextureRect
var _viewport: SubViewport
var _camera: Camera3D
var _layer_mask: int = 0

## Builds the nodes under [param host], showing render layer [param layer] (1 to 20).
func setup(host: Node, layer: int) -> void:
	_layer_mask = 1 << (layer - 1)
	_canvas = CanvasLayer.new()
	_canvas.name = "ViewOverlay"
	# Below the default layer, so the HUD draws over the gun.
	_canvas.layer = -1
	_canvas.visible = false
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_camera = Camera3D.new()
	_camera.cull_mask = _layer_mask
	_viewport.add_child(_camera)
	_rect = TextureRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture = _viewport.get_texture()
	_canvas.add_child(_rect)
	_canvas.add_child(_viewport)
	host.add_child(_canvas)

## True while the second pass is drawn.
func is_active() -> bool:
	return _canvas != null and _canvas.visible

## Turns the pass on or off and, while on, copies [param source]'s view into it.
func update(active: bool, source: Camera3D) -> void:
	if _canvas == null:
		return
	if not active or source == null or not source.is_inside_tree():
		_canvas.visible = false
		return
	var vp := source.get_viewport()
	var size := Vector2i(vp.get_visible_rect().size)
	if size.x > 0 and size.y > 0 and _viewport.size != size:
		_viewport.size = size
	_viewport.msaa_3d = vp.msaa_3d
	_camera.projection = source.projection
	_camera.fov = source.fov
	_camera.size = source.size
	_camera.near = source.near
	_camera.far = source.far
	_camera.keep_aspect = source.keep_aspect
	_camera.h_offset = source.h_offset
	_camera.v_offset = source.v_offset
	_camera.environment = source.environment
	_camera.attributes = source.attributes
	_camera.global_transform = source.global_transform
	_camera.current = true
	_canvas.visible = true
