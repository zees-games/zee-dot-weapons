extends RefCounted

## The suite's wall-exclude section: the wall probes step over the bodies they mean to skip and find the wall behind.
## A query's `exclude` getter returns a copy, so `query.exclude.append(rid)` once changed nothing: every probe below
## stopped on (or gave up at) the first body in its way, and the held gun's probe read its carrier as a wall.
## Reports through the suite's `_begin`, `_check` and `_end`.

const MASK := 1
const WallRay := preload("res://addons/zee_weapons/view/zee_world_wall_ray.gd")

var suite: Node
var _bodies: Array[CollisionObject3D] = []


func _init(host: Node) -> void:
	suite = host


## A thin wide slab, its face toward the eye, at [param z] in [param parent].
func _slab(parent: Node3D, body: CollisionObject3D, z: float) -> CollisionObject3D:
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.1)
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = MASK
	body.position = Vector3(0.0, 0.0, z)
	parent.add_child(body)
	_bodies.append(body)
	return body


func _settle() -> void:
	for _i in 2:
		await suite.get_tree().physics_frame


func _clear() -> void:
	for body in _bodies:
		body.get_parent().remove_child(body)
		body.free()
	_bodies.clear()


func run() -> void:
	suite._begin("wall probes skip the bodies they exclude")
	var room := Node3D.new()
	suite.add_child(room)
	await _slam_probes(room)
	_clear()
	await _world_ray(room)
	_clear()
	room.queue_free()
	suite._end()


## [ZeeWallSlam]'s muzzle, side and sweep probes with a character 0.35 m ahead and a wall 0.9 m ahead.
func _slam_probes(room: Node3D) -> void:
	_slab(room, CharacterBody3D.new(), -0.4)
	_slab(room, StaticBody3D.new(), -0.95)
	await _settle()
	var space := room.get_world_3d().direct_space_state
	var ahead := Vector3(0.0, 0.0, -1.0)
	var none: Array[RID] = []
	var hit := ZeeWallSlam.probe_from(space, Transform3D.IDENTITY, 1.2, MASK, true, none, ahead, 0.05, 0.5, 30.0, 0.1)
	suite._check("the muzzle ray steps over a character to the wall behind it (depth %.3f)" % hit["depth"], absf(hit["depth"] - 0.35) < 0.02)
	var up: float = (hit["sides"] as Dictionary)["up"]
	suite._check("the side rays step over a character to the wall behind it (up %.3f)" % up, up > 0.2)
	var swept := ZeeWallSlam._sweep(space, Vector3.ZERO, ahead, 1.25, 0.05, MASK, none, true)
	suite._check("the swept sphere steps over a character to the wall behind it (%.3f m)" % swept["distance"],
			absf(swept["distance"] - 0.9) < 0.05)
	var keep := ZeeWallSlam.probe_from(space, Transform3D.IDENTITY, 1.2, MASK, false, none, ahead, 0.05, 0.5, 30.0)
	suite._check("with characters counted the ray stops on the character (depth %.3f)" % keep["depth"], keep["depth"] > hit["depth"])
	var after := ZeeWallSlam.probe_from(space, Transform3D.IDENTITY, 1.2, MASK, true, none, ahead, 0.05, 0.5, 30.0)
	suite._check("a skipped character does not leak into the caller's list or the next probe",
			none.is_empty() and is_equal_approx(after["depth"], hit["depth"]))


## [ZeeWorldModel]'s wall ray starts WALL_ARM behind the hand: through the carrier's own body (excluded), and past a
## teammate, to the wall. The hand is at the origin facing -z, so the ray starts at z = WALL_ARM.
func _world_ray(room: Node3D) -> void:
	var ray := WallRay.new()
	var arm: float = ZeeWorldModel.WALL_ARM
	var forward := Vector3(0.0, 0.0, -1.0)
	var carrier := _slab(room, StaticBody3D.new(), arm * 0.5)
	await _settle()
	var world := room.get_world_3d()
	var own := ray.hit_distance(world, forward, Vector3.ZERO, 1.0, MASK, carrier.get_rid())
	suite._check("the held gun's wall ray passes through its carrier's own body (%.3f)" % own, own < 0.0)
	var mate := _slab(room, CharacterBody3D.new(), -0.3)
	var wall := _slab(room, StaticBody3D.new(), -0.7)
	await _settle()
	var face := arm + 0.65
	var past := ray.hit_distance(world, forward, Vector3.ZERO, 1.0, MASK, carrier.get_rid())
	suite._check("the held gun's wall ray steps over a teammate to the wall behind (%.3f m)" % past, absf(past - face) < 0.02)
	var again := ray.hit_distance(world, forward, Vector3.ZERO, 1.0, MASK, carrier.get_rid())
	suite._check("and does so again on the next probe (%.3f m)" % again, absf(again - face) < 0.02)
	var unheld := ray.hit_distance(world, forward, Vector3.ZERO, 1.0, MASK, RID())
	suite._check("a probe with no carrier stops on the body behind the hand (%.3f m)" % unheld, absf(unheld - (arm * 0.5 - 0.05)) < 0.02)
	_bodies.erase(mate)
	mate.get_parent().remove_child(mate)
	mate.free()
	await _settle()
	var lone := ray.hit_distance(world, forward, Vector3.ZERO, 1.0, MASK, carrier.get_rid())
	suite._check("the next probe starts again from the carrier alone (%.3f m)" % lone, absf(lone - face) < 0.02)
	_bodies.erase(wall)
	wall.get_parent().remove_child(wall)
	wall.free()
