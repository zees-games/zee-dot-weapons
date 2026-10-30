@tool
class_name ZeeViewModel
extends "zee_view_model_state.gd"

## By path, not by class_name: see the file's own header.
const SightFit := preload("zee_sight_fit.gd")
const ReloadParts := preload("zee_reload_parts.gd")
const Dress := preload("zee_attachment_dress.gd")
const HipHold := preload("zee_hip_hold.gd")
const HandReach := preload("zee_hand_reach.gd")
const ReloadSequence := preload("zee_reload_sequence.gd")
const ReloadProps := preload("zee_reload_props.gd")

## The weapon you see in your own hands. Parent it to the camera; it is told what happened (on_used, on_reload_started)
## and never reads a device, a clock or the arsenal, so it draws a remote player's gun the same way.
## Presentation only: it runs on render frames and never writes to the simulation.

const CHANNEL := "zee.view"

## Emitted once the weapon model for [param id] is in the tree and placed.
## For a muzzle flash, laser or scope overlay that cannot be hung before the model exists.
signal model_ready(id: StringName, weapon: Node3D)

## Every frame, where the hands belong: [param grip] and [param fore] in [param anchor]'s space, for a game that draws its own arms (with [member show_arms] off).
signal hands_reached(anchor: Node3D, grip: Vector3, fore: Vector3, pose: StringName)

@export_group("Wiring")

## The arms. Left null, the view model builds its own on first use.
## A [DotNodeRef], not a path: the host decides per instance.
@export var arms_ref: DotNodeRef = null

@export_group("Behaviour")

## Whether to build and show hands at all.
## A real configuration (non-humanoid characters, a gun with no holder), not a debug switch.
## Turned off after the model is built (a game mounting its own arms once this is in the tree), the built hands go too.
@export var show_arms: bool = true:
	set(value):
		show_arms = value
		if not _built:
			return
		if not value and _arms != null:
			if _arms.get_parent() == _animated:
				_animated.remove_child(_arms)
				_arms.queue_free()
			else:
				_arms.visible = false
			_arms = null
		elif value and _arms == null:
			_build_arms()
			if _art != null and _arms != null:
				_arms.set_pose(_art.pose)
				_reach_for(_art)

## Which skin the hands wear. Passed to [ZeeViewArms] when this builds its own.
@export_file("*.png", "*.jpg", "*.webp") var arm_skin: String = ""

## Hides the whole rig. What a "view model" video setting toggles.
@export var visible_model: bool = true:
	set(value):
		visible_model = value
		visible = value

@export_group("Wall")

## Physics layers the wall probe stops on (the world and bodies; the carrier is skipped). The rig copies its shot effects' mask.
@export_flags_3d_physics var wall_mask: int = 0xFFFFFFFF
## When on, the probe passes through character bodies: a person crossing the muzzle is not a wall and must not slam the weapon.
@export var wall_ignore_characters: bool = true

@export_group("Light")

## The render layer (1 to 20) every mesh of the view model and its arms is drawn on, and the
## only one [member view_light_energy]'s light reaches. 0 leaves the meshes on the default
## layer and builds no light. A game whose camera culls this layer does not see its hands.
@export_range(0, 20) var view_layer: int = 20

## The energy of the view model's own key light, which turns with the camera and lights only the view model. 0 builds none.
## The world's sun is fixed, so turning round leaves the gun lit by ambient alone; a key light keeps its side lit the same way.
@export_range(0.0, 4.0, 0.05) var view_light_energy: float = 0.3

## Where that light comes from, as Euler degrees of the light's own rotation in the camera's
## space: above, behind and to the left, so it rakes across the right side the hold shows.
@export var view_light_rotation: Vector3 = Vector3(-38.0, -32.0, 0.0)

@export_group("Finish")
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

@export_group("Feel")

## Scales sway, bob and kick for everything this rig draws.
@export_range(0.0, 3.0, 0.05) var feel: float = 1.0

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
			var _again := equip(_source_art)


## Sets [member hands_fov] from a horizontal field of view measured on a 4:3 frame, the
## convention a game's `field_of_view` setting already uses, so the two are comparable.
func set_hands_fov_at_4_3(horizontal: float) -> void:
	hands_fov = vertical_from_horizontal_4_3(horizontal)


## The vertical field of view that is [param horizontal] degrees across a 4:3 frame.
static func vertical_from_horizontal_4_3(horizontal: float) -> float:
	return DotViewLens.vertical_from_horizontal_4_3(horizontal)



func _init() -> void:
	add_to_group(&"dot_view_model")


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_build_structure()


