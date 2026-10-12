extends RefCounted

## What a heavy weapon reloads with when the kits have nothing: an energy cell and an
## ammunition box with its belt, built from primitives in code (`ZeeWeaponArt.magazine_part`).
##
## [b]Built here, not vendored as files.[/b] Every game that draws this pack carries its own copy
## of `assets/` (seven of them, for pack delivery), so a new model there is a copy in seven
## repositories before the first player sees it, and a game that missed one reloads with nothing
## in the hand. A part built in code arrives with the addon. The shapes and sizes were drawn and
## looked at in Blender first (the model-3d workflow); these are the same primitives.
##
## Preloaded by path (no `class_name`), as `zee_iron_sight.gd` is: a new global name would need a
## re-import in every consumer before any of them parsed.
##
## Both stand on their base, origin at the middle of the bottom face, +Y up, the way the kit's
## clips stand, so a [member ZeeWeaponArt.magazine_offset] is where the part's foot sits.

const CELL := &"cell"
const AMMO_BOX := &"ammo_box"
const BOX_MAGAZINE := &"box_magazine"


## The part named [param part], or null for a name this file does not know.
static func build(part: StringName) -> Node3D:
	match part:
		CELL:
			return cell()
		AMMO_BOX:
			return ammo_box()
		BOX_MAGAZINE:
			return box_magazine()
	return null


## An energy cell, 16 cm tall: grey caps round a glowing cyan charge with dark bands across it.
## The glow is what reads at half size on a moving gun; a grey cylinder was a pipe.
static func cell() -> Node3D:
	var root := Node3D.new()
	root.name = "Cell"
	var cap := _material(Color(0.32, 0.34, 0.40), 0.3, 0.5)
	var band := _material(Color(0.12, 0.13, 0.16), 0.0, 0.7)
	var charge := _material(Color(0.25, 0.95, 1.0), 0.0, 0.3, 1.6)
	_cylinder(root, 0.034, 0.030, Vector3(0.0, 0.015, 0.0), cap)
	_cylinder(root, 0.027, 0.090, Vector3(0.0, 0.075, 0.0), charge)
	for y in [0.050, 0.075, 0.100]:
		_cylinder(root, 0.029, 0.006, Vector3(0.0, y, 0.0), band)
	_cylinder(root, 0.034, 0.030, Vector3(0.0, 0.135, 0.0), cap)
	_cylinder(root, 0.015, 0.012, Vector3(0.0, 0.156, 0.0), band)
	return root


## An olive ammunition box (lighter than army olive: the darker one vanished against a grey floor), 15 cm long along the barrel (Z), with a belt of seven brass rounds
## climbing out of its lid and leaning toward the gun (-X). The belt is what says "machine gun"
## rather than "a box": without it the swap read as a crate being moved.
static func ammo_box() -> Node3D:
	var root := Node3D.new()
	root.name = "AmmoBox"
	var olive := _material(Color(0.42, 0.50, 0.26), 0.0, 0.8)
	var lid := _material(Color(0.28, 0.33, 0.18), 0.0, 0.8)
	var dark := _material(Color(0.12, 0.13, 0.16), 0.0, 0.7)
	var brass := _material(Color(0.85, 0.62, 0.22), 0.6, 0.35)
	var w := 0.075
	var tall := 0.10
	var length := 0.15
	_box(root, Vector3(w, tall, length), Vector3(0.0, tall * 0.5, 0.0), olive)
	_box(root, Vector3(w + 0.008, 0.014, length + 0.008), Vector3(0.0, tall + 0.004, 0.0), lid)
	_box(root, Vector3(0.012, 0.016, 0.05), Vector3(w * 0.5 + 0.006, tall * 0.55, 0.0), dark)
	_box(root, Vector3(w * 1.02, tall * 0.9, 0.012), Vector3(0.0, tall * 0.5, length * 0.5 - 0.02), lid)
	var count := 7
	for i in count:
		var t := float(i) / float(count - 1)
		var at := Vector3(-0.012 - 0.05 * t * t, tall + 0.028 + 0.07 * t, 0.0)
		var along := Basis(Vector3.RIGHT, PI * 0.5)
		_cylinder(root, 0.0085, 0.05, at, brass, along)
		_cylinder(root, 0.006, 0.014, at + Vector3(0.0, 0.0, -0.032), dark, along)
		_box(root, Vector3(0.024, 0.006, 0.012), at + Vector3(0.0, -0.010, 0.012), dark,
			Basis(Vector3.BACK, deg_to_rad(55.0 * t)))
	return root


## A stick magazine for a real-sized pistol or machine pistol (the second pack's), 14 cm tall: a
## dark body, a lighter base plate and a brass round showing at the lips. The kit those guns
## come from has no magazine, only a 6.5 cm cartridge, which inside a grip and a glove was
## nothing on screen: a reload where the gun lifted and nothing left it.
static func box_magazine() -> Node3D:
	var root := Node3D.new()
	root.name = "BoxMagazine"
	var body := _material(Color(0.30, 0.32, 0.38), 0.3, 0.6)
	var plate := _material(Color(0.42, 0.44, 0.50), 0.4, 0.5)
	var brass := _material(Color(0.85, 0.62, 0.22), 0.6, 0.35)
	_box(root, Vector3(0.034, 0.012, 0.05), Vector3(0.0, 0.006, 0.0), plate)
	_box(root, Vector3(0.028, 0.13, 0.042), Vector3(0.0, 0.075, 0.0), body)
	_cylinder(root, 0.0075, 0.03, Vector3(0.0, 0.142, 0.002), brass, Basis(Vector3.RIGHT, PI * 0.5))
	return root


static func _material(colour: Color, metal: float, rough: float, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	return m


static func _cylinder(root: Node3D, radius: float, height: float, at: Vector3,
		material: Material, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = Transform3D(basis, at)
	root.add_child(node)


static func _box(root: Node3D, size: Vector3, at: Vector3, material: Material,
		basis: Basis = Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = Transform3D(basis, at)
	root.add_child(node)
