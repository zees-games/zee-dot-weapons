class_name ZeeWeaponPack
extends "zee_weapon_pack_builders.gd"

## Twenty-seven weapons, as one [DotWeaponCatalogue] a server can check at boot. Every duration is in ticks ([method rpm_ticks] converts once).
## Nothing here mentions a mesh: a [DotWeaponDef] validates with no content installed; [ZeeWeaponArtTable] is what a client draws.
## Each row answers a different question (a corridor, a rooftop, movement, a door), and the comments say which.

# No CHANNEL: a table of documents built by static functions. It refuses nothing itself;
# DotWeaponCatalogue.validate() returns a DotResult and the caller decides who hears it.


# --- The catalogue ----------------------------------------------------------

## Every weapon, as one table.
##
## [param damage] is the damage-type table the weapons take their types from, so a game
## can harden armour or switch falloff off without editing a row here. Omitted, the
## pack's own is used.
static func catalogue(damage: Dictionary = {}) -> DotWeaponCatalogue:
	var types := damage if not damage.is_empty() else ZeeWeaponDamage.table()
	var out := DotWeaponCatalogue.new()

	for def in weapons(types):
		out.add(def)

	return out


## Carry weight in kg by weapon id; a weapon not listed falls back to its tier.
const WEIGHTS := {
	"battle_rifle": 4,
	"derringer": 1,
	"bullpup": 5,
	"launcher": 6,
	"charge_rifle": 6,
	"carbine": 4,
	"beamer": 6,
	"knife": 0.4,
	"hatchet": 1.5,
	"burst_rifle": 4,
	"fists": 1.5,
	"drum_shotgun": 4,
	"frag": 0.4,
	"minigun": 7.5,
	"machine_pistol": 1,
	"mallet": 1.5,
	"marksman": 5,
	"pickaxe": 1.5,
	"pistol": 1,
	"revolver": 1,
	"smg": 2.8,
	"shiv": 1.5,
	"spade": 1.5,
	"sniper": 6,
	"sticky": 0.4,
}


## [param profiled] false skips the cfg profiles (the Workshop export writes the builders' own numbers).
static func weapons(types: Dictionary = {}, profiled: bool = true) -> Array[DotWeaponDef]:
	var t := types if not types.is_empty() else ZeeWeaponDamage.table()

	var out: Array[DotWeaponDef] = [
		fists(t), knife(t), shiv(t), hatchet(t), mallet(t), pickaxe(t), spade(t),
		pistol(t), revolver(t), machine_pistol(t), derringer(t),
		smg(t), carbine(t), rifle(t), bullpup(t), battle_rifle(t), burst_rifle(t),
		shotgun(t), drum_shotgun(t), marksman(t),
		sniper(t), minigun(t), launcher(t), beamer(t), charge_rifle(t),
		frag(t), sticky(t),
	]

	for def in out:
		if WEIGHTS.has(String(def.id)):
			def.weight = float(WEIGHTS[String(def.id)])

	if profiled:
		errors = DotWeaponProfiles.tune(out, profile_set())
	return _with_sources(_kept(out), t)


## Ids of this pack's own weapons that stay when [method keep_only] was called; null keeps all.
static var _keep: Variant = null


## Drops every built-in weapon but [param ids] from [method weapons], so a game with its own weapon packs carries none of the
## blasters (and never needs their art). Pass null to bring them all back. Call before any rig is built: a rig reads its catalogue once.
static func keep_only(ids: Variant) -> void:
	_keep = ids
	ZeeWeaponArtTable.drop_cache()


static func _kept(own: Array[DotWeaponDef]) -> Array[DotWeaponDef]:
	if _keep == null:
		return own

	var out: Array[DotWeaponDef] = []

	for def in own:
		if (_keep as Array).has(def.id):
			out.append(def)

	return out


## The config addon name profiles are read under (`cfg/addons/zee_weapons/weapon`).
const ADDON := "zee_weapons"
## The game id for the game tier (`cfg/game/<game>/weapon`); empty skips it.
static var game: String = ""
## A mounted pack's `cfg` root (`DotCloudMounter.cfg_root_of`), the weakest root.
static var pack_cfg_root: String = ""
## Roots under [member pack_cfg_root]; empty means [method DotProfileSet.default_roots]. Tests set it.
static var base_roots: PackedStringArray = PackedStringArray()
## Profiles that failed to load in the last [method weapons]; their weapons keep the builder's numbers.
static var errors: PackedStringArray = PackedStringArray()