# --- Building ---------------------------------------------------------------

func _build_structure() -> void:
	if _built:
		return

	_animated = Node3D.new()
	_animated.name = "Animated"
	add_child(_animated)

	# Aim is a node of its own because the aim hold is turned as well as moved: the hip hold is canted,
	# the aim hold is straight down the sight, and moving only the position brought a canted gun end-on to the middle.
	_aim_node = Node3D.new()
	_aim_node.name = "Aim"
	_animated.add_child(_aim_node)

	_holder = Node3D.new()
	_holder.name = "Holder"
	_aim_node.add_child(_holder)

	if show_arms:
		_build_arms()

	_build_light()
	_built = true


func _build_arms() -> void:
	if arms_ref != null:
		var found := arms_ref.resolve(self)
		if found.ok and found.value is ZeeViewArms:
			_arms = found.value
			_arms.build()
			return

	_arms = ZeeViewArms.new()
	_arms.view_layer = view_layer
	_arms.name = "Arms"
	_arms.skin = arm_skin
	# Under Animated so the hands move with the gun (a reload would otherwise slide it out of them).
	# Not under Aim: carried rigidly to the sight, the shoulders went with the gun; they reach for the aimed hands each frame (_place_hands).
	_animated.add_child(_arms)

	var res := _arms.build()

	if not res.ok:
		# Not fatal, and not even an error: a rig with no hands still draws the weapon,
		# which is what a great many games in this genre ship anyway.
		DotLog.info(
			CHANNEL, "no first-person hands; drawing the weapon alone",
			{"why": res.error.message}
		)


## The view model's own key light. See [member view_light_energy].
func _build_light() -> void:
	if view_light_energy <= 0.0 or view_layer <= 0:
		return

	_light = DirectionalLight3D.new()
	_light.name = "ViewLight"
	_light.light_energy = view_light_energy
	_light.light_cull_mask = 1 << (view_layer - 1)
	# A light for one object a metre from the eye casts nothing worth a shadow map, and it
	# must not draw a second sun in the sky.
	_light.shadow_enabled = false
	_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_light.rotation_degrees = view_light_rotation
	add_child(_light)


# --- Weapons ----------------------------------------------------------------

## Draws [param art]'s weapon, replacing whatever was in hand; rebuilt, not hidden, as every model in the tree is culled per player.
func equip(art: ZeeWeaponArt) -> DotResult:
	_build_structure()

	if art == null:
		clear()
		return DotResult.fail(DotError.CODE_INVALID, "No art to equip.")

	_clear_models()

	_end_sequence()
	_source_art = art
	_art = HipHold.sized(art, ads_rules, position.z)
	art = _art
	_id = art.id
	_pose.weight = art.weight
	_pose.rules = feel_rules
	_pose.feel = maxf(0.0, feel)
	_pose.tunables.draw_keys = art.draw_keys if not art.draw_keys.is_empty() \
		else ZeeWeaponPose.DRAW_KEYS
	_pose.tunables.reload_keys = _default_reload_keys()
	var carry := ZeeWeaponArtTable.sprint_view(art.pose)
	_pose.tunables.sprint_offset = art.sprint_offset if art.sprint_offset.is_finite() else carry[0]
	_pose.tunables.sprint_rotation = art.sprint_rotation if art.sprint_rotation.is_finite() else carry[1]
	var bob := ZeeWeaponArtTable.sprint_bob(art.pose)
	_pose.tunables.sprint_bob = bob.x
	_pose.tunables.sprint_bob_roll = bob.y
	_reload_fraction = 0.0

	_holder.transform = art.view_transform()
	_pose.pivot = _holder.transform.origin  # the kick turns about the grip
	_pose.aim_shift = Vector3.ZERO  # aim is the Aim node's (_apply_aim); a new weapon starts at the hip
	_aim_fraction = 0.0
	_aim_node.transform = Transform3D.IDENTITY

	if _arms != null:
		_arms.set_pose(art.pose)

	if not art.has_model():
		# The fists: hands and no object. Not a failure, not worth a log line.
		_muzzle = Vector3.ZERO
		_reach_for(art)
		model_ready.emit(_id, null)
		return DotResult.success(null)

	_weapon = ZeeModelCache.instantiate(art.model_path)

	if _weapon == null:
		return DotResult.fail(
			DotError.CODE_IO, "No model for %s." % String(art.id), art.model_path
		)

	_weapon.name = "Weapon"
	_holder.add_child(_weapon)
	_set_on_top(_weapon)

	_dress()
	_muzzle = _measure_muzzle(art)
	_fit_sight(art)

	if art.has_magazine():
		if art.magazine_path != "":
			_magazine = _add_part(art.magazine_path, art.magazine_transform())
		else:
			_magazine = _add_built(ReloadParts.build(art.magazine_part), art.magazine_transform())

	for part in Dress.art_parts(art, _holder):
		_set_on_top(part)
		_attachments.append(part)

	_reach_for(art)
	model_ready.emit(_id, _weapon)
	return DotResult.success(null)


