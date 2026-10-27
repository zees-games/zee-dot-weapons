class_name ZeePackRoles
extends RefCounted

## Tier and role classification for other packs' weapons. The tables are the game's (passed in); the rules live here once.

## A provider's defs with exactly one of [param tiers] tagged. [param overrides] (id -> tier) win over what the pack tags;
## a def with none joins [param melee] when tagged so, else [param fallback]. Bind it as a source Callable: zee builds
## the defs fresh on every rig, so the tag has to be given each time.
static func tiered(types: Dictionary, provider: GDScript, tiers: Array, overrides: Dictionary, fallback: StringName = &"primary", melee: StringName = &"melee") -> Array[DotWeaponDef]:
	var defs: Array[DotWeaponDef] = provider.call(&"weapon_defs", types)

	for def in defs:
		var named := StringName(str(overrides.get(String(def.id), "")))

		if named != &"" and tiers.has(named):
			for tier: StringName in tiers:
				def.tags.erase(tier)

			def.tags.append(named)

		var has_tier := false

		for tier: StringName in tiers:
			has_tier = has_tier or def.tags.has(tier)

		if not has_tier:
			def.tags.append(melee if def.tags.has(melee) else fallback)

	return defs


## The first of [param ids] whose def in [param by_id] sits in [param slot]; one named `<prefix>_<default_name>` wins over the rest.
static func first_for_slot(ids: Array, by_id: Dictionary, slot: int, default_name: StringName) -> StringName:
	var first := &""
	var suffix := "_" + String(default_name)

	for id: StringName in ids:
		var def: DotWeaponDef = by_id.get(id)

		if def == null or def.slot != slot:
			continue

		if String(id).ends_with(suffix):
			return id

		if first == &"":
			first = id

	return first
