@tool
class_name ZeeWeaponArt
extends Resource

## How one weapon looks and where it sits, in the hand and on the screen.
##
## [b]Separate from [DotWeaponDef] on purpose, and the separation is the point of this
## addon.[/b] A definition is what a server validates at boot with none of the content
## installed: a slot, a cadence, a magazine. None of that has a mesh in it, and a
## dedicated server must never need one. This resource is everything a server can
## happily not have — a model path, two offsets and a scale — and a headless build
## never loads a single one.
##
## [b]Paths, never [PackedScene] references.[/b] Same rule dot-weapon's
## [member DotWeaponDef.behaviour_path] follows and for the same reason: a game
## delivered as a dot-cloud content pack is mounted at runtime and a mounted pack's
## `class_name` globals are not registered in the host, so a preloaded resource could
## only ever ship inside the build. A path is resolved when the model is first drawn,
## by [ZeeModelCache], which is the moment the content is definitely mounted.
##
## [b]Two transforms, not one.[/b] A weapon held at arm's length in front of a camera
## and the same weapon in a character's fist are different objects at different scales:
## the first-person one is deliberately oversized and pulled close so it reads at a
## 90-degree field of view, and using one transform for both gives you either a
## world model the size of a car or a view model nobody can see.

@export_group("Identity")

## The weapon id this art belongs to. Must match a [member DotWeaponDef.id].
@export var id: StringName = &""

@export_group("Model")

## The weapon mesh. Empty is legal and means the weapon draws nothing — which is what
## bare fists are, and is why this is not required.
@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var model_path: String = ""

## Which way the mesh points in its own space, before any rotation below. Kenney's blasters point along +Z, Godot's forward is -Z.
## A vector rather than a rotation baked into
## [member view_rotation], because the muzzle derives from it: wrong and shots leave the stock.
@export var model_forward: Vector3 = Vector3.BACK

## Metres from the mesh origin to the muzzle, along [member model_forward].
##
## [b]Zero means "measure it", and measuring it is almost always right.[/b]
## [ZeeModelCache] takes the far end of the mesh's own bounding box along the forward
## axis, which is the end of the barrel on every model in this kit — including
## `blaster-e`, whose origin is at the stock rather than the centre and which a
## hand-written offset would therefore have had wrong. Override it only for a mesh whose
## barrel is not its longest feature.
@export_range(0.0, 4.0, 0.001, "or_greater") var muzzle_distance: float = 0.0

## Sideways and vertical nudge of the muzzle from the barrel line, in metres.
@export var muzzle_offset: Vector3 = Vector3.ZERO

@export_group("First person")

## Where the weapon sits relative to the camera, in metres. +X is right, +Y is up,
## -Z is forward.
@export var view_offset: Vector3 = Vector3(0.22, -0.2, -0.45)

@export var view_rotation: Vector3 = Vector3.ZERO

@export_range(0.05, 8.0, 0.01) var view_scale: float = 1.0

## Which way the hands hold it. Drives the arm pose, nothing else.
##
## A [StringName] rather than an enum because an enum is a list this addon would own,
## and a game adding a two-handed launcher pose should not have to edit a file here.
## [ZeeViewArms] falls back to [constant POSE_RIFLE] for a pose it does not know.
@export var pose: StringName = &"rifle"

## How much this weapon sways and bobs, as a multiple of the rig's own settings.
##
## A heavy weapon that moves exactly as much as a pistol reads as weightless. One
## number rather than a set of them, because the alternative is six sliders per weapon
## that nobody will ever tune individually.
@export_range(0.0, 3.0, 0.05) var weight: float = 1.0

@export_group("Aim")

## Whether the weapon can be aimed down at all. Off for melee and anything thrown: there is
## nothing to look along.
@export var aim_enabled: bool = true

## The field of view at full aim, as a fraction of the unaimed one. 1 aims without zooming.
##
## [b]A scale and not a field of view in degrees[/b], because the game owns the base field
## of view (a player setting, usually) and an aim that set an absolute one would zoom a
## 110-degree player less than a 70-degree one.
@export_range(0.05, 1.0, 0.01) var aim_zoom: float = 0.8

