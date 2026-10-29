class_name ZeeRiggedArm
extends Node3D

## One first-person arm drawn from the rigged arm mesh (assets/arms/arms-rigged.glb), posed in
## code: two-bone IK from the shoulder to the wrist, the hand turned onto its grip, and every
## finger curled to wrap what it holds.
##
## [b]The file is one right arm and a mirror makes the left.[/b] A negative-determinant basis
## draws a left hand, which is what [ZeeViewArms]' gloves already do. The file has no animation
## and no constraints: its author's IK and copy-rotation controls are dropped by
## art-src/arms/build_arms.py, because a game posing bones itself needs neither.
##
## [b]Grip types are one number, the radius the fingers wrap.[/b] Each finger segment bends by
## its own length over that radius, so a pistol grip, a rifle fore-end, a knife handle, a
## grenade (open, a ball is wide) and an empty fist (tight) are the same code, and a weapon with
## a fatter handle gets a looser hand. Nothing is authored per weapon.
##
## [b]The flex axis is derived, not read from the file.[/b] A finger bends about
## [code]d x n[/code] (finger direction, palm normal) in the rest pose, and the bone's own axes
## depend on how the exporter rolled it. The palm normal is [code]d x s[/code], with [code]s[/code]
## from the index knuckle to the little finger's: right-handed, so that is the palm of a right
## hand.

## Where the file's two surfaces are named, so a game's colours land on the right one.
const SURFACE_GLOVE := "Glove"
const SURFACE_SLEEVE := "Sleeve"

## How far the palm's bone line sits behind the surface of what it holds, in metres (the mesh's
## skin is this far outside the bone).
const PALM_DEPTH := 0.022
## Where along the grip the palm sits: a little back of the cylinder's middle, like the glove.
const PALM_BACK := 0.012
## Half a finger's thickness, added to the grip radius for the wrap.
const FINGER_THICKNESS := 0.011
## No joint folds further than this (radians): a finger bends past ninety degrees at the
## knuckle and a little less at the others, and a fist is the limit.
const MAX_CURL := 1.65
## The forearm's scale, uniform so the hand keeps its size under a counter-scale of its own
## (a non-uniform one does not survive the wrist's rotation). The rigged mesh's forearm is thin
## beside its hand; its length grows with it and the IK uses the longer bone.
const FOREARM_SCALE := 1.3
## How far the shoulder-to-wrist span may use of the arm's length before the arm is scaled up.
const MAX_STRETCH := 0.96

const FINGERS: Array[String] = ["index", "middle", "ring", "pinky"]

var skeleton: Skeleton3D = null

var _upper := -1
var _fore := -1
var _hand := -1
var _chains := {}          # finger name -> Array[int] of its three joints
var _thumb: Array[int] = []
var _l_upper := 0.1
var _l_fore := 0.1
var _rest_global: Array[Basis] = []
var _rest_origin: Array[Vector3] = []
var _rest_local_q: Array[Quaternion] = []
var _dir_rest: Array[Vector3] = []  # each bone's rest direction, toward its child
var _hand_frame := Basis.IDENTITY   # columns: finger direction, palm normal, little-finger side
var _palm_offset := Vector3.ZERO    # palm centre from the wrist, rest, global
var _seg_len := {}                  # bone index -> its segment length
var _glove_mat: StandardMaterial3D = null
var _sleeve_mat: StandardMaterial3D = null
var _ready_ok := false
## Cloth and leather detail (a triplanar bump, tone variation, a rim); false is the flat colour. Set before [method setup].
var detail := true

static var _noise_cache := {}


