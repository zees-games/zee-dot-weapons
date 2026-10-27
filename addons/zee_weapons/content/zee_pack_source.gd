class_name ZeePackSource
extends RefCounted

## Joins another addon's weapons (a `spawn_provider.gd` with a static `weapon_defs()`) to zee's catalogue and art table.
## Games scan for providers and decide which to take; this is the part every game repeats, so it lives here once.

## Registers [param provider]'s weapons under [param source]. [param defs_source] is a static Callable taking the damage table and
## returning the defs (a game wraps `weapon_defs` to tag tiers); it is called on every rig, so it must return fresh defs.
static func register(source: StringName, provider: Script, defs_source: Callable) -> void:
	ZeeWeaponPack.add_source(source, defs_source)
	ZeeWeaponArtTable.add_source(source, Callable(ZeePackSource, &"art_of").bind(provider, defs_source))


static func unregister(source: StringName) -> void:
	ZeeWeaponPack.remove_source(source)
	ZeeWeaponArtTable.remove_source(source)


## The pack's art: its `weapon_art()` when it has one, else stand-in art for each of [param defs_source]'s defs.
static func art_of(provider: Script, defs_source: Callable) -> Array[ZeeWeaponArt]:
	if provider.has_method(&"weapon_art"):
		return provider.call(&"weapon_art")

	return stand_in_art(defs_source.call(ZeeWeaponDamage.table()), provider)


## A copy of the zee gun of the same slot under each def's id, dressed from the provider's `art_rows()` so a pack that ships a model shows it.
## A tier tag decides, else the slot (a default slot of 1 is melee, so tags win where a game tiers its packs). Built fresh, never read from the table: this runs while the table is built.
static func stand_in_art(defs: Array, provider: Script) -> Array[ZeeWeaponArt]:
	var out: Array[ZeeWeaponArt] = []
	var rows: Dictionary = provider.call(&"art_rows") if provider.has_method(&"art_rows") else {}

	for def: DotWeaponDef in defs:
		var copy := _base_for(def)
		copy.id = def.id
		ZeeArtDress.apply(copy, rows.get(def.id, {}))
		out.append(copy)

	return out


static func _base_for(def: DotWeaponDef) -> ZeeWeaponArt:
	if def.tags.has(&"sidearm"):
		return ZeeWeaponArtTable.pistol()
	if def.tags.has(&"heavy"):
		return ZeeWeaponArtTable.launcher()
	if def.tags.has(&"melee"):
		return ZeeWeaponArtTable.knife()
	if def.tags.has(&"thrown"):
		return ZeeWeaponArtTable.frag()
	if def.tags.has(&"primary"):
		return ZeeWeaponArtTable.rifle()

	match def.slot:
		ZeeWeaponIds.SLOT_SIDEARM:
			return ZeeWeaponArtTable.pistol()
		ZeeWeaponIds.SLOT_HEAVY:
			return ZeeWeaponArtTable.launcher()
		ZeeWeaponIds.SLOT_MELEE:
			return ZeeWeaponArtTable.knife()
		ZeeWeaponIds.SLOT_THROWN:
			return ZeeWeaponArtTable.frag()

	return ZeeWeaponArtTable.rifle()