## Draws [param fitting]'s attachments on the weapon in hand, and moves the muzzle and the sight line to suit.
func set_fitting(fitting: DotWeaponFitting) -> void:
	_fitting = fitting.duplicate_fitting() if fitting != null else null
	if _weapon == null:
		return
	_dress()
	_muzzle = _measure_muzzle(_art)
	if _sight != null:
		_sight.queue_free()
		_sight = null
	_fit_sight(_art)
	_apply_aim(_ease(_aim_fraction))


func _dress() -> void:
	_dressed = Dress.apply(_weapon, _fitting, _art.model_forward, _dressed)
	for part: Node3D in _dressed.parts:
		_set_on_top(part)


## Puts the hands on this weapon, measured from the weapon itself in the holder's space: a blaster's right hand round its grip,
## the left on the fore-end at 62%, a melee hand round its handle, a grenade's round its middle, each with the held axis.
func _reach_for(art: ZeeWeaponArt) -> void:
	var to_aim := _holder.transform
	var r := HandReach.measure(art, _weapon, _holder)
	var grip: Vector3 = r.grip
	var fore: Vector3 = r.fore
	var grip_axis: Vector3 = r.grip_axis
	var fore_axis: Vector3 = r.fore_axis
	var radius: float = r.radius

	if _arms != null:
		_arms.fit_glove_to(_weapon)
	_has_well = art.has_magazine() and _weapon != null
	_well = to_aim * art.magazine_transform().origin
	# A round fed by hand from somewhere (the top, the muzzle): where its push in starts, and
	# the bolt the hand works first, all in the same space as the well.
	_feeds = _has_well and art.magazine_loose and art.load_from.length_squared() > 0.000001
	_entry = to_aim * (art.magazine_offset + art.load_from)
	_bolted = _feeds and art.bolt_pull.length_squared() > 0.000001
	_bolt = to_aim * art.bolt_at
	_bolt_back = to_aim * (art.bolt_at + art.bolt_pull)

	_grip_at = to_aim * grip
	_fore_at = to_aim * fore
	# After the fore-end: the keys start and end on it.
	_feed_keys = _build_feed_keys(art) if _feeds else []
	_grip_axis = (to_aim.basis * grip_axis).normalized()
	_fore_axis = (to_aim.basis * fore_axis).normalized()
	if _weapon == null:
		# Bare fists, raised: closed round nothing, knuckles forward, leaning in a little.
		_grip_axis = Vector3(-0.35, 1.0, -0.25).normalized()
		_fore_axis = Vector3(0.35, 1.0, -0.25).normalized()
	# In the view's metres: the holder's scale is the art's view_scale.
	_grip_radius = radius * art.view_scale
	_place_hands()


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
	hands_reached.emit(_animated, grip, fore, pose)
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


## Removes whatever is in hand.
func clear() -> void:
	_clear_models()
	_art = null
	_id = &""
	_muzzle = Vector3.ZERO


## The weapon currently drawn, or an empty name.
func equipped() -> StringName:
	return _id


## The drawn weapon's model node, or null. A search by name can find the last one, which is freed only at the frame's end.
func weapon_node() -> Node3D:
	return _weapon


## Where the muzzle is right now in world space, for a flash, a tracer and a shell; the simulation never reads it.
func muzzle_transform() -> Transform3D:
	if _weapon == null:
		return global_transform

	return _weapon.global_transform * Transform3D(Basis.IDENTITY, _muzzle)


## True when the weapon in hand throws a spent case ([member ZeeWeaponArt.ejects]).
func ejects() -> bool:
	return _art != null and _art.ejects and _weapon != null


## Where the ejection port is right now, in world space: the receiver's right side, 45% from stock to muzzle, measured from the mesh bounds.
## The basis is the weapon's, unscaled (+X out of the right side, +Y up, -Z to the muzzle). Effects only.
func eject_transform() -> Transform3D:
	if _weapon == null:
		return global_transform

	var box := HandReach.bounds_in(_weapon, _weapon)
	if box.size == Vector3.ZERO:
		return _weapon.global_transform

	var local := Vector3(
		box.end.x * 0.9, box.position.y + box.size.y * 0.72, box.position.z + box.size.z * 0.55)
	var world := _weapon.global_transform
	return Transform3D(world.basis.orthonormalized(), world * local)