## The weapon profile set; call [method DotProfileSet.clear_cache] when done.
static func profile_set(layer: Variant = null) -> DotProfileSet:
	return DotWeaponProfiles.overlay_set(ADDON, game, pack_cfg_root, base_roots, layer)


## Weapon [param id] with the upgrades [param ids] applied; value `{def, cost}`.
static func upgraded(id: StringName, ids: Array, types: Dictionary = {}) -> DotResult:
	var def: DotWeaponDef = table(types).get(id)
	if def == null:
		return DotResult.fail(DotError.CODE_INVALID, "no weapon %s" % id)
	var set := profile_set()
	var res := DotWeaponProfiles.upgraded(def, ids, set)
	set.clear_cache()
	return res


# A second pack adds to this one rather than replacing it, so every rig, world model and loot table asking for "the weapons"
# ([method catalogue]) sees it, art through [method ZeeWeaponArtTable.add_source]. This pack's own weapons win an id;
# a source bringing a taken id loses it with a WARN.

const CHANNEL := "zee.pack"

## name -> Callable(types: Dictionary) -> Array[DotWeaponDef], in the order added.
static var _sources: Dictionary = {}


## Adds another pack's weapons after this one's, under [param name]. Adding the same name again replaces that source.
## Pass a static method's Callable (`Callable(MyPack, &"weapons")`), never a lambda: a lambda held in this static outlives its script
## and the process aborts on exit (`double free or corruption`, exit 134).
static func add_source(name: StringName, source: Callable) -> void:
	_sources[name] = source


static func remove_source(name: StringName) -> void:
	_sources.erase(name)


static func source_names() -> PackedStringArray:
	var out := PackedStringArray()

	for name: StringName in _sources:
		out.append(String(name))

	return out


static func _with_sources(own: Array[DotWeaponDef], types: Dictionary) -> Array[DotWeaponDef]:
	if _sources.is_empty():
		return own

	var taken := {}

	for def in own:
		taken[def.id] = true

	for name: StringName in _sources:
		var source: Callable = _sources[name]

		if not source.is_valid():
			continue

		for def: DotWeaponDef in source.call(types):
			if def == null:
				continue

			if taken.has(def.id):
				DotLog.warn(CHANNEL, "a weapon pack brought an id that is already taken", {
					"pack": String(name), "id": String(def.id),
				})
				continue

			taken[def.id] = true
			own.append(def)

	return own


## Weapons by id, for a module holding an id that needs the row.
static func table(types: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}

	for def in weapons(types):
		out[def.id] = def

	return out


# --- Melee ------------------------------------------------------------------
#
# Seven of them, and they are not seven reskins. A melee weapon in a game with
# twenty-six guns is only ever picked for a reason, so each of these has one: the knife
# is the fastest thing in the game, the mallet is the hardest single hit, the spade has
# the widest arc and the pickaxe has the longest reach. Damage alone would have made six
# of them pointless.

## Always carried, so a player is never holding nothing — after a drop, during a
## respawn, in a mode with no loadout.
static func fists(t: Dictionary = {}) -> DotWeaponDef:
	return _melee(
		t, ZeeWeaponIds.FISTS, "Fists", 22.0, 1.6, rpm_ticks(120.0), 30.0, 3
	)


## The fastest weapon in the pack, and the only one that can out-trade a sidearm inside
## two metres.
static func knife(t: Dictionary = {}) -> DotWeaponDef:
	var def := _melee(
		t, ZeeWeaponIds.KNIFE, "Knife", 45.0, 1.9, rpm_ticks(150.0), 24.0, 3
	)
	def.deploy_ticks = sec_ticks(0.15)
	def.holster_ticks = sec_ticks(0.1)
	return def


## Faster still and weaker: the weapon for finishing rather than for starting.
static func shiv(t: Dictionary = {}) -> DotWeaponDef:
	var def := _melee(
		t, ZeeWeaponIds.SHIV, "Shiv", 34.0, 1.8, rpm_ticks(190.0), 20.0, 2
	)
	def.deploy_ticks = sec_ticks(0.12)
	def.holster_ticks = sec_ticks(0.08)
	return def


static func hatchet(t: Dictionary = {}) -> DotWeaponDef:
	return _melee(
		t, ZeeWeaponIds.HATCHET, "Hatchet", 62.0, 2.0, rpm_ticks(80.0), 40.0, 4
	)


