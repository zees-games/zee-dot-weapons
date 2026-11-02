@tool
extends "zee_view_model_state.gd"

## Hands, feed and muzzle layer of ZeeViewModel, split out for file size.

## By path, not by class_name: see the file's own header.
const SightFit := preload("zee_sight_fit.gd")

const HandReach := preload("zee_hand_reach.gd")

## The server's amounts for sway, strafe tilt, bob and the landing (the `mp_vm_*` cvars). One
## object per view model, shared with its pose; assign a game's own to share it between rigs.
var feel_rules := ZeeViewFeel.new():
	set(value):
		feel_rules = value if value != null else ZeeViewFeel.new()
		if _pose != null:
			_pose.rules = feel_rules

## The server's aiming rules (enabled, time, zoom, sway, hold or toggle); null aims by the art alone.
var ads_rules: ZeeAdsRules = null:
	set(value):
		ads_rules = value
		if _source_art != null and _art != null:
			call(&"equip", _source_art)

## Every frame, where the hands belong: [param grip] and [param fore] in [param anchor]'s space, for a game that draws its own arms (with [member show_arms] off).
## With [member hands_scale] or [member hands_min_distance] set, the anchor is the drawn weapon scaled about the eye to
## that share of life size ([ZeeHandsFrame]), so a game's own arms reach it; otherwise the drawn weapon itself.
signal hands_reached(anchor: Node3D, grip: Vector3, fore: Vector3, pose: StringName)

const ReloadSequence := preload("zee_reload_sequence.gd")

## The reload being played as phases (zee_reload_sequence.gd), or null for the generic one.
var _seq: ReloadSequence = null

var _hands_frame: Node3D = null

## The size of a game's own arms against life size: [signal hands_reached]'s anchor shrinks the weapon to match, about the eye.
@export var hands_scale: float = 1.0

## The nearest the hands frame brings the grip to the eye, metres (0 = no limit): a weapon drawn close, a pistol, would
## otherwise put a life-size hand over the whole view.
@export var hands_min_distance: float = 0.0

## Every frame, the arms onto the hands: the hands follow the gun while the built arms' shoulders stay
## put in the view, so neither a wall's pull-back nor a reload swings them up into view or past the near plane.
func _place_hands() -> void:
	if _art == null or _aim_node == null:
		return
	var aim := _aim_node.transform
	var pose := _art.pose if _art.has_model() else &"fists"
	var fore := aim * _support_hand()
	var in_seq := _seq != null and _reload_fraction > 0.0 and _reload_fraction < 1.0
	var grip := aim * (_grip_at + (_seq.right_offset(_reload_fraction) if in_seq else Vector3.ZERO))
	var anchor := _animated
	if hands_scale != 1.0 or hands_min_distance > 0.0:
		var to_holder := transform * _animated.transform * aim * _holder.transform
		var scale := ZeeHandsFrame.life_scale(to_holder, _art) / maxf(hands_scale, 0.01)
		scale = ZeeHandsFrame.keep_distance(scale, (transform * _animated.transform * grip).length(), hands_min_distance)
		ZeeHandsFrame.place(_hands_frame, self, _animated, scale)
		anchor = _hands_frame
	hands_reached.emit(anchor, grip, fore, pose)
	if _arms == null or not _arms.has_method("reach"):
		return
	var into := Transform3D.IDENTITY
	if _arms.get_parent() == _animated:
		_arms.transform = _animated.transform.affine_inverse()
		into = _arms.transform.affine_inverse()
	aim = into * aim
	grip = into * grip
	fore = into * fore
	if "support_free" in _arms:
		_arms.set("support_free", in_seq or (_has_well and not _feeds and _reload_fraction > 0.0 and _reload_fraction < 1.0))
	# A game's own arms may answer the older three-argument reach; they get no axes.
	if _arms.get_method_argument_count("reach") >= 6:
		_arms.call(
			"reach", grip, fore, pose,
			aim.basis * _grip_axis, aim.basis * _fore_axis, _grip_radius
		)
	else:
		_arms.call("reach", grip, fore, pose)

