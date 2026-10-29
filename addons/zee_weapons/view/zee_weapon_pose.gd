class_name ZeeWeaponPose
extends "zee_weapon_pose_keys.gd"

## Where a first-person weapon sits this frame: sway, bob, recoil, deploy, reload and charge, as one transform.
## Pure arithmetic with no Node, viewport or clock, so a headless suite can assert it settles, never makes a NaN and returns to where it started.
## Not part of the netcode contract: it runs on render frames and never writes to anything the simulation reads.

## How the springs behave. One resource for the whole rig; a weapon scales it by its own
## [member ZeeWeaponArt.weight] rather than carrying its own copy.
class Tunables extends RefCounted:
	## Metres the weapon lags behind a turn, at [member sway_reference] degrees a second.
	var sway_amount: float = 0.035

	## Degrees per second of look movement producing the full sway.
	var sway_reference: float = 220.0

	## How quickly sway catches up, per second. Higher is stiffer.
	var sway_response: float = 9.0

	## Degrees the weapon rolls into a turn.
	var sway_roll: float = 4.0

	## Sideways ground speed producing the full strafe tilt, metres a second.
	var strafe_reference: float = 6.0

	## How quickly the tilt follows a change of strafe, per second.
	var strafe_response: float = 8.0

	## Degrees the weapon leans against a full strafe.
	var strafe_roll: float = 6.0

	## Metres the weapon trails behind a full strafe.
	var strafe_slide: float = 0.035

	## Metres of vertical travel at [member bob_reference] metres a second.
	var bob_amount: float = 0.022

	## Horizontal travel, as a fraction of [member bob_amount]. Slightly more than the
	## vertical, because a figure-of-eight reads as walking and a straight bounce reads
	## as a lift.
	var bob_lateral: float = 1.4

	## Ground speed producing the full bob.
	var bob_reference: float = 6.0

	## Bob cycles per metre travelled.
	##
	## [b]Per metre, not per second.[/b] A bob driven by time keeps bobbing when the
	## player walks into a wall, and slides rather than steps when they slow down.
	var bob_per_metre: float = 0.55

	## The most bob cycles a second, however fast the carrier moves: a cadence, not a speed.
	##
	## [b]Without it the bob became a buzz.[/b] Per metre alone, a carrier at 9 m/s (a fast
	## shooter's run) bobbed 10 footfalls a second, 1.1 cm up and down: a weapon vibrating
	## rather than carried, 2.3 mm of change in each frame's movement at 144 fps where a
	## walk's is a tenth of that (game-arena's `headless_feel`). A runner's legs speed up
	## to about three steps a second and then take longer strides, so the distance a cycle
	## covers grows past this rate instead. 1.5 cycles is three footfalls a second.
	var bob_max_rate: float = 1.5

	## How quickly the bob amplitude follows speed, per second.
	var bob_response: float = 7.0

	## Degrees of muzzle climb a small recoil produces per degree a behaviour asked for.
	##
	## [b]Not the whole story, because the curve bends.[/b] See [member kick_knee].
	var kick_pitch: float = 4.0

	## How hard large recoil is compressed: climb is
	## [code]kick_pitch * r / (1 + r * kick_knee)[/code].
	##
	## [b]Compressed, and the range it replaced is why.[/b] The behaviours' recoil runs
	## from 0.12 (the minigun) to 4.0 (the sniper), and that range is right for what it
	## is for — a camera that climbs. Fed linearly into a view model, and multiplied by
	## the weapon's weight on top, it made one minigun shot move the gun 0.6 degrees and
	## one sniper shot 17 degrees and 13 cm: the automatics did not visibly fire and the
	## heavy weapons threw the gun half-way up the screen. Compressed, the same pack runs
	## from about one degree to about six, which is the range a hand can hold.
	var kick_knee: float = 0.45

	## Degrees of sideways kick per degree of recoil yaw, compressed by the same curve.
	var kick_yaw: float = 3.0

	## Degrees the weapon rolls per degree of sideways kick, the same way it went.
	var kick_roll: float = 1.5

	## Metres the weapon is pushed back per degree of climb.
	var kick_back: float = 0.008

	## The most a single shot may push the weapon back, in metres.
	var kick_back_max: float = 0.045

	## The least a shot may lift the drawn weapon, in degrees, however small its recoil: the
	## automatics' recoil is tuned for the camera and was under a degree on screen. Drawn
	## only (a separate spring), so the camera punch and the shot are untouched. 0 off.
	var kick_min: float = 2.0

	## Metres the weapon slides back per degree of that minimum lift.
	var kick_min_back: float = 0.012

	## Stiffness of the recoil spring, per second, for a weapon of weight 1. A heavier
	## weapon returns more slowly, by the square root of its weight.
	var kick_response: float = 22.0

	## A weapon firing faster than this many seconds a shot gets a stiffer kick spring, so the kick settles between shots.
	var kick_rate_ref: float = 0.12

	## The most that stiffening multiplies [member kick_response] by.
	var kick_rate_max: float = 1.8

	## [b]The spring is critically damped, and that is not a tunable any more.[/b] It was
	## 0.7, which overshoots: on a sniper the barrel dipped visibly under where it rested
	## after every shot, a wobble that reads as the model being loose in the hand rather
	## than as a weapon going off. Critical is also what makes [method _critical] exact.

	## The fraction of the weapon's climb the camera takes, for [method view_punch].
	##
	## Small, because the camera is not where the shot went: the simulation fires along
	## the command's angles and nothing here changes them. A punch that recovers inside a
	## fifth of a second reads as the weapon going off; a large one reads as the crosshair
	## lying about where the next shot lands.
	var camera_share: float = 0.3

	## The draw, as keys from fully holstered (0) to in hand (1). See [method sample_keys].
	## The holster plays the same keys backwards. Replaced per weapon by the view model from
	## [member ZeeWeaponArt.draw_keys].
	var draw_keys: Array = ZeeWeaponPose.DRAW_KEYS

	## The reload, as keys over its fraction, 0 to 1. Empty is no reload motion.
	var reload_keys: Array = ZeeWeaponPose.RELOAD_KEYS_RIFLE

	## The sprint carry at full blend: metres and degrees (pitch up, yaw muzzle-left, roll), about the grip.
	var sprint_offset := Vector3.ZERO
	var sprint_rotation := Vector3.ZERO

	## While sprinting: the bob's amplitude multiplier and a roll in degrees that rocks with each stride, both at full blend.
	var sprint_bob: float = 1.0
	var sprint_bob_roll: float = 0.0

	## A melee swing, as keys over its own time (see [member swing_seconds]). Empty is none.
	var swing_keys: Array = ZeeWeaponPose.SWING_KEYS

	## How long a swing's keys take, in seconds. Presentation time, not the weapon's cooldown:
	## a swing that lasted the whole cooldown of a slow hammer would still be crossing the
	## screen when the next one was pressed.
	var swing_seconds: float = 0.36

	## A throw, as keys over [member throw_seconds].
	var throw_keys: Array = ZeeWeaponPose.THROW_KEYS

	var throw_seconds: float = 0.45

	## Metres it is pulled back at full charge.
	var charge_pull: float = 0.06

	## Metres of dip on a landing, at the controller's own reference speed.
	var landing_dip: float = 0.07

	## How quickly a landing dip recovers, per second.
	var landing_response: float = 8.0

	## The profile keys (`extra: params:`) that set each kick number, by name here: a server tunes a weapon's feel in cfg.
	const KICK_PARAMS := {
		&"view_kick_pitch": &"kick_pitch", &"view_kick_knee": &"kick_knee", &"view_kick_yaw": &"kick_yaw",
		&"view_kick_roll": &"kick_roll", &"view_kick_back": &"kick_back", &"view_kick_back_max": &"kick_back_max",
		&"view_kick_response": &"kick_response", &"view_kick_rate_ref": &"kick_rate_ref",
		&"view_kick_rate_max": &"kick_rate_max", &"view_camera_share": &"camera_share",
		&"view_kick_min": &"kick_min", &"view_kick_min_back": &"kick_min_back",
	}


	## The builders' kick numbers as profile params: the defaults above, so a profile that sets none changes nothing.
	static func kick_defaults() -> Dictionary:
		var base := Tunables.new()
		var out := {}
		for key: StringName in KICK_PARAMS:
			out[key] = float(base.get(KICK_PARAMS[key]))
		return out


	## Sets the kick numbers from a weapon's params; a key that is absent or not a number keeps the default.
	func apply_kick(params: Dictionary) -> void:
		var base := Tunables.new()
		for key: StringName in KICK_PARAMS:
			var field: StringName = KICK_PARAMS[key]
			var v: Variant = params.get(key, params.get(String(key)))
			set(field, float(v) if (v is float or v is int) and is_finite(float(v)) else base.get(field))


