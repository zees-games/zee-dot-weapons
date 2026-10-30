@tool
class_name ZeeWorldModel
extends Node3D

## The weapon everybody [i]else[/i] sees, hanging off a character's hand.
##
## [b]Not a second copy of [ZeeViewModel], and the difference is the point.[/b] A view
## model is drawn on top of the world at an exaggerated scale, sways with the camera and
## exists for exactly one viewer. A world model is an object in the world: it is
## depth-tested, it casts a shadow, it is the right size, and thirty of them can be on
## screen at once. Sharing one node between the two jobs means either a first-person
## weapon that clips through walls or a third-person weapon somebody can see through a
## floor.
##
## [b]It is attached by duck typing, never by class.[/b] `attach_to` takes any node that
## answers `attachment(point)` — which dot-player-char's visual does and a game's own rig
## can — and this file mentions no character class at all, because a script that
## references a `class_name` the project does not have fails to parse and takes every
## script that references [i]it[/i] down with it.
##
## [b]Recoil is smaller here and that is deliberate.[/b] The kick a player feels in their
## own hands is a feel effect tuned for one viewer; applied at full strength to a
## character twenty metres away it reads as the weapon coming loose. A fraction of it is
## enough to tell a watcher that the gun went off.

# No CHANNEL: a drawer. Its one failure, a model that will not load, is reported once by
# ZeeModelCache and handed back as a DotResult; "nowhere to attach" is headless, not wrong.

## How much of a weapon's recoil a watcher sees.
const Dress := preload("zee_attachment_dress.gd")

const RECOIL_SHARE := 0.35

# --- Authored motion ----------------------------------------------------------
#
# [b]A swing and a throw are keys here too, for the view model's reason[/b] ([ZeeWeaponPose]'s
# SWING_KEYS): a melee weapon has no recoil, so a watcher saw somebody's knife ride the arm's
# slash rigid in the hand, pointing where the held-gun pose points, and a grenade thrown from a
# hand that never moved. Each key is [t, position in metres, rotation in degrees (pitch up,
# yaw left, roll counter-clockwise)] in the hand's frame (-Z the way the person faces, +Y up),
# turned about the grip, on top of [method ZeeWeaponArt.world_transform], read through
# [method ZeeWeaponPose.sample_keys]. [b]Not the view model's keys[/b]: those are in the camera's
# frame at the view model's scale, and the arm under this one already moves (the person's
# slash overlay), so these are the wrist's share only: cocked back as the arm comes up, cut
# through as it comes down, followed through and back.