# --- Being told what happened -----------------------------------------------

## Seconds between this weapon's shots, set by the rig; drives the kick spring's rate.
var fire_interval: float = 0.0


## Sets this weapon's kick feel from its profile params (see [method ZeeWeaponPose.Tunables.apply_kick]).
func set_kick_params(params: Dictionary) -> void:
	_pose.tunables.apply_kick(params)


## A use produced [param outcome].
func on_used(outcome: DotWeaponOutcome) -> void:
	if outcome == null or not outcome.used:
		return

	_pose.fire_interval = fire_interval
	_pose.punch(outcome.recoil, outcome.recoil_signed)
	match outcome.kind:
		DotWeaponOutcome.KIND_SWING:
			_pose.swing()
		DotWeaponOutcome.KIND_THROW:
			_pose.throw()


## Recoil with no outcome to hand, for a remote player whose shots arrive as a counter.
func on_fired(recoil: Vector2 = Vector2(0.5, 0.1)) -> void:
	_pose.punch(recoil)


## A melee swing with no outcome to hand (a bash, or a remote player's swing): the swing's keys.
func on_swing() -> void:
	_pose.swing()


## How far recoil should turn the camera this frame, in degrees: x pitch up, y yaw.
## This node cannot apply it: controllers write the camera's angles from scratch each frame, so the game adds it
## where it writes the camera (`DotFpsView.external_angles`).
func view_punch() -> Vector2:
	return _pose.view_punch()


## How far through a switch, 1 fully in hand and 0 fully out of frame.
func on_deploy(fraction: float) -> void:
	_pose.set_deploy(fraction)


## How far through a reload, 0 to 1; the magazine is animated from the same number.
func on_reload(fraction: float) -> void:
	_reload_fraction = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0
	if _seq != null:
		if _reload_fraction > 0.0:
			_seq_ran = true
		elif _seq_ran:
			_end_sequence()
	_pose.set_reload(_reload_fraction)
	_animate_magazine(_reload_fraction)


## The reload being played as phases (zee_reload_sequence.gd), or null for the generic one.
var _seq: ReloadSequence = null
var _seq_ran := false
var _props: ReloadProps = null


## A reload began with [param left] of [param magazine] rounds in: plays the weapon's own phases, sized to what is there.
## [param start_share] is the part before the first round of a reload by the round. Off under `cl_vm_reload_detail` 0.
func on_reload_begin(left: int, magazine: int, start_share: float = 0.0) -> void:
	_end_sequence()
	if _art == null or _weapon == null or _holder == null or feel_rules.reload_detail <= 0.0:
		return
	if ReloadSequence.style_of(_art) == &"generic":
		return
	var to_aim := _holder.transform
	var well: Variant = _well if _has_well and _art.reload.is_empty() else null
	var anchors := ReloadSequence.anchors_for(_grip_at, _fore_at, to_aim * (_weapon.transform * _muzzle), well, _art.reload.get("anchors", {}), to_aim)
	var seq := ReloadSequence.new()
	seq.compose(_art, anchors, magazine, left, start_share)
	if seq.phases.is_empty():
		return
	_seq = seq
	_seq_ran = false
	_pose.tunables.reload_keys = seq.gun_keys
	var props := ReloadProps.new()
	props.name = "ReloadProps"
	props.on_top = _set_on_top
	_holder.add_child(props)
	_props = props


## The sequence playing now, or null.
func reload_sequence() -> ReloadSequence:
	return _seq


## How many reload parts named [param part] are drawn now (every part when empty).
func reload_parts_shown(part: StringName = &"") -> int:
	return _props.shown(part) if _props != null else 0


func _end_sequence() -> void:
	_seq = null
	_seq_ran = false
	if _props != null:
		_props.queue_free()
		_props = null
	if _art != null:
		_pose.tunables.reload_keys = _default_reload_keys()
		if _magazine != null:
			_magazine.visible = true
			_magazine.transform = _art.magazine_transform()


func _default_reload_keys() -> Array:
	return _art.reload_keys if not _art.reload_keys.is_empty() else ZeeWeaponArtTable.reload_keys(_art.pose)