## Samples [param keys] at [param t]: returns [position, rotation in degrees]. Nothing it is
## handed can make it return a non-finite value; empty or malformed keys sample as rest.
##
## [b]Catmull-Rom with the tangents scaled to each span[/b] (keys are not evenly spaced), and
## zero at the two ends, so a motion starts and finishes at rest and runs through the keys
## in between rather than stopping at each, which is what made eased-per-segment curves read
## as a robot.
static func sample_keys(keys: Array, t: float) -> Array:
	var rest := [Vector3.ZERO, Vector3.ZERO]
	if keys.size() < 2 or not is_finite(t):
		return rest

	var f := clampf(t, 0.0, 1.0)
	var i := 0
	while i < keys.size() - 2 and f > float(keys[i + 1][0]):
		i += 1

	var k0: Array = keys[maxi(i - 1, 0)]
	var k1: Array = keys[i]
	var k2: Array = keys[i + 1]
	var k3: Array = keys[mini(i + 2, keys.size() - 1)]
	var t1 := float(k1[0])
	var t2 := float(k2[0])
	var span := t2 - t1
	if span <= 0.0001:
		return [k2[1], k2[2]]
	var u := clampf((f - t1) / span, 0.0, 1.0)

	var out := []
	for field in [1, 2]:
		var p1: Vector3 = k1[field]
		var p2: Vector3 = k2[field]
		var m1 := Vector3.ZERO
		var m2 := Vector3.ZERO
		if i > 0:
			m1 = (p2 - (k0[field] as Vector3)) / maxf(t2 - float(k0[0]), 0.0001) * span
		if i + 2 < keys.size():
			m2 = ((k3[field] as Vector3) - p1) / maxf(float(k3[0]) - t1, 0.0001) * span
		var u2 := u * u
		var u3 := u2 * u
		var v := p1 * (2.0 * u3 - 3.0 * u2 + 1.0) + m1 * (u3 - 2.0 * u2 + u) \
			+ p2 * (-2.0 * u3 + 3.0 * u2) + m2 * (u3 - u2)
		out.append(v if v.is_finite() else Vector3.ZERO)
	return out