## Takes an instantiated model and finds its parts. False if it is not the arm this expects.
func setup(model: Node3D, glove: Color, sleeve: Color, layer: int) -> bool:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return false
	skeleton = found[0] as Skeleton3D
	add_child(model)
	# The model's own root transform is the importer's; the skeleton is posed in the arm's frame.
	model.transform = Transform3D.IDENTITY

	_upper = skeleton.find_bone("upper_arm")
	_fore = skeleton.find_bone("forearm")
	_hand = skeleton.find_bone("hand")
	for finger in FINGERS:
		var chain: Array[int] = []
		for j in 3:
			chain.append(skeleton.find_bone("f_%s_%d" % [finger, j + 1]))
		_chains[finger] = chain
	_thumb.clear()
	for j in 3:
		_thumb.append(skeleton.find_bone("thumb_%d" % (j + 1)))
	var needed: Array[int] = [_upper, _fore, _hand]
	needed.append_array(_thumb)
	for finger in FINGERS:
		needed.append_array(_chains[finger])
	for i in needed:
		if i < 0:
			return false

	_measure_rest()
	_glove_mat = _material(glove, 0.8, layer, 28.0)
	_sleeve_mat = _material(sleeve, 0.95, layer, 40.0)
	_paint(model, layer)
	_ready_ok = true
	return true


## Recolours the two surfaces, for a game that changes its hands after building.
func set_colors(glove: Color, sleeve: Color) -> void:
	if _glove_mat != null:
		_glove_mat.albedo_color = glove
	if _sleeve_mat != null:
		_sleeve_mat.albedo_color = sleeve


func is_ready() -> bool:
	return _ready_ok


## The arm's full length from shoulder to wrist, in the file's own units (metres).
func reach_length() -> float:
	return _l_upper + _l_fore


