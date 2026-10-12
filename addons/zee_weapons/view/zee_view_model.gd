@tool
class_name ZeeViewModel
extends Node3D

## By path, not by class_name: see the file's own header.
const IronSight := preload("zee_iron_sight.gd")
const ReloadParts := preload("zee_reload_parts.gd")

## The weapon you see in your own hands, and everything it does while you hold it.
##
## Parent it to the camera. It builds the arms once, swaps the weapon model whenever the
## arsenal switches, and every render frame asks [ZeeWeaponPose] where the thing should
## actually be.
##
## [b]It is told what happened; it never asks.[/b] Nothing here reads an input device, a
## clock or the arsenal's internals — a game calls [method on_used],
## [method on_reload_started] and the rest from the signals it is already handling. That
## is what lets exactly the same node draw a remote player's weapon in third person,
## driven by replicated events rather than by local ones, with no branch anywhere in it.
##
## [b]Nothing here is part of the netcode contract.[/b] It runs on render frames, never
## writes to the simulation, and a player who turns it off simulates identically to one
## who does not — which is the whole reason dot-player-controller keeps its view in a
## separate node, and this is the same line drawn in the same place.
##
## [b]Structure, and why it is four nodes deep.[/b]
## [codeblock]
## ZeeViewModel          at the camera, identity
##   Animated            the pose's transform: sway, bob, kick, deploy, reload
##     Arms              the hands: shoulders fixed, reaching every frame for the weapon
##     Aim               hip to sight: the move from the art's hip hold to its aim hold
##       Holder          the art's resting transform: offset, orientation, scale
##         Weapon        the mesh, in its own +Z-forward space
##         Magazine      a sibling, so a reload can animate it independently
##         Attachment(s) siblings too, in the same model space
## [/codeblock]
## The split between Animated and Holder is what lets the art's placement and the frame's
## animation be authored independently: fold them together and every weapon's resting
## offset has to be re-derived every time the sway changes.

const CHANNEL := "zee.view"

## Emitted once the weapon model for [param id] is in the tree and placed.
##
## For a game hanging a muzzle flash, a laser sight or a scope overlay off it, which
## cannot be done until the model exists.
signal model_ready(id: StringName, weapon: Node3D)

@export_group("Wiring")

## The arms. Left null, the view model builds its own on first use.
##
## A [DotNodeRef] rather than a path, family-wide rule: the host decides per instance,
## in the inspector, and nothing in this addon hardcodes a scene path.
@export var arms_ref: DotNodeRef = null

@export_group("Behaviour")

## Whether to build and show hands at all.
##
## Off is a real configuration, not a debug switch: a game whose characters are not
## humanoid, or one drawing a weapon with no holder at all, wants the model and not the
## arms.
@export var show_arms: bool = true

## Which skin the hands wear. Passed to [ZeeViewArms] when this builds its own.
@export_file("*.png", "*.jpg", "*.webp") var arm_skin: String = ""

## Hides the whole rig. What a "view model" video setting toggles.
@export var visible_model: bool = true:
	set(value):
		visible_model = value
		visible = value

@export_group("Light")

## The render layer (1 to 20) every mesh of the view model and its arms is drawn on, and the
## only one [member view_light_energy]'s light reaches. 0 leaves the meshes on the default
## layer and builds no light. A game whose camera culls this layer does not see its hands.
@export_range(0, 20) var view_layer: int = 20

## The energy of the view model's own key light, a directional light that turns with the
## camera and lights nothing but the view model. 0 builds none.
##
## [b]Why the hands carry a light.[/b] The world's sun is fixed in the world, so turning
## round puts it behind the gun and leaves the gun lit by the ambient alone, flat and dark;
## turning back, bright. A key light from over the shoulder keeps the side the hold shows
## lit and shaded the same way whichever way the player faces. The world's lights still
## reach the view model too, so it is not lifted out of the place it is in.
@export_range(0.0, 4.0, 0.05) var view_light_energy: float = 0.3

## Where that light comes from, as Euler degrees of the light's own rotation in the camera's
## space: above, behind and to the left, so it rakes across the right side the hold shows.
@export var view_light_rotation: Vector3 = Vector3(-38.0, -32.0, 0.0)

@export_group("Feel")

## Scales sway, bob and kick for everything this rig draws.
@export_range(0.0, 3.0, 0.05) var feel: float = 1.0