# --- Configuration ----------------------------------------------------------

var tunables := Tunables.new()

## Multiplies sway and bob, and slows the recoil spring. A heavy weapon moves more and
## settles more slowly.
##
## [b]It does not multiply the kick[/b], and it did. A weapon's recoil already says how
## hard it kicks; scaling that by weight again counted the sniper's size twice.
var weight: float = 1.0

## Seconds between the weapon's shots, or 0 when unknown. A faster weapon gets a stiffer kick spring (up to 1.8x) so the kick settles between shots; a slow one keeps the base spring.
var fire_interval: float = 0.0

## Scales sway, bob and kick together: what a "weapon motion" setting turns down.
var feel: float = 1.0

## The server's amounts for each motion (the `mp_vm_*` cvars), read every frame so a change
## applies at once. [ZeeViewModel] hands it in; a pose made alone gets the defaults.
var rules := ZeeViewFeel.new()

## Where the weapon pivots when it kicks, in the space this pose's transform is applied
## in. [ZeeViewModel] sets it to the grip.
##
## [b]The grip, not the eye.[/b] A rotation about the origin of the view model is a
## rotation about the camera, which does not tip the muzzle up: it carries the whole gun
## up the screen. That was what every shot did before this existed.
var pivot := Vector3.ZERO

# --- State ------------------------------------------------------------------

## Sway, in metres, x right and y up. Lags the look direction.
var _sway := Vector2.ZERO

## Roll from turning, in degrees.
var _roll: float = 0.0

## Distance travelled, in metres. Drives the bob phase.
var _bob_distance: float = 0.0

## Smoothed sideways speed over [member Tunables.strafe_reference], -1 (left) to 1 (right).
var _strafe: float = 0.0

## Smoothed bob amplitude, 0 to 1.
var _bob_amount: float = 0.0

