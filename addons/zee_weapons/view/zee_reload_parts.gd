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
## The reload sequence's loose pieces (zee_reload_sequence.gd): cases thrown out, rounds carried in.
const LOOSE := [&"casing", &"round", &"shell", &"grenade", &"grenade_case", &"rocket", &"speedloader", &"clip", &"belt"]


## The part named [param part] (tagged with it as the `part` meta), or null for a name this file does not know.
static func build(part: StringName) -> Node3D:
	var node: Node3D = null
	match part:
		CELL:
			node = cell()
		AMMO_BOX:
			node = ammo_box()
		BOX_MAGAZINE:
			node = box_magazine()
		&"casing":
			node = _cartridge(0.006, 0.026, false)
		&"round":
			node = _cartridge(0.006, 0.030, true)
		&"shell":
			node = _shell()
		&"grenade":
			node = _grenade(true)
		&"grenade_case":
			node = _grenade(false)
		&"rocket":
			node = _rocket()
		&"speedloader":
			node = _speedloader()
		&"clip":
			node = _clip()
		&"belt":
			node = _belt()
	if node != null:
		node.set_meta(&"part", part)
	return node


static func _brass() -> StandardMaterial3D:
	return _material(Color(0.85, 0.62, 0.22), 0.6, 0.35)


## A pistol or rifle cartridge standing on its base; a spent one has no bullet.
static func _cartridge(radius: float, tall: float, live: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Round" if live else "Casing"
	_cylinder(root, radius, tall, Vector3(0.0, tall * 0.5, 0.0), _brass())
	if live:
		_cylinder(root, radius * 0.8, tall * 0.4, Vector3(0.0, tall * 1.2, 0.0), _material(Color(0.55, 0.36, 0.24), 0.5, 0.4))
	return root


## A red shotgun shell with a brass head, 7 cm: bright enough to read in a moving hand.
static func _shell() -> Node3D:
	var root := Node3D.new()
	root.name = "Shell"
	_cylinder(root, 0.011, 0.016, Vector3(0.0, 0.008, 0.0), _brass())
	_cylinder(root, 0.0105, 0.052, Vector3(0.0, 0.042, 0.0), _material(Color(0.75, 0.12, 0.10), 0.0, 0.6))
	return root


## A 40 mm grenade round, 10 cm: a brass case and, live, a dark olive ogive with a yellow band.
static func _grenade(live: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Grenade" if live else "GrenadeCase"
	_cylinder(root, 0.021, 0.045, Vector3(0.0, 0.0225, 0.0), _brass())
	if live:
		_cylinder(root, 0.020, 0.040, Vector3(0.0, 0.065, 0.0), _material(Color(0.30, 0.34, 0.20), 0.1, 0.7))
		_cylinder(root, 0.0205, 0.006, Vector3(0.0, 0.050, 0.0), _material(Color(0.95, 0.80, 0.15), 0.0, 0.5))
		var tip := SphereMesh.new()
		tip.radius = 0.019
		tip.height = 0.026
		tip.material = _material(Color(0.30, 0.34, 0.20), 0.1, 0.7)
		var node := MeshInstance3D.new()
		node.mesh = tip
		node.position = Vector3(0.0, 0.086, 0.0)
		root.add_child(node)
	return root


## A rocket, 45 cm along its own +Y: an olive body, a dark cone nose and crossed fins.
static func _rocket() -> Node3D:
	var root := Node3D.new()
	root.name = "Rocket"
	var olive := _material(Color(0.36, 0.42, 0.24), 0.1, 0.7)
	var dark := _material(Color(0.12, 0.13, 0.16), 0.2, 0.6)
	_cylinder(root, 0.03, 0.34, Vector3(0.0, 0.17, 0.0), olive)
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.03
	nose.height = 0.11
	nose.material = dark
	var node := MeshInstance3D.new()
	node.mesh = nose
	node.position = Vector3(0.0, 0.395, 0.0)
	root.add_child(node)
	for i in 2:
		_box(root, Vector3(0.004, 0.06, 0.09), Vector3(0.0, 0.03, 0.0), dark, Basis(Vector3.UP, PI * 0.5 * i))
	return root


## A speedloader: a dark ring with six rounds standing in it.
static func _speedloader() -> Node3D:
	var root := Node3D.new()
	root.name = "Speedloader"
	_cylinder(root, 0.022, 0.014, Vector3(0.0, 0.007, 0.0), _material(Color(0.12, 0.13, 0.16), 0.3, 0.6))
	for i in 6:
		var a := TAU * float(i) / 6.0
		_cylinder(root, 0.0055, 0.03, Vector3(cos(a) * 0.014, 0.028, sin(a) * 0.014), _brass())
	return root


## A stripper clip of five rifle rounds in a row.
static func _clip() -> Node3D:
	var root := Node3D.new()
	root.name = "Clip"
	_box(root, Vector3(0.010, 0.004, 0.062), Vector3(0.0, 0.002, 0.0), _material(Color(0.30, 0.32, 0.36), 0.6, 0.4))
	for i in 5:
		_cylinder(root, 0.0055, 0.055, Vector3(0.0, 0.03, -0.024 + 0.012 * i), _brass())
	return root


## A short length of linked belt, eight rounds across the feed tray.
static func _belt() -> Node3D:
	var root := Node3D.new()
	root.name = "Belt"
	var dark := _material(Color(0.12, 0.13, 0.16), 0.0, 0.7)
	for i in 8:
		var at := Vector3(-0.07 + 0.02 * i, 0.0, 0.0)
		_cylinder(root, 0.0065, 0.05, at, _brass(), Basis(Vector3.RIGHT, PI * 0.5))
		_box(root, Vector3(0.016, 0.004, 0.012), at + Vector3(0.0, -0.007, 0.008), dark)
	return root


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
