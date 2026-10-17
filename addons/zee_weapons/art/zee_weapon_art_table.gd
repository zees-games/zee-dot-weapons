class_name ZeeWeaponArtTable
extends RefCounted

## Which mesh each weapon wears, and where it sits in the hand and on the screen.
##
## [b]The only file in the pack that knows a filename.[/b] Everything else names a role
## — [constant ZeeWeaponIds.SNIPER], not `blaster-e.glb` — so a game that wants its own
## art replaces this one table and changes no rule, no loadout and no save. That is the
## same seam dot-fx draws between a catalogue and a scene, and dot-props between a
## definition and a script.
##
## [b]Built in code rather than as `.tres` files, and only because this is a pack.[/b]
## Every class here is `@tool`-annotated and inspector-editable, which is what a game
## with an artist wants. What a reference pack wants is the opposite: one file you can
## read top to bottom and see every weapon's placement with the reasoning beside it.
##
## [b]The roles were assigned from the models' measurements, not from their names.[/b]
## `blaster-a` through `blaster-r` are the order Kenney exported them in and say nothing
## about what they are. Each was measured — length, width, height — and given the role
## its silhouette can carry: the two widest became the revolver and the drum shotgun
## because width reads as a cylinder, the slimmest became the beam weapon, the 1.39 m
## one became the sniper, and the 0.42 m one became the derringer. A role assigned from
## a filename would have been a coin flip eighteen times.

# No CHANNEL: a table of filenames. validate() returns a DotResult for the caller to log,
# and the one runtime that can fail against the disk, ZeeModelCache, logs its own misses.

## The arms model [ZeeViewArms] loads for `style = &"model"`; here so the vendoring list can name it.
const ARMS_MODEL := "res://assets/arms/character-a.glb"
const BLASTERS := "res://assets/blaster-kit/"
const MELEE := "res://assets/melee/"
## The real-world guns (Quaternius, CC0; the launcher by Khairul Hidayat): one file per role, the muzzle on -Z and the origin at the bounds' centre like the blasters, a magazine split off as `<role>_magazine.glb` where the source had one.
const GUNS := "res://assets/low-poly-guns/"

# --- Shared parts -----------------------------------------------------------
#
# The kit ships these as separate models, which is the whole reason the reload and the
# attachment systems are worth having: a magazine that visibly falls out is readable in
# a way that a gun waggling for two seconds is not.

const CLIP_SMALL := BLASTERS + "clip-small.glb"
const CLIP_LARGE := BLASTERS + "clip-large.glb"

## Loose foam darts, for the guns with no clip: what the support hand carries in on a reload
## (`ZeeWeaponArt.magazine_loose`), so no gun reloads with an empty hand.
## Realistic rounds (Kenney Weapon Pack, CC0) for the real-world guns; the darts stay for the toy ones.
const AMMO := "res://assets/ammo/"
const ROUND_CARTRIDGE := AMMO + "ammo_uzi.glb"
const ROUND_SHELL := AMMO + "ammo_shotgun.glb"
const ROUND_RIFLE := AMMO + "ammo_sniper.glb"
const ROUND_ROCKET := AMMO + "ammo_rocketModern.glb"

const DART := BLASTERS + "bullet-foam.glb"
const DART_THICK := BLASTERS + "bullet-foam-thick.glb"
const DART_TIP := BLASTERS + "bullet-foam-tip.glb"
const DART_TIP_THICK := BLASTERS + "bullet-foam-tip-thick.glb"
const SCOPE_SMALL := BLASTERS + "scope-small.glb"
const SCOPE_LARGE := BLASTERS + "scope-large-a.glb"
const SCOPE_LARGE_ALT := BLASTERS + "scope-large-b.glb"
const SILENCER_SMALL := BLASTERS + "silencer-small.glb"
const SILENCER_LARGE := BLASTERS + "silencer-larger.glb"

# --- Poses ------------------------------------------------------------------
#
# Five hand positions rather than twenty-seven. A pistol and a derringer are held the
# same way and differ by a centimetre nobody can see, so the offsets live here once and
# a weapon states which family it belongs to. The per-weapon nudges below are then only
# the ones that are actually about that weapon.

const POSE_PISTOL := &"pistol"
const POSE_RIFLE := &"rifle"
const POSE_HEAVY := &"heavy"
const POSE_MELEE := &"melee"
const POSE_THROWN := &"thrown"