func _animate_sequence(f: float) -> void:
	var out: bool = _seq.own_magazine_out(f)
	if _magazine != null:
		_magazine.visible = not _art.magazine_loose and not out
		_magazine.transform = _art.magazine_transform()
	if _art.hide_during_reload != &"" and _weapon != null:
		var own := _weapon.find_child(String(_art.hide_during_reload), true, false) as Node3D
		if own != null:
			own.visible = not out
	if _props != null:
		var scale := maxf(_holder.transform.basis.get_scale().x, 0.0001)
		_props.show_at(_seq, f if f > 0.0 and f < 1.0 else -1.0, _holder.transform.affine_inverse(), float(_seq.prop_scale) / scale)


## A charged weapon's draw, 0 to 1.
func on_charge(fraction: float) -> void:
	_pose.set_charge(fraction)


## A landing, with the downward speed in metres a second.
func on_landed(impact: float) -> void:
	_pose.land(impact)


## Everything back to rest. A respawn, a teleport, a correction.
func on_reset() -> void:
	_pose.reset()
	_wall.reset()
	_wall_excluded.clear()
	_look_seen = false
	_aim_fraction = 0.0


# --- The frame --------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)


## One frame of the view model, [param delta] seconds long. [method _process] calls it; a
## tool that freezes processing (the range's contact sheet) calls it with a fixed step so
## that "fire frame 4" is the same picture on every machine.
func advance(delta: float) -> void:
	if Engine.is_editor_hint() or not _built:
		return

	_pose.advance(delta, _look_delta(), _speed, _on_floor, _crouched, _strafe_speed(delta))
	_sprint = move_toward(_sprint, 1.0 if _sprinting and sprint_pose else 0.0, delta / SPRINT_SECONDS)
	_pose.set_sprint(_ease(_sprint))
	_advance_aim(delta)
	_animated.transform = _pose.offset()
	_advance_wall(delta)
	_place_hands()
	_apply_hands_lens()
	if _sight != null:
		SightFit.track(_sight, (transform * _animated.transform * _aim_node.transform * _holder.transform).affine_inverse() * Vector3.ZERO)
	# Through a scope the weapon is not drawn: the scope is the view. The built arms go with Animated;
	# a game's own arms (arms_ref) may live anywhere, so they are hidden by name too.
	var scoped := is_scoped()
	_animated.visible = not scoped
	if _arms != null:
		_arms.visible = not scoped


## Pulls the weapon back and up when its muzzle would be inside a wall. The probe is cast against the un-retracted pose, so the answer does not feed back into itself.
func _advance_wall(delta: float) -> void:
	var on := feel_rules.wall_retract > 0.0 and _weapon != null and is_inside_tree()
	_wall.step(ZeeWallSlam.target(self, muzzle_transform().origin, wall_mask, wall_ignore_characters, _wall_exclude()) if on else 0.0, delta)
	if _wall.amount > 0.0:
		_animated.transform = _wall.offset(feel_rules.wall_retract, feel_rules.wall_tilt) * _animated.transform


## The carrier's own body, so the probe never stops on the player it hangs from.
func _wall_exclude() -> Array[RID]:
	if _wall_excluded.is_empty():
		var node: Node = get_parent()
		while node != null and not (node is CollisionObject3D):
			node = node.get_parent()
		if node != null:
			_wall_excluded.append((node as CollisionObject3D).get_rid())
	return _wall_excluded


## The retract and pitch the wall asks of the weapon now, for a suite and a tool.
func wall_amount() -> float:
	return _wall.amount


## The scale that draws the hands at [member hands_fov]. See there.
func _apply_hands_lens() -> void:
	# Only under a camera: the scale is in the camera's own space, and a view model hung
	# anywhere else is in some other space where this would be a distortion, not a lens.
	DotViewLens.apply(self, get_parent() as Camera3D, hands_fov, hands_depth_comp)


## How much X and Y are scaled to draw at [param hands] degrees under a [param camera]-degree
## lens. 1 when either is not a usable field of view.
static func lens_scale(camera: float, hands: float) -> float:
	return DotViewLens.lens_scale(camera, hands)


# --- Aiming -----------------------------------------------------------------

## Holds or releases the aim. Call every frame with the button's state, or on its edges.
func aim(held: bool) -> void:
	_aim_held = held


## The aim button's raw state every frame; held follows it, or a press flips it under toggle rules.
func aim_input(pressed: bool) -> void:
	if _toggles():
		if pressed and not _aim_button_was:
			_aim_held = not _aim_held
	else:
		_aim_held = pressed
	_aim_button_was = pressed


## Whether the sights are being held up (the key, or the toggle's state): what a game sends as its aim button.
func is_aim_held() -> bool:
	return _aim_held


## The range at which the hip barrel crosses the screen's centre (metres), 0 when it is stood up by `hip_lean` instead.
func hip_zero() -> float:
	var id := _art.id if _art != null else &""
	return ads_rules.hip_zero_for(id) if ads_rules != null else float(ZeeAdsRules.SPECS["hip_zero"]["default"])