## Whether full aim looks through a scope: the model is hidden and the game draws a scope
## over the screen ([ZeeScopeOverlay]). For the long-range weapons.
@export var aim_scoped: bool = false

## ZeeScopeOverlay properties this weapon sets over the default look (`{"glass_tint": Color(...), "mil_ticks": false}`).
@export var scope_style: Dictionary = {}

## Where the holder sits at full aim, in place of [member view_offset]: centred, so the
## weapon's top lines up under the crosshair. Tuned per pose like the resting place.
@export var aim_offset: Vector3 = Vector3(0.0, -0.11, -0.42)

## The weapon's rotation at full aim, in place of [member view_rotation]: straight down the
## sight, so zero. The hip hold is canted and turned to show the weapon's side, and a gun
## brought to the eye still canted is drawn end-on and crooked.
@export var aim_rotation: Vector3 = Vector3.ZERO

## Whether aiming looks along an iron sight measured from the mesh and built on it (a notch
## at the rear, a ring round a post at the front; see `view/zee_iron_sight.gd`). When the
## view model can measure one, it replaces [member aim_offset] and [member aim_rotation]:
## the line through the two sights goes through the eye, so the front sight sits on the
## crosshair and the gun's top runs away below it. Off, or on a scoped weapon, or with no
## mesh to measure, aim is the written [member aim_offset] as before.
@export var iron_sight: bool = true

## Whether aiming looks along the model's own sight, read off its mesh (`view/zee_own_sight.gd`), with nothing built over it.
## Found, it wins over [member iron_sight]; not found, [member iron_sight] decides between the built sight and [member aim_offset].
@export var sight_own: bool = false

## Whether the sight is a red dot: a glowing dot on the aim axis in a lens window cut through the housing (ADS rules `red_dot_*`).
@export var sight_red_dot: bool = false

## Metres from the eye to the rear sight at full aim, before the view model pushes it out
## far enough that the gun's back end stays in front of the near plane.
@export_range(0.05, 1.0, 0.01) var aim_eye_relief: float = 0.2

## Seconds from hip to full aim (and back).
@export_range(0.01, 1.0, 0.01) var aim_time: float = 0.16

@export_group("Motion")

## The draw, as [ZeeWeaponPose] keys ([t, position, rotation degrees] from holstered at 0 to
## in hand at 1). Empty takes [constant ZeeWeaponPose.DRAW_KEYS].
@export var draw_keys: Array = []

## The reload, as [ZeeWeaponPose] keys over its fraction. Empty takes the pose's
## ([method ZeeWeaponArtTable.reload_keys]).
@export var reload_keys: Array = []

## The reload's phases (view/zee_reload_sequence.gd): `style` and its parts, timing weights, hand targets, anchors.
## Empty: the style the rest of this art implies.
@export var reload: Dictionary = {}

@export_group("Third person")

## Where the weapon sits relative to the character's hand attachment point.
@export var world_offset: Vector3 = Vector3.ZERO

@export var world_rotation: Vector3 = Vector3.ZERO

@export_range(0.05, 8.0, 0.01) var world_scale: float = 1.0

## How many hands hold it in third person: 0 takes the pose's (a pistol one, a long gun two), 1 or 2 says.
@export_range(0, 2, 1) var hands: int = 0

## Where the support hand goes, in the weapon model's own space. [constant Vector3.INF] derives it
## from [member fore_along] and [member fore_up] over the mesh's bounds.
@export var support_grip: Vector3 = Vector3.INF

## Where the firing hand's palm goes and where the bore ends, in the weapon model's own space; [constant Vector3.INF] measures them.
@export var grip_socket: Vector3 = Vector3.INF
@export var muzzle_socket: Vector3 = Vector3.INF

