class_name ZeeViewArms
extends Node3D

## The hands holding the weapon, in first person: two arm meshes lifted out of a Kenney character (the rest is deleted on load).
## All eighteen characters share the arm geometry and differ by a texture atlas, so [member skin] is a path, not a model.
## Poses are a position and rotation per arm (no skeleton); a game with a skinned rig replaces this node and answers [method set_pose].

const CHANNEL := "zee.arms"

## By path, not by class_name.
const Glove := preload("zee_glove_mesh.gd")
const HandReach := preload("zee_hand_reach.gd")

## The nodes worth keeping out of a blocky character. Everything else is thrown away.
const ARM_LEFT := "arm-left"
const ARM_RIGHT := "arm-right"

@export_group("Style")

## What the arms are made of. [code]&"rigged"[/code] (the default) draws a rigged arm mesh
## with finger bones ([ZeeRiggedArm], [constant ZeeWeaponArtTable.RIGGED_ARMS_MODEL]) and wraps
## its fingers on whatever it holds; [b]a game that has not vendored the file gets the gloves
## below, not nothing[/b] (`tools/sync-art.sh <game> --arms` copies it). [code]&"gloves"[/code]
## builds gloved hands that close round what they hold and faceted sleeves, in code;
## [code]&"model"[/code] lifts the two arm boxes out of [member model_path], the way this pack's
## first hands were made.
##
## [b]Why gloves are the default.[/b] The character kit's arms are a box each with no hand
## at the end: two pale slabs reaching for the gun, which is what a production shooter's
## hands were compared with and found wanting. A gloved fist round the grip is what reads as
## holding something, and it is a dozen boxes, which needs no model and no licence.
@export var style: StringName = &"rigged"

## The glove's colour (the hands).
@export var glove_color: Color = Color(0.17, 0.16, 0.15)

## Swaps the glove for [member glove_light_color] when the held gun's mean albedo is within [member glove_contrast_min] of it in luminance (rigged arms only). Off keeps [member glove_color].
@export var glove_contrast: bool = true

## The glove used against a dark gun: tan leather, readable against black metal and a dark sleeve.
@export var glove_light_color: Color = Color(0.6, 0.52, 0.4)

## The luminance gap below which the glove counts as merging with the gun.
@export_range(0.0, 0.5, 0.01) var glove_contrast_min: float = 0.2

## The sleeve's colour (the forearms). A game hands in its team or the player's colour.
@export var sleeve_color: Color = Color(0.16, 0.2, 0.15)

## Cloth and leather detail on the rigged arms (a triplanar bump, tone variation, a rim light). Off is the flat colour.
@export var arm_detail: bool = true

@export_group("Model")

## The character the arms come from, for [code]style = &"model"[/code].
@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var model_path: String = \
	ZeeWeaponArtTable.ARMS_MODEL

## The atlas painted onto them. Empty keeps whatever the model shipped with.
##
## [b]This is how the hands match the player.[/b] Every atlas in the kit shares one UV
## layout, so swapping it recolours the sleeves and the skin and nothing else needs
## touching — which is what lets a game hand a player's own avatar texture straight in.
@export_file("*.png", "*.jpg", "*.webp") var skin: String = ""

@export_group("Placement")

## Scale of the arms.
##
## [b]0.20, and it is set by reach rather than by taste.[/b] Measured, the blocky
## character is **2.7 m tall** — a stylised giant, not a person — and one arm is a
## 0.4 x 1.1 x 0.4 box. The shoulders below sit about 0.35 m out and 0.35 m down; the
## weapon's grip is about 0.45 m out and 0.17 m down. A fifth of a metre is the distance
## between those two points, so it is the length the arm has to be.
##
## [b]Thickness is why this cannot simply be made bigger.[/b] The box is 0.4 wide in its
## own units, so the scale sets the forearm's thickness as well as its length: at 0.20 an
## arm is 8 cm across, which at a third of a metre from a 90-degree camera is about a
## seventh of the screen. At 0.36 it was 14 cm at 0.1 m out — the whole screen — and the
## render was two cream slabs with the rifle somewhere behind them.
@export_range(0.05, 5.0, 0.01) var arm_scale: float = 0.20

## Nudge applied to both arms after the pose, for a game with a different camera height.
@export var arm_offset: Vector3 = Vector3.ZERO

