@tool
class_name ZeeViewModel
extends "zee_view_model_aim.gd"

const ReloadParts := preload("zee_reload_parts.gd")
const Dress := preload("zee_attachment_dress.gd")
const HipHold := preload("zee_hip_hold.gd")
const ReloadProps := preload("zee_reload_props.gd")

## The weapon you see in your own hands. Parent it to the camera; it is told what happened (on_used, on_reload_started)
## and never reads a device, a clock or the arsenal, so it draws a remote player's gun the same way.
## Presentation only: it runs on render frames and never writes to the simulation.

const CHANNEL := "zee.view"

## Emitted once the weapon model for [param id] is in the tree and placed.
## For a muzzle flash, laser or scope overlay that cannot be hung before the model exists.
signal model_ready(id: StringName, weapon: Node3D)


@export_group("Wiring")

## The arms. Left null, the view model builds its own on first use.
## A [DotNodeRef], not a path: the host decides per instance.
@export var arms_ref: DotNodeRef = null

@export_group("Behaviour")

## How far into the aim-in a scoped weapon's arms are hidden: past it the raised gun is out of the arms' reach and the scope covers the view.
@export_range(0.0, 1.0, 0.01) var scope_arms_hide: float = 0.6
## A game's setting (a cvar) that beats the weapon's art and [member scope_arms_hide]; below 0 is off.
const ChargeFx := preload("zee_charge_fx.gd")
const BeltFeed := preload("zee_belt_feed.gd")
## Where this view gets its meshes, pose tables and keys; a pack with its own art assigns a [ZeeArtProvider] subclass.
var art_provider: ZeeArtProvider = ZeeArtProvider.new()
var _belt: Node3D = null
var _charge_fx: Node3D = null

var scope_arms_hide_override: float = -1.0

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

## Draws the view model again in a pass with no world in it while it is pressed against one, so a wall cannot hide the gun. Costs a second render of the view layer only while active.
@export var wall_overlay: bool = true


@export_group("Light")


## The energy of the view model's own key light, which turns with the camera and lights only the view model. 0 builds none.
## The world's sun is fixed, so turning round leaves the gun lit by ambient alone; a key light keeps its side lit the same way.
@export_range(0.0, 4.0, 0.05) var view_light_energy: float = 0.3

## Where that light comes from, as Euler degrees of the light's own rotation in the camera's
## space: above, behind and to the left, so it rakes across the right side the hold shows.
@export var view_light_rotation: Vector3 = Vector3(-38.0, -32.0, 0.0)

@export_group("Finish")

@export_group("Feel")

## Scales sway, bob and kick for everything this rig draws.
@export_range(0.0, 3.0, 0.05) var feel: float = 1.0


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
	if wall_overlay and view_layer > 0:
		_overlay = ZeeViewOverlay.new()
		add_child(_overlay)
		_overlay.setup(self, view_layer)


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
	_hands_frame = Node3D.new()
	_hands_frame.name = "HandsFrame"
	add_child(_hands_frame)

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
	var carry := art_provider.sprint_view(art.pose)
	_pose.tunables.sprint_offset = art.sprint_offset if art.sprint_offset.is_finite() else carry[0]
	_pose.tunables.sprint_rotation = art.sprint_rotation if art.sprint_rotation.is_finite() else carry[1]
	var bob := art_provider.sprint_bob(art.pose)
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

	_weapon = art_provider.instantiate(art.model_path)

	if _weapon == null:
		return DotResult.fail(
			DotError.CODE_IO, "No model for %s." % String(art.id), art.model_path
		)

	_weapon.name = "Weapon"
	_holder.add_child(_weapon)
	_set_on_top(_weapon)

	_dress()
	_muzzle = _measure_muzzle(art)
	_build_belt(art)
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


## The multiple of the default speed this weapon's cases leave at ([member ZeeWeaponArt.eject_speed]).
func eject_speed() -> float:
	return _art.eject_speed if _art != null else 1.0


## The moving belt of a belt-fed gun, or null.
func belt_feed() -> Node3D:
	return _belt


func _build_belt(art: ZeeWeaponArt) -> void:
	_belt = null
	if not art.belt_feed or _weapon == null:
		return
	var box := HandReach.bounds_in(_weapon, _weapon)
	if box.size == Vector3.ZERO:
		return
	var tray := Vector3(box.position.x * 0.8, box.position.y + box.size.y * 0.62, box.position.z + box.size.z * 0.5) + art.belt_offset
	_belt = BeltFeed.new()
	_belt.name = "BeltFeed"
	_weapon.add_child(_belt)
	_belt.build(tray + Vector3(-0.07, -0.10, 0.0), tray)


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

	var f := _art.eject_port if _art != null and _art.eject_port != Vector3.ZERO else Vector3(0.9, 0.72, 0.55)
	var local := Vector3(box.end.x * f.x, box.position.y + box.size.y * f.y, box.position.z + box.size.z * f.z)
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
	if _belt != null and outcome.kind == DotWeaponOutcome.KIND_SHOT:
		_belt.step()
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


