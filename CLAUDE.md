# zee-dot-weapons

A weapons pack on top of dot-weapon: twenty-seven weapons (blasters, melee, grenades, fists) as one catalogue a server validates, plus the half dot-weapon deliberately refuses: a first-person view model with arms, a third-person world model, procedural animation, tracers, flashes, baked sounds, and the replicated fields that let a watcher see somebody else's gun move. Ships its CC0 art. On `gamemann`, like the games, not `modcommunity` (`origin` is `git@github.com:gamemann/zee-dot-weapons.git`).

Read the family [CLAUDE.md](../../CLAUDE.md) first, and [dot-weapon's](../dot-weapon/CLAUDE.md). This file is only what is specific to this repository. **The detail is in [docs/](docs/README.md).**

**Everything about a view model is placement and motion, and no assertion reaches either.** Every view-model bug here was found by rendering. Touch the view model, then run `tools/screenshot.sh` and look.

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/design.md](docs/design.md) | documents vs art, roles, ticks, the bash, the rig's snapshot, the carrier, replication, the asset root, a second pack |
| [docs/view-model.md](docs/view-model.md) | the muzzle, orientation, pose and recoil, aiming, the hands' lens, hip poses, the arms, measured numbers |
| [docs/shot-fx.md](docs/shot-fx.md) | tracers, flashes, impacts, sounds, reload sounds, the range's capture |
| [docs/testing.md](docs/testing.md) | adding a check, or rendering the pack |
| [docs/history.md](docs/history.md) | a bug that "cannot be happening" |

## Layout

| Path | What |
| --- | --- |
| `addons/zee_weapons/content/` | `ZeeWeaponPack` (the catalogue, in ticks), `ZeeWeaponIds` (roles), `ZeeWeaponDamage` |
| `addons/zee_weapons/art/` | `ZeeWeaponArtTable` (the only file with filenames, poses, aim settings), `ZeeWeaponArt`, `ZeeModelCache` (loading, muzzle measurement, asset root) |
| `addons/zee_weapons/runtime/` | `ZeeWeaponRig` (drives a `DotWeaponArsenal`, the bash, the snapshot), `ZeeWeaponInput` (the only file that reads a device) |
| `addons/zee_weapons/behaviour/` | `ZeeWeaponBash` |
| `addons/zee_weapons/view/` | `ZeeViewModel`, `ZeeViewArms`, `ZeeWeaponPose`, `ZeeWorldModel`, `ZeeShotFx`, `ZeeWeaponSound`, `ZeeScopeOverlay` |
| `addons/zee_weapons/net/` | `ZeeWeaponNet`: the replicated fields |
| `assets/` | the vendored CC0 art: blasters, melee, arms |
| `examples/` | `zee_selftest` (the suite), `zee_range` (a playable range, and the render target) |
| `tools/` | `screenshot.sh`, `rack.tscn` |
| `docs/rack.png` | the README's picture of the pack |

## Running and testing