## Where a weapon of each pose sits relative to the camera.
##
## [b]Lower and further out than a real weapon would be, and smaller than one.[/b] These
## numbers are not anatomical, and the arithmetic says why. The camera runs at a
## 90-degree vertical field of view, so at 0.5 m the visible world is a metre tall — and
## a 0.7 m rifle held there at life size fills two thirds of the screen. Every game in
## this genre answers that by drawing the view model at a much narrower field of view
## than the world; a single camera cannot do that, so the equivalent is done here by
## shrinking the weapon, which produces the same angular size.
##
## See [method pose_scale] for the other half of the same decision.
static func pose_offset(pose: StringName) -> Vector3:
	match pose:
		POSE_PISTOL:
			return Vector3(0.15, -0.19, -0.36)
		POSE_HEAVY:
			return Vector3(0.19, -0.24, -0.42)
		POSE_MELEE:
			return Vector3(0.22, -0.25, -0.40)
		POSE_THROWN:
			return Vector3(0.17, -0.19, -0.36)
		_:
			return Vector3(0.19, -0.23, -0.40)


## How a blaster of each pose is turned at the hip, in degrees (pitch, yaw, roll) in the
## model's own space (a blaster's is the view's: it points -Z): yaw positive brings the muzzle
## in toward the crosshair, roll positive cants the weapon's right side up toward the eye.
##
## [b]Canted and turned, because pointed straight down the view it is drawn end-on.[/b] A
## weapon below and right of the eye, pointing where the eye points, shows the camera its
## back face and a sliver of its left side: a stub in the corner, which is what this pack
## drew until the contact sheet put it beside a production shooter's. Perspective already
## carries a straight barrel toward the screen's centre; the yaw adds to that, and the cant
## is what turns the right side (the side with the detail) toward the eye. At this distance a
## right side needs about thirty degrees of cant before it faces the camera at all.
static func pose_rotation(pose: StringName) -> Vector3:
	match pose:
		POSE_PISTOL:
			return Vector3(0.0, 8.0, 22.0)
		POSE_HEAVY:
			return Vector3(0.0, 10.0, 26.0)
		_:
			return Vector3(0.0, 10.0, 30.0)


## How much a weapon of each pose is shrunk to stand in for a narrower field of view.
##
## [b]Roughly half, and it is not an arbitrary taste.[/b] A weapon drawn at life size
## half a metre from a 90-degree camera spans most of the screen; a watcher reads that as
## the gun being enormous rather than as the camera being wide. Halving it puts a rifle
## at about a third of the screen height, which is where this genre has settled. A heavy
## weapon is shrunk a little further because it is longer to begin with.
static func pose_scale(pose: StringName) -> float:
	match pose:
		POSE_PISTOL:
			return 0.55
		POSE_HEAVY:
			return 0.55
		# [b]Melee is not shrunk the way the blasters are.[/b] A knife is 35 cm long against
		# a rifle's 71, so the correction that puts a rifle at a third of the screen puts a
		# knife at a sixth — behind the hand holding it, which is where the first render
		# had it. Held slightly above life size is what a first-person blade looks like in
		# every game that ships one.
		POSE_MELEE:
			return 1.20
		POSE_THROWN:
			return 0.75
		_:
			return 0.60


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


# --- The table --------------------------------------------------------------

## Every weapon's art, keyed by weapon id.
##
## Ordered as [method ZeeWeaponIds.all] is, so the two can be read side by side. The
## self-test asserts they cover exactly the same ids, which is the check that catches a
## weapon added to one file and not the other — the failure mode being an invisible gun
## that works perfectly, which nobody notices on a dedicated server and everybody
## notices in a screenshot.
static func table() -> Dictionary:
	var out: Dictionary = {}

	for art in all():
		out[art.id] = art

	return out