## Recoil offset in metres (z back) and its velocity.
var _kick: float = 0.0
var _kick_velocity: float = 0.0

## Recoil rotation in degrees (x pitch, y yaw, z roll) and its velocity.
var _kick_rotation := Vector3.ZERO
var _kick_rotation_velocity := Vector3.ZERO
## The drawn-only top-up to a small shot (see [member Tunables.kick_min]): pitch and push back.
var _extra_pitch: float = 0.0
var _extra_pitch_velocity: float = 0.0
var _extra_back: float = 0.0
var _extra_back_velocity: float = 0.0

## Which way the next sideways kick goes. Presentation only, so a plain generator.
var _rng := RandomNumberGenerator.new()

## 0 fully holstered, 1 fully deployed.
var _deploy: float = 1.0

## How far through a reload, 0 to 1. 0 and 1 are both at rest.
var _reload: float = 0.0

## 0 to 1, a charged weapon's draw.
var _charge: float = 0.0

## Metres of landing dip left to recover.
var _landing: float = 0.0

## The swing or throw playing: its keys, and how far through it is (1 or more is finished).
var _action_keys: Array = []
var _action: float = 1.0
var _action_seconds: float = 0.36

## How far into aiming down the weapon, 0 at the hip to 1 at full aim. See [method set_aim].
var _aim: float = 0.0

## How far the sprint carry is blended in, 0 to 1 (see [method set_sprint]).
var _sprint: float = 0.0

## Where full aim moves the weapon to, relative to where it rests. Set by the view model
## from the art, because the resting place is the art's and so is the sight line.
var aim_shift := Vector3.ZERO

## How much of the kick's turn full aim takes away. The kick still happens (the front sight
## climbs and settles: a shot has to be seen), but a hip kick at the sight is several degrees,
## which threw the front sight a ring's width off the crosshair on every shot. The kick's push
## back is left alone; it does not move the sight on the screen.
var aim_kick_steadiness: float = 0.6

## What is left of the sway and bob at full aim, on top of the feel rules' steadiness (1 leaves them).
var aim_sway_scale: float = 1.0


static func make(p_weight: float = 1.0) -> ZeeWeaponPose:
	var pose := ZeeWeaponPose.new()
	pose.weight = p_weight
	# Seeded, so a suite that fires twice sees the same two kicks. Nothing reads it but
	# the picture, so the seed being known costs nothing.
	pose._rng.seed = 0x2EE
	return pose


# --- Driving ----------------------------------------------------------------

## One render frame.
##
## [param look_delta] is degrees of yaw and pitch this frame, [param speed] is ground
## speed in metres a second, and the rest is posture. Everything is clamped and
## sanitised on the way in, because a single NaN reaching a [Transform3D] makes the
## weapon vanish with no error anywhere — which presents as "the view model broke" and
## takes an hour to trace back to one frame with a zero delta in it.
func advance(
	delta: float,
	look_delta: Vector2,
	speed: float,
	on_floor: bool,
	crouched: bool = false,
	strafe: float = 0.0
) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return

	# Capped rather than trusted: a frame after a level load can be a whole second long,
	# and an exponential smoothing step with a one-second delta overshoots past its
	# target and comes back, which reads as the weapon snapping.
	var step := minf(delta, 0.1)

	_advance_sway(step, look_delta)
	_advance_strafe(step, strafe if on_floor else 0.0)
	_advance_bob(step, speed, on_floor, crouched)
	_advance_kick(step)
	_advance_landing(step)
	if _action < 1.0:
		_action = minf(1.0, _action + step / maxf(0.05, _action_seconds))


