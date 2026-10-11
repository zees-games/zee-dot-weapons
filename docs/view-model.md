# The view model: placement, orientation, motion and the arms

Every bug in this file was found by rendering a frame and looking at it; none could be found by an assertion. Change any of it, then render ([testing](testing.md#look-at-it-because-the-suite-cannot)).

## The muzzle is measured, never written down

`ZeeModelCache.muzzle_distance()` takes the far end of the mesh's own bounding box along its forward axis. The alternative is a hand-authored offset per model, and one of them would have been wrong: `blaster-e` is the only model in the kit whose origin sits at the stock rather than at its centre, so the offset right for the other seventeen puts its muzzle behind the player's ear.

**The muzzle is for effects only.** A shot's real origin is the player's eye, decided by the server. A muzzle origin would make a weapon's reach depend on its model, and a player with the view model off would shoot from somewhere else.

## Orientation, and the three ways it goes wrong

`ZeeWeaponArt.model_forward` states which way a mesh points and `orientation()` derives the rotation that fixes it. Never state both: they drift, and a weapon points backwards in the world and forwards on the screen.

The blasters point along **+Z** and Godot's forward is **-Z**. The melee models and the grenades point along **+Y**, standing on their handle with the origin exactly where a hand grips them.

1. **Handle the reversed case before the general one.** Two opposite vectors have a zero cross product, so the general axis-angle formula gives a basis full of `NaN`, which draws nothing with no error.
2. **A melee weapon must not also carry a `world_rotation` of -90.** `model_forward` has already turned +Y onto -Z, so a second rotation puts the blade through the floor (six melee weapons drawn end-on as specks).
3. **A per-model offset correction is scaled with the model.** The sniper's pull-back is a distance along a mesh drawn at 40% in first person; applied flat it pulled four times too far and put the stock 16 cm from the eye.

## Presentation is never part of the netcode contract

`ZeeWeaponPose` runs on render frames, reads a delta in seconds, and never writes to anything the simulation reads. A player with the view model off simulates identically to one with it on: dot-player-controller's line between motor and view, drawn again in the same place.

- **Everything the pose is handed is clamped and checked for finiteness.** One `NaN` in a `Transform3D` makes the weapon vanish with no error, and presents as "the view model broke".
- **The recoil spring is critically damped and solved in closed form.** Explicit Euler adds energy every step (a spring that grows over seconds of held fire, which reads as tuning). Semi-implicit Euler is unstable past w·dt ≈ 2, which a 10 fps frame is, and under critical damping bled about a third of every kick in its first step. The suite holds the trigger for thirty seconds, and asserts the climb drawn at 144 fps and at 30 is the climb asked for.
- The view model and the arms cast no shadow; the world model does (`ZeeWorldModel.cast_shadow`).

## Light: no world shadow, and a key light of its own

**The view model receives no shadow** (`disable_receive_shadows` on every duplicated material, the arms' too). It is drawn where the camera is, so the world's shadow map darkened it whenever the player's head was in shade, and the gun flipped bright and dark walking along a wall. The sheet's "in shade" frame stands the player under a roof and must look like the hip frame.

**It carries its own key light** (`ZeeViewModel.view_light_energy`, 0.3): a `DirectionalLight3D` under the view model, so it turns with the camera, raking from above, behind and left across the right side the hold shows. Its `light_cull_mask` is `view_layer` (20) and every view-model and arm mesh is drawn on that layer alone, so it lights nothing in the world; it has no shadow and `SKY_MODE_LIGHT_ONLY`, so it draws no second sun. Without it, turning away from the sun left the gun lit by the ambient alone, flat. The world's lights still reach the view model (their masks include every layer), so it stays in the place it is in. At 0.55 the gun and arms washed out to white under the range's sun; 0.3 keeps the faces distinct.

- A game whose camera culls layer 20 does not see the hands; set `view_layer` to a layer it draws, or 0 for none (and no key light).
- Unshaded materials were the other option and are wrong: a flat gun reads as a sticker over the screen.

## Recoil

Each of these is its own line in `ZeeWeaponPose`:

- **Weight does not scale the kick.** A behaviour's `recoil_pitch` already says how hard a weapon kicks; `ZeeWeaponArt.weight` slows the spring (by its square root) and scales sway and bob, and never touches the size of a kick. Scaling both counted the sniper's size twice (17 degrees and 13 cm back for one shot).
- **The range is compressed.** Recoil runs 0.12 to 4.0 across the pack, right for a camera climbing and wrong for a gun in a hand: `kick_degrees()` is `kick_pitch · r / (1 + r · kick_knee)`.
- **The gun turns about the grip, not the eye.** `Animated` sits at the camera, so a rotation there carries the whole weapon up the screen. `pivot` is the holder's rest origin, the grip, and the kick turns about that.
- **The yaw picks a side per shot** (`punch()`). Every behaviour hands over a positive `recoil_yaw`.

**The camera's half is the game's to apply**, through `rig.view_punch()` (30% of the climb). The view model is a child of the camera, and every controller in the family writes the camera's angles from scratch each frame, so anything the pack added there would be overwritten. dot-player-controller's `DotFpsView.external_angles` exists for it. It is never added to a command: the shot went where the command pointed.

## Aiming is presentation, and the game decides the button

`ZeeViewModel.aim(held)` eases the weapon from the hip to `ZeeWeaponArt.aim_offset` over `aim_time`, steadies sway and bob by `ZeeWeaponPose.aim_steadiness`, and reports `aim_fov_scale()` (the art's `aim_zoom` at full aim) and `is_scoped()`. **It changes nothing the server simulates**: no command bit, no snapshot field. The half of aiming that is a rule (tighter spread, slower walk) is a game's, in its own command.

- The game applies the zoom to its camera (`DotFpsView.external_fov_scale`) and puts a `ZeeScopeOverlay` in its HUD for scoped weapons.
- Through a scope the view model hides the weapon **and the arms**: the arms are the view model's own child, so hiding the animated node alone leaves an arm across the scope.
- The scope overlay sets its offsets as well as its anchors, or it fills nothing.
- Melee and throwables have `aim_enabled` off; the sniper is x0.3 and the marksman x0.5, both scoped; everything else aims at x0.8.
- Right mouse is the bash's button too; which one it is, is a game setting. The alt-fire is `BUTTON_ALT` in the command; the aim is a local hold.

## The hands have a lens of their own

**The hands are drawn at `ZeeViewModel.hands_fov` (90 degrees) whatever the game's camera.** Every pose was set under the range's 90-degree camera, and games hold them under 83 to 100, which drew a smaller gun drifting to the middle, or a bigger one, and magnified the gun with the world on an aim zoom. The view model's X and Y are scaled by `tan(camera/2) / tan(hands/2)` (`lens_scale`) in the camera's space with Z left alone, which is exactly a perspective projection at the other lens: depth is untouched, so sorting and the muzzle a tracer starts from are unchanged. Applied only when the view model's parent is a `Camera3D`; anywhere else the same scale would be a distortion.

## Where the weapon is held

**Hip poses sit low and right** (`ZeeWeaponArtTable.pose_offset`). A rifle 12 cm right and 16 down at 48 cm out sat almost on the crosshair with its top toward the eye.

**And canted and turned** (`pose_rotation`: yaw +10 brings the muzzle in, roll -30 tilts the right side up; pistols and heavies a little less). A weapon below and right of the eye pointing where the eye points shows the camera its back face and a sliver of its left side, which is what this pack drew: a stub in the corner of the screen, beside a production shooter's rifle lying large across the lower right with its right side and top showing. Perspective already carries a straight barrel toward the centre; at this distance the right side does not face the eye at all until the cant is about thirty degrees (the face normal against the direction back to the camera). The rifle is at 0.6 scale and 0.40 m out, so its length runs from the bottom-right corner to just short of the crosshair.

- **Rotations are in the model's own space**, before `orientation()` turns +Z onto -Z: positive yaw is muzzle-in and negative roll is right-side-up for a blaster. A sign written by intuition is the wrong one about half the time; render it.
- **A correction along a weapon's length goes through the hold's basis**, not along the camera's Z (the sniper's pull-back): once the hold is turned, the camera's Z is no longer the weapon's.
- **The aim hold is a transform of its own** (`aim_offset` plus `aim_rotation`, zero: straight down the sight), reached through the view model's `Aim` node by a slerp of the rotation and a lerp of the position. Moving only the position, as the pose's `aim_shift` did, brought the canted gun to the middle end-on and crooked; interpolating the bases component-wise shrinks the gun half way.
- **The arms are not under `Aim`.** Carried rigidly to the sight, the shoulders went with the gun and the left arm lay across the screen. They are under `Animated` (so a kick, a reload and a draw carry them) and reach every frame for the grip and fore-end put through the `Aim` transform.
- `--hold "x,y,z,pitch,yaw,roll,scale"` on the range's `--sheet` re-equips with that hold, for tuning without an edit per guess.

## The arms

**The arms reach** (`ZeeViewArms.reach`): each arm is stretched from a shoulder below the screen to its hand, and the hands are measured off the weapon's own bounds along the barrel (right hand 30% from the back, left 62%). A knife or a grenade has one hand. Fixed per-pose placements held any weapon slid along its length in the art table a hand's width off its grip.

- **Thickness is `forearm_width` (7 cm), set apart from the length.** `arm_scale` scales both (the box is 0.4 wide in its own units), so an arm long enough to reach was a slab across the gun. At 0.36 the render was two cream slabs with the rifle somewhere behind them.
- **`arm_scale` is 0.20** for the fixed placements: the shoulders sit about 0.35 m out and the grip about 0.45 m out, so a fifth of a metre is the distance between them, and 8 cm of forearm at a third of a metre from a 90-degree camera is about a seventh of the screen.
- **Every shoulder is in front of the near plane.** A clipping plane does not hide an object, it slices it: shoulders placed anatomically behind the eye drew their cut face as a pale slab across the lower half of the screen.
- **`set_pose` still works** for a game that drives its own arms, and falls back to the fixed placements until a weapon is equipped. The pitches in those placements are past 90 degrees on purpose: the shoulder is below the weapon and the hand above it, so the arm rises as it goes forward.
- `--no-arms` on the range draws the weapon alone: an arm drawn wrongly and a weapon drawn wrongly look identical until one is switched off.

## Numbers that were measured, so nobody has to measure them again

| | |
| --- | --- |
| Blasters | 18, from 0.42 m (`blaster-b`) to 1.39 m (`blaster-e`) |
| `blaster-e` | the only one whose mesh origin is at the stock rather than the centre |
| Blocky character | 2.7 m tall, 1.6 m wide: a stylised giant, not a person |
| One arm | a 0.4 × 1.1 × 0.4 box, pivot at the shoulder, mesh hanging to `y = -1` |
| Melee tools | 0.15 m to 0.35 m tall, origin at the butt of the handle, pointing +Y |
| Target discs | modelled in the YZ plane, 0.34 m across: they need turning and scaling |