static var _parts_warmed := false
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
	return _art.reload_keys if not _art.reload_keys.is_empty() else art_provider.reload_keys(_art.pose)


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
	if fraction > 0.0 and _charge_fx == null and _built:
		_charge_fx = ChargeFx.new()
		_charge_fx.name = "ChargeFx"
		_charge_fx.follow = muzzle_transform
		add_child(_charge_fx)
	if _charge_fx != null:
		_charge_fx.set_charge(fraction)


## The weapon fired this frame, for the charge ball to tell a shot from a fizzle.
func note_fired() -> void:
	if _charge_fx != null:
		_charge_fx.note_fired()


## The charge ball, or null before the weapon has been charged. For a suite.
func charge_fx() -> Node3D:
	return _charge_fx


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
	if _charge_fx != null:
		_charge_fx.reset()


# --- The frame --------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)


## One frame of the view model, [param delta] seconds long. [method _process] calls it; a
## tool that freezes processing (the range's contact sheet) calls it with a fixed step so
## that "fire frame 4" is the same picture on every machine.
func advance(delta: float) -> void:
	if Engine.is_editor_hint() or not _built:
		return

	if _belt != null:
		_belt.advance(delta)

	_strafe_now = _strafe_speed(delta)
	_pose.advance(delta, _look_delta(), _speed, _on_floor, _crouched, _strafe_now)
	_sprint = move_toward(_sprint, 1.0 if _sprinting and sprint_pose else 0.0, delta / SPRINT_SECONDS)
	_pose.set_sprint(_ease(_sprint))
	_advance_aim(delta)
	_animated.transform = _pose.offset()
	_advance_wall(delta)
	if _overlay != null:
		# Hysteresis: the pass must not flicker at the edge of contact.
		_overlay.update(_wall.amount > (0.002 if _overlay.is_active() else 0.02), get_parent() as Camera3D)
	# The lens first: the hands are handed out in world space, and a frame that runs before any _process has drawn one must not
	# hand out a grip at the unscaled size (the selftest's first frame after equip did).
	_apply_hands_lens()
	_place_hands()
	if _sight != null:
		SightFit.track(_sight, (transform * _animated.transform * _aim_node.transform * _holder.transform).affine_inverse() * Vector3.ZERO)
	# Through a scope the weapon is not drawn: the scope is the view. The built arms go with Animated;
	# a game's own arms (arms_ref) may live anywhere, so they are hidden by name too.
	var scoped := is_scoped()
	_animated.visible = scope_is_lens() or not scoped
	if _arms != null:
		_arms.visible = scope_is_lens() or not (scoped or arms_hidden_by_scope())


## The scale that draws the hands at [member hands_fov]. See there.
func _apply_hands_lens() -> void:
	# Only under a camera: the scale is in the camera's own space, and a view model hung
	# anywhere else is in some other space where this would be a distortion, not a lens.
	DotViewLens.apply(self, get_parent() as Camera3D, hands_fov, hands_depth_comp)


# --- Aiming -----------------------------------------------------------------


## The aim fraction the arms hide at: the override, else the weapon's art key, else [member scope_arms_hide].
func scope_arms_hide_at() -> float:
	if scope_arms_hide_override >= 0.0:
		return scope_arms_hide_override
	return _art.scope_arms_hide if _art != null and _art.scope_arms_hide >= 0.0 else scope_arms_hide


## Whether a scoped weapon's arms are hidden: from [method scope_arms_hide_at] of the aim-in on.
func arms_hidden_by_scope() -> bool:
	return not scope_is_lens() and _art != null and (_art.aim_scoped or _dressed.get("scoped", false)) and _aim_fraction >= scope_arms_hide_at()


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

	var part := art_provider.instantiate(path)

	if part == null:
		return null

	_holder.add_child(part)
	part.transform = at
	_set_on_top(part)
	return part


## Measures the muzzle, honouring an override on the art.
func _measure_muzzle(art: ZeeWeaponArt) -> Vector3:
	if art.muzzle_socket.is_finite():
		return art.muzzle_socket

	var distance := art.muzzle_distance

	if distance <= 0.0:
		distance = art_provider.muzzle_distance(art.model_path, art.model_forward)

	distance = maxf(distance, float(_dressed.get("reach", 0.0)))
	return art.model_forward.normalized() * distance + art.muzzle_offset


## Builds [param art]'s view of the weapon once and drops it again, so the model is loaded,
## its materials made and its hand spans measured before the weapon is first drawn in play.
## Call it on a spare view model under a loading cover, one weapon a frame.
func prewarm(art: ZeeWeaponArt) -> void:
	var _r := equip(art)
	clear()
	if not _parts_warmed:
		_parts_warmed = true
		for node in ReloadParts.build_all():
			_set_on_top(node)
			node.free()


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
	_belt = null
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