static func all() -> Array[ZeeWeaponArt]:
	var out: Array[ZeeWeaponArt] = [
		fists(), knife(), shiv(), hatchet(), mallet(), pickaxe(), spade(),
		pistol(), revolver(), machine_pistol(), derringer(),
		smg(), carbine(), rifle(), bullpup(), battle_rifle(), burst_rifle(),
		shotgun(), drum_shotgun(), marksman(),
		sniper(), minigun(), launcher(), beamer(), charge_rifle(),
		frag(), sticky(),
	]

	var taken := {}

	for art in out:
		taken[art.id] = true

	# Another pack's art, after this one's; the same rule as [method ZeeWeaponPack.add_source].
	for name: StringName in _sources:
		var source: Callable = _sources[name]

		if not source.is_valid():
			continue

		for art: ZeeWeaponArt in source.call():
			if art != null and not taken.has(art.id):
				taken[art.id] = true
				out.append(art)

	return out


## name -> Callable() -> Array[ZeeWeaponArt].
static var _sources: Dictionary = {}


## Adds another pack's art under [param name], beside its weapons
## ([method ZeeWeaponPack.add_source], whose rule applies: a static method's Callable, never
## a lambda, or the process aborts at exit).
static func add_source(name: StringName, source: Callable) -> void:
	_sources[name] = source


static func remove_source(name: StringName) -> void:
	_sources.erase(name)


## One weapon's art, or null.
static func get_art(id: StringName) -> ZeeWeaponArt:
	return table().get(id, null)


# --- Melee ------------------------------------------------------------------
#
# [b]Every melee model points along +Y, not +Z.[/b] Kenney's tools stand upright on
# their handle with the origin at the butt, which is exactly where a hand grips them —
# so the grip needs no offset at all, and `model_forward` does the rest. Getting this
# wrong would point the blade at the player's own face, which is the kind of thing that
# is obvious in a picture and invisible in every assertion.

## Nothing in the hands. Always carried, so a player is never holding nothing.
static func fists() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.FISTS, "")
	art.weight = 0.5
	return art


static func knife() -> ZeeWeaponArt:
	return _melee(ZeeWeaponIds.KNIFE, MELEE + "knife_sharp.glb")


static func shiv() -> ZeeWeaponArt:
	return _melee(ZeeWeaponIds.SHIV, MELEE + "knifeRound_sharp.glb")


static func hatchet() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.HATCHET, MELEE + "tool-axe.glb")
	# The tools are modelled at about a quarter of a metre, which is a toy hatchet.
	# Scaled up until the head reads at arm's length rather than as a detail.
	art.view_scale *= 1.5
	art.world_scale = 1.5
	art.weight = 1.1
	return art


static func mallet() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.MALLET, MELEE + "tool-hammer.glb")
	art.view_scale *= 1.7
	art.world_scale = 1.7
	art.weight = 1.4
	return art


static func pickaxe() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.PICKAXE, MELEE + "tool-pickaxe.glb")
	art.view_scale *= 1.5
	art.world_scale = 1.5
	art.weight = 1.2
	return art


static func spade() -> ZeeWeaponArt:
	var art := _melee(ZeeWeaponIds.SPADE, MELEE + "tool-shovel.glb")
	art.view_scale *= 1.6
	art.world_scale = 1.6
	art.weight = 1.3
	return art


# --- Sidearms ---------------------------------------------------------------

static func pistol() -> ZeeWeaponArt:
	return _blaster(ZeeWeaponIds.PISTOL, "blaster-k", POSE_PISTOL).with_magazine(
		CLIP_SMALL, Vector3(0.0, -0.09, 0.02)
	)


## The widest short model in the kit. Width reads as a cylinder, so it is the revolver.
static func revolver() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.REVOLVER, "revolver", POSE_PISTOL)
	return _loose(art, ROUND_CARTRIDGE, Vector3(0.0, -0.02, 0.02))


static func machine_pistol() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.MACHINE_PISTOL, "machine_pistol", POSE_PISTOL).with_magazine(
		GUNS + "machine_pistol_magazine.glb", Vector3(0.0, -0.042, 0.003)
	)
	return art


## The smallest model in the kit, at 42 cm.
static func derringer() -> ZeeWeaponArt:
	return _loose(_blaster(ZeeWeaponIds.DERRINGER, "blaster-b", POSE_PISTOL), DART, Vector3(0.0, -0.05, 0.0))


# --- Primaries --------------------------------------------------------------

static func smg() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.SMG, "smg", POSE_RIFLE).with_magazine(
		GUNS + "smg_magazine.glb", Vector3(0.0, -0.06, -0.092)
	)
	return art