## Size of the first-person hands on this weapon (a small gun wants smaller hands); 0 keeps the arms' own.
@export var hand_scale: float = 0.0

## Size of the first-person forearm on this weapon (a short grip near the eye wants a slimmer one); 0 keeps the arms' own.
@export var forearm_scale: float = 0.0

@export_group("Sprint")

## The sprint carry, a layer over the hip hold: [constant Vector3.INF] takes the pose's default
## ([method ZeeWeaponArtTable.sprint_view] first person, [method ZeeWeaponArtTable.sprint_world] third).
## Offsets in metres, rotations in degrees (pitch up, yaw muzzle-left, roll counter-clockwise), turned about the grip.
@export var sprint_offset: Vector3 = Vector3.INF
@export var sprint_rotation: Vector3 = Vector3.INF
@export var sprint_world_offset: Vector3 = Vector3.INF
@export var sprint_world_rotation: Vector3 = Vector3.INF

@export_group("Magazine")

## The magazine mesh, dropped and replaced during a reload. Empty means the reload is
## the weapon tipping out of frame and back, with nothing leaving it.
##
## [b]This kit ships the clip as a separate model[/b], which is the whole reason the
## reload animation is worth having: a magazine that visibly falls away and a fresh one
## that slides in is the difference between a reload the player can read and a gun that
## waggles for two seconds.
@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var magazine_path: String = ""

## Where the magazine sits in the weapon, in the weapon's own space.
@export var magazine_offset: Vector3 = Vector3.ZERO

@export var magazine_rotation: Vector3 = Vector3.ZERO

## Where the support hand holds the gun, as fractions of the model's bounds: along the barrel
## from the stock (0) to the muzzle (1), and up from the bottom. The defaults are measured for a
## plain body. A gun with something tall on top (a scope) has bounds that put 45% of the way up
## inside the scope, with the glove drawn over barrel and scope.
@export var fore_along: float = 0.62
@export var fore_up: float = 0.45

## The firing hand's place, in the same fractions as [member fore_along]: a long gun's trigger is not 30% from its back.
@export var grip_along: float = 0.30
@export var grip_up: float = 0.30

## Where a magazine is held from the support hand while it is carried in, in the view's space
## (+Y up, +Z toward the eye): above the palm by default. A gun whose well is under the fist
## (a pistol's grip) lifts it and brings it toward the eye, or the glove is in front of it from
## the pull to the seat. It eases back to the default as the magazine seats.
@export var magazine_carry: Vector3 = Vector3(0.0, 0.035, 0.0)

## The "magazine" is a loose round fed by hand (a shell, a cartridge, a grenade, a rocket):
## nothing drops out, it is drawn only while the support hand carries it in, and it is gone
## once it is in. A pack whose guns have no separate magazine still gets a hand that fetches
## something and puts it in the gun.
@export var magazine_loose: bool = false

## A node of the weapon's own model (a high-detail gun's `magazine`) that is hidden from the
## moment the support hand pulls the magazine out until the fresh one is seated, so the carried
## [member magazine_path] part replaces it instead of meeting a second magazine already in the
## gun. Empty draws the model whole throughout.
@export var hide_during_reload: StringName = &""

## A part built in code instead of a file (`&"cell"`, `&"ammo_box"`: `view/zee_reload_parts.gd`),
## used when [member magazine_path] is empty. Built, not vendored, because every game that
## draws this pack carries its own copy of `assets/`, and a new file there is a copy in seven
## games before the first one shows it; a part built in code arrives with the addon.
@export var magazine_part: StringName = &""

## How much larger than its file the magazine or round is drawn. A real round is 5-10 cm and
## the gun is drawn at half size, so a round at 1.0 is a few pixels inside the fist.
@export_range(0.1, 6.0, 0.05) var magazine_scale: float = 1.0

## Where a round fed by hand starts its push into the gun, as an offset from its seat
## ([member magazine_offset]) in the model's own space: above for a round pressed in from the
## top, ahead of the muzzle for a rocket loaded down the tube. Zero keeps the round in the
## hand until it is in (the hand comes up under the gun, as a magazine does).
@export var load_from: Vector3 = Vector3.ZERO