## A melee swing, timed to the person's slash overlay (the arm is up at about 0.12 s and through
## by 0.3 s at the rate the family plays it).
const SWING_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.22, Vector3(0.0, 0.03, 0.04), Vector3(65.0, -15.0, -10.0)],
	[0.42, Vector3(0.0, 0.0, -0.05), Vector3(-35.0, 30.0, 20.0)],
	[0.58, Vector3(0.0, -0.02, -0.03), Vector3(-55.0, 38.0, 25.0)],
	[0.82, Vector3(0.0, 0.0, 0.0), Vector3(-15.0, 10.0, 6.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

const SWING_SECONDS := 0.5

## A throw: the wrist cocked back as the arm swings forward, flicked through, and the weapon gone
## from [constant THROW_RELEASE] (the projectile is the game's, and a grenade still in the hand
## beside it is two grenades) until it is back in the hand at [constant THROW_BACK]. The arm is
## the person's: a thrown weapon is held with empty-handed arms, which have no throw of their
## own, so [method throw] asks the person it hangs from for the slash overlay (see
## [method _person]): up past the head and over, an overhand throw's path. Without an arm under
## it a grenade moved by keys alone floated away from a hand that stayed where it was, and the
## punch overlay punches with the other hand.
const THROW_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.20, Vector3(0.0, 0.03, 0.05), Vector3(55.0, 0.0, -8.0)],
	[0.36, Vector3(0.0, 0.02, -0.04), Vector3(-30.0, 0.0, 4.0)],
	[0.60, Vector3(0.0, 0.0, -0.03), Vector3(-40.0, 0.0, 0.0)],
	[0.85, Vector3(0.0, 0.0, 0.0), Vector3(-8.0, 0.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

const THROW_SECONDS := 0.55

## The fractions of a throw between which the thrown weapon is not in the hand.
const THROW_RELEASE := 0.36
const THROW_BACK := 0.9

## A watcher's reload, in the hand's frame like the swing: the gun dipped and rolled so its well faces the support
## hand, which goes from the fore-end to the well, down to the belt and back once per cycle (one reload, or one round).
const RELOAD_DIP := Vector3(0.0, -0.05, 0.03)
const RELOAD_TURN := Vector3(-18.0, 12.0, 38.0)
const RELOAD_SUPPORT_KEYS := [
	[0.0, Vector3(0.0, 0.0, 0.0), Vector3.ZERO],
	[0.25, Vector3(1.0, 0.0, 0.0), Vector3.ZERO],
	[0.5, Vector3(1.0, 1.0, 0.0), Vector3.ZERO],
	[0.75, Vector3(1.0, 0.0, 0.0), Vector3.ZERO],
	[0.9, Vector3(1.0, 0.0, 0.0), Vector3.ZERO],
	[1.0, Vector3(0.0, 0.0, 0.0), Vector3.ZERO],
]

@export_group("Attachment")

## The attachment point on the character to hang from.
##
## Any node answering `attachment(point)`. The name is the character rig's to define;
## `right_hand` is what dot-player-char ships.
@export var mount: StringName = &"right_hand"

@export_group("Behaviour")

## Whether the weapon casts a shadow.
##
## On by default because a weapon with no shadow floats, and a floating weapon is one of
## the few third-person artefacts a player will actually mention.
@export var cast_shadow: bool = true

## Hides the model while the character is switching weapons.
##
## The third-person counterpart of the view model's deploy animation, and much simpler:
## nobody watching can tell a holster from a deploy at range, so it is a visibility
## toggle rather than an animation.
@export var hide_while_switching: bool = true

## Whether a shot is drawn and heard from this hand. See [method on_fired].
@export var effects: bool = true

## Whether the report is heard, when [member effects] draws the shot.
##
## [b]Off for a game that already has a sound for somebody else's shot[/b] — one that plays
## a use by its kind from the replicated counter, before any of this pack's art was drawn.
## Leaving both on is two reports for one shot from the same place; turning [member effects]
## off to stop it throws away the flash and the tracer, which are the part a watcher needs.
## Set with `set(&"sounds", …)` from a delivered game, because a shell built before this
## property existed fails to parse a pack that names it.
@export var sounds: bool = true

var _holder: Node3D = null
var _weapon: Node3D = null
var _attachments: Array[Node3D] = []
var _dressed: Dictionary = {}
var _fitting: DotWeaponFitting = null
var _fit_code: int = -1

## The catalogue [method on_fitted] decodes a replicated fitting against; the arsenal's own.
var attachments: DotWeaponAttachments = null
var _art: ZeeWeaponArt = null
var _id: StringName = &""
var _fx: ZeeShotFx = null

## Recoil offset in metres and its decay, so a watcher sees the gun move when it fires.
var _kick: float = 0.0

## The swing or throw playing: its keys, its length, and how far through it is (1 is none).
var _action_keys: Array = []
var _action_seconds: float = SWING_SECONDS
var _action: float = 1.0
var _action_hides: bool = false

var _built: bool = false

## The person this hangs from (duck-typed, see [method _person]), the sprint carry blended in (read from
## it), and the support hand's place in the holder's space, [constant Vector3.INF] for one hand.
var _owner_cache: Object = null
var _sprint: float = 0.0
var _support_local := Vector3.INF
var _support_sent: bool = false
var _sprint_was_on: bool = false

## The reload a watcher sees: whether one is on, its blend in and out, time into it and one cycle's length.
var _reloading: bool = false
var _reload_blend: float = 0.0
var _reload_time: float = 0.0
var _reload_period: float = 1.5


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_build()


func _build() -> void:
	if _built:
		return

	_holder = Node3D.new()
	_holder.name = "Holder"
	add_child(_holder)
	_built = true


# --- Attaching --------------------------------------------------------------

## Hangs this model off [param character]'s [member mount] point.
##
## [b]Returning false is not an error.[/b] A dedicated server has no character model, a
## 2D game has no hand, and a rig that treats "nowhere to attach" as a failure cannot run
## headless — which is the one place this whole family insists on being able to run.
func attach_to(character: Object) -> bool:
	if character == null or not character.has_method("attachment"):
		return false

	var point: Variant = character.call("attachment", mount)

	if not (point is Node):
		return false

	if get_parent() != null:
		get_parent().remove_child(self)

	(point as Node).add_child(self)
	transform = Transform3D.IDENTITY
	return true


# --- Weapons ----------------------------------------------------------------

## Draws [param art]'s weapon at the hand, replacing whatever was there.
func equip(art: ZeeWeaponArt) -> DotResult:
	_build()
	_clear_models()

	_art = art

	if art == null:
		_id = &""
		return DotResult.fail(DotError.CODE_INVALID, "No art to equip.")

	_id = art.id
	_holder.transform = _rest()
	_support_local = Vector3.INF

	if not art.has_model():
		return DotResult.success(null)

	_weapon = ZeeModelCache.instantiate(art.model_path)

	if _weapon == null:
		return DotResult.fail(
			DotError.CODE_IO, "No model for %s." % String(art.id), art.model_path
		)

	_weapon.name = "Weapon"
	_holder.add_child(_weapon)

	# Attachments come across, magazines do not: a watcher cannot see a magazine fall
	# out at range, and thirty players each carrying one extra mesh they cannot see is
	# thirty meshes being culled every frame for nothing.
	_attachments.append_array(Dress.art_parts(art, _holder))

	_apply_shadows()
	_support_local = _support_point_for(art)
	return DotResult.success(null)


## Draws [param fitting]'s attachments on the weapon in hand, and moves the muzzle to the suppressor's end.
func set_fitting(fitting: DotWeaponFitting) -> void:
	_fitting = fitting.duplicate_fitting() if fitting != null else null
	if _weapon == null or _art == null:
		return
	_dressed = Dress.apply(_weapon, _fitting, _art.model_forward, _dressed)
	_apply_shadows()


## Follows a carrier's replicated [code]net_fitted[/code] [param code]; needs [member attachments] to decode it.
func on_fitted(code: int) -> void:
	if code == _fit_code or attachments == null or _id == &"":
		return
	_fit_code = code
	var base := ZeeWeaponPack.catalogue().get_def(_id)
	if base != null and attachments.code_bits(base) <= DotWeaponNetSync.FITTED_BITS:
		set_fitting(attachments.decode(base, code))


func clear() -> void:
	_send_support(false)
	_clear_models()
	_art = null
	_id = &""


func equipped() -> StringName:
	return _id


## Where this weapon's muzzle is in the world, for an effect a watcher can see.
func muzzle_transform() -> Transform3D:
	if _weapon == null or _art == null:
		return global_transform

	var distance := _art.muzzle_distance

	if distance <= 0.0:
		distance = ZeeModelCache.muzzle_distance(_art.model_path, _art.model_forward)

	distance = maxf(distance, float(_dressed.get("reach", 0.0)))

	return _weapon.global_transform * Transform3D(
		Basis.IDENTITY,
		_art.model_forward.normalized() * distance + _art.muzzle_offset
	)


# --- Being told what happened -----------------------------------------------

## The weapon fired. [param recoil] is the pitch and yaw a behaviour asked for, and
## [param kind] a [ZeeWeaponNet] kind number.
##
## [param with_effects] draws the shot from this hand — a flash, a tracer along the barrel
## and the report — and is what a watcher sees of somebody else firing. It stands down by
## itself when the carrier's own first-person rig is on this machine, because that rig has
## already drawn the shot from the view model's muzzle and a second report a few
## centimetres away is the same gun going off twice.
func on_fired(
	recoil: Vector2 = Vector2(0.5, 0.1),
	kind: int = ZeeWeaponNet.KIND_SHOT,
	with_effects: bool = true
) -> void:
	if not is_finite(recoil.x):
		return
	match kind:
		ZeeWeaponNet.KIND_SWING:
			swing()
		ZeeWeaponNet.KIND_THROW:
			throw()
		_:
			_kick = minf(_kick + recoil.x * 0.008 * RECOIL_SHARE, 0.08)

	if with_effects and effects and is_inside_tree() and not _carrier_draws_its_own():
		_shot_fx().play_remote(kind, muzzle_transform(), muzzle_direction(), _id)


## Plays [constant SWING_KEYS] from the top: what [method on_fired] does with a swing. A swing
## during a swing starts again, which is what a second strike looks like.
func swing() -> void:
	_start_action(SWING_KEYS, SWING_SECONDS, false)


## Plays [constant THROW_KEYS]: what [method on_fired] does with a throw. Also starts the slash
## overlay on the person this hangs from, if it hangs from one.
func throw() -> void:
	_start_action(THROW_KEYS, THROW_SECONDS, true)
	var person := _person()
	if person != null:
		person.call(&"swing", &"slash")


## The person this hand belongs to: the nearest node above it that answers both `swing(which)`
## and `set_hold(kind)`, which dot-player-char's figure does.
##
## [b]Asked for a throw only, and duck-typed for [method attach_to]'s reason.[/b] Every game
## already plays the slash on a swing itself, and a second call would restart it; nobody plays
## anything on a throw, because the figure has no throw clip and empty-handed arms are what a
## thrown weapon is held with.
func _person() -> Object:
	if _owner_cache != null and is_instance_valid(_owner_cache) and _owner_cache is Node and (_owner_cache as Node).is_ancestor_of(self):
		return _owner_cache
	_owner_cache = null
	var node := get_parent()
	var depth := 0
	while node != null and depth < 10:
		if node.has_method(&"swing") and node.has_method(&"set_hold"):
			_owner_cache = node
			return node
		node = node.get_parent()
		depth += 1
	return null


## How far through the swing or throw playing, 0 to 1; 1 when none is.
func action_fraction() -> float:
	return _action


func _start_action(keys: Array, seconds: float, hides: bool) -> void:
	_action_keys = keys
	_action_seconds = seconds
	_action_hides = hides
	_action = 0.0
	# The kick a swing used to be is not added to the cut: a knife pushed back along its own
	# blade as it strikes reads as the hand flinching.
	_kick = 0.0


## Which way the barrel points in the world: the art's forward through the model's basis.
func muzzle_direction() -> Vector3:
	if _weapon == null or _art == null:
		return -global_basis.z.normalized()

	return (_weapon.global_basis * _art.model_forward).normalized()


## Whether the character is mid-switch. Hides the model while they are, if asked to.
func on_switching(switching: bool) -> void:
	if hide_while_switching:
		visible = not switching


## Whether the character is reloading (the replicated flag): plays the watcher's reload while it is on.
func on_reloading(reloading: bool) -> void:
	if reloading and not _reloading:
		_reload_time = 0.0
		_reload_period = _cycle_seconds()
	_reloading = reloading


## How far into the watcher's reload, 0 to 1 per cycle; -1 when none is showing.
func reload_fraction() -> float:
	return fposmod(_reload_time / _reload_period, 1.0) if _reload_blend > 0.0 else -1.0


## One cycle of the support hand: the weapon's whole reload, or one round of a reload by the round.
func _cycle_seconds() -> float:
	var def: DotWeaponDef = ZeeWeaponPack.catalogue().get_def(_id) if _id != &"" else null
	if def == null or def.reload_ticks <= 0:
		return 1.5
	var rate := float(def.authored_tick_rate) if def.authored_tick_rate > 0 else float(ZeeWeaponPack.TICK_RATE)
	return clampf(float(def.reload_ticks) / rate, 0.4, 6.0)


func _process(delta: float) -> void:
	advance(delta)


## One frame of the hand, [param delta] seconds long. [method _process] calls it; a tool that
## freezes processing (`tools/world_sheet.gd`) calls it with a fixed step, so a frame is the
## same picture on every machine.
func advance(delta: float) -> void:
	if Engine.is_editor_hint() or not _built or _holder == null:
		return
	if not is_finite(delta) or delta < 0.0:
		return

	_reload_blend = move_toward(_reload_blend, 1.0 if _reloading else 0.0, delta / 0.2)
	_reload_time += delta
	_follow_person()
	if _kick <= 0.00001 and _action >= 1.0 and _sprint <= 0.0 and not _sprint_was_on and _reload_blend <= 0.0 and not _reloading:
		return
	_sprint_was_on = _sprint > 0.0

	# Decayed rather than sprung. A watcher cannot see an overshoot at twenty metres, so
	# the spring the view model runs would be arithmetic nobody ever sees the result of.
	_kick = move_toward(_kick, 0.0, _kick * 12.0 * delta + 0.0002)

	var turn := Basis.IDENTITY
	var moved := Vector3.ZERO
	if _action < 1.0:
		_action = minf(1.0, _action + delta / maxf(_action_seconds, 0.01))
		var at := ZeeWeaponPose.sample_keys(_action_keys, _action)
		moved = at[0]
		var degrees: Vector3 = at[1]
		turn = Basis.from_euler(Vector3(
			deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)
		))
	_show_in_hand(not (_action_hides and _action >= THROW_RELEASE and _action < THROW_BACK))
	if _reload_blend > 0.0:
		var share := smoothstep(0.0, 1.0, _reload_blend)
		moved += RELOAD_DIP * share
		turn = turn * Basis.from_euler(RELOAD_TURN * share * (PI / 180.0))

	# About the grip, which is where the hand is: the rest transform's origin.
	var rest := _rest()
	var carry := _sprint_carry()
	_holder.transform = Transform3D(
		carry[1] * turn * rest.basis, rest.origin + moved + carry[0] + Vector3(0.0, 0.0, _kick)
	)


## The art's third-person transform, scaled by its pose's share of the figure's hand scale.
func _rest() -> Transform3D:
	if _art == null:
		return Transform3D.IDENTITY
	var rest := _art.world_transform()
	return Transform3D(rest.basis.scaled(Vector3.ONE * ZeeWeaponArtTable.pose_world_factor(_art.pose)), rest.origin)


## The sprint carry at the current blend: [offset, rotation basis], in the hand's frame, about the grip.
func _sprint_carry() -> Array:
	if _art == null or _sprint <= 0.0:
		return [Vector3.ZERO, Basis.IDENTITY]
	var base := ZeeWeaponArtTable.sprint_world(_art.pose)
	var offset: Vector3 = _art.sprint_world_offset if _art.sprint_world_offset.is_finite() else base[0]
	var degrees: Vector3 = _art.sprint_world_rotation if _art.sprint_world_rotation.is_finite() else base[1]
	degrees *= _sprint
	return [offset * _sprint, Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))]