static func carbine() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.CARBINE, "carbine", POSE_RIFLE).with_magazine(
		GUNS + "carbine_magazine.glb", Vector3(0.0, -0.083, -0.102)
	)
	return art


static func rifle() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.RIFLE, "rifle", POSE_RIFLE).with_magazine(
		GUNS + "rifle_magazine.glb", Vector3(0.0, -0.033, -0.009)
	)
	return art


## Rear-heavy: this is the one model whose bulk sits behind the grip.
static func bullpup() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.BULLPUP, "bullpup", POSE_RIFLE)
	# The Polyy mesh has no separable magazine, so the reload's is built in code.
	art.magazine_part = &"box_magazine"
	art.magazine_offset = Vector3(0.0, -0.049, 0.267)
	return art


static func battle_rifle() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.BATTLE_RIFLE, "battle_rifle", POSE_RIFLE).with_magazine(
		GUNS + "battle_rifle_magazine.glb", Vector3(0.0, -0.059, 0.017)
	)
	return art


static func burst_rifle() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.BURST_RIFLE, "burst_rifle", POSE_RIFLE).with_magazine(
		GUNS + "burst_rifle_magazine.glb", Vector3(0.0, -0.032, -0.014)
	)
	return art


static func shotgun() -> ZeeWeaponArt:
	return _tube(_gun(ZeeWeaponIds.SHOTGUN, "shotgun", POSE_RIFLE))


## The widest model in the kit, at 24 cm across. A drum, so a drum shotgun.
static func drum_shotgun() -> ZeeWeaponArt:
	return _tube(_blaster(ZeeWeaponIds.DRUM_SHOTGUN, "blaster-l", POSE_RIFLE))


static func marksman() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.MARKSMAN, "marksman", POSE_RIFLE)
	# The scope is part of the mesh, so it is looked through (aim_scoped) and nothing is added.
	# Less zoom than the sniper's: the rifle for the middle distance, where a 4x view loses the
	# target sideways.
	art.aim_scoped = true
	art.aim_zoom = 0.5
	art.weight = 1.5
	return art


# --- Heavies ----------------------------------------------------------------

## The longest model at 1.39 m, and the only one whose origin is not at its centre: it is at
## the muzzle, the mesh running 1.39 m back (+Z) to the stock. Which is why the muzzle is
## measured rather than assumed.
static func sniper() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.SNIPER, "sniper", POSE_HEAVY)
	# [b]Slid forward along its own length, in both views, and scaled with the model.[/b]
	# Its origin is the muzzle, so left alone the whole rifle lies back past the hand into
	# the player's face. 0.8 m back from the muzzle is the grip, and it goes on the hold.
	# Along the hold's own basis (which carries the scale, the cant and the yaw), never the
	# camera's Z: once the hold is turned the camera's Z is not the rifle's. This line has
	# been wrong three times (a flipped sign, an unscaled distance, and the direction itself,
	# while every blaster was drawn backwards); render the rack and the sheet after touching it.
	art.view_offset += art.view_transform().basis * Vector3(0.0, 0.0, -0.8)
	art.aim_offset += art.aim_transform().basis * Vector3(0.0, 0.0, -0.8)
	art.world_offset += Vector3(0.0, 0.0, -0.8 * art.world_scale)
	# No scope attachment: the mesh has its own, and the one added sat in the air above it.
	art.weight = 1.8
	art.aim_scoped = true
	art.aim_zoom = 0.3
	art.aim_time = 0.22
	# A bolt gun: the bolt drawn back, two rounds pressed down into the top of the receiver from
	# above and to the right, the bolt shoved home (ZeeWeaponPose.RELOAD_KEYS_BOLT).
	art = _fed(_loose(art, ROUND_RIFLE, Vector3(0.0, 0.03, 0.72)), Vector3(0.07, 0.10, 0.0), 2, 1.0)
	art.magazine_rotation = Vector3(90.0, 0.0, 0.0)
	art.bolt_at = Vector3(0.03, 0.03, 0.93)
	art.bolt_pull = Vector3(0.0, 0.0, 0.10)
	art.reload_keys = ZeeWeaponPose.RELOAD_KEYS_BOLT
	return art