var _arms: ZeeViewArms = null
var _light: DirectionalLight3D = null
var _animated: Node3D = null
var _aim_node: Node3D = null
var _holder: Node3D = null
var _weapon: Node3D = null
var _magazine: Node3D = null
var _attachments: Array[Node3D] = []
var _sight: Node3D = null

## The iron sight's line, measured at equip in the holder's (model) space: `rear` and `front`
## on the line, or empty when the weapon aims at its written aim_offset. See zee_iron_sight.gd.
var _sight_line: Dictionary = {}

## The holder's transform at full aim when there is a sight line: the line through the eye.
var _sight_aim := Transform3D.IDENTITY

## The camera's near plane the eye relief keeps the gun's back end in front of, plus a margin
## for the kick pushing it back. A view model under no camera assumes Godot's default.
const NEAR_MARGIN := 0.05

var _pose := ZeeWeaponPose.make()
var _art: ZeeWeaponArt = null
var _id: StringName = &""

## Where the right and left hands go, in the Aim node's space, measured at equip.
var _grip_at := Vector3.ZERO
var _fore_at := Vector3.ZERO

## The axis of what each hand holds (a pistol grip, a fore-end, a handle), in the same space.
var _grip_axis := Vector3.UP
var _fore_axis := Vector3.FORWARD
var _grip_radius := 0.0

## Where the magazine sits at rest, in the Aim node's space (the well), or NAN-free zero
## with [member _has_well] false when the weapon has none.
var _well := Vector3.ZERO
var _has_well := false

## A round fed by hand from [member ZeeWeaponArt.load_from], and its keys (`_build_feed_keys`):
## where its push starts, and the bolt's handle forward and drawn back, in the well's space.
var _feeds := false
var _entry := Vector3.ZERO
var _bolted := false
var _bolt := Vector3.ZERO
var _bolt_back := Vector3.ZERO
var _feed_keys: Array = []

## The share of a reload the rounds are fed in, and where in each round's share the hand has it
## at the start of its push and home. Matched by the fed weapons' keys (ZeeWeaponPose
## `RELOAD_KEYS_BOLT`, `_BREAK`, `_MUZZLE`), which hold the gun still across it.
const FEED_START := 0.26
const FEED_END := 0.70
const FEED_AT_ENTRY := 0.45
const FEED_AT_SEAT := 0.82

## Where a fed round is held from the palm: above it and to its right, between the fingertips,
## so the fist is below and beside the round rather than over it. Straight above the palm by
## 3.5 cm, the glove hid every round on the contact sheet.
const FEED_CARRY := Vector3(0.03, 0.06, 0.0)

## The last reload fraction handed in, for the hand that fetches the magazine.
var _reload_fraction: float = 0.0

## Where the muzzle sits in the weapon's own space, measured when the model was built.
var _muzzle := Vector3.ZERO

## The look angles last frame, so sway can be driven by how far the view moved.
var _last_look := Vector2.ZERO
var _look_seen := false

var _built: bool = false

## Posture for this frame, written by whoever is driving the rig.
##
## [b]Plain fields rather than a call into the controller.[/b] The rig has to work for a
## remote player, a bot and a replay, none of which have a controller to ask — so the
## driver pushes what it knows, and the default is somebody standing still looking
## straight ahead, which draws correctly rather than not at all.
var _speed: float = 0.0
var _on_floor: bool = true
var _crouched: bool = false
var _look := Vector2.ZERO

## Whether the aim button is held, and how far the weapon has come up to the eye.
##
## [b]Presentation only.[/b] Aiming changes what the player sees — the weapon centred, the
## view zoomed, a scope — and nothing the server simulates, so it is never part of a
## command or a snapshot. A game that wants aim to tighten spread puts that in its own
## command; this is the half that draws.
var _aim_held: bool = false
var _aim_fraction: float = 0.0