## The render layer the arms are drawn on (1 to 20), set by [ZeeViewModel] to its own so its
## key light reaches them. 0 leaves them on the default layer.
var view_layer: int = 0

var _left: Node3D = null
var _right: Node3D = null
var _pose: StringName = &"rifle"
var _built: bool = false
## What was actually built: [code]&"rigged"[/code] falls back to [code]&"gloves"[/code] when the
## model is not there.
var _style_built: StringName = &"gloves"

## How thick a forearm is drawn, in metres, when the arms reach for a weapon.
##
## [b]Set apart from the length, which is the whole point of reaching.[/b] [member arm_scale]
## scaled both, so a box long enough to get from below the screen to the grip was a slab as
## thick as the gun was long, and in every pose it covered the weapon it held.
@export_range(0.02, 0.2, 0.005) var forearm_width: float = 0.05

var _reach_grip := Vector3.ZERO
var _reach_muzzle := Vector3.ZERO
var _reach_grip_axis := Vector3.UP
var _reach_fore_axis := Vector3.FORWARD
var _reach_radius := 0.0
var _reaching := false


## Loads the model and keeps the two arms.
##
## [b]Failing to find an arm is not an error.[/b] A game substituting its own model may
## name the nodes anything, and hands that do not appear are a visual disappointment
## rather than a broken weapon — the gun still fires. It is logged once, at WARN,
## because it is also not something anybody meant.
func build() -> DotResult:
	if _built:
		return DotResult.success(null)

	_style_built = style

	if style == &"rigged":
		if _build_rigged():
			_built = true
			set_pose(_pose)
			return DotResult.success(null)
		# Not vendored, or not the arm this expects: the gloves, quietly (one WARN, once).
		DotLog.warn(
			CHANNEL, "no rigged arm model; using the code-built gloves",
			{"model": ZeeWeaponArtTable.RIGGED_ARMS_MODEL}
		)
		_style_built = &"gloves"

	if _style_built == &"gloves":
		_right = _build_glove_arm("arm-right")
		_left = _build_glove_arm("arm-left")
		_set_on_top(self)
		_built = true
		set_pose(_pose)
		return DotResult.success(null)

	var model := ZeeModelCache.instantiate(model_path)

	if model == null:
		return DotResult.fail(
			DotError.CODE_IO, "No arms model at %s." % model_path
		)

	_left = _find_named(model, ARM_LEFT)
	_right = _find_named(model, ARM_RIGHT)

	# [b]The arms are lifted out and the rest of the character is thrown away whole.[/b]
	# Deleting the other parts in place looks equivalent and is not: the arms can be
	# nested any number of levels down, so "remove every child that is not an arm" also
	# removes the node an arm is sitting inside. Reparenting first and freeing the
	# remains afterwards cannot get that wrong at any depth.
	for arm in [_left, _right]:
		if arm != null:
			arm.get_parent().remove_child(arm)
			# Cleared before reparenting: an imported scene stamps every node's `owner`
			# with the scene root, and adding a node whose owner is a tree it is no
			# longer in warns on every single load.
			arm.owner = null
			add_child(arm)

	model.queue_free()

	if _left == null or _right == null:
		DotLog.warn(
			CHANNEL,
			"could not find both arms in the model; first person will show fewer hands "
			+ "than it should",
			{"model": model_path, "left": _left != null, "right": _right != null}
		)

	if skin != "":
		_apply_skin(self)

	# The arms are drawn on top of the world, the same as the weapon: an arm that
	# clips into a wall the player is standing against is the single most common
	# first-person artefact, and the fix is the one every game in this genre uses.
	_set_on_top(self)

	_built = true
	set_pose(_pose)
	return DotResult.success(null)


## True while the support hand is sent somewhere ([method reach]'s `fore`) even though the pose
## would cup it on the grip: set by the view model through a pistol's magazine change.
var support_free := false
## Where each shoulder and hand was put last ([method _hands_for]'s keys), in this node's space, for a check.
var last_hands: Dictionary = {}


