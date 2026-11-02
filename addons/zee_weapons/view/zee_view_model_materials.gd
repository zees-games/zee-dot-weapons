@tool
extends "zee_view_model_wall.gd"

## View-layer materials of ZeeViewModel, split out for file size.

## The render layer (1 to 20) every mesh of the view model and its arms is drawn on, and the
## only one [member view_light_energy]'s light reaches. 0 leaves the meshes on the default
## layer and builds no light. A game whose camera culls this layer does not see its hands.
@export_range(0, 20) var view_layer: int = 20

## Gives each surface of a real-world gun its own metal, polymer, wood or glass shading (see
## [ZeeWeaponFinish]); off leaves the imported materials as they came.
@export var finish_materials: bool = true

## Metallic factor of bare metal. Kept modest: metal with no reflections to show is black.
@export_range(0.0, 1.0, 0.05) var finish_metal: float = 0.4

## Roughness of metal (low is shiny), polymer and wood.
@export_range(0.0, 1.0, 0.05) var finish_metal_roughness: float = 0.38

@export_range(0.0, 1.0, 0.05) var finish_polymer_roughness: float = 0.6

@export_range(0.0, 1.0, 0.05) var finish_wood_roughness: float = 0.85

## Multiplier on the albedo of finished surfaces (1 as authored).
@export_range(0.5, 4.0, 0.05) var finish_lift: float = 1.4

static var _view_materials: Dictionary = {}

static var _view_sources: Array = []

## Draws a part so it reads as a view model without breaking its own depth.
## Depth testing stays ON: `no_depth_test` stops a wall clipping but lets the arms and gun paint over each other. A sorting offset biases the order instead.
## The cost: it can still clip a wall the player is pressed against (offsets stay within 0.6 m); a game wanting it gone renders through its own SubViewport camera.
func _set_on_top(root: Node) -> void:
	for mesh in HandReach.meshes(root):
		mesh.sorting_offset = 100.0

		# A view model casts no shadow: it is drawn half a metre from the camera at under life size, so its shadow
		# would be a large dark smear ahead of the player with no object; the world model casts the shadow others see.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# Each surface is its own material (one override flattened a rifle to a tan plank), duplicated from the imported one
		# because a fresh StandardMaterial3D turns flat white and the import is shared with the third-person copy.
		# It receives no shadow (the world's shadow map darkened it whenever the head was in shade); sun, ambient and key light still shade it.
		if mesh.mesh != null and mesh.material_override == null:
			for surface in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(surface, _view_material(mesh.get_active_material(surface)))
		elif mesh.material_override is BaseMaterial3D:
			(mesh.material_override as BaseMaterial3D).disable_receive_shadows = true

		if view_layer > 0:
			mesh.layers = 1 << (view_layer - 1)

## The view copy of [param source], made once per source and finish and kept for good.
## Kept for good: when the last copy dies the engine drops its shader, and recompiling it stalled 60 ms per switch.
func _view_material(source: Material) -> Material:
	var key := "%d|%s|%s|%s|%s|%s|%s" % [source.get_instance_id() if source != null else 0, finish_materials,
		finish_metal, finish_metal_roughness, finish_polymer_roughness, finish_wood_roughness, finish_lift]
	if _view_materials.has(key):
		return _view_materials[key]
	var material: Material = (source as StandardMaterial3D).duplicate() \
		if source is StandardMaterial3D else StandardMaterial3D.new()
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		base.disable_receive_shadows = true
		SightFit.sharpen(base)
		if finish_materials:
			ZeeWeaponFinish.apply(base, finish_metal, finish_metal_roughness,
				finish_polymer_roughness, finish_wood_roughness, finish_lift)
	_view_materials[key] = material
	# The source is pinned with its copy: an id of a freed material could be handed to another.
	_view_sources.append(source)
	return material

## Every view material made so far, for a loading cover to draw once so their shaders compile
## under it.
static func prepared_materials() -> Array:
	return _view_materials.values()