## The vertical field of view, in degrees, the hands are drawn at whatever the camera's is.
## 0 draws them through the camera's own lens.
##
## [b]Why the hands have a lens of their own.[/b] Every pose in [ZeeWeaponArtTable] was set
## under a 90-degree camera, and the games hold them under 83, 92 and 100: through a wider
## lens the same pose is a smaller gun drifting toward the middle of the screen, through a
## narrower one a bigger gun pushed to the edge, and a zoom to aim magnified the gun with
## the world. This genre draws the hands at a fixed field of view for exactly that reason.
##
## [b]Done with a scale, not a second camera.[/b] Scaling the view model's X and Y by
## `tan(camera / 2) / tan(this / 2)` in the camera's own space, with Z left alone, gives
## every vertex the screen position it would have under this lens -- exactly, because a
## perspective projection divides X and Y by Z and nothing else. Depth is untouched, so the
## hands still sort against the world the way they did, and the muzzle a tracer starts from
## is read through the same transform, so a shot still leaves the drawn barrel.
@export var hands_fov: float = 90.0


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

	# [b]Aim is a node of its own, because the aim hold is turned as well as moved.[/b] The hip
	# hold is canted and turned to show the weapon's side; the aim hold is straight down the
	# sight. Moving only the position (as the pose's aim_shift did) brought a canted gun to
	# the middle of the screen end-on.
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
	# [b]Under Animated, so the hands move with the gun.[/b] They were the view model's own
	# child, and every reload, draw and kick moved the gun out of hands that stayed where
	# they were: the contact sheet's draw frames had the rifle sliding away from two
	# forearms holding nothing. [b]Not under Aim[/b]: carried rigidly to the sight, the
	# shoulders went with the gun and the left arm lay across the screen. They reach for the
	# aimed hands every frame instead (_place_hands).
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

## Draws [param art]'s weapon, replacing whatever was in hand.
##
## [b]Rebuilds rather than hides.[/b] Keeping every weapon in the tree and toggling
## visibility is the obvious optimisation and it costs more than it saves here:
## twenty-seven models, their magazines and their attachments is a hundred-odd nodes per
## player, all of them being culled and sorted every frame to draw one.
func equip(art: ZeeWeaponArt) -> DotResult:
	_build_structure()

	if art == null:
		clear()
		return DotResult.fail(DotError.CODE_INVALID, "No art to equip.")

	_clear_models()

	_art = art
	_id = art.id
	_pose.weight = art.weight
	_pose.feel = maxf(0.0, feel)
	_pose.tunables.draw_keys = art.draw_keys if not art.draw_keys.is_empty() \
		else ZeeWeaponPose.DRAW_KEYS
	_pose.tunables.reload_keys = art.reload_keys if not art.reload_keys.is_empty() \
		else ZeeWeaponArtTable.reload_keys(art.pose)
	_reload_fraction = 0.0

	_holder.transform = art.view_transform()
	# The kick turns about the hand. The holder's origin is where the art puts the weapon
	# in the hand, so it is the grip, measured once per weapon rather than written down.
	_pose.pivot = _holder.transform.origin
	# Aim is the Aim node's (see _apply_aim), not a shift in the pose. A new weapon starts at
	# the hip.
	_pose.aim_shift = Vector3.ZERO
	_aim_fraction = 0.0
	_aim_node.transform = Transform3D.IDENTITY

	if _arms != null:
		_arms.set_pose(art.pose)

	if not art.has_model():
		# Legitimate, and the fists are exactly this: a weapon with hands and no object
		# in them. Not a failure and not worth a log line.
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

	_muzzle = _measure_muzzle(art)
	_fit_sight(art)

	if art.has_magazine():
		if art.magazine_path != "":
			_magazine = _add_part(art.magazine_path, art.magazine_transform())
		else:
			_magazine = _add_built(ReloadParts.build(art.magazine_part), art.magazine_transform())

	for entry in art.attachments:
		var part := _add_part(
			str(entry.get("path", "")),
			Transform3D(
				Basis.from_euler(_radians(entry.get("rotation", Vector3.ZERO))),
				entry.get("offset", Vector3.ZERO)
			)
		)
		if part != null:
			_attachments.append(part)

	_reach_for(art)
	model_ready.emit(_id, _weapon)
	return DotResult.success(null)