## Points each arm from a shoulder below the screen to its hand on the weapon: the right
## hand on [param grip], the left on [param fore] (both in the view model's space, which is
## this node's parent's).
##
## [b]Why the arms reach rather than take a pose.[/b] [method set_pose]'s placements are
## numbers written for where each pose class put a weapon. A weapon whose own art moved it
## (most of them shift along their length) was held a hand's width from its grip, and when
## the poses were moved the arms stayed where they were, across the gun. Reaching makes
## the hands meet the weapon wherever its art puts it.
func reach(
	grip: Vector3, fore: Vector3, pose: StringName,
	grip_axis: Vector3 = Vector3.UP, fore_axis: Vector3 = Vector3.FORWARD,
	grip_radius: float = 0.0
) -> void:
	_pose = pose
	_reach_grip = grip
	_reach_muzzle = fore
	_reach_grip_axis = grip_axis
	_reach_fore_axis = fore_axis
	_reach_radius = grip_radius
	_reaching = true

	if not _built:
		return

	var hands := _hands_for(pose, grip, fore)
	if support_free and pose == &"pistol":
		# A pistol's support hand cups the grip and ignores [param fore]; through a magazine
		# change it must go to the well and fetch, or the magazine travels alone, a hand's
		# width from the fist that is supposed to carry it.
		hands["left"] = fore
		hands["left_shoulder"] = Vector3(minf(fore.x - 0.05, -0.05), -0.46, minf(fore.z + 0.26, -0.09))
	last_hands = hands

	if _style_built == &"rigged":
		_right.visible = true
		_reach_rigged(hands, pose, grip_axis, fore_axis, grip_radius)
		return

	if _style_built == &"gloves":
		# A hand closes round what it holds: scaled so its grip is the measured radius, within
		# what still reads as a hand next to the others. The weapons are drawn at about half
		# size (ZeeWeaponArtTable.pose_scale) and a full-size glove beside one is a giant's.
		var size := clampf(grip_radius / GRIP_RADIUS, 0.6, 1.2) if grip_radius > 0.0 else 1.0
		# One-handed things are held with the forearm square to them (a hammer grip), so the
		# shoulder is found from the hand rather than the hand bent to a fixed shoulder: bent,
		# the wrist kinked at a right angle under a knife held blade-up.
		var square := pose in [&"thrown", &"fists"]
		_glove(_right, hands["right_shoulder"], hands["right"], grip_axis, false, size, square)
		# The left hand on a pistol cups the right one, holding what it holds.
		var left_axis := grip_axis if pose == &"pistol" else fore_axis
		_glove(_left, hands["left_shoulder"], hands["left"], left_axis, true, size, square)
		_left.visible = not (pose in [&"melee", &"thrown"])
		return

	if _right != null:
		_right.transform = _span(_right, hands["right_shoulder"], hands["right"])

	if _left != null:
		_left.transform = _span(_left, hands["left_shoulder"], hands["left"])
		# One hand on a knife or a grenade: the other has nothing to hold, and a forearm
		# raised at nothing in the corner of the screen read as a loose box in every render.
		_left.visible = not (pose in [&"melee", &"thrown"])


## Where each shoulder is and where each hand goes, for a weapon held at [param grip].
##
## The shoulders are below the bottom of the screen and in front of the near plane (a
## shoulder behind it is sliced, and the cut face draws as a pale slab), so an arm enters
## from the bottom edge and only its forearm is seen. Two-handed poses put the left hand on
## the fore-end; a pistol cups the right hand; a melee weapon or a throwable has one hand.
static func _hands_for(pose: StringName, grip: Vector3, fore: Vector3) -> Dictionary:
	var right := grip
	var left: Vector3

	match pose:
		&"pistol":
			left = grip + Vector3(-0.03, -0.035, -0.01)
		&"melee", &"thrown":
			left = Vector3(-0.17, -0.23, -0.36)
		&"fists":
			# Bare hands: two fists up, either side of the centre.
			left = Vector3(-right.x * 0.85, right.y, right.z - 0.04)
		_:
			left = fore

	return {
		"right": right,
		"right_shoulder": Vector3(right.x + 0.08, -0.44, minf(right.z + 0.24, -0.09)),
		"left": left,
		"left_shoulder": Vector3(minf(left.x - 0.05, -0.05), -0.46, minf(left.z + 0.26, -0.09)),
	}


