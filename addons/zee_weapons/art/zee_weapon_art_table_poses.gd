extends "zee_weapon_art_table_paths.gd"

## Per-pose placement of ZeeWeaponArtTable (where each pose sits, how it sprints, reloads and
## weighs), split out for file size.


## Where a weapon of each pose sits relative to the camera: lower, further out and smaller than a real one. At a 90-degree vertical field of view the
## world at 0.5 m is a metre tall, so a 0.7 m rifle at life size fills two thirds of the screen. Games draw the view model at a narrower field of view;
## one camera cannot, so the weapon is shrunk to the same angular size instead ([method pose_scale] is the other half of the decision).
static func pose_offset(pose: StringName) -> Vector3:
	match pose:
		POSE_PISTOL:
			return Vector3(0.15, -0.20, -0.34)
		POSE_HEAVY:
			return Vector3(0.21, -0.27, -0.42)
		POSE_MELEE:
			return Vector3(0.22, -0.25, -0.40)
		POSE_THROWN:
			return Vector3(0.17, -0.19, -0.36)
		_:
			return Vector3(0.21, -0.26, -0.40)


## How a blaster of each pose is turned at the hip, in degrees (pitch, yaw, roll) in the model's own space (it points -Z): yaw positive brings the muzzle
## toward the crosshair, roll positive cants the right side up toward the eye. Pointed straight down the view, a weapon shows the camera its back face and
## a sliver of its left side, a stub in the corner; the cant turns the detailed right side to the eye, which takes about thirty degrees at this distance.
static func pose_rotation(pose: StringName) -> Vector3:
	match pose:
		POSE_PISTOL:
			return Vector3(0.0, 8.0, 22.0)
		POSE_HEAVY:
			return Vector3(0.0, 10.0, 26.0)
		_:
			return Vector3(0.0, 10.0, 30.0)


## How much bigger than life a weapon is drawn in a person's hand, by pose, as a share of the figure's own hand scale
## (`DotHumanoidFigure.held_scale`, which makes a pistol visible in a fist): a pistol needs all of it, a long gun would be a plank.
static func pose_world_factor(pose: StringName) -> float:
	match pose:
		POSE_PISTOL:
			return 1.0
		POSE_HEAVY:
			return 0.62
		POSE_MELEE, POSE_THROWN:
			return 1.0
		_:
			return 0.7


## Whether a pose is held with two hands in third person (before [member ZeeWeaponArt.hands]).
static func pose_two_handed(pose: StringName) -> bool:
	return pose == POSE_RIFLE or pose == POSE_HEAVY


## The sprint carry in first person, [offset m, rotation deg] over the hip hold: lowered and turned so
## the barrel points left of the body; every pose stays in the lower half of the screen.
static func sprint_view(pose: StringName) -> Array:
	match pose:
		POSE_PISTOL:
			return [Vector3(-0.04, -0.02, 0.05), Vector3(28.0, 18.0, -14.0)]
		POSE_MELEE:
			return [Vector3(0.0, -0.17, 0.03), Vector3(-18.0, 0.0, 20.0)]
		POSE_THROWN:
			return [Vector3(0.0, -0.14, 0.02), Vector3(-10.0, 0.0, 10.0)]
		POSE_HEAVY:
			return [Vector3(-0.1, -0.18, 0.17), Vector3(-18.0, 36.0, -28.0)]
		_:
			return [Vector3(-0.1, -0.16, 0.16), Vector3(-14.0, 38.0, -24.0)]


## The sprint stride in first person, [bob multiplier, roll degrees]: a long gun swings heavier than a pistol or a blade.
static func sprint_bob(pose: StringName) -> Vector2:
	match pose:
		POSE_PISTOL:
			return Vector2(2.2, 3.0)
		POSE_MELEE, POSE_THROWN:
			return Vector2(1.8, 2.0)
		POSE_HEAVY:
			return Vector2(2.6, 5.0)
		_:
			return Vector2(2.6, 4.0)


## The sprint carry in a person's hand (third person), same units, in the hand's frame (-Z the way the person faces).
static func sprint_world(pose: StringName) -> Array:
	match pose:
		POSE_PISTOL:
			return [Vector3.ZERO, Vector3(30.0, 15.0, 0.0)]
		POSE_MELEE, POSE_THROWN:
			return [Vector3.ZERO, Vector3(-15.0, 0.0, 0.0)]
		_:
			return [Vector3.ZERO, Vector3(0.0, 50.0, 0.0)]


## How much a weapon of each pose is shrunk to stand in for a narrower field of view: roughly half, because a weapon at life size half a metre
## from a 90-degree camera spans most of the screen and reads as enormous. Halving it puts a rifle at about a third of the screen height, where
## this genre has settled; a heavy weapon is shrunk a little further because it is longer to begin with.
static func pose_scale(pose: StringName) -> float:
	match pose:
		POSE_PISTOL:
			return 0.72
		POSE_HEAVY:
			return 0.72
		# [b]Melee is not shrunk the way the blasters are.[/b] A knife is 35 cm against a rifle's 71, so the correction that puts a rifle
		# at a third of the screen puts a knife at a sixth, behind the hand holding it. Held slightly above life size is what a
		# first-person blade looks like in every game that ships one.
		POSE_MELEE:
			return 1.20
		POSE_THROWN:
			return 0.9
		_:
			return 0.80


## The reload keys a weapon of each pose uses unless its art names its own. Melee and
## throwables do not reload, so they have none.
static func reload_keys(pose: StringName) -> Array:
	match pose:
		POSE_PISTOL:
			return ZeeWeaponPose.RELOAD_KEYS_PISTOL
		POSE_HEAVY:
			return ZeeWeaponPose.RELOAD_KEYS_HEAVY
		POSE_MELEE, POSE_THROWN:
			return []
		_:
			return ZeeWeaponPose.RELOAD_KEYS_RIFLE


## How much a weapon of each pose sways, before its own [member ZeeWeaponArt.weight].
static func pose_weight(pose: StringName) -> float:
	match pose:
		POSE_PISTOL:
			return 0.8
		POSE_HEAVY:
			return 1.5
		POSE_MELEE:
			return 0.7
		POSE_THROWN:
			return 0.6
		_:
			return 1.0