## Reads the person's sprint blend and tells it where the support hand goes: every frame, because the holder moves.
func _follow_person() -> void:
	var person := _person()
	if person == null:
		_sprint = 0.0
		return
	_sprint = clampf(float(person.get(&"sprint_blend")), 0.0, 1.0) if person.get(&"sprint_blend") != null else 0.0
	if not person.has_method(&"set_support_grip"):
		return
	var two := _art != null and _weapon != null and visible and _weapon.visible and _support_local.is_finite() \
		and (_art.hands == 2 or (_art.hands == 0 and ZeeWeaponArtTable.pose_two_handed(_art.pose)))
	if two:
		person.call(&"set_support_grip", _support_world())
		_support_sent = true
	else:
		_send_support(false)


## The support hand's point in the world: on the fore-end, or on the reload's path (well, belt) while one shows.
func _support_world() -> Vector3:
	var fore := _holder.global_transform * _support_local
	if _reload_blend <= 0.0:
		return fore
	var well := _holder.global_transform * (_support_local * 0.45)
	var belt := well + Vector3.DOWN * 0.28
	var at: Vector3 = ZeeWeaponPose.sample_keys(RELOAD_SUPPORT_KEYS, reload_fraction())[0]
	var path := fore.lerp(well, clampf(at.x, 0.0, 1.0)).lerp(belt, clampf(at.y, 0.0, 1.0))
	return fore.lerp(path, smoothstep(0.0, 1.0, _reload_blend))