## The transform that stretches [param arm] from [param shoulder] to [param hand], at
## [member forearm_width], measured from the arm's own mesh rather than from a number about
## it: its top end is the shoulder, its bottom end the hand.
func _span(arm: Node3D, shoulder: Vector3, hand: Vector3) -> Transform3D:
	var box := _local_bounds(arm)
	var length := maxf(box.size.y, 0.001)
	var down := shoulder - hand

	if down.length() < 0.001:
		return arm.transform

	# Y runs hand -> shoulder over the mesh's height; X and Z are its width, squared off
	# against the camera's back axis (or its right, for an arm pointing straight back).
	var y_col := down / length
	var axis := down.normalized()
	var side := axis.cross(Vector3.BACK)
	if side.length() < 0.01:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var depth := side.cross(axis).normalized()
	var x_col := side * (forearm_width / maxf(box.size.x, 0.001))
	var z_col := depth * (forearm_width / maxf(box.size.z, 0.001))
	var basis := Basis(x_col, y_col, z_col)
	var centre := box.get_center()

	# The mesh's top face (its shoulder end) on the shoulder, centred in X and Z.
	var origin := shoulder + arm_offset - basis * Vector3(centre.x, box.end.y, centre.z)
	return Transform3D(basis, origin)


## The arm's own bounds, in its local space, from the meshes under it.
static func _local_bounds(arm: Node3D) -> AABB:
	var out := AABB()
	var seeded := false
	var meshes: Array[MeshInstance3D] = []
	if arm is MeshInstance3D:
		meshes.append(arm as MeshInstance3D)
	for child in arm.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var to_arm := Transform3D.IDENTITY if mi == arm else arm.global_transform.affine_inverse() * mi.global_transform if arm.is_inside_tree() else mi.transform
		var b := to_arm * mi.mesh.get_aabb()
		out = b if not seeded else out.merge(b)
		seeded = true
	return out if seeded else AABB(Vector3(-0.2, -1.0, -0.2), Vector3(0.4, 1.0, 0.4))


## How the arms are held. Unknown names fall back to the rifle pose.
func set_pose(pose: StringName) -> void:
	_pose = pose

	if not _built:
		return

	# A weapon the view model told us where to hold wins over the pose's fixed numbers.
	if _reaching:
		reach(_reach_grip, _reach_muzzle, pose, _reach_grip_axis, _reach_fore_axis, _reach_radius)
		return

	if _style_built == &"rigged":
		# No weapon to reach for yet: an unposed rigged arm is a full-size arm at the camera, so
		# it stays hidden until the view model hands it a grip.
		_left.visible = false
		_right.visible = false
		return

	var placement := _placement_for(pose)

	if _left != null:
		_left.visible = true
		_left.transform = _arm_transform(placement["left"], placement["left_rotation"])

	if _right != null:
		_right.transform = _arm_transform(
			placement["right"], placement["right_rotation"]
		)


func current_pose() -> StringName:
	return _pose


func has_arms() -> bool:
	return _left != null or _right != null


## The fingers' openness by what is held: a ball is held open, an empty fist is shut.
## What an empty hand closes on: small enough that every joint folds to its limit, a real fist.
const FIST_RADIUS := 0.004

const OPEN_BY_POSE := {&"thrown": 0.1, &"fists": 0.0}

## Picks the glove for a gun whose surfaces are [param surfaces] (see [method surface_albedos]): [param base] unless the mean or a third of the surfaces merge with it, then [param light].
static func glove_for(surfaces: Array[Color], base: Color, light: Color, gap: float) -> Color:
	if surfaces.is_empty():
		return base
	var mean := mean_of(surfaces)
	var merging := 0
	for c in surfaces:
		if absf(base.get_luminance() - c.get_luminance()) < gap:
			merging += 1
	var merges := absf(base.get_luminance() - mean.get_luminance()) < gap or merging * 3 >= surfaces.size()
	if not merges:
		return base
	return light if mean.get_luminance() < light.get_luminance() else base.darkened(0.6)


static func mean_of(colors: Array[Color]) -> Color:
	var sum := Color(0, 0, 0, 1)
	for c in colors:
		sum += Color(c.r, c.g, c.b, 0.0)
	var n := maxf(1.0, float(colors.size()))
	return Color(sum.r / n, sum.g / n, sum.b / n)


## The albedo of each mesh surface under [param root]: material colour times a 4x4 downsample of its texture where readable.
static func surface_albedos(root: Node) -> Array[Color]:
	var out: Array[Color] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var c := mat.albedo_color
			var tex := mat.albedo_texture
			var img: Image = tex.get_image() if tex != null else null
			if img != null and not img.is_empty() and img.is_compressed() and img.decompress() != OK:
				img = null
			if img != null and not img.is_empty():
				img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
				var t := Color(0, 0, 0, 0)
				for y in 4:
					for x in 4:
						t += img.get_pixel(x, y)
				c *= t / 16.0
			out.append(Color(c.r, c.g, c.b, 1.0))
	return out