## Puts the hands on this weapon, measured from the weapon itself, in the holder's (the
## model's own) space: a blaster's right hand round its grip under the body 30% of the way
## from the back, the left round the fore-end at 62%; a melee weapon's hand round its handle;
## a grenade's round its middle. Each hand also gets the axis of what it is holding, so a
## gripping hand can wrap round it.
##
## [b]Measured, because the holder's origin is not the grip for every weapon.[/b] The long
## ones are slid back along their length in the art table, and a right hand put on the
## origin closed on air a hand's length in front of the stock.
##
## [b]In the model's own space, not the view's.[/b] The hold is canted thirty degrees, so the
## view's "down" is no longer under the gun, and a view-space bounding box of a canted gun is
## a box round a diagonal: a hand put "under the middle" of it closed on air beside the gun.
func _reach_for(art: ZeeWeaponArt) -> void:
	var to_aim := _holder.transform
	var forward := art.model_forward.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	var grip := Vector3.ZERO
	var fore := forward * 0.4
	var grip_axis := up
	var fore_axis := forward
	var radius := 0.0

	if _weapon != null:
		var box := _bounds_in(_holder, _weapon)
		if box.size != Vector3.ZERO:
			var t_min := INF
			var t_max := -INF
			for i in 8:
				var t := box.get_endpoint(i).dot(forward)
				t_min = minf(t_min, t)
				t_max = maxf(t_max, t)
			var centre := box.get_center()
			var on_axis := centre - forward * centre.dot(forward)
			match art.pose:
				&"melee":
					# Round the handle, a hand's width up from its butt (the origin).
					grip = forward * minf(0.055, (t_max - t_min) * 0.3)
					grip_axis = forward
					radius = minf(box.size.x, box.size.z) * 0.38
				&"thrown":
					grip = centre
					grip_axis = forward
					radius = minf(box.size.x, box.size.z) * 0.4
				_:
					# Under the body: the grip and fore-end are below the bore, so the hands
					# sit a third and a half of the way up from the bottom of the model.
					var low := box.position.y
					var tall := box.size.y
					grip = on_axis + forward * lerpf(t_min, t_max, 0.30)
					grip.y = low + tall * 0.30
					fore = on_axis + forward * lerpf(t_min, t_max, 0.62)
					fore.y = low + tall * 0.45
					# A pistol grip rakes: its top is forward of its bottom.
					grip_axis = (up + forward * 0.3).normalized()
					radius = box.size.x * 0.3

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


## The bounds of every mesh under [param node], in [param space]'s own coordinates.
func _bounds_in(space: Node3D, node: Node) -> AABB:
	var out := AABB()
	var seeded := false
	for mi: MeshInstance3D in _meshes(node):
		if mi.mesh == null:
			continue
		var to_space := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != space:
			if walk is Node3D:
				to_space = (walk as Node3D).transform * to_space
			walk = walk.get_parent()
		var b := to_space * mi.mesh.get_aabb()
		out = b if not seeded else out.merge(b)
		seeded = true
	return out


## Puts the hands where the weapon's grip and fore-end are this frame: through the Aim
## node, so the hands come up to the sight with the gun while the shoulders stay below the
## screen. Cheap (two transforms), so it runs every frame.
func _place_hands() -> void:
	if _arms == null or _art == null or not _arms.has_method("reach"):
		return
	var aim := _aim_node.transform if _aim_node != null else Transform3D.IDENTITY
	var pose := _art.pose if _art.has_model() else &"fists"
	var fore := aim * _support_hand()
	# A game's own arms may answer the older three-argument reach; they get no axes.
	if _arms.get_method_argument_count("reach") >= 6:
		_arms.call(
			"reach", aim * _grip_at, fore, pose,
			aim.basis * _grip_axis, aim.basis * _fore_axis, _grip_radius
		)
	else:
		_arms.call("reach", aim * _grip_at, fore, pose)


## Where the support hand is this frame: on the fore-end, or, through a reload of a weapon with
## a magazine, to the well, down with the old magazine and out of sight, back up with the next
## one, and back to the fore-end. Keys in the same shape as the gun's, so the two agree.
func _support_hand() -> Vector3:
	var f := _reload_fraction
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


## The support hand's keys for a gun fed by hand ([member ZeeWeaponArt.load_from]): the bolt
## drawn back (when there is one), each round fetched, carried to where its push starts and
## pushed home, the bolt closed, the hand back on the fore-end. Built once per weapon.
##
## [b]The round is drawn at the hand ([constant FEED_CARRY] above it) for its whole trip[/b], so
## the two cannot part company: the hand's keys put it at the entry and then the seat, and
## [method _animate_magazine] reads the hand. A round that slid on its own line while the hand
## followed a curve was a round floating a finger's width off the glove.
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