func _send_support(_on: bool) -> void:
	if not _support_sent:
		return
	_support_sent = false
	var person := _person()
	if person != null and person.has_method(&"set_support_grip"):
		person.call(&"set_support_grip", Vector3.INF)


## Where the support hand holds [param art]'s model, in the holder's space: its own `support_grip`, else
## the fractions [member ZeeWeaponArt.fore_along] and [member ZeeWeaponArt.fore_up] over the mesh's bounds.
func _support_point_for(art: ZeeWeaponArt) -> Vector3:
	if art.support_grip.is_finite():
		return art.support_grip
	if _weapon == null:
		return Vector3.INF
	var box := AABB()
	var seeded := false
	for mi in _meshes(_weapon):
		if mi.mesh == null:
			continue
		var to_holder := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != _holder:
			if walk is Node3D:
				to_holder = (walk as Node3D).transform * to_holder
			walk = walk.get_parent()
		var part := to_holder * mi.mesh.get_aabb()
		box = part if not seeded else box.merge(part)
		seeded = true
	if not seeded:
		return Vector3.INF
	var forward := art.model_forward.normalized()
	var t_min := INF
	var t_max := -INF
	for i in 8:
		var t := box.get_endpoint(i).dot(forward)
		t_min = minf(t_min, t)
		t_max = maxf(t_max, t)
	var centre := box.get_center()
	var point := centre - forward * centre.dot(forward) + forward * lerpf(t_min, t_max, art.fore_along)
	point.y = box.position.y + box.size.y * art.fore_up
	return point