## The glove now worn: [member glove_color], or the light one when the held gun [param weapon] is as dark as it.
func fit_glove_to(weapon: Node) -> Color:
	var glove := glove_color
	if glove_contrast and weapon != null:
		glove = glove_for(surface_albedos(weapon), glove_color, glove_light_color, glove_contrast_min)
	for arm in [_left, _right]:
		if arm is ZeeRiggedArm:
			(arm as ZeeRiggedArm).set_colors(glove, sleeve_color)
	return glove


func _build_rigged() -> bool:
	var path := ZeeWeaponArtTable.RIGGED_ARMS_MODEL
	if not ResourceLoader.exists(ZeeModelCache.resolve(path)):
		return false
	var parts: Array[ZeeRiggedArm] = []
	for arm_name in ["arm-right", "arm-left"]:
		var model := ZeeModelCache.instantiate(path)
		if model == null:
			return false
		var arm := ZeeRiggedArm.new()
		arm.name = arm_name
		arm.detail = arm_detail
		add_child(arm)
		if not arm.setup(model, glove_color, sleeve_color, view_layer):
			arm.queue_free()
			model.queue_free()
			return false
		parts.append(arm)
	_right = parts[0]
	_left = parts[1]
	return true


## Poses both rigged arms for a weapon: the same frame the gloves use (Y along what is held, Z
## the way the forearm leaves), the left hand its mirror, the fingers wrapped to the grip radius.
func _reach_rigged(
	hands: Dictionary, pose: StringName, grip_axis: Vector3, fore_axis: Vector3, grip_radius: float
) -> void:
	var size := clampf(grip_radius / GRIP_RADIUS, 0.6, 1.2) if grip_radius > 0.0 else 1.0
	var square := pose in [&"thrown", &"fists"]
	var open: float = OPEN_BY_POSE.get(pose, 0.0)
	# A hand with nothing in it closes on nothing: the radius a fist makes.
	var radius := grip_radius if grip_radius > 0.0 and pose != &"fists" else FIST_RADIUS
	_rigged_arm(
		_right, hands["right_shoulder"], hands["right"], grip_axis, false, size, square, radius, open
	)
	var left_axis := grip_axis if pose == &"pistol" else fore_axis
	_rigged_arm(
		_left, hands["left_shoulder"], hands["left"], left_axis, true, size, square, radius, open
	)
	_left.visible = not (pose in [&"melee", &"thrown"])


func _rigged_arm(
	arm: Node3D, shoulder: Vector3, hand: Vector3, axis: Vector3, mirror: bool, size: float,
	square: bool, radius: float, open: float
) -> void:
	var rigged := arm as ZeeRiggedArm
	if rigged == null:
		return
	# The frame is the glove's, so both styles hold a weapon in the same place.
	var y := axis.normalized() if axis.length() > 0.001 else Vector3.UP
	var toward := shoulder - hand
	if toward.length() < 0.001:
		toward = Vector3.BACK
	var z := toward - y * toward.dot(y)
	if z.length() < 0.001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z)
	if square:
		shoulder = hand + z * toward.length()
		shoulder.z = minf(shoulder.z, -0.09)
	if mirror:
		x = -x
	rigged.pose_arm(
		Basis(x, y, z), hand + arm_offset, shoulder + arm_offset, radius, RIGGED_SCALE * size,
		open, -1.0 if mirror else 1.0
	)


# --- Gloves -----------------------------------------------------------------

const GRIP_RADIUS := Glove.GRIP_RADIUS

## The rigged arm's scale against the file (a 0.52 m arm and a 0.19 m hand): the weapons are
## drawn at about half size and the hand must not be a giant's beside them.
const RIGGED_SCALE := 1.0

