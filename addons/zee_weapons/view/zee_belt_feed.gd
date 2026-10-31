extends Node3D
## The belt of a belt-fed gun, moving: a short run of rounds from the ammo box to the feed tray,
## one step along per shot, the last one going into the receiver as a fresh one leaves the box.
## Six meshes sharing one mesh and one material, a child of the weapon so it rides every
## animation; nothing is drawn for a weapon that is not firing.

const COUNT := 6
## Rounds per second the belt can be pulled at: a gun firing faster than this shows a belt at its limit, not a blur.
const MAX_RATE := 14.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _rounds: Array[MeshInstance3D] = []
var _phase := 0.0
var _target := 0.0


## Builds the run from [param from] (at the box) to [param to] (at the feed tray), in the weapon's space.
func build(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var prim := CylinderMesh.new()
	prim.top_radius = 0.0065
	prim.bottom_radius = 0.0065
	prim.height = 0.05
	prim.radial_segments = 6
	# An ArrayMesh: the sight cut walks every mesh under the gun and cannot read a primitive one.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prim.get_mesh_arrays())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.22)
	mat.metallic = 0.8
	mat.roughness = 0.35
	for i in COUNT:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = mat
		node.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_rounds.append(node)
	_place()


## One round is drawn into the gun.
func step() -> void:
	_target += 1.0


## Where the belt is, in rounds of travel; the tests read it.
func travelled() -> float:
	return _phase


func advance(delta: float) -> void:
	if _phase < _target:
		_phase = minf(_phase + MAX_RATE * delta, _target)
		_place()
	elif _target > 64.0:
		_phase -= 64.0
		_target -= 64.0


func _place() -> void:
	for i in _rounds.size():
		var t := fposmod((float(i) + _phase) / float(COUNT), 1.0)
		var at := _from.lerp(_to, t)
		# A belt hangs between its ends: sagging mid-run, taut where it meets the tray.
		at.y -= sin(t * PI) * 0.025 * (1.0 - t)
		var node := _rounds[i]
		node.position = at
		# The round that has just wrapped is hidden: it is in the receiver, and a new one is at the box.
		node.scale = Vector3.ONE * clampf(minf(t, 1.0 - t) * 12.0, 0.0, 1.0)