## Where the support hand is this frame: on the fore-end, or, through a reload of a weapon with
## a magazine, to the well, down with the old magazine and out of sight, back up with the next
## one, and back to the fore-end. Keys in the same shape as the gun's, so the two agree.
func _support_hand() -> Vector3:
	var f := _reload_fraction
	if _seq != null and f > 0.0 and f < 1.0:
		return _seq.left_hand(f)
	if not _has_well or f <= 0.0 or f >= 1.0:
		return _fore_at
	if _feeds:
		return ZeeWeaponPose.sample_keys(_feed_keys, f)[0]
	var below := _well + Vector3(0.0, -0.24, 0.08)
	var keys := [
		[0.0, _fore_at, Vector3.ZERO],
		[0.08, _fore_at, Vector3.ZERO],
		[0.16, _well + Vector3(0.0, -0.03, 0.0), Vector3.ZERO],
		[0.30, below, Vector3.ZERO],
		[0.40, below + Vector3(0.0, -0.04, 0.0), Vector3.ZERO],
		[0.50, _well + Vector3(0.0, -0.08, 0.0), Vector3.ZERO],
		[0.58, _well + Vector3(0.0, -0.035, 0.0), Vector3.ZERO],
		[0.64, _well + Vector3(0.0, -0.03, 0.0), Vector3.ZERO],
		[0.78, _fore_at, Vector3.ZERO],
		[1.0, _fore_at, Vector3.ZERO],
	]
	return ZeeWeaponPose.sample_keys(keys, f)[0]

## The support hand's keys for a gun fed by hand ([member ZeeWeaponArt.load_from]): bolt back, each round fetched, carried and pushed home, bolt closed. Built once per weapon.
## The round is drawn at the hand ([constant FEED_CARRY] above it) for the whole trip, because [method _animate_magazine] reads the hand and the two must not part.
func _build_feed_keys(art: ZeeWeaponArt) -> Array:
	var carry := FEED_CARRY
	var keys: Array = [[0.0, _fore_at, Vector3.ZERO], [0.06, _fore_at, Vector3.ZERO]]
	var start := FEED_START
	if _bolted:
		keys.append([0.12, _bolt, Vector3.ZERO])
		keys.append([0.20, _bolt_back, Vector3.ZERO])
	# Fetched from below the gun, out of frame the first time and from a pouch nearer for the
	# next, so a round at a time does not send the hand off screen between each.
	var far := _well + Vector3(0.0, -0.26, 0.06)
	var near := _entry - carry + Vector3(0.0, -0.13, 0.05)
	var count := maxi(1, art.load_count)
	var span := (FEED_END - start) / float(count)
	for i in count:
		var a := start + span * float(i)
		keys.append([a, far if i == 0 else near, Vector3.ZERO])
		keys.append([a + span * FEED_AT_ENTRY, _entry - carry, Vector3.ZERO])
		keys.append([a + span * FEED_AT_SEAT, _well - carry, Vector3.ZERO])
	if _bolted:
		keys.append([0.75, _bolt_back, Vector3.ZERO])
		keys.append([0.82, _bolt, Vector3.ZERO])
		keys.append([0.92, _fore_at, Vector3.ZERO])
	else:
		keys.append([0.84, _fore_at, Vector3.ZERO])
	keys.append([1.0, _fore_at, Vector3.ZERO])
	return keys

## A fed round in the hand: where it is this frame in the holder's (model) space, and whether
## it is drawn; empty when it is in the gun or not yet fetched.
func _fed_round(fraction: float) -> Dictionary:
	var count := maxi(1, _art.load_count)
	var span := (FEED_END - FEED_START) / float(count)
	var into := fraction - FEED_START
	if into < 0.0 or fraction >= FEED_END:
		return {}
	var local := fmod(into, span) / span
	if local >= FEED_AT_SEAT:
		return {}
	var hand := _support_hand() + FEED_CARRY
	var at := _holder.transform.affine_inverse() * hand
	return {"at": at} if at.is_finite() else {}

## Where the muzzle is right now in world space, for a flash, a tracer and a shell; the simulation never reads it.
func muzzle_transform() -> Transform3D:
	if _weapon == null:
		return global_transform

	return _weapon.global_transform * Transform3D(Basis.IDENTITY, _muzzle)

## 0 at the hip to 1 at full aim.
func aim_fraction() -> float:
	return _aim_fraction