## One arm: a gloved hand (never stretched) and a faceted sleeve stretched from the wrist to
## the shoulder.
func _build_glove_arm(arm_name: String) -> Node3D:
	var arm := Node3D.new()
	arm.name = arm_name
	add_child(arm)

	var hand := MeshInstance3D.new()
	hand.name = "Hand"
	hand.mesh = Glove.mesh()
	hand.material_override = Glove.flat(glove_color, 0.85)
	arm.add_child(hand)

	var sleeve := MeshInstance3D.new()
	sleeve.name = "Sleeve"
	var tube := CylinderMesh.new()
	# Six sides, so the sleeve is shaded in facets the way the blocky world is, rather than
	# a smooth tube that reads as plastic.
	tube.radial_segments = 6
	tube.rings = 1
	tube.height = 1.0
	tube.top_radius = 0.5
	tube.bottom_radius = 0.46
	sleeve.mesh = tube
	sleeve.material_override = Glove.flat(sleeve_color, 0.9)
	arm.add_child(sleeve)

	var cuff := MeshInstance3D.new()
	cuff.name = "Cuff"
	var ring := CylinderMesh.new()
	ring.radial_segments = 6
	ring.rings = 1
	ring.height = 1.0
	ring.top_radius = 0.5
	ring.bottom_radius = 0.5
	cuff.mesh = ring
	cuff.material_override = Glove.flat(glove_color.lightened(0.12), 0.85)
	arm.add_child(cuff)
	return arm


## Places one gloved arm: the hand at [param hand] closed round [param axis], the sleeve from
## its wrist to [param shoulder]. [param mirror] draws the left hand as the right one's mirror.
func _glove(
	arm: Node3D, shoulder: Vector3, hand: Vector3, axis: Vector3, mirror: bool,
	size: float = 1.0, square: bool = false
) -> void:
	if arm == null:
		return

	var y := axis.normalized() if axis.length() > 0.001 else Vector3.UP
	var toward := shoulder - hand
	if toward.length() < 0.001:
		toward = Vector3.BACK
	# The forearm direction, made square to what the hand holds.
	var z := toward - y * toward.dot(y)
	if z.length() < 0.001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z)
	if square:
		# The forearm straight back from the fist, as long as the reach was, and never
		# behind the near plane (a sliced sleeve draws its cut face).
		shoulder = hand + z * toward.length()
		shoulder.z = minf(shoulder.z, -0.09)
	if mirror:
		# A mirror image of the right hand is a left hand; the renderer handles a basis with
		# a negative determinant by flipping the faces it culls.
		x = -x

	arm.transform = Transform3D.IDENTITY
	var hand_node := arm.get_node("Hand") as Node3D
	hand_node.transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * size), hand + arm_offset)

	# The wrist leaves the heel of the palm toward the shoulder itself (not the hand's own
	# square-on direction), so the bend is at the wrist; the cuff covers the joint, and the
	# sleeve runs on to the shoulder, forearm_width across.
	var heel := hand + Basis(x, y, z).scaled(Vector3.ONE * size) * Vector3(GRIP_RADIUS * 0.4, 0.0, GRIP_RADIUS + 0.03) + arm_offset
	var out := (shoulder + arm_offset - heel).normalized()
	var cuff_end := heel + out * 0.05 * size
	Glove.tube(arm.get_node("Cuff") as Node3D, heel - out * 0.012 * size, cuff_end, forearm_width * 0.85 * size)
	Glove.tube(arm.get_node("Sleeve") as Node3D, cuff_end - out * 0.005, shoulder + arm_offset, forearm_width)


# --- Poses ------------------------------------------------------------------