## Adds recoil. [param recoil] is the pitch and yaw in degrees a behaviour asked for.
##
## [b]An impulse into a spring, not a position.[/b] Setting the offset directly makes
## every shot look identical however fast they come; pushing a spring means a second
## shot arriving before the first has settled stacks on it, which is what makes holding
## the trigger down feel different from tapping it.
##
## [b]The impulse is sized from the peak it should reach.[/b] A critically damped spring
## kicked with velocity v peaks at v / (w e), so asking for a peak and deriving v keeps
## the climb the same whatever the stiffness — and a heavier weapon's slower spring then
## reads as heavier rather than as kicking further.
##
## [b]The sideways kick picks a side each shot.[/b] The behaviours hand over a magnitude
## and it was applied as given, so every shot of every weapon pushed the gun the same way
## and a held trigger walked it steadily off to one side.
## With [param signed_yaw] (the outcome's `recoil_signed`, from dot-weapon's recoil rules) the sign of [code]recoil.y[/code] is the side, so the view agrees with the server's bullet.
func punch(recoil: Vector2, signed_yaw: bool = false) -> void:
	if not is_finite(recoil.x) or not is_finite(recoil.y):
		return

	var scale := maxf(0.0, feel)
	var climb := kick_degrees(recoil.x) * scale
	var side := _compress(absf(recoil.y)) * tunables.kick_yaw * scale
	if signed_yaw:
		side *= -1.0 if recoil.y < 0.0 else 1.0
	else:
		side *= -1.0 if _rng.randf() < 0.5 else 1.0

	var omega := _omega()
	var to_velocity := omega * exp(1.0)

	_kick_rotation_velocity += Vector3(
		climb, side, side * tunables.kick_roll
	) * to_velocity
	_kick_velocity += minf(
		climb * tunables.kick_back, tunables.kick_back_max
	) * omega * 1.3 * exp(1.0)

	if recoil.x > 0.0 and tunables.kick_min > 0.0:
		var lacking := maxf(0.0, tunables.kick_min * scale - climb)
		_extra_pitch_velocity += lacking * to_velocity
		_extra_back_velocity += lacking * tunables.kick_min_back * omega * 1.3 * exp(1.0)


## Plays a melee swing ([member Tunables.swing_keys]) from its start. A swing pressed during a
## swing starts again from the top, which is what a second press looks like.
func swing() -> void:
	_start_action(tunables.swing_keys, tunables.swing_seconds)


## Plays a throw ([member Tunables.throw_keys]).
func throw() -> void:
	_start_action(tunables.throw_keys, tunables.throw_seconds)


## How far through the swing or throw playing, 0 to 1; 1 when none is.
func action_fraction() -> float:
	return _action


func _start_action(keys: Array, seconds: float) -> void:
	if keys.size() < 2:
		return
	_action_keys = keys
	_action_seconds = seconds if is_finite(seconds) and seconds > 0.0 else 0.36
	_action = 0.0


## The muzzle climb, in degrees, a recoil of [param pitch] produces before [member feel].
func kick_degrees(pitch: float) -> float:
	return _compress(maxf(0.0, pitch)) * tunables.kick_pitch


## How far the camera should be turned this frame by recoil, in degrees: x pitch up, y yaw.
##
## [b]Presentation, and the caller must keep it that way.[/b] Add it to the camera after
## the controller has written the view; never to the command's angles. It is the same
## spring as the weapon's own kick, so the two can never disagree about when a shot went
## off.
func view_punch() -> Vector2:
	return Vector2(_kick_rotation.x, _kick_rotation.y) * tunables.camera_share


## A landing, with [param impact] the downward speed in metres a second.
func land(impact: float) -> void:
	if not is_finite(impact):
		return
	_landing = minf(
		_landing + absf(impact) / 16.0 * tunables.landing_dip, tunables.landing_dip * 3.0
	)


## Where the switch is: 1 fully in hand, 0 fully out of frame.
func set_deploy(fraction: float) -> void:
	_deploy = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else _deploy


## How far into aiming, 0 to 1. The view model eases it; the pose only applies it.
## The sprint carry's blend, 0 (hip) to 1 (lowered, barrel to the side). Eased by the caller.
func set_sprint(fraction: float) -> void:
	_sprint = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0


func set_aim(fraction: float) -> void:
	_aim = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0


## How far through a reload, 0 to 1: the raw fraction, which the reload keys shape.
func set_reload(fraction: float) -> void:
	_reload = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else _reload


## A charged weapon's draw, 0 to 1.
func set_charge(fraction: float) -> void:
	_charge = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else _charge