static func minigun() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.MINIGUN, "blaster-f", POSE_HEAVY)
	# On the muzzle (see the machine pistol's), but not on the -Z end of the bounds: that is
	# the tip of a slanted brake that runs 13 cm past the barrel (which ends at z -0.52, its
	# bore 5.2 cm above the origin). At the bounds' end and the origin's height the silencer
	# floated in front of the gun, below the bore, with the flash in the gap; slid over the
	# brake it sits on the barrel. The effects' muzzle is its far end (0.283 m long): written
	# down, the one case ZeeWeaponArt.muzzle_distance allows, because the measurement covers
	# the gun's mesh and not what is screwed onto it. Found by a third-person render
	# (docs/history.md).
	art.with_attachment(SILENCER_LARGE, Vector3(0.0, 0.052, -0.52))
	art.muzzle_distance = 0.52 + 0.283
	art.muzzle_offset = Vector3(0.0, 0.052, 0.0)
	art.weight = 2.0
	# A box and its belt hanging on the right of the body (built in code: view/zee_reload_parts.gd),
	# the belt leaning in to the gun. The minigun feeds from the reserve and never reloads
	# (ZeeWeaponPack: magazine 0), so here the box only says "belt-fed"; the swap is what a range
	# reload sheet shows, and what a game that gives it a magazine would play.
	art.magazine_part = &"ammo_box"
	art.magazine_offset = Vector3(0.17, -0.22, 0.0)
	art.magazine_scale = 2.0
	return art


## The tallest short model: a drum sitting above the body reads as a grenade launcher.
static func launcher() -> ZeeWeaponArt:
	var art := _gun(ZeeWeaponIds.LAUNCHER, "launcher", POSE_HEAVY)
	art.weight = 1.6
	# Broken open: the muzzle drops, a grenade goes into the breech from above and behind, and it
	# snaps shut (ZeeWeaponPose.RELOAD_KEYS_BREAK).
	art = _fed(_loose(art, ROUND_ROCKET, Vector3(0.0, 0.0, 0.30)), Vector3(0.0, 0.0, 0.30), 1, 1.0)
	art.magazine_rotation = Vector3(0.0, 180.0, 0.0)
	art.reload_keys = ZeeWeaponPose.RELOAD_KEYS_MUZZLE
	return art


## The slimmest model in the kit. Nothing about it reads as a magazine, so it is the
## one that does not have one.
static func beamer() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.BEAMER, "blaster-h", POSE_RIFLE)
	art.weight = 1.2
	return art


static func charge_rifle() -> ZeeWeaponArt:
	var art := _blaster(ZeeWeaponIds.CHARGE_RIFLE, "blaster-d", POSE_HEAVY)
	art.with_attachment(SCOPE_LARGE_ALT, Vector3(0.0, 0.19, 0.10))
	art.weight = 1.5
	# Aimed through the scope it carries, like the bullpup.
	art.aim_scoped = true
	art.aim_zoom = 0.6
	# A glowing cell under the body, dropped and replaced (built in code: view/zee_reload_parts.gd).
	art.magazine_part = &"cell"
	art.magazine_offset = Vector3(0.0, -0.33, -0.15)
	art.magazine_scale = 1.5
	return art


# --- Thrown -----------------------------------------------------------------
#
# The grenades stand on their base with the origin at the bottom, the same as the melee
# tools, so they take the same forward axis.

static func frag() -> ZeeWeaponArt:
	return _thrown(ZeeWeaponIds.FRAG, BLASTERS + "grenade-a.glb")


static func sticky() -> ZeeWeaponArt:
	return _thrown(ZeeWeaponIds.STICKY, BLASTERS + "grenade-b.glb")


# --- Builders ---------------------------------------------------------------

## A blaster: points along -Z, Godot's own forward, sits at its pose's offset, measures its
## own muzzle.
##
## [b]-Z, and for years the table said +Z.[/b] Seventeen of the eighteen meshes have
## symmetric bounds along their length, so the rack's muzzle pip (the far end of the bounds
## along model_forward) sat at whichever end it was told to, and every blaster was drawn
## stock-first in both views, with its tracers leaving the stock. A side render with a
## marker on +Z settled it: the marker is on the stock of all eighteen (docs/history.md).
## A gun fed by hand: [param path] is the round the support hand carries in, delivered at
## [param offset] (model space). Nothing drops out and nothing shows at rest.
static func _loose(art: ZeeWeaponArt, path: String, offset: Vector3) -> ZeeWeaponArt:
	var _with := art.with_magazine(path, offset)
	art.magazine_loose = true
	return art