## How many rounds the hand feeds in one reload, one after another.
@export_range(1, 6, 1) var load_count: int = 1

## A bolt the support hand works before the rounds go in and after: where its handle is, in the
## model's own space, and how far (and which way) it is drawn back. A zero pull is no bolt.
@export var bolt_at: Vector3 = Vector3.ZERO
@export var bolt_pull: Vector3 = Vector3.ZERO

@export_group("Effects")

## Whether a shot throws a spent case from the ejection port ([method ZeeViewModel.eject_transform],
## [method ZeeShotFx.play_eject]). On for the real-world guns; the foam blasters fire darts and
## leave nothing behind. Which class of case is the weapon's sound class's ([constant ZeeShotFx.FLASH]).
@export var ejects: bool = false

@export_group("Attachments")

## Extra meshes parented to the weapon: a scope, a silencer, a drum.
##
## Each entry is `{"path": String, "offset": Vector3, "rotation": Vector3}`. A
## dictionary rather than a resource per attachment because an attachment is three
## values and a resource per scope would be sixty files to say what sixty lines say.
@export var attachments: Array[Dictionary] = []


static func make(p_id: StringName, p_model: String = "") -> ZeeWeaponArt:
	var art := ZeeWeaponArt.new()
	art.id = p_id
	art.model_path = p_model
	return art


## Adds an attachment and returns self, so a table can be written as a chain.
func with_attachment(
	path: String, offset: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO
) -> ZeeWeaponArt:
	attachments.append({"path": path, "offset": offset, "rotation": rotation})
	return self


## Sets the magazine and returns self.
func with_magazine(path: String, offset: Vector3 = Vector3.ZERO) -> ZeeWeaponArt:
	magazine_path = path
	magazine_offset = offset
	return self


## The first-person transform, before any animation the rig applies.
## [param row] (a profile's `extra: art:`; vectors as 3-number arrays) over a copy of this art, or this
## art itself when the row says nothing. Keys: `hands`, `support_grip`, `grip_socket`, `muzzle_socket`, `fore_along`, `fore_up`, `grip_along`, `grip_up`, `muzzle_distance`, `hand_scale`, `forearm_scale`, `sprint_offset`, `sprint_rotation`,
## `sprint_world_offset`, `sprint_world_rotation`, `world_scale`, `reload` (merged over the art's).
func with_overrides(row: Variant) -> ZeeWeaponArt:
	if not (row is Dictionary) or (row as Dictionary).is_empty():
		return self
	var out := duplicate() as ZeeWeaponArt
	for key: String in (row as Dictionary):
		var value: Variant = row[key]
		match key:
			"hands":
				out.hands = int(value)
			"world_scale":
				out.world_scale = float(value)
			"fore_along", "fore_up", "grip_along", "grip_up", "muzzle_distance", "hand_scale", "forearm_scale":
				out.set(key, float(value))
			"support_grip", "grip_socket", "muzzle_socket", "sprint_offset", "sprint_rotation", "sprint_world_offset", "sprint_world_rotation":
				if value is Array and (value as Array).size() == 3:
					out.set(key, Vector3(float(value[0]), float(value[1]), float(value[2])))
				elif value is Vector3:
					out.set(key, value)
			"reload_class":
				var table := ZeeWeaponArtTable.named_reload_keys(String(value))
				if not table.is_empty():
					out.reload_keys = table
			"reload":
				if value is Dictionary:
					var merged := out.reload.duplicate(true)
					merged.merge(value as Dictionary, true)
					out.reload = merged
			"reload_keys":
				var parsed := _parse_keys(value)
				if not parsed.is_empty():
					out.reload_keys = parsed
	return out