## Where the muzzle is right now, in world space.
##
## [b]What a muzzle flash, a tracer and a shell ejection hang off, and nothing the
## simulation ever reads.[/b] A shot's real origin is the player's eye, decided on the
## server; this is where the effect should be drawn so that it comes out of the barrel
## rather than out of the player's face. Using this as a shot origin would mean a
## weapon's reach depended on its model, and a player with the view model turned off
## would shoot from somewhere else.
func muzzle_transform() -> Transform3D:
	if _weapon == null:
		return global_transform

	return _weapon.global_transform * Transform3D(Basis.IDENTITY, _muzzle)


# --- Being told what happened -----------------------------------------------

## A use produced [param outcome].
func on_used(outcome: DotWeaponOutcome) -> void:
	if outcome == null or not outcome.used:
		return

	_pose.punch(outcome.recoil)
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
##
## [b]This node cannot apply it, and that is not an omission.[/b] It is a child of the
## camera, and every controller in this family writes the camera's angles from scratch
## each frame — so anything added here is overwritten, or, under a controller that adds
## rather than writes, never taken back off. The game adds it where it writes the camera:
## `DotFpsView.external_angles`, or its own line.
func view_punch() -> Vector2:
	return _pose.view_punch()


## How far through a switch, 1 fully in hand and 0 fully out of frame.
func on_deploy(fraction: float) -> void:
	_pose.set_deploy(fraction)


## How far through a reload, 0 to 1.
##
## The magazine is animated from the same number, so a game driving one drives both.
func on_reload(fraction: float) -> void:
	_reload_fraction = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0
	_pose.set_reload(_reload_fraction)
	_animate_magazine(_reload_fraction)


## A charged weapon's draw, 0 to 1.
func on_charge(fraction: float) -> void:
	_pose.set_charge(fraction)


## A landing, with the downward speed in metres a second.
func on_landed(impact: float) -> void:
	_pose.land(impact)


## Everything back to rest. A respawn, a teleport, a correction.
func on_reset() -> void:
	_pose.reset()
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

	_pose.advance(delta, _look_delta(), _speed, _on_floor, _crouched)
	_advance_aim(delta)
	_animated.transform = _pose.offset()
	_place_hands()
	_apply_hands_lens()
	# Through a scope the weapon is not drawn at all: the scope IS the view, and a barrel
	# across the bottom of it is a weapon held in front of the eye that should be at it.
	# The built arms are under Animated and go with it; a game's own arms (arms_ref) may live
	# anywhere, so they are hidden by name too, or they are drawn across the bottom of the
	# scope.
	var scoped := is_scoped()
	_animated.visible = not scoped
	if _arms != null:
		_arms.visible = not scoped


## The scale that draws the hands at [member hands_fov]. See there.
func _apply_hands_lens() -> void:
	# Only under a camera: the scale is in the camera's own space, and a view model hung
	# anywhere else is in some other space where this would be a distortion, not a lens.
	var camera := get_parent() as Camera3D
	var k := lens_scale(camera.fov, hands_fov) if camera != null else 1.0
	scale = Vector3(k, k, 1.0)


## How much X and Y are scaled to draw at [param hands] degrees under a [param camera]-degree
## lens. 1 when either is not a usable field of view.
static func lens_scale(camera: float, hands: float) -> float:
	if hands <= 1.0 or hands >= 179.0 or camera <= 1.0 or camera >= 179.0:
		return 1.0
	return tan(deg_to_rad(camera) * 0.5) / tan(deg_to_rad(hands) * 0.5)


# --- Aiming -----------------------------------------------------------------

## Holds or releases the aim. Call every frame with the button's state, or on its edges.
func aim(held: bool) -> void:
	_aim_held = held


## 0 at the hip to 1 at full aim.
func aim_fraction() -> float:
	return _aim_fraction


## Whether the weapon in hand can be aimed at all (melee and throwables cannot).
func can_aim() -> bool:
	return _art != null and _art.aim_enabled


## The field-of-view multiplier for this frame: 1 at the hip, the art's zoom at full aim.
##
## [b]The game applies it to its own camera[/b] (dot-player-controller's
## `DotFpsView.external_fov_scale`), for the same reason as [method view_punch]: the view
## model is a child of the camera and has no business setting the camera's lens.
func aim_fov_scale() -> float:
	if _art == null:
		return 1.0
	return lerpf(1.0, _art.aim_zoom, _ease(_aim_fraction))