## Drops every spring to rest. For a respawn, a teleport and a correction.
##
## [b]Called on a teleport, and it matters.[/b] Sway is driven by how far the view moved
## this frame; a teleport moves it a hundred and eighty degrees in one frame, and
## without this the weapon swings right across the screen on arrival.
func reset() -> void:
	_sway = Vector2.ZERO
	_roll = 0.0
	_strafe = 0.0
	_bob_amount = 0.0
	_kick = 0.0
	_kick_velocity = 0.0
	_kick_rotation = Vector3.ZERO
	_kick_rotation_velocity = Vector3.ZERO
	_extra_pitch = 0.0
	_extra_pitch_velocity = 0.0
	_extra_back = 0.0
	_extra_back_velocity = 0.0
	_landing = 0.0
	_aim = 0.0
	_action = 1.0


# --- The result -------------------------------------------------------------

## Everything above, as one transform to apply on top of the weapon's resting place.
func offset() -> Transform3D:
	var holstered := 1.0 - _deploy

	# Aiming steadies what the hands add, and leaves what the weapon does (kick, reload,
	# deploy) alone: a reload at full aim still has to be seen to happen.
	var steady := (1.0 - _aim * clampf(rules.aim_steadiness, 0.0, 1.0)) * lerpf(1.0, clampf(aim_sway_scale, 0.0, 1.0), _aim)
	var carried := maxf(0.1, weight) * maxf(0.0, feel)

	# The trail behind a strafe: opposite the move, so a step right leaves the gun to the left.
	var trail := -_strafe * tunables.strafe_slide * carried * rules.strafe_tilt
	# [b]Sideways, aim holds nearly dead still.[/b] The sight is on the crosshair only while the
	# gun is on the view axis, and a quarter of the look lag, the strafe trail and the bob's
	# sideways swing (centimetres, at a half metre's range) slid the whole sight picture off the
	# crosshair, left and right, in a fight: "when aimed in the gun slides to the left or right".
	var steady_x := steady * (1.0 - _aim * 0.8)
	var position := Vector3(
		(_sway.x * rules.sway + trail) * steady_x,
		_sway.y * rules.sway * steady - _landing * rules.landing,
		(_kick + _extra_back) * maxf(0.0, rules.kick) + _charge * tunables.charge_pull
	)

	var bob := _bob_offset() * rules.bob
	position += Vector3(bob.x * steady_x, bob.y * steady, bob.z * steady)
	position += aim_shift * _aim

	# Roll is steadied too: at the sight a rolling gun is the sight picture tipping, and it
	# was the one motion aim left whole. Counter-clockwise is positive, so a strafe right (the
	# top leaning left) is a positive roll.
	var roll := _roll * rules.sway + _strafe * tunables.strafe_roll * carried * rules.strafe_tilt
	var basis := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(roll * steady_x)))

	# The authored half: the draw and the reload, both turned about the grip like the kick.
	# A rotation about this transform's origin is a rotation about the camera, which swings
	# the whole gun across the screen rather than turning it in the hand.
	var drawn := sample_keys(tunables.draw_keys, _deploy) if holstered > 0.0 else [Vector3.ZERO, Vector3.ZERO]
	var reloaded := sample_keys(tunables.reload_keys, _reload) if _reload > 0.0 else [Vector3.ZERO, Vector3.ZERO]
	var swung := sample_keys(_action_keys, _action) if _action < 1.0 else [Vector3.ZERO, Vector3.ZERO]
	var acted: Vector3 = (drawn[1] as Vector3) + (reloaded[1] as Vector3) + (swung[1] as Vector3) \
		+ tunables.sprint_rotation * _sprint
	acted.z += sin(_bob_distance * tunables.bob_per_metre * PI) * tunables.sprint_bob_roll * _sprint * _bob_amount
	position += (drawn[0] as Vector3) + (reloaded[0] as Vector3) + (swung[0] as Vector3) \
		+ tunables.sprint_offset * _sprint
	var hand := Basis.from_euler(Vector3(
		deg_to_rad(acted.x), deg_to_rad(acted.y), deg_to_rad(acted.z)
	))

	# The kick turns about the grip, inside everything else: sway and bob carry the
	# kicking weapon around, rather than the kick being taken about wherever sway left it.
	var held := (1.0 - _aim * clampf(aim_kick_steadiness, 0.0, 1.0)) * maxf(0.0, rules.kick)
	var kick := Basis.from_euler(Vector3(
		deg_to_rad((_kick_rotation.x + _extra_pitch) * held),
		deg_to_rad(_kick_rotation.y * held),
		deg_to_rad(_kick_rotation.z * held)
	))
	var about_grip := Transform3D(Basis.IDENTITY, pivot) \
		* Transform3D(hand * kick, Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -pivot)

	return Transform3D(basis, position) * about_grip


