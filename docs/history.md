# History: bugs worth recognising again

Each is kept because its shape could come back; the live lesson is also a rule in [CLAUDE.md](../CLAUDE.md) or a topic file. The family-wide list is [bugs-found.md](../../../docs/bugs-found.md).

## Every shot on every dedicated server came out of the world origin, pointing north

`player_ref` was resolved inside `_resolve_presentation()`, behind its `role == SERVER` early return, so a server rig built every `DotWeaponContext` with `(0, 0, 0)` and `(0, 0, -1)`. The weapon fired, the ammunition went down, the use counter replicated, and hit registration found nothing where it looked: a fight in which nobody can be shot and every number about it correct. Found in mg-smash-copter by running bots for twenty rounds: every round ended with exactly one player alive per side, a draw. **A number that is identical every round is a number nothing is deciding.** The test range had the same bug in the example, and its hit marks still landed where expected because the targets stand on that axis; the first rendered tracer ran from the gun to the floor under the player's feet.

## Recoil, reported as "very bad" (2026-10-05)

Measured before anything changed: the sniper kicked 17 degrees and 13 cm back for one shot, the hardest weapon kicked 28 times the softest, the sideways kick always went the same way, and the camera never moved. Four faults (weight counted twice, a linear range, the gun turning about the eye, an unsigned yaw); after the fix the sniper is 5.7 degrees and 4.5 cm and the ratio is 11.

## "Doesn't shoot any bullets, and no sounds" (2026-10-05)

True of every game on the pack: the rig decided the use, the server resolved the hit, and the only thing a player saw was the gun kick. "The half that draws" drew the gun and stopped. `ZeeShotFx` and `ZeeWeaponSound` are the rest.

## Rendered, never asserted

- Six melee weapons drawn end-on as specks (a second -90 rotation).
- The sniper's stock 16 cm from the eye (an offset correction not scaled with the model).
- Two cream slabs with the rifle somewhere behind them (`arm_scale` 0.36), and later every reaching arm a slab across its gun (thickness tied to length).
- A pale slab across the lower half of the screen (shoulders behind the near plane, sliced).
- A scope overlay that filled nothing (anchors without offsets) and an arm across the scope (hiding the animated node, not the arms).
- A sniper tracer as a yellow fleck; the first muzzle flash as a pale square a tenth of the screen across.
- The hands held under each game's own lens: a smaller gun drifting to the middle, or a bigger one, magnified on an aim zoom; the rifle almost on the crosshair with its top toward the eye.

## "Doesn't look like a production shooter" (2026-10-10)

Christian's clip of arena put six things side by side with a production shooter's view model: the rifle pointed straight down the view so only its back face showed; it sat almost centred; the arms were unlit pale slabs with no hand; the gun flipped bright and dark walking through shade; the reload pitched the barrel 32 degrees at the sky; and every weapon moved by the same springs. None of it was reachable by the suite (192 checks, all green throughout). The contact sheet (`tools/screenshot.sh --sheet`) was built first so that each fix could be seen beside the one before; it also found that the arms did not move with the gun at all (a draw slid the rifle out of two hands holding nothing), and that the turning sway led the turn instead of lagging it. The suite's new jolt check then found the bob's `|sin|` corner at every footfall.

## Every blaster was drawn backwards (2026-10-10)

`ZeeWeaponArtTable._blaster` said `model_forward = Vector3.BACK` (+Z), and the meshes point -Z. Every blaster in first person and in every carrier's hands was stock-first, with tracers and flashes leaving the stock and the silencers placed "in front of the barrel" on the stock. The rack, built to prove orientation, could not: seventeen meshes have symmetric bounds along their length, so the measured muzzle sits at whichever end the table names, and the rack showed the table agreeing with itself. Found by the contact sheet (the shotgun's two barrels at the near end), settled by a Blender side render with a marker on +Z. **A check that measures what it was told to measure proves nothing about the axis it was told.**

## Found in a game

- **Every weapon in a delivered game loaded invisible**, one WARN each: the art was under the pack's mount and the table named `res://assets/`. Found by game-playground; `set_asset_root` is the fix.
- **A lambda source aborted the process at exit (134)** after every check passed. Found by zed-dot-weapons through dot-server-deploy's zombiezone client.
- **A restored rig refused the next alt-fire press, once**: the previous command's buttons were not in the snapshot. Found by the suite's rollback section.