## `[[t, [x, y, z], [rx, ry, rz]], ...]` from a profile, as the Vector3 keys a pose samples. Empty if malformed.
static func _parse_keys(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for k: Variant in value:
		if not (k is Array and (k as Array).size() == 3 and k[1] is Array and k[2] is Array and (k[1] as Array).size() == 3 and (k[2] as Array).size() == 3):
			return []
		out.append([float(k[0]), Vector3(float(k[1][0]), float(k[1][1]), float(k[1][2])), Vector3(float(k[2][0]), float(k[2][1]), float(k[2][2]))])
	return out if out.size() >= 2 else []


func view_transform() -> Transform3D:
	return _transform(view_offset, view_rotation, view_scale)


## The third-person transform, relative to the hand it hangs off.
func world_transform() -> Transform3D:
	return _transform(world_offset, world_rotation, world_scale)


## The first-person transform at full aim.
func aim_transform() -> Transform3D:
	return _transform(aim_offset, aim_rotation, view_scale)


func magazine_transform() -> Transform3D:
	return _transform(magazine_offset, magazine_rotation, magazine_scale)


## The rotation that turns [member model_forward] into Godot's -Z.
##
## [b]Derived rather than authored[/b], so a table only ever states which way the mesh
## points and never also states the rotation that fixes it — the two drifting apart is
## how a weapon ends up pointing backwards in the world and forwards on the screen.
func orientation() -> Basis:
	var forward := model_forward.normalized()

	# Already pointing the way Godot does. Nothing to correct.
	if forward.is_equal_approx(Vector3.FORWARD):
		return Basis.IDENTITY

	# Pointing exactly backwards, which is every blaster in this kit. Handled before the
	# general case rather than by it: two opposite vectors have a zero cross product, so
	# the axis below would be the zero vector and the basis would come out full of NaN —
	# and a NaN transform draws nothing at all, with no error anywhere.
	if forward.is_equal_approx(Vector3.BACK):
		return Basis(Vector3.UP, PI)

	# Anything else: the shortest rotation taking the model's forward onto -Z.
	var axis := forward.cross(Vector3.FORWARD)

	if axis.length_squared() < 0.000001:
		return Basis(Vector3.UP, PI)

	return Basis(axis.normalized(), forward.angle_to(Vector3.FORWARD))


func has_model() -> bool:
	return model_path != ""


func has_magazine() -> bool:
	return magazine_path != "" or magazine_part != &""


func _transform(offset: Vector3, rotation: Vector3, scale: float) -> Transform3D:
	var basis := orientation() * Basis.from_euler(
		Vector3(
			deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)
		)
	)
	return Transform3D(basis.scaled(Vector3.ONE * scale), offset)


## Checks the document without loading a single mesh.
##
## [b]Loads nothing, for [DotWeaponDef.validate]'s reason[/b]: this has to be runnable
## on a dedicated server that has no art installed and never will have, so that a typo
## in a scale or a zeroed forward vector is caught at boot rather than the first time
## somebody with a screen joins.
func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "Weapon art needs an id.")

	var where := String(id)

	if model_forward.length_squared() < 0.000001:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"model_forward is zero, so there is no way to tell which end the muzzle is.",
			where
		)

	if view_scale <= 0.0 or world_scale <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID, "A scale of zero draws nothing at all.", where
		)

	if has_magazine() and not has_model():
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A magazine with no weapon to come out of.",
			where
		)

	for i in range(attachments.size()):
		var entry: Dictionary = attachments[i]
		if str(entry.get("path", "")) == "":
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Attachment %d has no path." % i,
				where
			)

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"id": String(id),
		"model": model_path,
		"pose": String(pose),
		"weight": weight,
		"attachments": attachments.size(),
		"magazine": magazine_path if magazine_path != "" else String(magazine_part),
		"aim": ("scoped x%.2f" % aim_zoom) if aim_scoped else (
			("x%.2f" % aim_zoom) if aim_enabled else "no"
		),
	}


func _to_string() -> String:
	return "ZeeWeaponArt(%s, %s)" % [
		String(id), model_path.get_file() if model_path != "" else "no model"
	]