## The hardest single hit in the pack, and the slowest. A miss costs a second.
static func mallet(t: Dictionary = {}) -> DotWeaponDef:
	var def := _melee(
		t, ZeeWeaponIds.MALLET, "Mallet", 85.0, 1.9, rpm_ticks(55.0), 50.0, 5
	)
	def.deploy_ticks = sec_ticks(0.5)
	def.holster_ticks = sec_ticks(0.4)
	# Death reactions (dot-player-char's DotPlayerDeathReactions): A swing that kills may knock the body over backwards.
	def.params[ZeeWeaponIds.PARAM_DEATH_POWER] = 0.6
	return def


## The longest reach of anything without a barrel.
static func pickaxe(t: Dictionary = {}) -> DotWeaponDef:
	return _melee(
		t, ZeeWeaponIds.PICKAXE, "Pickaxe", 68.0, 2.4, rpm_ticks(70.0), 26.0, 3
	)


## The widest arc: five rays across fifty-five degrees, so it is the one that reliably
## catches somebody strafing past.
static func spade(t: Dictionary = {}) -> DotWeaponDef:
	return _melee(
		t, ZeeWeaponIds.SPADE, "Spade", 56.0, 2.3, rpm_ticks(85.0), 55.0, 5
	)


# --- Sidearms ---------------------------------------------------------------

## The one everybody starts with. Never runs out, always loses a fair fight — which is
## what makes picking something up worth doing.
static func pistol(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.PISTOL, "Dart Pistol", ZeeWeaponIds.SLOT_SIDEARM,
		DotWeaponDef.Fire.SEMI, rpm_ticks(400.0)
	)
	def.tags = [ZeeWeaponIds.TAG_SIDEARM]
	def.ammo_type = ZeeWeaponIds.AMMO_LIGHT
	def.magazine = 15
	def.reserve = 60
	def.reserve_max = 120
	def.reload_ticks = sec_ticks(1.6)
	def.deploy_ticks = sec_ticks(0.22)
	def.holster_ticks = sec_ticks(0.16)

	var b := _ballistics(t, 20.0)
	b.spread = 0.35
	b.spread_moving = 1.5
	b.bloom = 0.3
	b.bloom_max = 2.6
	b.recoil_pitch = 0.5
	b.max_range = 120.0
	def.tuning = b
	return def


## Six shots that each hurt, and a reload that takes as long as a fight. The sidearm for
## somebody who expects to hit.
static func revolver(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.REVOLVER, "Revolver", ZeeWeaponIds.SLOT_SIDEARM,
		DotWeaponDef.Fire.SEMI, rpm_ticks(140.0)
	)
	def.tags = [ZeeWeaponIds.TAG_SIDEARM]
	def.ammo_type = ZeeWeaponIds.AMMO_LIGHT
	def.magazine = 6
	def.reserve = 36
	def.reserve_max = 72
	def.reload_ticks = sec_ticks(2.4)
	def.deploy_ticks = sec_ticks(0.3)
	def.holster_ticks = sec_ticks(0.22)

	var b := _ballistics(t, 46.0)
	b.spread = 0.2
	b.spread_moving = 2.4
	b.bloom = 1.1
	b.bloom_max = 5.0
	# The biggest kick on anything one-handed. Two shots in a second is possible and
	# the second one goes over their head, which is the whole balance of the weapon.
	b.recoil_pitch = 2.4
	b.recoil_yaw = 0.5
	b.max_range = 100.0
	def.tuning = b
	return def


## Quiet, and the only automatic weapon that fits in the sidearm slot.
static func machine_pistol(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.MACHINE_PISTOL, "Machine Pistol", ZeeWeaponIds.SLOT_SIDEARM,
		DotWeaponDef.Fire.AUTO, rpm_ticks(900.0)
	)
	def.tags = [
		ZeeWeaponIds.TAG_SIDEARM, ZeeWeaponIds.TAG_AUTOMATIC, ZeeWeaponIds.TAG_SILENCED
	]
	def.ammo_type = ZeeWeaponIds.AMMO_LIGHT
	def.magazine = 25
	def.reserve = 100
	def.reserve_max = 200
	def.reload_ticks = sec_ticks(1.9)
	def.deploy_ticks = sec_ticks(0.25)
	def.holster_ticks = sec_ticks(0.18)

	var b := _ballistics(t, 13.0)
	b.spread = 0.9
	b.spread_moving = 3.2
	b.spread_airborne = 6.0
	b.bloom = 0.32
	b.bloom_max = 5.5
	b.bloom_recovery = 10.0 / float(TICK_RATE)
	b.recoil_pitch = 0.3
	b.recoil_yaw = 0.18
	b.max_range = 70.0
	def.tuning = b
	return def


