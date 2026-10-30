extends RefCounted

## Tick constants, behaviour paths and row builders of ZeeWeaponPack, split out for file size.

## The tick rate everything below is tuned for; every row says so in [member DotWeaponDef.authored_tick_rate].
## dot-weapon scales each count to the rate it runs at. Set on the row by every builder, so [code]ZeeWeaponPack.rifle()[/code] alone gets it too.
const TICK_RATE := 64

const HITSCAN := "res://addons/dot_weapon/behaviour/dot_weapon_hitscan.gd"
const PROJECTILE := "res://addons/dot_weapon/behaviour/dot_weapon_projectile.gd"
const THROWN := "res://addons/dot_weapon/behaviour/dot_weapon_thrown.gd"
const BEAM := "res://addons/dot_weapon/behaviour/dot_weapon_beam.gd"
const MELEE := "res://addons/dot_weapon/behaviour/dot_weapon_melee.gd"


## Ticks between uses for a weapon quoted in rounds per minute.
static func rpm_ticks(rpm: float) -> int:
	return maxi(1, int(round(60.0 / rpm * float(TICK_RATE))))


## Ticks for a duration quoted in seconds.
static func sec_ticks(seconds: float) -> int:
	return maxi(0, int(round(seconds * float(TICK_RATE))))



## Automatic guns that also offer a burst on the selector; the rest of the automatics offer semi only.
const BURST_SELECTOR: Array[StringName] = [&"machine_pistol", &"smg", &"carbine", &"rifle", &"bullpup"]


## The fields every blaster shares. Hitscan unless the caller changes it.
static func _gun(
	id: StringName,
	name: String,
	slot: int,
	fire: DotWeaponDef.Fire,
	interval: int
) -> DotWeaponDef:
	var def := DotWeaponDef.new()
	def.authored_tick_rate = TICK_RATE
	def.id = id
	def.display_name = name
	def.behaviour_path = HITSCAN
	def.slot = slot
	def.fire_mode = fire
	def.fire_modes = DotWeaponDef.selector_modes(fire, id in BURST_SELECTOR)
	def.use_interval_ticks = interval
	def.cost_per_use = 1
	# Every blaster can bash, and the bash is the same for all of them bar the reach and
	# the damage its own size earns. Read by ZeeWeaponBash through the rig.
	def.params = {
		&"bash_damage": 42.0,
		&"bash_reach": 1.9,
		&"bash_cooldown_ticks": sec_ticks(0.8),
	}
	def.params.merge(ZeeWeaponPose.Tunables.kick_defaults())
	return def


## The fields every melee weapon shares.
static func _melee(
	t: Dictionary,
	id: StringName,
	name: String,
	damage: float,
	reach: float,
	interval: int,
	arc: float,
	rays: int
) -> DotWeaponDef:
	var def := DotWeaponDef.new()
	def.authored_tick_rate = TICK_RATE
	def.id = id
	def.display_name = name
	def.behaviour_path = MELEE
	def.slot = ZeeWeaponIds.SLOT_MELEE
	def.fire_mode = DotWeaponDef.Fire.SEMI
	def.use_interval_ticks = interval
	def.tags = [ZeeWeaponIds.TAG_MELEE]
	# No pool, no magazine, no reload. A melee weapon that could run out would be a
	# weapon a player can be left with nothing after.
	def.ammo_type = &""
	def.magazine = 0
	def.cost_per_use = 0
	def.auto_reload = false
	def.reload_ticks = 0
	def.deploy_ticks = sec_ticks(0.25)
	def.holster_ticks = sec_ticks(0.18)
	def.params = {
		&"arc_degrees": arc,
		&"rays": rays,
	}

	var b := _ballistics(t, damage, ZeeWeaponIds.DAMAGE_STRIKE)
	b.max_range = reach
	b.spread = 0.0
	b.spread_moving = 0.0
	b.spread_airborne = 0.0
	b.recoil_pitch = 0.0
	def.tuning = b
	return def


## The fields both grenades share.
static func _thrown(
	t: Dictionary, id: StringName, name: String, fuse_seconds: float
) -> DotWeaponDef:
	var def := DotWeaponDef.new()
	def.authored_tick_rate = TICK_RATE
	def.id = id
	def.display_name = name
	def.behaviour_path = THROWN
	def.slot = ZeeWeaponIds.SLOT_THROWN
	def.fire_mode = DotWeaponDef.Fire.CHARGE
	def.use_interval_ticks = sec_ticks(1.0)
	def.tags = [ZeeWeaponIds.TAG_THROWN, ZeeWeaponIds.TAG_EXPLOSIVE]
	def.ammo_type = ZeeWeaponIds.AMMO_GRENADE
	def.magazine = 0
	def.reserve = 2
	def.reserve_max = 4
	def.cost_per_use = 1
	def.auto_reload = false
	def.reload_ticks = 0
	# The cook. Held past this and it goes off in the hand, which is what makes cooking
	# a decision rather than a free improvement.
	def.charge_ticks = sec_ticks(fuse_seconds)
	def.charge_requires_min = false
	def.deploy_ticks = sec_ticks(0.35)
	def.holster_ticks = sec_ticks(0.25)
	def.params = {
		&"fuse_ticks": sec_ticks(fuse_seconds),
		&"speed_scales_with_cook": false,
	}

	var b := _ballistics(t, 0.0, ZeeWeaponIds.DAMAGE_BLAST)
	b.radius = 0.12
	b.life_ticks = sec_ticks(12.0)
	b.max_range = 100.0
	b.splash_hurts_owner = true
	def.tuning = b
	return def


static func _ballistics(
	t: Dictionary, damage: float, type: StringName = ZeeWeaponIds.DAMAGE_DART
) -> DotWeaponBallistics:
	var b := DotWeaponBallistics.new()
	b.damage = damage
	b.damage_type = ZeeWeaponDamage.from(
		t if not t.is_empty() else ZeeWeaponDamage.table(), type
	)
	return b