func _toggles() -> bool:
	return ads_rules != null and _art != null and ads_rules.toggle_for(_art.id)


## 0 at the hip to 1 at full aim.
func aim_fraction() -> float:
	return _aim_fraction


## Whether the weapon in hand can be aimed at all (melee and throwables cannot).
func can_aim() -> bool:
	return _art != null and _art.aim_enabled and (ads_rules == null or ads_rules.enabled_for(_art.id))


## How big a muzzle flash is drawn: 1 at the hip, the scope's own zoom through a scope, which cancels the magnification.
func flash_scale() -> float:
	return clampf(aim_fov_scale(), 0.1, 1.0) if is_scoped() else 1.0


## The field-of-view multiplier this frame: 1 at the hip, the zoom at full aim; the game applies it (`DotFpsView.external_fov_scale`).
func aim_fov_scale() -> float:
	if _art == null:
		return 1.0
	var base := float(_dressed.get("zoom", 0.0))
	base = base if base > 0.0 else _art.aim_zoom
	var zoom := base if ads_rules == null else ads_rules.zoom_for(_art.id, base)
	return lerpf(1.0, zoom, _ease(_aim_fraction))


## Whether the view is through a scope right now: a scoped weapon at (nearly) full aim.
func is_scoped() -> bool:
	return _art != null and (_art.aim_scoped or _dressed.get("scoped", false)) and _aim_fraction >= 0.95


## Whether the weapon in hand is looked through (a scope), at any point of the aim-in.
func has_scope() -> bool:
	return _art != null and (_art.aim_scoped or _dressed.get("scoped", false))


## The weapon's overrides of the default scope look, applied by [method ZeeScopeOverlay.follow].
func scope_style() -> Dictionary:
	return _art.scope_style if _art != null else {}


## How visible the scope's surround is, 0 to 1: it fades in over the last of the aim-in, not at the end.
func scope_fraction() -> float:
	if not has_scope():
		return 0.0
	var start := 0.6 if ads_rules == null else ads_rules.scope_fade_start_for(_art.id)
	return smoothstep(start, 1.0, _aim_fraction)


## The scope lens's size, a share of its full size: small at the start of the aim-in, growing toward the eye.
func scope_lens_scale() -> float:
	if not has_scope():
		return 1.0
	var least := 0.3 if ads_rules == null else ads_rules.scope_lens_min_for(_art.id)
	return lerpf(least, 1.0, _ease(_aim_fraction))


func _advance_aim(delta: float) -> void:
	# A reload lowers the aim: the keys turn the gun about the rear sight, centimetres from the eye, and swing it out of view.
	var reloading := _reload_fraction > 0.0 and _reload_fraction < 1.0
	var target := 1.0 if (_aim_held and can_aim() and not reloading) else 0.0
	var time := _art.aim_time if _art != null else 0.16
	if ads_rules != null and _art != null:
		time = ads_rules.aim_time_for(_art.id, time)
		_pose.aim_sway_scale = ads_rules.sway_for(_art.id)
	if not can_aim():
		_aim_held = false
	_aim_fraction = move_toward(_aim_fraction, target, delta / maxf(time, 0.01))
	_pose.set_aim(_ease(_aim_fraction))
	_apply_aim(_ease(_aim_fraction))


## Moves and turns the Aim node so the holder sits [param f] of the way from the art's hip hold to its aim hold,
## and tells the pose where the grip now is so a kick turns about it.
func _apply_aim(f: float) -> void:
	if _art == null or _aim_node == null:
		return

	var hip := _art.view_transform()
	if _sight != null:
		SightFit.fade(_sight, f)
	if f <= 0.0:
		_aim_node.transform = Transform3D.IDENTITY
		_pose.pivot = hip.origin
		return

	var sight := _aim_target()
	var turn := hip.basis.get_rotation_quaternion().slerp(
		sight.basis.get_rotation_quaternion(), f
	)
	var now := Transform3D(
		Basis(turn).scaled(Vector3.ONE * _art.view_scale), hip.origin.lerp(sight.origin, f)
	)
	_aim_node.transform = now * hip.affine_inverse()
	# Aimed, the kick turns about the rear sight, not the grip, or the sight picture jumps up the screen.
	_pose.pivot = now.origin.lerp(now * _sight_line.rear, f) if not _sight_line.is_empty() \
		else now.origin


