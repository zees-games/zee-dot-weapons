extends "zee_weapon_pack_builders.gd"

## The melee weapons and sidearms of ZeeWeaponPack, split out for file size.


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
	def.mounts = [DotWeaponAttachment.MOUNT_MUZZLE, DotWeaponAttachment.MOUNT_MAGAZINE]
	def.ammo_type = ZeeWeaponIds.AMMO_LIGHT
	def.magazine = 15
	def.reserve = 60
	def.reserve_max = 120
	def.reload_ticks = sec_ticks(1.6)
	def.deploy_ticks = sec_ticks(0.22)
	def.holster_ticks = sec_ticks(0.16)

	var b := _ballistics(t, 20.0)
	flight(b, 380, 0.0009, 25, 0.6, 0.15, 0, 0.008)
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
	flight(b, 430, 0.0008, 30, 0.55, 0.25, 0, 0.01)
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
	flight(b, 360, 0.0009, 15, 0.5, 0.1, 0, 0.006)
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