## Whether the view is through a scope right now: a scoped weapon at (nearly) full aim.
func is_scoped() -> bool:
	return _art != null and _art.aim_scoped and _aim_fraction >= 0.95


func _advance_aim(delta: float) -> void:
	var target := 1.0 if (_aim_held and can_aim()) else 0.0
	var time := _art.aim_time if _art != null else 0.16
	_aim_fraction = move_toward(_aim_fraction, target, delta / maxf(time, 0.01))
	_pose.set_aim(_ease(_aim_fraction))
	_apply_aim(_ease(_aim_fraction))


## Moves and turns the Aim node so the holder sits [param f] of the way from the art's hip
## hold to its aim hold, and tells the pose where the grip now is so a kick still turns
## about it.
##
## [b]The rotation is slerped, the position lerped.[/b] Interpolating the two transforms'
## bases component by component would shrink the weapon half way (the average of two
## rotations is not a rotation).
func _apply_aim(f: float) -> void:
	if _art == null or _aim_node == null:
		return

	var hip := _art.view_transform()

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
	# Aimed, the kick turns about the rear sight rather than the grip: the eye stays behind
	# the notch and the front sight climbs off the crosshair and settles back onto it. About
	# the grip, the whole sight picture jumped up the screen on every shot.
	_pose.pivot = now.origin.lerp(now * _sight_line.rear, f) if not _sight_line.is_empty() \
		else now.origin


## The holder's transform at full aim: down the measured sight line, or the art's written
## aim hold when there is none.
func _aim_target() -> Transform3D:
	return _sight_aim if not _sight_line.is_empty() else _art.aim_transform()


## Measures [param art]'s sight line on the mesh just built, builds the sight on it, and
## works out the aim hold that puts the line through the eye.
##
## [b]The hold is derived, not written.[/b] One written aim place for every blaster put the
## eye level with the middle of each gun's back, and the screen showed the gun's pale rear
## face. With the line, `origin = (0, 0, -relief) - B * rear` (B the orientation, scaled,
## with no aim rotation: the line is the rotation) puts the rear sight straight ahead of the
## eye and the front sight on the crosshair, for any model's shape.
func _fit_sight(art: ZeeWeaponArt) -> void:
	_sight_line = {}
	if not art.iron_sight or not art.aim_enabled or art.aim_scoped or _weapon == null:
		return
	var line := IronSight.measure(_weapon, _holder, art.model_forward)
	if line.is_empty():
		return
	var basis := art.orientation().scaled(Vector3.ONE * art.view_scale)
	# The gun's back end is this far behind the rear sight; the eye stands back far enough to
	# keep it in front of the near plane (a clip plane slices, it does not hide).
	var behind := maxf(0.0, (basis * (line.back as Vector3)).z - (basis * (line.rear as Vector3)).z)
	var camera := get_parent() as Camera3D
	var near := camera.near if camera != null else 0.05
	var relief := maxf(art.aim_eye_relief, behind + near + NEAR_MARGIN)
	# The ring is sized to how far out it ends up, so it reads the same on a toy blaster and on
	# a real-sized rifle drawn at another scale.
	var span := absf((basis * (line.front as Vector3)).z - (basis * (line.rear as Vector3)).z)
	var ring := (relief + span) * tan(deg_to_rad(IronSight.RING_DEGREES)) / art.view_scale
	line = IronSight.with_ring(line, clampf(ring, IronSight.RING_FIT_MIN, IronSight.RING_FIT_MAX))

	_sight_line = line
	_sight = IronSight.build(line, art.model_forward)
	_holder.add_child(_sight)
	_set_on_top(_sight)
	_sight_aim = Transform3D(basis, Vector3(0.0, 0.0, -relief) - basis * (line.rear as Vector3))


## Where the iron sight's rear and front points are this frame, in the view model's own space
## (the camera's, before the hands' lens), as `{rear, front}`; empty without a sight. Aimed and
## at rest both are on the view axis (x and y zero): the line runs through the crosshair.
func sight_points() -> Dictionary:
	if _sight_line.is_empty() or _animated == null:
		return {}
	var to_view := _animated.transform * _aim_node.transform * _holder.transform
	return {"rear": to_view * (_sight_line.rear as Vector3), "front": to_view * (_sight_line.front as Vector3)}


