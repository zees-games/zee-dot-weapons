extends RefCounted

## zee-dot-weapons' API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.
##
## 2: [method ZeeModelCache.set_asset_root] and [method ZeeModelCache.resolve], which a
## delivered game calls to find its own vendored art. A client shell built before them
## would mount such a pack and then fail to compile its client script.

## 3: [ZeeWeaponCards] (card, stats, BLURB, KIND): what a loadout screen says about a weapon.

## 4: [method ZeeShotFx.play_body_hit] (a confirmed hit drawn on a body the client's physics
## cannot see), [method ZeeShotFx.play_impact], [method ZeeShotFx.impact_kind], the
## [constant ZeeShotFx.BODY_GROUP] / [constant ZeeShotFx.NOT_BODY_GROUP] groups, and
## [method ZeeViewModel.on_swing], and the `box_magazine` reload part. A game calls them through `has_method` until its shell has them.

## 5: [method ZeeWorldModel.advance], [method ZeeWorldModel.swing], [method ZeeWorldModel.throw],
## [method ZeeWorldModel.action_fraction] and its SWING_KEYS / THROW_KEYS: somebody else's swing
## and throw drawn on their world model.

## 6: [method ZeeWeaponArtTable.model_paths] (the one list of art files a game vendors),
## [constant ZeeWeaponArtTable.ARMS_MODEL], and `validate_models(with_arms)` resolving through
## [method ZeeModelCache.resolve]. The sync tool is `tools/sync-art.sh`.
const LEVEL := 6
const OLDEST := 1
