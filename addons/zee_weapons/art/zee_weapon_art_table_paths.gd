extends RefCounted

## Model paths and pose names of ZeeWeaponArtTable, split out for file size.

## The arms model [ZeeViewArms] loads for `style = &"model"`; here so the vendoring list can name it.
const ARMS_MODEL := "res://assets/arms/character-a.glb"
## The rigged arm [ZeeViewArms] draws by default (`style = &"rigged"`): one right arm with finger bones, built by art-src/arms/ from a CC0 base. Without the file the arms fall back to the code-built gloves, so a game that has not synced it loses nothing.
const RIGGED_ARMS_MODEL := "res://assets/arms/arms-rigged.glb"
const BLASTERS := "res://assets/blaster-kit/"
const MELEE := "res://assets/melee/"
## The real-world guns (kitbashed from CC0 Quaternius and Kenney parts by art-src/guns/): one file per role, the muzzle on -Z and the origin at the bounds' centre like the blasters, a magazine split off as `<role>_magazine.glb` where the source had one.
const GUNS := "res://assets/low-poly-guns/"

## Shared parts ship as separate models, so a magazine visibly falls out on reload.

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

## Five hand positions rather than twenty-seven; a weapon states its family and only nudges what is its own.

const POSE_PISTOL := &"pistol"
const POSE_RIFLE := &"rifle"
const POSE_HEAVY := &"heavy"
const POSE_MELEE := &"melee"
const POSE_THROWN := &"thrown"