## Where each arm's SHOULDER sits, and which way the arm points from it.
##
## [b]These are shoulders, not hands, and the mesh is why.[/b] Measured, an arm in this
## kit is a 0.4 x 1.1 x 0.4 box whose origin sits at the [i]top[/i] of it: the mesh runs
## from y=0 down to y=-1. So the transform below places the shoulder and the hand follows
## an arm's length away in whatever direction the rotation points.
##
## [b]The pitch is positive, and that is the whole of the first attempt being wrong.[/b]
## Rotating the arm by +90 degrees about X takes its local "down" onto Godot's forward,
## which is an arm held out in front of you. Negative takes it onto backward — an arm
## pointing behind the camera. Seventy-odd degrees is forward and slightly down, which is
## where a hand on a grip actually is.
##
## [b]Every shoulder is in FRONT of the camera, and anatomy is the trap.[/b] A real
## shoulder is behind the eye, so the natural z here is positive — and a positive z puts
## the shoulder behind the near clip plane, which does not hide the arm. It slices it,
## and what draws is the cut face: a pale slab across the lower half of the screen that
## reads as a broken model rather than as a clipping plane. Every z below is negative,
## and the arm simply starts where the player can see it.
##
## [b]The yaws are mirrored, and getting the signs the wrong way round splays the arms
## outward across the gun[/b] instead of bringing them in under it. The left arm reaches
## right (negative yaw) and the right arm reaches left (positive), because both hands are
## converging on one weapon held slightly right of centre.
##
## [b]How these were derived, so the next person can redo them rather than nudge them.[/b]
## Each pair is a shoulder and a hand: the hand is where the weapon's grip and fore-end
## actually are (see [method ZeeWeaponArtTable.pose_offset]), the shoulder is placed low
## and about 0.3 m out, and the rotation is the one that points the arm from the first at
## the second — pitch from the vertical rise, yaw from the sideways offset.
## [member arm_scale] is then the distance between them.
##
## [b]The pitches are past 90 degrees, and that is a forearm, not a mistake.[/b] The
## shoulder is below the weapon and the hand is above it, so the arm rises as it goes
## forward — which is what a hand coming up from the bottom of the screen onto a grip
## looks like. Under 90 the arm would go forward and down, out of frame.
##
## [b]The right hand is on the grip and the left is further out on the fore-end[/b],
## which is what makes a two-handed weapon read as two-handed. A pistol brings the left
## hand in to meet the right rather than removing it, because a single floating arm reads
## as a bug rather than as a stance.
func _placement_for(pose: StringName) -> Dictionary:
	match pose:
		&"pistol":
			return {
				"left": Vector3(0.00, -0.30, -0.42),
				"left_rotation": Vector3(140.0, -44.0, 0.0),
				"right": Vector3(0.19, -0.34, -0.32),
				"right_rotation": Vector3(146.0, 42.0, 0.0),
			}
		&"heavy":
			return {
				"left": Vector3(0.02, -0.30, -0.56),
				"left_rotation": Vector3(140.0, -44.0, 0.0),
				"right": Vector3(0.21, -0.34, -0.34),
				"right_rotation": Vector3(146.0, 42.0, 0.0),
			}
		&"melee":
			return {
				"left": Vector3(-0.16, -0.32, -0.34),
				"left_rotation": Vector3(132.0, -34.0, 0.0),
				"right": Vector3(0.19, -0.34, -0.30),
				"right_rotation": Vector3(144.0, 40.0, 0.0),
			}
		&"thrown":
			return {
				"left": Vector3(-0.16, -0.32, -0.32),
				"left_rotation": Vector3(130.0, -32.0, 0.0),
				"right": Vector3(0.17, -0.34, -0.28),
				"right_rotation": Vector3(140.0, 40.0, 0.0),
			}
		_:
			return {
				"left": Vector3(0.02, -0.30, -0.50),
				"left_rotation": Vector3(142.0, -45.0, 0.0),
				"right": Vector3(0.20, -0.36, -0.34),
				"right_rotation": Vector3(148.0, 45.0, 0.0),
			}


func _arm_transform(position: Vector3, rotation: Vector3) -> Transform3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)
	))
	return Transform3D(
		basis.scaled(Vector3.ONE * arm_scale), position + arm_offset
	)


# --- Internals --------------------------------------------------------------

func _find_named(node: Node, wanted: String) -> Node3D:
	if node.name == wanted and node is Node3D:
		return node

	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found

	return null


func _apply_skin(root: Node) -> void:
	if not ResourceLoader.exists(skin):
		DotLog.warn(CHANNEL, "no arm skin at that path", {"skin": skin})
		return

	var texture: Variant = load(skin)

	if not (texture is Texture2D):
		DotLog.warn(CHANNEL, "the arm skin is not a texture", {"skin": skin})
		return

	for mesh in HandReach.meshes(root):
		# An override on the instance rather than an edit to the material: the material
		# came off a shared imported mesh, and writing to it would recolour every other
		# instance of the same model in the scene, including the third-person one.
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mesh.material_override = material


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
	for mesh in HandReach.meshes(root):
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

		# Receives no world shadow, for ZeeViewModel._set_on_top's reason.
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).disable_receive_shadows = true

		if view_layer > 0:
			mesh.layers = 1 << (view_layer - 1)


func describe() -> Dictionary:
	return {
		"built": _built,
		"pose": String(_pose),
		"left": _left != null,
		"right": _right != null,
		"model": model_path,
		"skin": skin,
	}
