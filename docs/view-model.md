# The view model: placement, orientation, motion and the arms

Every bug in this file was found by rendering a frame and looking at it; none could be found by an assertion. Change any of it, then render ([testing](testing.md#look-at-it-because-the-suite-cannot)).

## The muzzle is measured, never written down

`ZeeModelCache.muzzle_distance()` takes the far end of the mesh's own bounding box along its forward axis. The alternative is a hand-authored offset per model, and one of them would have been wrong: `blaster-e` is the only model in the kit whose origin sits at the stock rather than at its centre, so the offset right for the other seventeen puts its muzzle behind the player's ear.

**The muzzle is for effects only.** A shot's real origin is the player's eye, decided by the server. A muzzle origin would make a weapon's reach depend on its model, and a player with the view model off would shoot from somewhere else.

## Orientation, and the three ways it goes wrong

`ZeeWeaponArt.model_forward` states which way a mesh points and `orientation()` derives the rotation that fixes it. Never state both: they drift, and a weapon points backwards in the world and forwards on the screen.

The blasters point along **-Z**, Godot's own forward, so their orientation is the identity. The melee models and the grenades point along **+Y**, standing on their handle with the origin exactly where a hand grips them.

**For as long as the pack existed the table said +Z, and every blaster was drawn stock-first**, in first person and in a carrier's hands, with its tracers and flashes leaving the stock. Nothing caught it: seventeen of the eighteen meshes have bounds symmetric along their length, so the measured muzzle (the far end of the bounds along `model_forward`) sat at whichever end it was told to, and the rack's pips agreed with whatever the table said. Everything placed by eye on the reversed guns was consistent with the reversal, so the silencers sat on the stocks. The shotgun's two barrels at the near end of the contact sheet gave it away, and a side render of all eighteen in Blender with a marker on +Z settled it: the marker is on the stock of every one. `blaster-e` (the sniper then) was the one whose origin was not central: it was at the muzzle, the mesh running 1.39 m back along +Z. The sniper since 2026-10-19 is art-src/guns' kitbash, 1.30 m and centred like every other model, and carries no slide. **The rack proves a muzzle is at an end, not at the right end; settle an axis by rendering the model side-on with a marker on it.**

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

## Authored motion: the draw, the reload and the swing are keys, the reactions are springs

Sway, bob and kick are reactions, and a spring is the right model of a reaction. A draw and a reload are actions with a shape somebody chose, and a spring or one eased number can only ever produce "goes down and comes back". The reload this replaced was that: `reload_tip` pitched the barrel 32 degrees nose-up, which read as the gun flipping at the sky.

- **Keys** (`ZeeWeaponPose.DRAW_KEYS`, `RELOAD_KEYS_RIFLE` / `_PISTOL` / `_HEAVY`) are `[t, position m, rotation deg (pitch up, yaw muzzle-left, roll counter-clockwise)]`, read by `sample_keys` through a Catmull-Rom curve with span-scaled tangents and zero tangents at the ends: motion carries through a key instead of stopping on it (an ease per segment reads as a robot), and starts and ends at rest. Malformed keys or a NaN sample as rest.
- **A reload lifts the gun up and in, then rolls it onto its side** so the magazine well is on screen while the magazine drops (0.10-0.28), holds while the hand fetches the next (the support hand goes to the well, down out of frame and back, `_support_hand`), jolts up as it seats (0.55-0.60), comes back down and racks (0.84-0.90). At the hip the well is below the bottom of the screen, so the first keys (roll and dip in place) dropped every magazine and fetched every new one out of frame: a play test called the result "no proper reload animations". The magazine's own timing in `_animate_magazine` is cut to the same fractions; change one, change both.
- **The new magazine is in the hand**: from 0.36 it is drawn at the support hand (`_support_hand()` + 3.5 cm, put through the holder's inverse into model space) and seats at 0.58, where the hand's keys reach the well. A magazine that rose out of nothing under the gun while the hand was elsewhere read as the hand reaching for one already there. A `magazine_loose` art (a shell, a cartridge, a grenade, a rocket: zed-dot-weapons' guns, which have no separate magazine) shows only while carried in, and nothing drops.
- **A heavy gun's reload is the job it does, not the rifle's with less lift** (`ZeeWeaponPose.RELOAD_KEYS_HEAVY` / `_BOLT` / `_BREAK` / `_MUZZLE`, per weapon through `ZeeWeaponArt.reload_keys`). The first heavy keys lifted half as far as a rifle's and every heavy gun fed by hand carried a 5 cm dart drawn at the hold's half size inside a fist: the play test said the sniper, the launchers, the charge rifle and the machine gun "read as a tilt", and a 18-frame reload sheet (`--reloads`) showed it. Now: the sniper's bolt is drawn back, two rounds pressed down into the top, the bolt shoved home; the grenade launcher breaks (muzzle down) and takes a grenade from above; the second pack's rocket launcher is tipped up and a rocket pushed down the muzzle; the charge rifle drops a glowing cell and seats a new one; the minigun swaps an ammunition box with its belt. The box and the cell are **built in code** (`view/zee_reload_parts.gd`, `ZeeWeaponArt.magazine_part`), because a file in `assets/` is a copy in seven games before the first player sees it.
- **A round fed from somewhere in sight** (`load_from`, `load_count`, `bolt_at` / `bolt_pull`, `magazine_scale`): the support hand's keys are built once per weapon (`ZeeViewModel._build_feed_keys`): bolt back (0.12-0.20), each round fetched, carried to `seat + load_from` and pushed to the seat inside `FEED_START`-`FEED_END` (0.26-0.70), bolt home (0.75-0.82). **The round is drawn at the hand** (`FEED_CARRY`, above and to the right of the palm) for its whole trip, so the two never part; straight above the palm the glove hid it. The keys must be built after the fore-end is measured (`_reach_for`), or the hand starts at the camera: the first sheet had the arm reaching for the ceiling at 4%. A `magazine_scale` draws a round larger than its file: at 1.0 a real round at half size is a few pixels.
- **A pump gun is fed shells through the port underneath** (`ZeeWeaponArtTable._tube`, `RELOAD_KEYS_TUBE`): rolled well over so the underside is to the eye, three shells carried up and pushed in through `FEED_START`-`FEED_END`, then the pump worked. Loose (one dart carried once from below the screen) the whole reload showed a yellow fleck in one frame of eighteen.
- **A swing and a throw are keys too** (`SWING_KEYS`, `THROW_KEYS`, over `swing_seconds` / `throw_seconds` of presentation time, started by `ZeeWeaponPose.swing()` / `throw()` from `ZeeViewModel.on_used` on a `KIND_SWING` / `KIND_THROW` outcome, and `on_swing()` for a use with no outcome). A swing was the recoil spring alone and melee has no recoil, so the knife, the hatchet and the fists did nothing on screen when they struck. A bash is a swing as well. The "never jolts" check does not hold them: a cut is meant to be fast, like the kick.
- **Somebody else's swing and throw are keys on their world model** (`ZeeWorldModel.SWING_KEYS`, `THROW_KEYS`, started from `on_fired` by the replicated kind, so every game driving the counter gets them with no change). They are not the view model's keys: those are in the camera's frame at the view model's scale, while the world model hangs off a hand the person's slash overlay already moves, so its keys are the wrist's share only (cocked as the arm comes up, cut through as it comes down) in the hand's frame (-Z the way the person faces), about the grip. Before them, a watcher saw the knife ride the arm rigid and a grenade thrown from a hand that never moved. A throw also asks the person it hangs from (the nearest ancestor answering `swing` and `set_hold`, which dot-player-char's figure does) for the slash overlay, an overhand throw's path, because a thrown weapon is held with empty-handed arms and no game plays anything on a throw; the punch overlay was tried and punches with the other hand. The thrown weapon is hidden from `THROW_RELEASE` to `THROW_BACK`, because the projectile is the game's. Review on `tools/screenshot.sh --world`.
- **Every authored rotation turns about the grip** (`pivot`), like the kick: about the transform's origin it is about the camera, which swings the whole gun across the screen.
- **Per weapon**: `ZeeWeaponArt.draw_keys` / `reload_keys`; empty takes `DRAW_KEYS` and the pose's (`ZeeWeaponArtTable.reload_keys`). Melee and throwables have no reload keys. The view model hands the pose the raw reload fraction now; the keys shape it.
- **The holster plays the draw keys backwards**, because the rig hands a deploy fraction that falls.

**The suite checks for jolts, not speed** ("never jolts"): a draw and a reload at 144 fps while walking and turning, measuring the change in each frame's movement. A fast smooth motion changes speed a little a frame; a corner in a curve changes it at once. It found the bob's `|sin|`, a corner at every footfall (5 mm a frame at 144 fps); the bob is `sin²` now.

**The bob is a cadence at a run, not a distance** (2026-10-11): `bob_per_metre` drives the phase up to `bob_max_rate` cycles a second (1.5, three footfalls), and past that a faster carrier takes longer strides. Per metre alone, game-arena's 9 m/s run bobbed ten footfalls a second, 1.1 cm up and down: a weapon buzzing, 2.3 to 3.0 mm of change in a frame's movement at 144 fps where a walk's is a tenth of that (game-arena's `headless_feel`, p99 2.98 mm before, 0.19 after). The suite's "a 9 m/s run bobs at most three and a half footfalls a second" holds it.

**The sway lags the turn.** The controller's yaw is positive to the left, so a right turn is a negative rate, and the sway had the sign that made the gun lead the turn (the sheet's "turning right" frame); the suite now asserts the gun goes left on a right turn.

## Recoil

Each of these is its own line in `ZeeWeaponPose`:

- **Every kick number is a profile param.** `extra: params: view_kick_pitch|knee|yaw|roll|back|back_max|response|rate_ref|rate_max` and `view_camera_share` (`ZeeWeaponPose.Tunables.KICK_PARAMS`) override the rig-wide defaults per weapon, so a server tunes the feel in cfg; the builders write the defaults (`_gun`), the rig applies them on equip (`ZeeViewModel.set_kick_params`).

- **Weight does not scale the kick.** A behaviour's `recoil_pitch` already says how hard a weapon kicks; `ZeeWeaponArt.weight` slows the spring (by its square root) and scales sway and bob, and never touches the size of a kick. Scaling both counted the sniper's size twice (17 degrees and 13 cm back for one shot).
- **The range is compressed.** Recoil runs 0.12 to 4.0 across the pack, right for a camera climbing and wrong for a gun in a hand: `kick_degrees()` is `kick_pitch · r / (1 + r · kick_knee)`.
- **The gun turns about the grip, not the eye.** `Animated` sits at the camera, so a rotation there carries the whole weapon up the screen. `pivot` is the holder's rest origin, the grip, and the kick turns about that.
- **The yaw picks a side per shot** (`punch()`). Every behaviour hands over a positive `recoil_yaw`.

**The camera's half is the game's to apply**, through `rig.view_punch()` (30% of the climb). The view model is a child of the camera, and every controller in the family writes the camera's angles from scratch each frame, so anything the pack added there would be overwritten. dot-player-controller's `DotFpsView.external_angles` exists for it. It is never added to a command: the shot went where the command pointed.

## Aiming is presentation, and the game decides the button

`ZeeViewModel.aim(held)` eases the weapon from the hip to `ZeeWeaponArt.aim_offset` over `aim_time`, steadies sway and bob by `ZeeWeaponPose.aim_steadiness`, and reports `flash_scale()` (the muzzle flash is shrunk by the zoom while scoped, so the optics do not magnify it into a starburst), `aim_fov_scale()` (the art's `aim_zoom` at full aim) and `is_scoped()`. **It changes nothing the server simulates**: no command bit, no snapshot field. The half of aiming that is a rule (tighter spread, slower walk) is a game's, in its own command.

- The game applies the zoom to its camera (`DotFpsView.external_fov_scale`) and puts a `ZeeScopeOverlay` in its HUD for scoped weapons.
- Through a scope the view model hides the weapon **and the arms**: the arms are the view model's own child, so hiding the animated node alone leaves an arm across the scope.
- The scope overlay sets its offsets as well as its anchors, or it fills nothing.
- Melee and throwables have `aim_enabled` off; the sniper is x0.3 and the marksman x0.5, the bullpup and the charge rifle x0.6, all four scoped; everything else aims at x0.8 down an iron sight.
- Right mouse is the bash's button too; which one it is, is a game setting. The alt-fire is `BUTTON_ALT` in the command; the aim is a local hold.

## ADS rules: a profile the server owns

`ZeeAdsRules` (`content/zee_ads_rules.gd`) is a Resource: a default profile plus per-weapon overrides by weapon id. Keys: `enabled`, `aim_time`, `zoom` (FOV multiplier), `move_speed_multiplier`, `spread_multiplier`, `sway_multiplier`, `toggle`, `view_scale`, `view_shift_x/y/z`, `hip_cant` (0..1, shipped 0.3: how much of the art's hip roll is kept), `hip_lean` (degrees, shipped 25: how far the barrel is drawn off screen-up toward the middle), `thrown_span` (metres, shipped 0.31: the longest side a grenade is drawn at, so a small model and a large one both span 20-35% of the screen at the hip; the suite checks it); 0 for `aim_time` or `zoom` means the art table's value. `ZeeAdsRules.load_config()` layers the shipped `cfg/addons/zee_weapons/ads.yml` < `cfg/server/addons/zee_weapons/ads.yml` < env `ZEE_WEAPONS_ADS_...` < argv `--zee_weapons.ads...`. The game assigns it to `ZeeWeaponRig.ads_rules` (which hands it to the view model) and `ZeeViewModel.ads_rules`.

Server side the rig scales spread and bloom while the command holds `ads_button` (default `BUTTON_USER_0`), and `ads_move_scale()` gives the walk-speed multiplier the game applies to its motor. A disabled weapon cannot aim and is neither slowed nor tightened. `ZeeViewModel.aim_input(pressed)` honours hold versus toggle. `view_scale` and `view_shift_*` size the gun on screen per weapon (shipped: 2.0 and a shift right and down so the gun is drawn large in the lower right, the sniper 1.6, the sidearms 1.9 nearer the middle, the derringer 3.2, a palm-sized gun; `--ads-rules` on the range draws with them); the hands reach for grip points capped by the measured body span, so they stay on the gun at any scale.

**A barrel pointed straight ahead is drawn diagonally.** Held in the lower right, a forward barrel runs to the vanishing point in the screen's middle: from a hold at (x, y) its drawn lean off upright is atan(x/|y|), about 45-60 degrees, whatever the cant or field of view. `ZeeViewModel.hip_yaw` turns the muzzle out until it is drawn `hip_lean` degrees off upright; this applies with no rules assigned too (the art's own size, the default lean). Below about 15 degrees the gun is seen end-on, from behind. `tools/view_check.tscn` prints each weapon's drawn lean, cant and width, and the selftest's `view on screen` holds them (lean 10-35, cant at most 12, width at least 18%).

## Aiming down the sight is a line measured on the gun

**The picture is a sight on the crosshair with the gun's top running away below it.** Aim was one written place for every blaster (`aim_offset` 0 / -0.135 / -0.46, straight): the eye level with the middle of the gun's back, so the screen showed the pale rear face of the gun as a block under the crosshair. No single place can be right for eighteen shapes, and no blaster in the kit has a readable iron sight (they are toys: fins and drums).

So `view/zee_iron_sight.gd` measures and builds one per gun at equip, for every weapon with `aim_enabled`, `iron_sight` and not `aim_scoped`:

- **Measured by casting straight down onto the mesh** at two stations along the barrel, 35% from the back (behind the grip) and 88% (short of a brake), on the centre line, or a little either side when the middle is a gap (the flamethrower's tank and barrel). Not from the bounds, whose top is a fin or a drum somewhere else, and not from a slice of vertices, which on these long low-poly faces is often empty. The line's height clears the highest top between the stations.
- **Built from boxes in the gun's own colours**: each vertex carries the UV of the face the part stands on, with that face's material, so a sight is the colour of the metal under it and lit like it. A ring of sixteen segments round a post at the front, its centre on the line; a notch at the rear.
- **The rear notch sits below the line.** The rear sight is about half the front's distance from the eye, so the same height there is twice the size on the screen: ears up to the line hid the bottom of the ring and filled the middle of the screen. Kept low, it reads as a rear sight under the front one, like the reference picture.
- **The ring is sized by angle** (`RING_DEGREES`, 4.8 degrees of radius at full aim), from the eye relief and the distance between the sights. Sized by the gun's width, the second pack's slimmer real-sized guns drew a ring a third the size.
- **The hold is derived**: `origin = (0, 0, -relief) - B * rear`, with `B` the orientation scaled and no aim rotation (the line is the rotation). `relief` is `aim_eye_relief` (0.2 m), pushed out until the gun's back end is in front of the near plane plus `NEAR_MARGIN` for the kick. `aim_offset` / `aim_rotation` are the fallback when nothing could be measured, and a scoped weapon's hold.
- **The kick at the sight turns about the rear sight, not the grip, and at 40% of the hip's turn** (`ZeeWeaponPose.aim_kick_steadiness`). About the grip at full strength, the whole sight picture jumped a ring's width up the screen on every shot; now the front sight climbs under a degree and settles back on the crosshair.
- **A model with real sights marks them, and nothing is built** (`IronSight.from_marks`): nodes named `sight_rear` and `sight_front` (`MARK_REAR`, `MARK_FRONT`), placed on the top of the rear aperture and the tip of the front post, are the line, and the hold is derived from it the same way. No ring or notch is added: drawn over a modelled post and aperture they made a second sight in front of the first (zed-dot-weapons' high-detail carbine was the first such model). The measured cast stays the fallback for a model without the marks.
- **A gun carrying a scope attachment is scoped.** An iron sight's line on the bullpup and the charge rifle ran into the back of their scopes.
- The suite checks that each unscoped gun's two sight points are on the view axis at full aim, the front further out, and that a kick moves the front sight under three degrees and settles back (`ZeeViewModel.sight_points()`); zed-dot-weapons checks its own guns the same way.

## The hands have a lens of their own

**The hands are drawn at `ZeeViewModel.hands_fov` (90 degrees) whatever the game's camera.** Every pose was set under the range's 90-degree camera, and games hold them under 83 to 100, which drew a smaller gun drifting to the middle, or a bigger one, and magnified the gun with the world on an aim zoom. The view model's X and Y are scaled by `tan(camera/2) / tan(hands/2)` (`lens_scale`) in the camera's space with Z left alone, which is exactly a perspective projection at the other lens: depth is untouched, so sorting and the muzzle a tracer starts from are unchanged. Applied only when the view model's parent is a `Camera3D`; anywhere else the same scale would be a distortion.

## Where the weapon is held

**Hip poses sit low and right** (`ZeeWeaponArtTable.pose_offset`). A rifle 12 cm right and 16 down at 48 cm out sat almost on the crosshair with its top toward the eye.

**And canted and turned** (`pose_rotation`: yaw +10 brings the muzzle in, roll -30 tilts the right side up; pistols and heavies a little less). A weapon below and right of the eye pointing where the eye points shows the camera its back face and a sliver of its left side, which is what this pack drew: a stub in the corner of the screen, beside a production shooter's rifle lying large across the lower right with its right side and top showing. Perspective already carries a straight barrel toward the centre; at this distance the right side does not face the eye at all until the cant is about thirty degrees (the face normal against the direction back to the camera). The rifle is at 0.6 scale and 0.40 m out, so its length runs from the bottom-right corner to just short of the crosshair.

- **Rotations are in the model's own space**, which for a blaster is the view's: positive yaw is muzzle-in and positive roll is right-side-up. A sign written by intuition is the wrong one about half the time; render it.
- **A correction along a weapon's length goes through the hold's basis**, not along the camera's Z (the sniper's pull-back): once the hold is turned, the camera's Z is no longer the weapon's.
- **The aim hold is a transform of its own** (the measured sight hold, [below](#aiming-down-the-sight-is-a-line-measured-on-the-gun); `aim_offset` plus `aim_rotation`, zero, where there is none), reached through the view model's `Aim` node by a slerp of the rotation and a lerp of the position. Moving only the position, as the pose's `aim_shift` did, brought the canted gun to the middle end-on and crooked; interpolating the bases component-wise shrinks the gun half way.
- **The arms are not under `Aim`.** Carried rigidly to the sight, the shoulders went with the gun and the left arm lay across the screen. They are under `Animated` (so a kick, a reload and a draw carry them) and reach every frame for the grip and fore-end put through the `Aim` transform.
- **The hands' places are the art's** (`fore_along`/`fore_up` for the support hand, `grip_along`/`grip_up` for the firing hand, fractions of the bounds; defaults 0.62/0.45 and 0.30/0.30). The sniper's trigger is 40% from its back and its scope inflates the bounds' height, so it sets 0.40/0.28 and 0.66/0.28: at the defaults the firing hand held the air behind the wrist and the support hand floated over the fore-end.
- `--hold "x,y,z,pitch,yaw,roll,scale"` on the range's `--sheet` re-equips with that hold, for tuning without an edit per guess.

## The arms

**Gloved hands are the fallback; the rigged arm is the default** (`RIGGED_SCALE` 1.0, `ZeeRiggedArm.FINGER_THICKNESS` 0.011 after the 2026-10-20 pass: at 0.8 and 0.009 the hands read small against the gun; forearm scaled 1.3 (`ZeeRiggedArm.FOREARM_SCALE`, uniform with a counter-scale on the hand) and an empty fist closes at `FIST_RADIUS` 0.004 so every joint folds to its limit; a missing `arms-rigged.glb` gives the gloves and one WARN per view model). Gloved hands, as before: (`ZeeViewArms.style = &"gloves"`). The character kit's arms are a box each with no hand on the end, and beside a production shooter's they read as two pale slabs reaching for the gun (and with the knife, two planks with the blade floating between them). A glove is a dozen boxes merged into one mesh in code: a ring of finger segments and a thumb closed round a cylinder of `GRIP_RADIUS` along its +Y, the back of the hand +X, the forearm leaving +Z. A six-sided sleeve and a cuff are stretched from the heel of the palm to the shoulder. `glove_color` and `sleeve_color` are a game's to set; `style = &"model"` keeps the old lifted arms.

- **The view model hands each hand the axis of what it holds** (`reach(grip, fore, pose, grip_axis, fore_axis, grip_radius)`): a blaster's raked pistol grip and its barrel for the fore-end, a melee weapon's handle, a grenade's long axis. A game's own arms with the old three-argument `reach` still work (`get_method_argument_count`).
- **The hands are measured in the model's own space**, not the view's: the hold is canted, so a view-space "under the middle" of a canted gun's box is beside the gun.
- **The left hand is the right one mirrored**: its basis has a negative determinant, which the renderer draws with its faces flipped.
- **A glove is sized to its grip within 0.6 to 1.2** (`grip_radius / GRIP_RADIUS`). Sized to the real radius it was a giant's hand: the weapons are drawn at half size (`pose_scale`), the hands are not.
- **The wrist bends at the heel of the palm.** The cuff runs from the heel toward the real shoulder; carried out along the hand's own square-on axis it put a box out sideways under a knife held blade-up.
- **Bare fists and grenades are held with the forearm square to the fist** (the shoulder is found from the hand); a knife is not, since a blade-up knife held square throws the forearm across the screen.
- **An empty fist has a core** inside the finger ring, or the camera looks through the hole.

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
| Blaster axis | every one points **-Z**; the side render with a +Z marker is the proof, not the rack |
| Sniper | art-src/guns' kitbash, 1.30 m long and centred (z -0.65 to +0.65) like every model, so the hold needs no slide: the trigger is at about z +0.13, as on the marksman. Receiver z +0.19 to -0.07, top at y 0.055; bolt knob (0.047, 0.028, -0.016). It carries its own scope. The Blaster Kit's `blaster-e`, which it replaced, had its origin at the muzzle and was slid 0.8 m forward |
| Hip holds | rifle 0.19 / -0.23 / -0.40 at 0.60, yaw 10 roll 30; heavy 0.19 / -0.24 / -0.42 at 0.55, yaw 10 roll 26; pistol 0.15 / -0.19 / -0.36 at 0.55, yaw 8 roll 22; melee 0.22 / -0.25 / -0.40 at 1.2, (70, 80, 40); aim fallback 0 / -0.135 / -0.46 straight (the measured sight hold replaces it) |
| Silencers | origin at their back end, body running -Z, centred on it: the origin goes on the barrel's end at the bore's height (`blaster-f`: z -0.52, y 0.052, not its bounds' end, which is a brake; `blaster-c`: z -0.238, y 0.017), and the art's `muzzle_distance` / `muzzle_offset` move the effects' muzzle to the silencer's far end (0.283 m and 0.244 m long) |
| Blocky character | 2.7 m tall, 1.6 m wide: a stylised giant, not a person |
| One arm | a 0.4 × 1.1 × 0.4 box, pivot at the shoulder, mesh hanging to `y = -1` |
| Melee tools | 0.15 m to 0.35 m tall, origin at the butt of the handle, pointing +Y |
| Target discs | modelled in the YZ plane, 0.34 m across: they need turning and scaling |

## Motion with the carrier, and the server's cvars (2026-10-15)

The view model reacts to look (lag and roll), strafing (a trail and a lean against the move), walking (bob) and a landing (a dip). **Every amount is a multiplier a server owner sets** through `ZeeViewFeel` (`rig.feel_rules()`): `mp_vm_sway`, `mp_vm_strafe_tilt`, `mp_vm_bob`, `mp_vm_landing` (0 off, 1 the pack's own amount, up to 3) and `mp_vm_aim_steadiness` (0 to 1, default 0.75). A game binds them with `rig.feel_rules().bind_cvars(add_cvar, flags)` on the server and `follow_cvars(link)` on the client, the same shape as `mp_forceview`. Read every frame, so a change applies at once.

Strafe speed is handed to `drive_view(..., strafe)` (metres a second, positive right) or, left out, measured from how the view model's node moved (a teleport over 30 m/s is no strafe).

**Aimed, the gun drifted sideways** (arena, 2026-10-15): aim steadied the sway and bob to a quarter but left the roll whole, and a quarter of the look lag and the bob's sideways swing is centimetres at a half metre's range, so the body of the gun swung left and right of a sight that was meant to stay on the crosshair. Sideways motion and roll are now held to a twentieth aimed (`steady_x` in `ZeeWeaponPose.offset`). Review on `EXTRA="--moves" tools/screenshot.sh --sheet rifle`: hip and aimed, strafing, turning, walking, landing.


## Sprint carry and grips

Sprinting lowers the weapon on its own layer, separate from the aim layer: `ZeeViewModel.set_sprinting` eases `sprint_fraction` over `SPRINT_SECONDS`, and `ZeeWeaponPose.offset()` adds the art's `sprint_offset` and `sprint_rotation` (barrel left and down). In the third person `ZeeWorldModel` reads the figure's `sprint_blend` and yaws the barrel left (`sprint_world_offset`, `sprint_world_rotation`). Both default per pose class in `ZeeWeaponArtTable`; a profile overrides them, `hands` (1 or 2) and `support_grip` through `extra: art:`, applied by `ZeeWeaponArt.with_overrides(row)`. A two-handed weapon sends its foregrip to the figure (`set_support_grip`), which reaches the off hand there with two-bone IK. With `sv_sprint_barrel` on (the controller's, default 1) the rig also turns a sprinting shot's direction by that same `sprint_rotation` at full blend (`ZeeWeaponRig._aim_along_sprint_barrel`); the origin stays the eye, so reach never depends on the model. The first-person sprint pose has not been looked at in a rendered frame.