- `./game.sh test` parses everything and runs `zee_selftest`; read its stderr even when it exits 0. [testing](docs/testing.md)
- `tools/screenshot.sh <weapon>`, `--all`, `--rack`; `EXTRA="--aim"` for the scope, `EXTRA="--no-arms 1"` for the weapon alone. Not `--headless` (a black PNG). [testing](docs/testing.md#look-at-it-because-the-suite-cannot)
- `zee_range -- --weapon smg --fire --capture <prefix>` saves a slowed flip-book of one shot. [shot-fx](docs/shot-fx.md#seeing-a-shot-on-a-machine-with-no-hands)

## Rules that bite

Short forms; the reasoning is in the linked file.

**The pack**

- Simulation never touches art: a headless build never reaches `ZeeModelCache`. [design](docs/design.md#the-one-idea)
- `ZeeWeaponArtTable` is the only file with a filename; weapons are named by role. [design](docs/design.md#weapons-are-named-by-role-never-by-model)
- Durations are ticks at `ZeeWeaponPack.TICK_RATE` (64), through `rpm_ticks`; never seconds. [design](docs/design.md#durations-are-ticks)
- The bash is the rig's own state machine; dot-weapon is not forked. [design](docs/design.md#the-alt-fire-is-not-a-fork)
- The previous command's buttons and the bash cooldown are in the rig's snapshot. [design](docs/design.md#what-the-rig-counts-and-why)
- The holster is seen by `is_switching()` going true; `switched` fires between holster and deploy. [design](docs/design.md#what-the-rig-counts-and-why)
- `player_ref` resolves on a SERVER rig too; a rig without a carrier is handed a context from the eye, not the camera. [design](docs/design.md#the-rig-needs-its-player-on-every-role)
- Shots replicate as a four-bit counter in the snapshot; compare with wrap-aware `uses_between()`. [design](docs/design.md#replication-is-a-counter-not-an-event)
- A game sets `ZeeModelCache.set_asset_root` on load and puts `res://` back when it goes. [design](docs/design.md#the-art-inside-a-delivered-game)
- A second pack registers through `add_source` / `set_class`; this pack's ids win; **a source is a static method's Callable, never a lambda** (exit 134). [design](docs/design.md#a-second-pack-adds-to-this-one)

**The view model** (every one found by rendering)

- The muzzle is measured from the mesh's bounds (`muzzle_distance`), never authored; it is for effects only, never a shot's origin. [view-model](docs/view-model.md#the-muzzle-is-measured-never-written-down)
- State `model_forward`, derive `orientation()`; never both. Blasters point +Z, melee and grenades +Y with the origin at the grip. [view-model](docs/view-model.md#orientation-and-the-three-ways-it-goes-wrong)
- Handle the reversed vector before the general axis-angle case (`NaN` draws nothing). [view-model](docs/view-model.md#orientation-and-the-three-ways-it-goes-wrong)
- A melee weapon carries no extra `world_rotation` of -90. [view-model](docs/view-model.md#orientation-and-the-three-ways-it-goes-wrong)
- A per-model offset correction is scaled with the model. [view-model](docs/view-model.md#orientation-and-the-three-ways-it-goes-wrong)
- The pose runs on render frames and writes nothing the simulation reads; everything it is handed is clamped and finite-checked. [view-model](docs/view-model.md#presentation-is-never-part-of-the-netcode-contract)
- The recoil spring is critically damped and solved in closed form; no Euler integrator. [view-model](docs/view-model.md#presentation-is-never-part-of-the-netcode-contract)
- Weight slows the spring and scales sway and bob, never the kick; `kick_degrees()` compresses the range; the kick turns about `pivot` (the grip); the yaw picks a side per shot. [view-model](docs/view-model.md#recoil)
- The camera's recoil is the game's, through `rig.view_punch()` into `DotFpsView.external_angles`; never into a command. [view-model](docs/view-model.md#recoil)
- Aiming changes nothing simulated; the zoom is the game's (`external_fov_scale`); a scope hides the weapon and the arms. [view-model](docs/view-model.md#aiming-is-presentation-and-the-game-decides-the-button)
- The hands are drawn at `hands_fov` (90) under any camera, by scaling X and Y only, and only under a `Camera3D`. [view-model](docs/view-model.md#the-hands-have-a-lens-of-their-own)
- Hip poses sit low and right (`ZeeWeaponArtTable.pose_offset`), off the crosshair. [view-model](docs/view-model.md#where-the-weapon-is-held)
- Arms reach for hands measured off the weapon's bounds (30% / 62% along the barrel); thickness is `forearm_width`, never `arm_scale`. [view-model](docs/view-model.md#the-arms)
- Every shoulder is in front of the near plane (a clip plane slices, it does not hide). [view-model](docs/view-model.md#the-arms)
- The view model and arms cast no shadow. [view-model](docs/view-model.md#presentation-is-never-part-of-the-netcode-contract)

**Shots**

- A tracer ends at a presentation raycast from the eye, drawn from the muzzle; never waits for the server's hit. [shot-fx](docs/shot-fx.md#decisions-each-the-obvious-alternative-being-wrong)
- Tracers and impacts are sized by camera distance; billboards need a texture and `billboard_keep_scale`. [shot-fx](docs/shot-fx.md#decisions-each-the-obvious-alternative-being-wrong)
- A world model whose carrier draws its own effects stays quiet (`_carrier_draws_its_own`). [shot-fx](docs/shot-fx.md#decisions-each-the-obvious-alternative-being-wrong)
- No sound or effect on a server or on a replayed tick. [shot-fx](docs/shot-fx.md)

## Not here yet

- **Nothing scales by tick rate.** The pack is authored in 64 Hz ticks and neither `ZeeWeaponRig` nor dot-weapon's arsenal rescales a duration, so on a 128 Hz server (game-playground) every weapon fires, reloads and deploys twice as fast. Open; queued as `playground-zee-tickrate-1`, to be fixed in the arsenal rather than per game. [design](docs/design.md#durations-are-ticks)
- **No recorded sounds.** Every report is baked; `ZeeWeaponSound.set_stream` takes a recording per weapon when there is one to vendor. [shot-fx](docs/shot-fx.md#sounds-are-baked)
- **Client shells.** A game calling `set_asset_root`, `view_punch` or the reaching arms needs a client shell built with a zee-dot-weapons that has them, or the zee pack delivered as an addon release; a game calls newer methods through `has_method`.