## The holder's transform at full aim: down the measured sight line, or the art's written
## aim hold when there is none.
func _aim_target() -> Transform3D:
	return _sight_aim if not _sight_line.is_empty() else _art.aim_transform()


## Fits [param art]'s sight on the mesh just built (see zee_sight_fit.gd) and keeps the aim hold that puts it through the eye.
func _fit_sight(art: ZeeWeaponArt) -> void:
	_sight_line = {}
	var camera := get_parent() as Camera3D
	var near := (camera.near if camera != null else 0.05) + NEAR_MARGIN
	var dot := ads_rules.sight_dot_for(art.id) if ads_rules != null else float(ZeeAdsRules.SPECS["sight_dot"]["default"])
	var fitted := SightFit.fit(art, _weapon, _holder, _dressed.get("line", {}), near, dot)
	if not fitted.is_empty():
		_sight_line = fitted.line
		_sight_aim = fitted.aim
		_sight = fitted.sight
	var roots: Array = [_weapon]
	roots.append_array(_dressed.get("parts", []))
	var red := SightFit.cut(art, ads_rules, roots, _holder, _aim_target(), _sight_line)
	if red != null and _sight != null:
		_sight.add_child(red)
	elif red != null:
		_sight = red
	if _sight != null:
		_holder.add_child(_sight)
		_set_on_top(_sight)


## The sight's rear and front points this frame in the camera's space (before the hands' lens), as `{rear, front}`; empty without a sight.
func sight_points() -> Dictionary:
	if _sight_line.is_empty() or _animated == null:
		return {}
	var to_view := _animated.transform * _aim_node.transform * _holder.transform
	return {"rear": to_view * (_sight_line.rear as Vector3), "front": to_view * (_sight_line.front as Vector3)}


## Smoothstep, so the weapon leaves the hip and arrives at the eye gently.
static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Whether the carrier is sprinting: the weapon lowers and swings to the side, blended over [constant SPRINT_SECONDS].
func set_sprinting(on: bool) -> void:
	_sprinting = on


## Where the sprint carry is, 0 (hip) to 1.
func sprint_fraction() -> float:
	return _sprint


## Tells the rig how the holder is moving and looking this frame.
## [param look] is absolute yaw and pitch in degrees (the rig takes the difference itself, so sway is computed once);
## [param strafe] is sideways ground speed in m/s, positive right; left out, measured from this node's own movement.
func drive(look: Vector2, speed: float, on_floor: bool, crouched: bool = false, strafe: float = NAN) -> void:
	_strafe_given = strafe
	_look = look
	_speed = speed
	_on_floor = on_floor
	_crouched = crouched


## Sideways speed this frame, m/s, to the right of the view. Measured as the camera's world
## movement across its own right axis when the game did not say; a teleport (a jump of more
## than 30 m/s) is no strafe, and the first frame has nothing to compare with.
func _strafe_speed(delta: float) -> float:
	if not is_nan(_strafe_given):
		return _strafe_given
	if not is_inside_tree():
		return 0.0
	var origin := global_position
	var moved := origin - _last_origin
	var seen := _origin_seen
	_last_origin = origin
	_origin_seen = true
	if not seen or delta <= 0.0:
		return 0.0
	var side := moved.dot(global_transform.basis.x.normalized()) / delta
	return side if absf(side) < 30.0 else 0.0


func _look_delta() -> Vector2:
	if not _look_seen:
		_look_seen = true
		_last_look = _look
		return Vector2.ZERO

	# Yaw wraps, and the wrap is the bug: turning from 179 to -179 degrees is two
	# degrees of movement and reads as 358 without this, which throws the weapon clear
	# off the screen once per full turn.
	var delta := Vector2(
		wrapf(_look.x - _last_look.x, -180.0, 180.0), _look.y - _last_look.y
	)
	_last_look = _look
	return delta


# --- Internals --------------------------------------------------------------

