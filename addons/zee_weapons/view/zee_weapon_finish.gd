class_name ZeeWeaponFinish
extends RefCounted

## What a gun's surfaces are made of, told apart: bare metal, polymer, wood and glass shade
## differently under the same light, which is most of what keeps a low-poly gun from reading as
## a box. The imported materials carry only a flat colour and a roughness of 0.75, so every
## surface of every gun was one dull plastic; this sets metallic and roughness per material
## name ("Metal", "DarkMetal", "Black", "Wood", "Glass", "Green"...), and leaves a material it
## does not recognise (a Kenney colormap, a launcher's texture) exactly as imported.
##
## [b]No texture is added.[/b] Factors only, so nothing here needs to survive pack delivery.
## Every amount is an exported field on [ZeeViewModel] (`finish_*`), handed in as arguments.

const METAL := &"metal"
const POLYMER := &"polymer"
const WOOD := &"wood"
const GLASS := &"glass"


## Which kind a material name is, or an empty name when it is not one of these.
static func kind_of(material_name: String) -> StringName:
	var n := material_name.to_lower()
	if n.contains("glass"):
		return GLASS
	if n.contains("wood"):
		return WOOD
	if n.contains("metal"):
		return METAL
	# Main, MainDark and MainLight are the carbine family's receiver (painted steel); Grey is the
	# SMG's slide; Black and Green are moulded polymer.
	if n.begins_with("main") or n == "grey":
		return METAL
	if n == "black" or n == "green":
		return POLYMER
	return &""


## Sets [param material] up for its kind. True when it changed anything.
##
## [param metal_amount] is the metallic factor of bare metal, and the three roughnesses are
## each kind's. A metal with no environment to reflect looks black, so the metallic factor is
## kept modest and the albedo lifted a little ([param lift], 1 = as authored).
static func apply(
	material: BaseMaterial3D, metal_amount: float, metal_rough: float,
	polymer_rough: float, wood_rough: float, lift: float
) -> bool:
	var kind := kind_of(material.resource_name)
	if kind == &"":
		return false

	match kind:
		METAL:
			material.metallic = clampf(metal_amount, 0.0, 1.0)
			material.roughness = clampf(metal_rough, 0.0, 1.0)
			material.metallic_specular = 0.7
		POLYMER:
			material.metallic = 0.0
			material.roughness = clampf(polymer_rough, 0.0, 1.0)
		WOOD:
			material.metallic = 0.0
			material.roughness = clampf(wood_rough, 0.0, 1.0)
		GLASS:
			material.metallic = 0.2
			material.roughness = 0.08

	if kind != GLASS and lift != 1.0:
		var c := material.albedo_color
		material.albedo_color = Color(
			minf(1.0, c.r * lift), minf(1.0, c.g * lift), minf(1.0, c.b * lift), c.a)
	return true