func _show_in_hand(shown: bool) -> void:
	if _weapon != null and _weapon.visible != shown:
		_weapon.visible = shown
	for part in _attachments:
		if part.visible != shown:
			part.visible = shown


# --- Internals --------------------------------------------------------------

## The effects node, built the first time this hand fires.
##
## Lazily, because most world models in a match belong to somebody who has not fired yet,
## and thirty effects nodes waiting to be needed is thirty nodes in every frame's walk.
func _shot_fx() -> ZeeShotFx:
	if _fx != null and is_instance_valid(_fx):
		# Read every shot, not only at creation: a game that turns sounds off after the
		# first shot (a settings change) would otherwise keep hearing them.
		_fx.sounds = sounds
		return _fx

	_fx = ZeeShotFx.new()
	_fx.name = "ShotFx"
	_fx.sounds = sounds
	add_child(_fx)
	_fx.exclude_carrier(_carrier_body())
	return _fx


## The nearest physics body above this hand: the character carrying it, whose own capsule
## the barrel starts inside.
func _carrier_body() -> Node:
	var node := get_parent()
	var depth := 0

	while node != null and depth < 8:
		if node is CollisionObject3D:
			return node
		node = node.get_parent()
		depth += 1

	return null


## Whether a first-person rig with its own effects carries this hand on this machine.
##
## [b]Asked of the tree, not configured, and the configuration was tried in the head
## first.[/b] A game that forgot to switch the local player's world model off would play
## every one of its own shots twice, a few centimetres apart — and the game that would
## forget is the one that drives every player's world model from the replicated counter,
## its own included, which is the simplest way to write it.
func _carrier_draws_its_own() -> bool:
	var node := get_parent()
	var depth := 0

	while node != null and depth < 8:
		for child in node.get_children():
			if child is ZeeWeaponRig and (child as ZeeWeaponRig).shot_fx() != null:
				return true
		node = node.get_parent()
		depth += 1

	return false


func _apply_shadows() -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for mesh in _meshes(self):
		mesh.cast_shadow = mode


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		out.append(node)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out


func _clear_models() -> void:
	if _weapon != null:
		_weapon.queue_free()

	for node in _attachments:
		node.queue_free()

	_weapon = null
	_attachments.clear()
	_dressed = {}
	_fitting = null
	_fit_code = -1
	_kick = 0.0
	_action = 1.0


func describe() -> Dictionary:
	return {
		"equipped": String(_id),
		"has_model": _weapon != null,
		"attachments": _attachments.size(),
		"attached": get_parent() != null,
		"mount": String(mount),
		"action": snappedf(_action, 0.01),
		"reload": snappedf(reload_fraction(), 0.01),
	}