## A gun fed by hand from somewhere in sight: [param from] (model space, from the seat) is where
## each round's push starts, [param count] rounds, drawn at [param scale] (a real round at half
## size is a few pixels in a fist).
static func _fed(art: ZeeWeaponArt, from: Vector3, count: int, scale: float) -> ZeeWeaponArt:
	art.load_from = from
	art.load_count = count
	art.magazine_scale = scale
	return art


## A pump gun: three shells pushed up one at a time into the port under the body, the gun held
## rolled over to show it (ZeeWeaponPose.RELOAD_KEYS_TUBE).
##
## [b]Fed, not loose.[/b] Loose, a single dart rode the hand once from below the screen and the
## contact sheet showed a yellow fleck in one frame of the whole reload: the play test's "no
## proper reload animations" for exactly the guns that reload most often.
static func _tube(art: ZeeWeaponArt) -> ZeeWeaponArt:
	art = _fed(_loose(art, ROUND_SHELL, Vector3(0.0, -0.05, -0.04)), Vector3(0.0, -0.12, 0.03), 3, 1.6)
	art.reload_keys = ZeeWeaponPose.RELOAD_KEYS_TUBE
	return art


## A real-world gun from [constant GUNS]: placed like a blaster (the same poses, the same -Z muzzle).
static func _gun(id: StringName, model: String, pose: StringName) -> ZeeWeaponArt:
	var art := _blaster(id, "", pose)
	art.model_path = GUNS + model + ".glb"
	art.ejects = true
	return art


static func _blaster(id: StringName, model: String, pose: StringName) -> ZeeWeaponArt:
	var art := ZeeWeaponArt.make(id, BLASTERS + model + ".glb")
	art.model_forward = Vector3.FORWARD
	art.pose = pose
	art.view_offset = pose_offset(pose)
	art.view_scale = pose_scale(pose)
	art.weight = pose_weight(pose)
	art.view_rotation = pose_rotation(pose)
	# The fallback aim place, used only when the view model cannot measure a sight line (no
	# mesh data) or the weapon is scoped: the view model measures each gun's iron sight and
	# puts its line through the eye instead (ZeeWeaponArt.iron_sight).
	art.aim_offset = Vector3(0.0, -0.135, -0.46)
	return art


## A melee weapon or a tool: points along +Y with the grip on the origin.
static func _melee(id: StringName, model: String) -> ZeeWeaponArt:
	var art := ZeeWeaponArt.make(id, model)
	art.model_forward = Vector3.UP
	art.pose = POSE_MELEE
	art.view_offset = pose_offset(POSE_MELEE)
	art.view_scale = pose_scale(POSE_MELEE)
	art.weight = pose_weight(POSE_MELEE)
	# [b]Carried across the view, not pointed down it.[/b] `model_forward` turns the blade
	# onto Godot's forward, which for a gun is exactly right and for a knife means the
	# blade points directly away from the eye — so it draws as its own cross-section, a
	# small disc floating above the hands, which is what the first melee render was.
	# Pitching it up and yawing it inward puts its length across the screen where it can
	# be seen, and keeps it off the crosshair.
	# [b]Held in a fist, blade up and leaning in, its flat to the eye[/b] (model space: pitch
	# the blade up off the view axis, yaw spins the flat round to face the camera, roll leans
	# it toward the crosshair). It lay across the view between two planks before the hands
	# could close; a hand round the handle is what makes it read as held.
	art.view_rotation = Vector3(70.0, 80.0, 40.0)
	art.aim_enabled = false
	# [b]No world rotation, and the temptation to add one is the trap.[/b] These models
	# stand on their handle along +Y, so it is natural to write a -90 here to lay them
	# down — but `model_forward` has already turned +Y onto -Z by the time this is
	# applied, so a second rotation puts the blade through the floor. The rack render is
	# what caught it: six melee weapons drawn end-on as specks.
	return art


static func _thrown(id: StringName, model: String) -> ZeeWeaponArt:
	var art := ZeeWeaponArt.make(id, model)
	art.model_forward = Vector3.UP
	art.pose = POSE_THROWN
	art.view_offset = pose_offset(POSE_THROWN)
	art.view_scale = pose_scale(POSE_THROWN)
	art.weight = pose_weight(POSE_THROWN)
	art.view_rotation = Vector3(-35.0, 0.0, 0.0)
	art.aim_enabled = false
	return art