## Drops the magazine out and slides a fresh one in, if there is one to animate.
func _animate_magazine(fraction: float) -> void:
	if _seq != null:
		_animate_sequence(clampf(fraction, 0.0, 1.0))
		return
	if _magazine == null or _art == null:
		return

	var f := clampf(fraction, 0.0, 1.0)
	var rest := _art.magazine_transform()

	# The gun's own magazine node is out of the gun from when the hand pulls it (0.20) to the seat.
	if _art.hide_during_reload != &"" and _weapon != null:
		var own := _weapon.find_child(String(_art.hide_during_reload), true, false) as Node3D
		if own != null:
			own.visible = not (f >= 0.20 and f < 0.58)

	# Timed to the reload keys (ZeeWeaponPose.RELOAD_KEYS_*) and `_support_hand`: out while the gun rolls onto its side (0.10-0.28),
	# in the hand from 0.36, seated with the jolt at 0.58. Visible throughout it reads as the gun shaking; rising from nothing, as a hand reaching for air.
	var shown := true
	var at := rest.origin
	var basis := rest.basis

	if _feeds:
		# Fetched, carried to where its push starts and pushed home (_build_feed_keys).
		var fed := _fed_round(f)
		shown = not fed.is_empty()
		if shown:
			at = fed.at
	elif _art.magazine_loose:
		# A round fed by hand: in sight only while it is carried in.
		shown = f >= 0.36 and f < 0.58
		if shown and _holder != null:
			# Held up between the fingertips, higher than a magazine: a round inside the fist
			# is a hand that fetched nothing.
			var carried := _holder.transform.affine_inverse() * (_support_hand() + Vector3(0.0, 0.065, 0.0))
			at = carried if carried.is_finite() else rest.origin
	elif f >= 0.10 and f < 0.28:
		var drop := (f - 0.10) / 0.18
		# Falls, faster as it goes, and tips forward off the hand's line.
		at = rest.origin + Vector3(0.0, -0.40 * drop * drop - 0.04 * drop, 0.02 * drop)
		basis = rest.basis * Basis(Vector3.RIGHT, deg_to_rad(-35.0 * drop))
	elif f >= 0.28 and f < 0.36:
		shown = false
	elif f >= 0.36 and f < 0.58 and _holder != null:
		# Where the support hand is, a little above the palm, in the holder's (model) space.
		var settle := clampf((f - 0.36) / 0.22, 0.0, 1.0)
		var carry := _art.magazine_carry.lerp(Vector3(0.0, 0.035, 0.0), settle * settle * settle)
		var hand := _support_hand() + carry
		var held := _holder.transform.affine_inverse() * hand
		at = held if held.is_finite() else rest.origin
		basis = rest.basis * Basis(Vector3.RIGHT, deg_to_rad(-20.0 * (1.0 - settle)))

	_magazine.visible = shown
	_magazine.transform = Transform3D(basis, at)


## Puts a part built in code ([method _add_part]'s other half) on the weapon.
func _add_built(part: Node3D, at: Transform3D) -> Node3D:
	if part == null:
		return null
	_holder.add_child(part)
	part.transform = at
	_set_on_top(part)
	return part


func _add_part(path: String, at: Transform3D) -> Node3D:
	if path == "":
		return null

	var part := ZeeModelCache.instantiate(path)

	if part == null:
		return null

	_holder.add_child(part)
	part.transform = at
	_set_on_top(part)
	return part


## Measures the muzzle, honouring an override on the art.
func _measure_muzzle(art: ZeeWeaponArt) -> Vector3:
	var distance := art.muzzle_distance

	if distance <= 0.0:
		distance = ZeeModelCache.muzzle_distance(art.model_path, art.model_forward)

	distance = maxf(distance, float(_dressed.get("reach", 0.0)))
	return art.model_forward.normalized() * distance + art.muzzle_offset


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


## Builds [param art]'s view of the weapon once and drops it again, so the model is loaded,
## its materials made and its hand spans measured before the weapon is first drawn in play.
## Call it on a spare view model under a loading cover, one weapon a frame.
func prewarm(art: ZeeWeaponArt) -> void:
	var _r := equip(art)
	clear()


func _clear_models() -> void:
	for node in [_weapon, _magazine, _sight]:
		if node != null:
			node.queue_free()
	_sight = null
	_sight_line = {}
	_dressed = {}
	_fitting = null

	for node in _attachments:
		node.queue_free()

	_weapon = null
	_magazine = null
	_attachments.clear()


func describe() -> Dictionary:
	return {
		"equipped": String(_id),
		"has_model": _weapon != null,
		"magazine": _magazine != null,
		"attachments": _attachments.size(),
		"arms": _arms.describe() if _arms != null else {},
		"reload": _seq.describe() if _seq != null else {},
		"pose": _pose.describe(),
		"muzzle": _muzzle,
		"aim": "%.2f%s%s" % [_aim_fraction, " held" if _aim_held else "", " scoped" if is_scoped() else ""],
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("view model: %s%s" % [
		String(_id) if _id != &"" else "(nothing)",
		"" if _weapon != null else " (no mesh)",
	])
	out.append("  muzzle %.3f m out, %d attachment(s)" % [
		_muzzle.length(), _attachments.size()
	])
	out.append("  %s" % str(_pose.describe()))
	return out


static var _view_materials: Dictionary = {}
static var _view_sources: Array = []