## The deploy fraction, for a caller that wants to hide the model entirely at zero.
func deploy_fraction() -> float:
	return _deploy


# --- Internals --------------------------------------------------------------

func _advance_sway(step: float, look_delta: Vector2) -> void:
	var reference := maxf(1.0, tunables.sway_reference)
	# Divided by the step to get degrees a second: the same mouse movement over two
	# frames must produce the same sway as over one, or the weapon sways further at a
	# low frame rate.
	var rate := Vector2(
		look_delta.x / step / reference, look_delta.y / step / reference
	)
	rate.x = clampf(rate.x, -1.0, 1.0)
	rate.y = clampf(rate.y, -1.0, 1.0)

	var scale := tunables.sway_amount * maxf(0.1, weight) * maxf(0.0, feel)
	# The weapon lags the turn, so turning right leaves it behind on the left. Yaw is
	# positive to the LEFT (the controller's Basis(UP, yaw)), so a right turn is a negative
	# rate and the lag is that same sign on X: this was negated, and the contact sheet's
	# "turning right" frame showed the gun leading the turn. Pitch is up-positive, so a look
	# up leaves the weapon low: negated.
	var target := Vector2(rate.x * scale, -rate.y * scale)

	var follow := _smoothing(step, tunables.sway_response)
	_sway = _sway.lerp(target, follow)
	# Rolls into the turn: clockwise (negative) turning right, which is a negative rate.
	_roll = lerpf(
		_roll, rate.x * tunables.sway_roll * maxf(0.1, weight) * maxf(0.0, feel), follow
	)


## Strafing: the weapon trails the sideways motion (it lags to the side opposite the move) and
## leans against it, which is what a hand does when the body slides under it. Driven by the
## sideways ground speed in metres a second, signed to the right.
func _advance_strafe(step: float, lateral: float) -> void:
	var side := clampf(lateral if is_finite(lateral) else 0.0, -1.0e3, 1.0e3)
	var target := clampf(side / maxf(0.1, tunables.strafe_reference), -1.0, 1.0)
	_strafe = lerpf(_strafe, target, _smoothing(step, tunables.strafe_response))


func _advance_bob(step: float, speed: float, on_floor: bool, crouched: bool) -> void:
	var ground := maxf(0.0, speed) if is_finite(speed) else 0.0

	# Airborne means no footfalls, so the bob fades out rather than continuing in the
	# air — which is the tell that a bob is driven by a timer rather than by walking.
	var target := 0.0
	if on_floor:
		target = clampf(ground / maxf(0.1, tunables.bob_reference), 0.0, 1.0)
	if crouched:
		target *= 0.45

	_bob_amount = lerpf(
		_bob_amount, target, _smoothing(step, tunables.bob_response)
	)

	# Advanced by distance travelled rather than by time, so the weapon stops bobbing
	# the instant the player stops rather than easing out over half a step, and a player
	# walking into a wall does not bob at all.
	if on_floor:
		var cadence := ground
		if tunables.bob_max_rate > 0.0 and tunables.bob_per_metre > 0.0:
			cadence = minf(ground, tunables.bob_max_rate * lerpf(1.0, 1.35, _sprint) / tunables.bob_per_metre)
		_bob_distance += cadence * step

	_bob_distance = fposmod(_bob_distance, 1000.0)


func _bob_offset() -> Vector3:
	if _bob_amount <= 0.0001:
		return Vector3.ZERO

	var phase := _bob_distance * tunables.bob_per_metre * TAU
	var scale := tunables.bob_amount * _bob_amount * maxf(0.1, weight) * maxf(0.0, feel)
	scale *= lerpf(1.0, tunables.sprint_bob, _sprint)

	# A figure of eight: the lateral term runs at half the vertical's frequency, which
	# is what a walk cycle does — two footfalls per left-right sway.
	#
	# [b]sin squared, not |sin|.[/b] |sin| has the same period and a corner at every footfall:
	# the weapon's vertical speed reverses in one frame, which at 144 fps is a 5 mm jolt per
	# step, found by the suite's jolt check. sin squared turns over smoothly.
	var s := sin(phase)
	return Vector3(
		sin(phase * 0.5) * scale * tunables.bob_lateral,
		s * s * scale - scale * 0.5,
		0.0
	)