## Smoothstep, so the weapon leaves the hip and arrives at the eye gently rather than at
## a constant rate, which reads as mechanical.
static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Tells the rig how the holder is moving and looking this frame.
##
## [param look] is absolute yaw and pitch in degrees; the rig takes the difference
## itself, because the difference is what sway is made of and two callers computing it
## independently is two chances to compute it differently.
func drive(look: Vector2, speed: float, on_floor: bool, crouched: bool = false) -> void:
	_look = look
	_speed = speed
	_on_floor = on_floor
	_crouched = crouched


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
	if _magazine == null or _art == null:
		return

	var f := clampf(fraction, 0.0, 1.0)
	var rest := _art.magazine_transform()

	# Timed to the reload keys (ZeeWeaponPose.RELOAD_KEYS_*) and the support hand
	# (`_support_hand`): out and falling while the gun rolls onto its side (0.10-0.28), gone
	# while the hand goes down for the next one, then IN THE HAND from 0.36, carried up to the
	# well and seated with the jolt at 0.58. A magazine visible throughout is a reload that reads
	# as the gun shaking; one that rose out of nothing under the gun (the first version) was a
	# hand reaching for a magazine that was already there.
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
		var hand := _support_hand() + Vector3(0.0, 0.035, 0.0)
		var held := _holder.transform.affine_inverse() * hand
		var settle := clampf((f - 0.36) / 0.22, 0.0, 1.0)
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

	return art.model_forward.normalized() * distance + art.muzzle_offset


## Draws a part so it reads as a view model without breaking its own depth.
##
## [b]Depth testing stays ON, and switching it off is the obvious mistake.[/b] The
## tempting fix for a weapon poking through a wall is `no_depth_test`, and it works —
## right up until the hands and the gun are drawn against each other, at which point
## neither can occlude the other and whichever sorts last wins. The first render of this
## rig had a forearm painted flat over the rifle it was supposed to be holding.
##
## What is set instead is a sorting offset, which biases the draw order without throwing
## the depth buffer away, so the arms and the weapon occlude each other correctly.
##
## [b]The cost, stated plainly:[/b] a view model can still clip into a wall the player is
## pressed against. The pack's offsets keep everything within about 0.6 m of the camera
## and a player capsule is 0.35 m across, so it is rare rather than impossible. A game
## that wants it gone renders the view model through its own [SubViewport] with its own
## camera and composites the result — which is the real fix, is more machinery than a
## weapons pack should impose, and needs no change here to adopt.
func _set_on_top(root: Node) -> void:
	for mesh in _meshes(root):
		mesh.sorting_offset = 100.0

		# [b]A view model casts no shadow.[/b] It is drawn half a metre from the camera at
		# well under life size, so the shadow it casts is a large dark smear on the ground
		# a couple of metres ahead of the player — an object-shaped shadow with no object,
		# because the thing casting it is only visible to one viewer. The third-person
		# world model is what casts the shadow other people see.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var material: Material = mesh.material_override

		if material == null:
			# Duplicated from the imported material rather than replaced by a fresh one:
			# a new StandardMaterial3D turns the model flat white, and the imported one is
			# shared with the third-person copy of the same mesh, which must not be edited.
			var source := mesh.get_active_material(0)
			material = (source as StandardMaterial3D).duplicate() \
				if source is StandardMaterial3D else StandardMaterial3D.new()
			mesh.material_override = material

		# [b]A view model receives no shadow either.[/b] It is drawn where the camera is,
		# so the world's shadow map darkens it whenever the player's head is in shade: the
		# gun flipped bright and dark walking along a wall, which no real hand does. Lit,
		# not flat: the sun, the ambient and the view's own key light all still shade it.
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).disable_receive_shadows = true

		if view_layer > 0:
			mesh.layers = 1 << (view_layer - 1)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		out.append(node)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out


func _clear_models() -> void:
	for node in [_weapon, _magazine, _sight]:
		if node != null:
			node.queue_free()
	_sight = null
	_sight_line = {}

	for node in _attachments:
		node.queue_free()

	_weapon = null
	_magazine = null
	_attachments.clear()


static func _radians(value: Variant) -> Vector3:
	var v: Vector3 = value if value is Vector3 else Vector3.ZERO
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))


func describe() -> Dictionary:
	return {
		"equipped": String(_id),
		"has_model": _weapon != null,
		"magazine": _magazine != null,
		"attachments": _attachments.size(),
		"arms": _arms.describe() if _arms != null else {},
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