## Poses the arm. [param frame] is the grip frame in the parent's space: its Y along what is
## held, its Z the way the forearm leaves, X the back of the hand (negated for a left hand, which
## is why it can have a negative determinant). [param hand] is where the hand holds, [param
## shoulder] where the arm comes from, both in the parent's space. [param radius] is the
## grip's radius, [param size] the hand's scale and [param open] how far open the fingers stay
## (0 closed round the grip, 1 flat).
func pose_arm(
	frame: Basis, hand: Vector3, shoulder: Vector3, radius: float, size: float, open: float,
	outward: float
) -> void:
	if not _ready_ok:
		return

	var reach := reach_length()
	var scale_to := maxf(size, hand.distance_to(shoulder) / (MAX_STRETCH * reach * 0.94))
	var s := maxf(scale_to, 0.05)
	transform = Transform3D(frame.scaled(Vector3.ONE * s), hand)

	# Everything below is in the arm's own frame: metres in the file, the grip frame scaled.
	var inv := transform.affine_inverse()
	var palm_at := Vector3(radius + PALM_DEPTH, 0.0, PALM_BACK) / s
	# The target frame for the hand: fingers away from the shoulder (-Z), the palm facing the
	# grip (-X), the little finger toward -Y.
	var target := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0))
	var turn := target * _hand_frame.inverse()
	var wrist := palm_at - turn * _palm_offset
	var shoulder_l := inv * shoulder

	# Two-bone IK, the elbow bent down and out.
	var to_wrist := wrist - shoulder_l
	var d := clampf(to_wrist.length(), 0.001, (_l_upper + _l_fore) * MAX_STRETCH)
	var w_hat := to_wrist.normalized() if to_wrist.length() > 0.0001 else Vector3(0, 0, -1)
	var pole := inv.basis * Vector3(0.45 * outward, -1.0, 0.45)
	pole = pole - w_hat * pole.dot(w_hat)
	pole = pole.normalized() if pole.length() > 0.0001 else w_hat.cross(Vector3.RIGHT).normalized()
	var cos_a := clampf(
		(_l_upper * _l_upper + d * d - _l_fore * _l_fore) / (2.0 * _l_upper * d), -1.0, 1.0
	)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var elbow := shoulder_l + w_hat * (_l_upper * cos_a) + pole * (_l_upper * sin_a)
	var wrist_ik := shoulder_l + w_hat * d

	var q_upper := _swing(_dir_rest[_upper], (elbow - shoulder_l).normalized())
	var g_upper := Basis(q_upper) * _rest_global[_upper]
	var f_dir := (wrist_ik - elbow).normalized()
	var q_fore := _swing(_dir_rest[_fore], f_dir)
	var g_fore := Basis(q_fore) * _rest_global[_fore]
	var g_hand := turn * _rest_global[_hand]

	# Carry the hand's roll up the forearm, so the wrist does not wring the skin.
	var local_rest := _rest_global[_fore].inverse() * _rest_global[_hand]
	var deviation := (g_fore.inverse() * g_hand * local_rest.inverse()).get_rotation_quaternion()
	var axis_in_fore := _rest_global[_fore].inverse() * _dir_rest[_fore]
	var twist := 2.0 * atan2(
		Vector3(deviation.x, deviation.y, deviation.z).dot(axis_in_fore), deviation.w
	)
	if twist > PI:
		twist -= TAU
	elif twist < -PI:
		twist += TAU
	g_fore = Basis(Quaternion(f_dir, twist * 0.7)) * g_fore

	skeleton.set_bone_pose_position(_upper, shoulder_l)
	skeleton.set_bone_pose_rotation(_upper, g_upper.get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(
		_fore, (g_upper.inverse() * g_fore).get_rotation_quaternion()
	)
	skeleton.set_bone_pose_rotation(
		_hand, (g_fore.inverse() * g_hand).get_rotation_quaternion()
	)
	skeleton.set_bone_pose_scale(_fore, Vector3.ONE * FOREARM_SCALE)
	skeleton.set_bone_pose_scale(_hand, Vector3.ONE / FOREARM_SCALE)
	# Posed hand rotation, in the arm's frame: the fingers are driven relative to it.
	_curl_fingers(clampf((radius + FINGER_THICKNESS) / s, 0.004, 0.2), open)


## The fingers' and the thumb's joint angles for a wrap radius (in the file's units).
func _curl_fingers(rho: float, open: float) -> void:
	var palm_n := _hand_frame.y
	var flex := _hand_frame.x.cross(palm_n).normalized()   # d x n, the finger's bend axis
	var slack := clampf(open, 0.0, 1.0)

	for finger in FINGERS:
		var chain: Array = _chains[finger]
		for j in 3:
			var bone: int = chain[j]
			# A segment bends by its own length over the radius; the knuckle takes the most
			# and the tip the least, as a real finger round a handle does.
			var angle := clampf(float(_seg_len[bone]) / rho, 0.0, MAX_CURL)
			angle *= float([1.0, 0.95, 0.8][j]) * (1.0 - slack)
			_bend(bone, flex, angle)

	# The thumb closes across: toward the palm and a little over the fingers.
	var thumb_n := (palm_n + _hand_frame.z * 0.35).normalized()
	for j in 3:
		var bone: int = _thumb[j]
		var tflex: Vector3 = _dir_rest[bone].cross(thumb_n).normalized()
		var angle: float = clampf(float(_seg_len[bone]) / rho, 0.0, MAX_CURL) * float([0.55, 0.8, 0.8][j])
		_bend(bone, tflex, angle * (1.0 - slack))


## Bends [param bone] about a global rest axis, in its own local frame.
func _bend(bone: int, global_axis: Vector3, angle: float) -> void:
	var local_axis := (_rest_global[bone].inverse() * global_axis).normalized()
	skeleton.set_bone_pose_rotation(bone, _rest_local_q[bone] * Quaternion(local_axis, angle))


## The shortest rotation taking one direction onto another.
static func _swing(from: Vector3, to: Vector3) -> Quaternion:
	var dot := clampf(from.dot(to), -1.0, 1.0)
	if dot > 0.99999:
		return Quaternion.IDENTITY
	if dot < -0.99999:
		var any := from.cross(Vector3.UP)
		if any.length() < 0.01:
			any = from.cross(Vector3.RIGHT)
		return Quaternion(any.normalized(), PI)
	return Quaternion(from.cross(to).normalized(), acos(dot))


func _measure_rest() -> void:
	var n := skeleton.get_bone_count()
	_rest_global.resize(n)
	_rest_origin.resize(n)
	_rest_local_q.resize(n)
	_dir_rest.resize(n)
	for i in n:
		var g := skeleton.get_bone_global_rest(i)
		_rest_global[i] = g.basis.orthonormalized()
		_rest_origin[i] = g.origin
		_rest_local_q[i] = skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
	for i in n:
		var next := _child_of(i)
		_dir_rest[i] = (
			(_rest_origin[next] - _rest_origin[i]).normalized() if next >= 0
			else _dir_rest[skeleton.get_bone_parent(i)] if skeleton.get_bone_parent(i) >= 0
			else Vector3.UP
		)
		_seg_len[i] = (
			(_rest_origin[next] - _rest_origin[i]).length() if next >= 0
			else float(_seg_len.get(skeleton.get_bone_parent(i), 0.03)) * 0.8
		)
	_l_upper = _rest_origin[_fore].distance_to(_rest_origin[_upper])
	_l_fore = _rest_origin[_hand].distance_to(_rest_origin[_fore]) * FOREARM_SCALE

	var middle_tip := _rest_origin[(_chains["middle"] as Array)[2]]
	var d := (middle_tip - _rest_origin[_hand]).normalized()
	var palm_index := skeleton.find_bone("palm_index")
	var palm_pinky := skeleton.find_bone("palm_pinky")
	var palm_middle := skeleton.find_bone("palm_middle")
	var side := _rest_origin[palm_pinky] - _rest_origin[palm_index]
	side = (side - d * side.dot(d)).normalized()
	var normal := d.cross(side).normalized()
	_hand_frame = Basis(d, normal, side)
	var palm_centre := (_rest_origin[_hand] + _rest_origin[palm_middle]) * 0.5
	_palm_offset = palm_centre - _rest_origin[_hand]


## The first child bone, or -1: a chain's direction is toward it.
func _child_of(bone: int) -> int:
	var children := skeleton.get_bone_children(bone)
	if children.is_empty():
		return -1
	# The hand has the palm bones and the thumb as children; its own direction is toward the
	# middle finger's palm bone.
	if bone == _hand:
		return skeleton.find_bone("palm_middle")
	return children[0]


func _material(colour: Color, roughness: float, _layer: int, weave: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	if detail:
		# The mesh has no UVs, so the cloth is triplanar in the arm's own space: a fine bump and
		# a faint tone variation, plus a soft rim that gives the flat colour a form.
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * weave
		m.normal_enabled = true
		m.normal_texture = _noise(true, 0.9)
		m.normal_scale = 0.6
		m.albedo_texture = _noise(false, 0.0)
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.4
	# The view model gets no world shadow, for ZeeViewModel's reason.
	m.disable_receive_shadows = true
	return m


## Paints each surface by its material's name, draws on the view layer and on top of the gun.
func _paint(root: Node, layer: int) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.sorting_offset = 100.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Skinned, and posed far from the rest pose its bounds were made in: culled whole when
		# the rest pose is off screen, which is where the arm starts.
		mi.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
		if layer > 0:
			mi.layers = 1 << (layer - 1)
		for s in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(s)
			var is_sleeve := source != null and source.resource_name == SURFACE_SLEEVE
			mi.set_surface_override_material(s, _sleeve_mat if is_sleeve else _glove_mat)


## A tileable noise, as a normal map or as a tone near white (so the colour stays the material's).
static func _noise(as_normal: bool, bump: float) -> Texture2D:
	var key := "n" if as_normal else "t"
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if as_normal else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.08 if as_normal else 0.02
	var t := NoiseTexture2D.new()
	t.width = 128
	t.height = 128
	t.seamless = true
	t.noise = n
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = bump * 4.0
	else:
		var g := Gradient.new()
		g.set_color(0, Color(0.82, 0.82, 0.82))
		g.set_color(1, Color(1, 1, 1))
		t.color_ramp = g
	_noise_cache[key] = t
	return t