## The recoil spring, critically damped and solved exactly.
##
## [b]Exactly, not integrated, and both integrators were tried.[/b] Explicit Euler adds
## energy at every step, so a spring that should settle grows until the weapon is flying
## around the screen — a few seconds of held automatic fire before it shows, and it looks
## like tuning rather than integration. Semi-implicit Euler fixed that and replaced it with
## two quieter faults at this stiffness: it is only stable while w * dt stays under about
## 2, which a 10 fps frame is not, and under critical damping it bleeds about a third of
## every kick away in the first step, so the climb asked for was never the climb drawn.
## A critically damped spring has a closed form, and the closed form has neither fault at
## any frame time.
func _advance_kick(step: float) -> void:
	var omega := _omega()

	# The push-back runs a little stiffer than the rotation, so the weapon is back in the
	# hand before the muzzle has finished coming down: the order a real one recovers in.
	var back := _critical(_kick, _kick_velocity, omega * 1.3, step)
	_kick = back.x
	_kick_velocity = back.y

	for axis in range(3):
		var turned := _critical(
			_kick_rotation[axis], _kick_rotation_velocity[axis], omega, step
		)
		_kick_rotation[axis] = turned.x
		_kick_rotation_velocity[axis] = turned.y

	var extra_back := _critical(_extra_back, _extra_back_velocity, omega * 1.3, step)
	_extra_back = extra_back.x
	_extra_back_velocity = extra_back.y
	var extra_pitch := _critical(_extra_pitch, _extra_pitch_velocity, omega, step)
	_extra_pitch = extra_pitch.x
	_extra_pitch_velocity = extra_pitch.y
	_extra_pitch = clampf(_extra_pitch, -20.0, 20.0)
	_extra_back = clampf(_extra_back, -0.2, 0.2)

	# Clamped so that a stack of impulses in one frame cannot throw the weapon somewhere
	# that reads as broken rather than as kicking.
	_kick = clampf(_kick, -0.5, 0.5)
	_kick_rotation.x = clampf(_kick_rotation.x, -45.0, 45.0)
	_kick_rotation.y = clampf(_kick_rotation.y, -45.0, 45.0)
	_kick_rotation.z = clampf(_kick_rotation.z, -45.0, 45.0)


## One critically damped spring at rest at zero, advanced [param t] seconds from position
## [param x] and velocity [param v]. Returns the new position and velocity.
static func _critical(x: float, v: float, omega: float, t: float) -> Vector2:
	var decay := exp(-omega * t)
	var c := v + omega * x
	return Vector2((x + c * t) * decay, (v - omega * c * t) * decay)


## The recoil spring's natural frequency for this weapon.
func _omega() -> float:
	var rate := 1.0
	if fire_interval > 0.0:
		rate = clampf(tunables.kick_rate_ref / fire_interval, 1.0, maxf(1.0, tunables.kick_rate_max))
	return maxf(1.0, tunables.kick_response) * rate / sqrt(clampf(weight, 0.5, 4.0))


## The recoil curve: linear for small recoil, flattening for large.
func _compress(r: float) -> float:
	return r / (1.0 + r * maxf(0.0, tunables.kick_knee))


func _advance_landing(step: float) -> void:
	_landing = move_toward(
		_landing, 0.0, _landing * tunables.landing_response * step + 0.0005
	)


## Frame-rate independent exponential smoothing.
##
## [b]`1 - exp(-rate * dt)`, not `rate * dt`.[/b] The linear form is the one everybody
## writes and it is a different amount of smoothing at 60 fps and at 144, so a weapon
## tuned on one machine sways visibly differently on another.
static func _smoothing(step: float, rate: float) -> float:
	return 1.0 - exp(-maxf(0.0, rate) * step)


func describe() -> Dictionary:
	return {
		"sway": _sway,
		"roll": _roll,
		"strafe": _strafe,
		"bob": _bob_amount,
		"kick": _kick,
		"kick_rotation": _kick_rotation,
		"deploy": _deploy,
		"reload": _reload,
		"charge": _charge,
		"landing": _landing,
		"action": _action,
		"weight": weight,
		"feel": feel,
	}