## Two shots, both of them enormous, and nothing at range. The last-resort weapon.
static func derringer(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.DERRINGER, "Derringer", ZeeWeaponIds.SLOT_SIDEARM,
		DotWeaponDef.Fire.SEMI, rpm_ticks(90.0)
	)
	def.tags = [ZeeWeaponIds.TAG_SIDEARM]
	def.ammo_type = ZeeWeaponIds.AMMO_LIGHT
	def.magazine = 2
	def.reserve = 12
	def.reserve_max = 24
	def.reload_ticks = sec_ticks(2.0)
	def.deploy_ticks = sec_ticks(0.18)
	def.holster_ticks = sec_ticks(0.12)

	var b := _ballistics(t, 62.0)
	# Wide even standing still, and a range that stops well short of a corridor. The
	# damage is only collectable in somebody's face, which is where this belongs.
	b.spread = 2.2
	b.spread_moving = 5.0
	b.recoil_pitch = 3.2
	b.max_range = 18.0
	def.tuning = b
	return def


# --- Primaries --------------------------------------------------------------

## Fast, light, and out of its depth past thirty metres.
static func smg(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.SMG, "SMG", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.AUTO, rpm_ticks(820.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY, ZeeWeaponIds.TAG_AUTOMATIC]
	def.ammo_type = ZeeWeaponIds.AMMO_LIGHT
	def.magazine = 30
	def.reserve = 120
	def.reserve_max = 240
	def.reload_ticks = sec_ticks(1.8)
	def.deploy_ticks = sec_ticks(0.26)
	def.holster_ticks = sec_ticks(0.2)

	var b := _ballistics(t, 16.0)
	b.spread = 0.7
	b.spread_moving = 2.4
	b.spread_airborne = 5.0
	b.spread_crouched = 0.6
	b.bloom = 0.26
	b.bloom_max = 4.5
	b.bloom_recovery = 9.0 / float(TICK_RATE)
	b.recoil_pitch = 0.26
	b.recoil_yaw = 0.14
	b.max_range = 80.0
	def.tuning = b
	return def


## The rifle you take when you do not know what the fight is going to be.
static func carbine(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.CARBINE, "Carbine", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.AUTO, rpm_ticks(660.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY, ZeeWeaponIds.TAG_AUTOMATIC]
	def.ammo_type = ZeeWeaponIds.AMMO_HEAVY
	def.magazine = 24
	def.reserve = 96
	def.reserve_max = 192
	def.reload_ticks = sec_ticks(2.0)
	def.deploy_ticks = sec_ticks(0.3)
	def.holster_ticks = sec_ticks(0.22)

	var b := _ballistics(t, 21.0)
	b.spread = 0.5
	b.spread_moving = 2.1
	b.spread_airborne = 4.5
	b.spread_crouched = 0.55
	b.bloom = 0.28
	b.bloom_max = 4.2
	b.bloom_recovery = 9.0 / float(TICK_RATE)
	b.recoil_pitch = 0.34
	b.recoil_yaw = 0.14
	b.max_range = 140.0
	def.tuning = b
	return def


## The all-rounder, and the one every other primary is balanced against.
static func rifle(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.RIFLE, "Assault Rifle", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.AUTO, rpm_ticks(600.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY, ZeeWeaponIds.TAG_AUTOMATIC]
	def.ammo_type = ZeeWeaponIds.AMMO_HEAVY
	def.magazine = 30
	def.reserve = 120
	def.reserve_max = 240
	def.reload_ticks = sec_ticks(2.2)
	def.deploy_ticks = sec_ticks(0.32)
	def.holster_ticks = sec_ticks(0.24)

	var b := _ballistics(t, 23.0)
	b.spread = 0.45
	b.spread_moving = 2.2
	b.spread_airborne = 4.8
	b.spread_crouched = 0.5
	b.bloom = 0.27
	b.bloom_max = 4.6
	b.bloom_recovery = 8.5 / float(TICK_RATE)
	b.recoil_pitch = 0.36
	b.recoil_yaw = 0.15
	b.max_range = 180.0
	def.tuning = b
	return def


## Accurate while moving, in a pack where nothing else is. The weapon for a player who
## refuses to stand still.
static func bullpup(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.BULLPUP, "Bullpup", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.AUTO, rpm_ticks(700.0)
	)
	def.tags = [
		ZeeWeaponIds.TAG_PRIMARY, ZeeWeaponIds.TAG_AUTOMATIC, ZeeWeaponIds.TAG_SCOPED
	]
	def.ammo_type = ZeeWeaponIds.AMMO_HEAVY
	def.magazine = 32
	def.reserve = 128
	def.reserve_max = 256
	def.reload_ticks = sec_ticks(2.4)
	def.deploy_ticks = sec_ticks(0.34)
	def.holster_ticks = sec_ticks(0.26)

	var b := _ballistics(t, 20.0)
	b.spread = 0.5
	# The whole weapon is in this line: barely wider moving than standing.
	b.spread_moving = 1.0
	b.spread_airborne = 3.4
	b.bloom = 0.3
	b.bloom_max = 4.0
	b.recoil_pitch = 0.32
	b.recoil_yaw = 0.2
	b.max_range = 150.0
	def.tuning = b
	return def


## Semi-automatic and hard-hitting: two taps at any range, if you can land two taps.
static func battle_rifle(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.BATTLE_RIFLE, "Battle Rifle", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.SEMI, rpm_ticks(300.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY]
	def.ammo_type = ZeeWeaponIds.AMMO_HEAVY
	def.magazine = 20
	def.reserve = 80
	def.reserve_max = 160
	def.reload_ticks = sec_ticks(2.3)
	def.deploy_ticks = sec_ticks(0.36)
	def.holster_ticks = sec_ticks(0.26)

	var b := _ballistics(t, 36.0)
	b.spread = 0.25
	b.spread_moving = 2.6
	b.spread_crouched = 0.4
	b.bloom = 0.7
	b.bloom_max = 4.0
	b.recoil_pitch = 1.1
	b.recoil_yaw = 0.2
	b.max_range = 200.0
	def.tuning = b
	return def


## Three rounds per press, tight enough that all three land at range.
##
## [b]The burst interval is its own number and is much shorter than the gap between
## bursts.[/b] Using one interval for both is the bug that makes a three-round burst
## indistinguishable from automatic fire.
static func burst_rifle(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.BURST_RIFLE, "Burst Rifle", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.BURST, rpm_ticks(240.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY]
	def.ammo_type = ZeeWeaponIds.AMMO_HEAVY
	def.burst_count = 3
	def.burst_interval_ticks = 3
	def.magazine = 30
	def.reserve = 90
	def.reserve_max = 180
	def.reload_ticks = sec_ticks(2.1)
	def.deploy_ticks = sec_ticks(0.3)
	def.holster_ticks = sec_ticks(0.22)

	var b := _ballistics(t, 24.0)
	b.spread = 0.3
	b.spread_moving = 1.8
	b.bloom = 0.2
	b.bloom_max = 2.0
	b.recoil_pitch = 0.55
	b.recoil_yaw = 0.12
	b.max_range = 160.0
	def.tuning = b
	return def


## Nine pellets in a fixed ring, so range is a skill rather than a dice roll.
##
## [b]A fixed pattern, not a hashed one.[/b] A shotgun whose pellets land somewhere
## different every time is a weapon nobody can learn the range of, and "I hit them and
## nothing happened" is the complaint it generates.
static func shotgun(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.SHOTGUN, "Shotgun", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.SEMI, rpm_ticks(75.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY]
	def.ammo_type = ZeeWeaponIds.AMMO_SHELL
	def.magazine = 8
	def.reserve = 32
	def.reserve_max = 64
	# One shell at a time, so a reload can be cut short and the weapon used half full —
	# which is what makes a shotgun playable in a fight rather than between them.
	def.reload_per_round = true
	def.reload_ticks = sec_ticks(0.42)
	def.reload_start_ticks = sec_ticks(0.3)
	def.deploy_ticks = sec_ticks(0.38)
	def.holster_ticks = sec_ticks(0.28)

	var b := _ballistics(t, 12.0)
	b.pellets = 9
	b.fixed_pattern = true
	b.spread = 4.2
	b.spread_moving = 0.5
	b.recoil_pitch = 2.4
	b.max_range = 26.0
	def.tuning = b
	# Death reactions (dot-player-char's DotPlayerDeathReactions): Point-blank buckshot carries a body: half the time or so, by the server's weights.
	def.params[ZeeWeaponIds.PARAM_DEATH_POWER] = 0.6
	return def


## Automatic, fed from a drum, and weaker per shell. Volume instead of a single answer.
static func drum_shotgun(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.DRUM_SHOTGUN, "Drum Shotgun", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.AUTO, rpm_ticks(190.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY, ZeeWeaponIds.TAG_AUTOMATIC]
	def.ammo_type = ZeeWeaponIds.AMMO_SHELL
	def.magazine = 20
	def.reserve = 40
	def.reserve_max = 80
	# A whole drum at once, unlike the pump: the trade for firing automatically is that
	# running dry costs four seconds rather than being topped up between shots.
	def.reload_ticks = sec_ticks(4.0)
	def.deploy_ticks = sec_ticks(0.42)
	def.holster_ticks = sec_ticks(0.3)

	var b := _ballistics(t, 8.0)
	b.pellets = 7
	b.fixed_pattern = true
	b.spread = 5.4
	b.spread_moving = 1.2
	b.recoil_pitch = 1.1
	b.max_range = 20.0
	def.tuning = b
	# Death reactions (dot-player-char's DotPlayerDeathReactions): As the pump: a close kill may carry the body.
	def.params[ZeeWeaponIds.PARAM_DEATH_POWER] = 0.6
	return def


## Semi-automatic, scoped, and the answer to a rooftop that is not a sniper rifle.
static func marksman(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.MARKSMAN, "Marksman Rifle", ZeeWeaponIds.SLOT_PRIMARY,
		DotWeaponDef.Fire.SEMI, rpm_ticks(180.0)
	)
	def.tags = [ZeeWeaponIds.TAG_PRIMARY, ZeeWeaponIds.TAG_SCOPED]
	def.ammo_type = ZeeWeaponIds.AMMO_HEAVY
	def.magazine = 10
	def.reserve = 40
	def.reserve_max = 80
	def.reload_ticks = sec_ticks(2.6)
	def.deploy_ticks = sec_ticks(0.45)
	def.holster_ticks = sec_ticks(0.3)

	var b := _ballistics(t, 58.0)
	b.spread = 0.08
	# Punished hard for moving, which is what separates it from the battle rifle.
	b.spread_moving = 4.5
	b.spread_airborne = 8.0
	b.spread_crouched = 0.3
	b.bloom = 1.4
	b.bloom_max = 6.0
	b.recoil_pitch = 2.0
	b.max_range = 400.0
	def.tuning = b
	return def


# --- Heavies ----------------------------------------------------------------

## One shot, most of a player, and a second and a half before the next one.
static func sniper(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.SNIPER, "Sniper Rifle", ZeeWeaponIds.SLOT_HEAVY,
		DotWeaponDef.Fire.SEMI, rpm_ticks(45.0)
	)
	def.tags = [
		ZeeWeaponIds.TAG_HEAVY, ZeeWeaponIds.TAG_SCOPED, ZeeWeaponIds.TAG_PRIMARY
	]
	def.ammo_type = ZeeWeaponIds.AMMO_HEAVY
	def.magazine = 5
	def.reserve = 25
	def.reserve_max = 50
	def.reload_ticks = sec_ticks(3.2)
	def.deploy_ticks = sec_ticks(0.7)
	def.holster_ticks = sec_ticks(0.5)

	var b := _ballistics(t, 118.0)
	b.spread = 0.0
	b.spread_moving = 8.0
	b.spread_airborne = 14.0
	b.spread_crouched = 0.0
	b.recoil_pitch = 4.0
	b.max_range = 1000.0
	def.tuning = b
	# Death reactions (dot-player-char's DotPlayerDeathReactions): The heaviest single hit in the pack: a kill always throws the body.
	def.params[ZeeWeaponIds.PARAM_DEATH_REACTION] = &"power_launch"
	def.params[ZeeWeaponIds.PARAM_DEATH_POWER] = 1.0
	return def


## Belt-fed: no magazine at all, so it never reloads and simply runs out.
##
## [b]`magazine = 0` is not an oversight.[/b] dot-weapon reads a zero magazine as "feeds
## straight from the reserve", which is exactly what a belt is, and it means the weapon
## has no reload animation and no reload pause — the trade being that when the belt is
## gone, it is gone until somebody finds more.
static func minigun(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.MINIGUN, "Minigun", ZeeWeaponIds.SLOT_HEAVY,
		DotWeaponDef.Fire.AUTO, rpm_ticks(1100.0)
	)
	def.tags = [
		ZeeWeaponIds.TAG_HEAVY, ZeeWeaponIds.TAG_AUTOMATIC, ZeeWeaponIds.TAG_PRIMARY
	]
	def.ammo_type = ZeeWeaponIds.AMMO_BELT
	def.magazine = 0
	def.reserve = 200
	def.reserve_max = 400
	def.auto_reload = false
	def.reload_ticks = 0
	# Slow to bring up and slow to put away: the cost of carrying it is that you cannot
	# change your mind.
	def.deploy_ticks = sec_ticks(1.1)
	def.holster_ticks = sec_ticks(0.8)

	var b := _ballistics(t, 11.0)
	b.spread = 2.4
	b.spread_moving = 4.5
	b.spread_airborne = 7.0
	b.bloom = 0.08
	b.bloom_max = 2.0
	b.bloom_recovery = 4.0 / float(TICK_RATE)
	b.recoil_pitch = 0.12
	b.recoil_yaw = 0.1
	b.max_range = 110.0
	def.tuning = b
	return def


## Low direct damage, high splash. The interesting part of a launcher is what it does to
## the floor, and a launcher that kills on a direct hit is a hitscan weapon with travel
## time.
static func launcher(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.LAUNCHER, "Launcher", ZeeWeaponIds.SLOT_HEAVY,
		DotWeaponDef.Fire.SEMI, rpm_ticks(70.0)
	)
	def.behaviour_path = PROJECTILE
	def.tags = [ZeeWeaponIds.TAG_HEAVY, ZeeWeaponIds.TAG_EXPLOSIVE]
	def.ammo_type = ZeeWeaponIds.AMMO_ORDNANCE
	def.magazine = 4
	def.reserve = 12
	def.reserve_max = 24
	def.reload_ticks = sec_ticks(2.8)
	def.deploy_ticks = sec_ticks(0.5)
	def.holster_ticks = sec_ticks(0.34)

	var b := _ballistics(t, 32.0, ZeeWeaponIds.DAMAGE_BLAST)
	b.splash_type = ZeeWeaponDamage.from(
		t if not t.is_empty() else ZeeWeaponDamage.table(), ZeeWeaponIds.DAMAGE_BLAST
	)
	b.speed = 44.0
	# Not a charged weapon, so the floor and the ceiling are the same number: a launcher
	# that lobbed slower shells when tapped would be a different weapon.
	b.min_speed = 44.0
	b.min_charge_damage = 1.0
	b.gravity_scale = 0.25
	b.radius = 0.2
	b.life_ticks = sec_ticks(5.0)
	b.splash_radius = 4.5
	b.splash_damage = 88.0
	b.splash_hurts_owner = true
	b.spread = 0.0
	b.spread_moving = 0.0
	b.spread_airborne = 0.0
	b.recoil_pitch = 3.0
	b.max_range = 260.0
	def.tuning = b
	# Death reactions (dot-player-char's DotPlayerDeathReactions): A rocket kill always throws the body.
	def.params[ZeeWeaponIds.PARAM_DEATH_REACTION] = &"power_launch"
	def.params[ZeeWeaponIds.PARAM_DEATH_POWER] = 1.0
	return def


## Damage while it is held on a target, and nothing at all for a flick. The only weapon
## in the pack that rewards tracking rather than aim.
static func beamer(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.BEAMER, "Beamer", ZeeWeaponIds.SLOT_HEAVY,
		DotWeaponDef.Fire.HOLD, 4
	)
	def.behaviour_path = BEAM
	def.tags = [
		ZeeWeaponIds.TAG_HEAVY, ZeeWeaponIds.TAG_ENERGY, ZeeWeaponIds.TAG_PRIMARY
	]
	def.ammo_type = ZeeWeaponIds.AMMO_CELL
	# No magazine: cells feed straight from the reserve, so the beam simply stops.
	def.magazine = 0
	def.reserve = 260
	def.reserve_max = 520
	def.auto_reload = false
	def.reload_ticks = 0
	def.deploy_ticks = sec_ticks(0.4)
	def.holster_ticks = sec_ticks(0.3)
	# It ramps: half damage on contact, full after half a second on target. What makes
	# it a tracking weapon rather than a very fast automatic one.
	def.params.merge({
		&"ramp_ticks": sec_ticks(0.5),
		&"ramp_from": 0.45,
	})

	var b := _ballistics(t, 9.0, ZeeWeaponIds.DAMAGE_ENERGY)
	b.spread = 0.0
	b.spread_moving = 0.0
	b.spread_airborne = 0.0
	b.recoil_pitch = 0.0
	b.max_range = 40.0
	def.tuning = b
	return def


## Hold to charge, release to fire, and the damage is whatever the draw was worth.
##
## [b]Refuses to release below a third of a charge[/b], which the bow deliberately does
## not: a bow's weak shot is a real option, and a charge rifle spamming minimum-power
## shots would just be a bad automatic weapon.
static func charge_rifle(t: Dictionary = {}) -> DotWeaponDef:
	var def := _gun(
		ZeeWeaponIds.CHARGE_RIFLE, "Charge Rifle", ZeeWeaponIds.SLOT_HEAVY,
		DotWeaponDef.Fire.CHARGE, rpm_ticks(90.0)
	)
	def.tags = [
		ZeeWeaponIds.TAG_HEAVY, ZeeWeaponIds.TAG_ENERGY, ZeeWeaponIds.TAG_SCOPED
	]
	def.ammo_type = ZeeWeaponIds.AMMO_CELL
	def.magazine = 4
	def.reserve = 24
	def.reserve_max = 48
	def.charge_ticks = sec_ticks(1.1)
	def.charge_requires_min = true
	def.min_charge = 0.34
	def.reload_ticks = sec_ticks(2.6)
	def.deploy_ticks = sec_ticks(0.5)
	def.holster_ticks = sec_ticks(0.36)

	var b := _ballistics(t, 105.0, ZeeWeaponIds.DAMAGE_ENERGY)
	# A third of a charge is worth a third of the damage, so holding longer is always
	# the better trade and the only question is whether there is time.
	b.min_charge_damage = 0.33
	b.spread = 0.0
	b.spread_moving = 3.0
	b.spread_airborne = 6.0
	b.recoil_pitch = 2.6
	b.max_range = 500.0
	def.tuning = b
	# Death reactions (dot-player-char's DotPlayerDeathReactions): A full draw usually carries the body.
	def.params[ZeeWeaponIds.PARAM_DEATH_POWER] = 0.9
	return def


# --- Thrown -----------------------------------------------------------------
#
# [b]Both cook, and the fuse starts when the pin comes out rather than when the grenade
# leaves the hand.[/b] A fuse that starts on release makes every grenade a three-second
# warning for whoever it lands near, which is a grenade nobody has to react to. Cooking
# past the fuse kills the thrower, and it should: a grenade that refuses to go off in
# your hand is one with no downside to holding.

## Explodes on a fuse, wherever it has rolled to.
static func frag(t: Dictionary = {}) -> DotWeaponDef:
	var def := _thrown(t, ZeeWeaponIds.FRAG, "Frag Grenade", 3.0)
	var b := def.tuning as DotWeaponBallistics
	b.splash_radius = 5.2
	b.splash_damage = 115.0
	b.speed = 19.0
	b.min_speed = 19.0
	b.gravity_scale = 1.0
	return def


## Sticks where it lands, so it is thrown at a place rather than at a person. A shorter
## fuse, because it cannot be kicked away from where it stuck.
static func sticky(t: Dictionary = {}) -> DotWeaponDef:
	var def := _thrown(t, ZeeWeaponIds.STICKY, "Sticky Charge", 2.2)
	var b := def.tuning as DotWeaponBallistics
	b.splash_radius = 4.0
	b.splash_damage = 135.0
	b.speed = 22.0
	b.min_speed = 22.0
	b.gravity_scale = 0.8
	def.params[&"sticks"] = true
	return def


# --- Reporting --------------------------------------------------------------

static func describe_lines(types: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var built := weapons(types)
	out.append("zee-dot-weapons: %d weapons at %d Hz" % [built.size(), TICK_RATE])

	for def in built:
		var b := def.tuning as DotWeaponBallistics
		out.append("  %-16s slot %d  %-6s  %5.1f dmg  mag %-3d  %s" % [
			String(def.id),
			def.slot,
			DotWeaponDef.Fire.keys()[def.fire_mode],
			b.damage if b != null else 0.0,
			def.magazine,
			String(def.ammo_type) if def.ammo_type != &"" else "-",
		])

	return out
