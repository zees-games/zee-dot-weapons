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

## A silencer in front of the gun, and the flash behind it (2026-10-10)

After the -Z fix the minigun's silencer went on "the muzzle", the -Z end of the mesh's bounds. A third-person render of a carrier (a figure facing -Z with a hand where game-arena puts one) showed it floating ahead of the barrel and below it, with the flash and the tracer starting in the gap. The -Z end of `blaster-f`'s bounds is the tip of a slanted brake 13 cm past the barrel's end (z -0.52), and its bore is 5.2 cm above the origin; the attachment sat at the origin's height. The muzzle the effects use was the bounds' end too, so with the silencer on, every shot started inside it. The silencer now slides over the brake at the bore's height, and the art names the muzzle as the silencer's far end (`muzzle_distance`, `muzzle_offset`); the machine pistol's got the same treatment (1.7 cm of height). The muzzle direction, the rifle and the sniper (slid -0.8 m) were right in the same render. **The bounds' end is where the mesh stops, not where the bore does; an attachment on a barrel is placed at the bore and moves the muzzle to its own end.**

## Aimed at the back of the gun (2026-10-10)

Every aimed frame on the contact sheet showed a pale block under the crosshair: the rear face of the gun, because one written aim place put the eye level with the middle of every blaster's back. The first fix, a sight built on the gun with the hold derived from its line, drew a notch so close to the eye that it filled the middle of the screen and hid the ring; a rear sight is half the front's distance away and twice the size, so it sits below the line now. The ring sized by the gun's width came out a third the size on the second pack's slimmer guns; it is sized by angle. The range's crosshair label was 15 px under the screen's centre at the sheet's font size (its box grew downward only), which made a centred sight look low until a crop with centre lines settled it. **Check "centred" against the frame's centre, not against a HUD element.**

## Found in a game

- **Every weapon in a delivered game loaded invisible**, one WARN each: the art was under the pack's mount and the table named `res://assets/`. Found by game-playground; `set_asset_root` is the fix.
- **A lambda source aborted the process at exit (134)** after every check passed. Found by zed-dot-weapons through dot-server-deploy's zombiezone client.
- **A restored rig refused the next alt-fire press, once**: the previous command's buttons were not in the snapshot. Found by the suite's rollback section.