# --- Validation -------------------------------------------------------------

## Checks every entry, and that the table covers exactly the ids the pack defines.
##
## [b]Loads no mesh.[/b] It is the boot check, and a dedicated server runs it with the
## whole `assets/` directory absent — so it must be able to say "the launcher has no art
## entry" without being able to say "the launcher's mesh is missing". Whether the files
## are there is [method validate_models]'s question, asked where there is a screen.
static func validate() -> DotResult:
	var built := table()

	for art: ZeeWeaponArt in built.values():
		var res := art.validate()
		if not res.ok:
			return res

	for id in ZeeWeaponIds.all():
		if not built.has(id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"No art for '%s'. It would work perfectly and draw nothing, " % String(id)
				+ "which is a bug nobody notices on a server and everybody notices "
				+ "in a screenshot.",
				String(id)
			)

	# Another pack's art is that pack's to check; this is about entries written in this file.
	var sourced := {}

	for name: StringName in _sources:
		var source: Callable = _sources[name]
		if source.is_valid():
			for art: ZeeWeaponArt in source.call():
				if art != null:
					sourced[art.id] = true

	for id: StringName in built.keys():
		if not ZeeWeaponIds.all().has(id) and not sourced.has(id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Art for '%s', which is not a weapon in this pack." % String(id),
				String(id)
			)

	return DotResult.success(null)


## Every model file the table names, once each, sorted: the weapon, its magazine and its
## attachments, from this pack and every registered source (zed's included).
##
## [b]This is the list a game vendors, and the one list.[/b] A delivered game carries its own
## copy of the art (see [method ZeeModelCache.set_asset_root]), so what a game must copy is
## exactly what the table names, no more and no less; [method validate_models] checks it and
## `tools/sync-art.sh` copies it, both reading this. A hand-written list in a game drifts: the
## first one covered the weapons and missed the ammunition. [param with_arms] adds the arms
## model, which only a game using `ZeeViewArms.style = &"model"` needs (gloves are built in code).
static func model_paths(with_arms: bool = false) -> Array[String]:
	var seen := {}

	for art: ZeeWeaponArt in all():
		for path in _paths_of(art):
			if path != "":
				seen[path] = true

	if with_arms:
		seen[ARMS_MODEL] = true

	var out: Array[String] = []

	for path: String in seen.keys():
		out.append(path)

	out.sort()
	return out


## Checks that every mesh, magazine and attachment actually resolves.
##
## Loads scenes, so this is not the boot check. Run it once where there is a screen, or
## in the self-test. Reports every missing model rather than the first, because the
## usual cause is a whole directory that did not ship. Paths go through
## [method ZeeModelCache.resolve], so it asks the question the renderer asks, under a
## game's asset root too.
##
## [b]A game's suite calls this one line: `ZeeWeaponArtTable.validate_models()`.[/b] A game
## delivered as a pack has only the art it vendored, and a missing folder fails nothing else
## (one WARN per model, then invisible guns in production).
static func validate_models(with_arms: bool = false) -> DotResult:
	var missing: Array[String] = []

	for path in model_paths(with_arms):
		if not ResourceLoader.exists(ZeeModelCache.resolve(path)):
			missing.append(path)

	if missing.is_empty():
		return DotResult.success(null)

	return DotResult.fail(
		DotError.CODE_IO,
		"%d model(s) are missing: %s" % [missing.size(), ", ".join(missing)]
	)


## Every path one entry refers to: the weapon, its magazine and its attachments.
static func _paths_of(art: ZeeWeaponArt) -> Array[String]:
	var out: Array[String] = []

	if art.has_model():
		out.append(art.model_path)

	if art.magazine_path != "":
		out.append(art.magazine_path)

	for entry in art.attachments:
		out.append(str(entry.get("path", "")))

	return out


static func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var built := all()
	out.append("weapon art: %d entries" % built.size())

	for art in built:
		out.append("  %-16s %-28s %-7s x%.2f  %d attachment(s)" % [
			String(art.id),
			art.model_path.get_file() if art.has_model() else "(none)",
			String(art.pose),
			art.view_scale,
			art.attachments.size(),
		])

	return out
