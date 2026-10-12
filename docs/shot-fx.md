# What a shot looks and sounds like

`ZeeShotFx` is a tracer, a flash with a light, a spark, a puff and a mark on a wall, a red burst on a body, and a report from `ZeeWeaponSound`. Never built on a server, never played on a replayed tick.

## Decisions, each the obvious alternative being wrong

- **The tracer ends where a presentation raycast from the eye says**, not where the server's hit registration did. A client does not know what lag-compensated hitboxes decided and must not wait to be told. It is traced from the eye (where the shot really started) and drawn from the muzzle (where the picture should leave).
- **Tracers and impacts are sized by distance from the camera.** A tracer is seen almost end-on, and 2 cm at 30 m is one pixel (a sniper shot drew as a yellow fleck).
- **Billboards need a texture and `billboard_keep_scale`.** A quad with no texture is a square of light, and a billboard ignores its node's scale without the flag (the first flash was a pale square a tenth of the screen across).
- **A world model whose carrier has a first-person rig with effects stays quiet** (`_carrier_draws_its_own`). A game that drives every player's world model from the replicated counter, its own player's included, would otherwise hear every one of its own shots twice.
- **The flash is a hot disc and two crossed petals along the barrel** (12 cm across at the muzzle, drawn over the gun). The 7 cm disc alone was a play test's "almost no muzzle flash": a white dot lost against a pale barrel, the light on the floor doing more than the flash.
- **A wall gets a spark, a dark dust puff and a mark; a body gets a red burst and a mist, and no mark** (`impact_kind`: a `CharacterBody3D`, a `PhysicalBone3D` or a node in `ZeeShotFx.BODY_GROUP` is a body; `NOT_BODY_GROUP` opts a character out, for a game where the impact must not give a disguised player away). The pale grey puff on a grey wall was invisible on every frame of the contact sheet once the spark was gone, and every impact sized for six metres was ten pixels at seventeen.
- **A mark only goes on what never moves** (`takes_marks`: a static body, CSG, a grid map), because it is placed in world space and would hang in the air where a crate used to be. Marks have their own budget (`MAX_MARKS` 32, `MARK_LIFE` 8 s, fading over the last quarter), so a held minigun cannot evict its own tracers with them.
- **A body the client's physics cannot see is drawn from the server's confirmation**: `play_body_hit(point, direction)`, called by a game from the same confirmed hit that flashes `DotHitMarker`. A horde drawn as figures and hit through the server's hitboxes is never met by the presentation ray, which draws a world impact behind it. A body the ray already drew within a fifth of a second and half a metre is not drawn again.
- `ZeeViewModel.model_ready` is where a game could hang its own flash, but a game should not need to: the pack draws the shot.

## Sounds are baked

There is no CC0 set of twenty-seven matched weapon reports to vendor. dot-audio's synthesiser is right for a placeholder of anything and wrong for twenty-seven weapons that should be told apart, so `ZeeWeaponSound` layers a band-passed crack, a swept body and a low-passed tail per class, deterministically, so the suite can assert about the bytes. `set_stream(id_or_class, stream)` puts a recording in front of it one weapon at a time. A second pack adds classes with `set_class` ([design](design.md#a-second-pack-adds-to-this-one)).

**A reload is heard**: `ZeeWeaponSound.RELOAD_OUT` when the arsenal starts one and `RELOAD_IN` when it finishes, played at the carrier through `ZeeShotFx.play_reload` and announced as `ZeeWeaponRig.reload_sound`. Same rule as a report: never on a server, never on a replayed tick.

## Seeing a shot on a machine with no hands

The contact sheet's fire frames (`tools/screenshot.sh --sheet`) pull the trigger through the rig and step `ZeeShotFx.advance` with the view model, so they show the flash (fire 1, 2), the tracer and the impact (fire 4-14); `EXTRA="--dummy"` stands a character in the line of fire to see a hit on a body. `zee_range -- --weapon smg --fire --capture <prefix>` pulls the trigger itself and saves six frames counted from the first shot, with the clock slowed twenty times, so that a software renderer's tenth-of-a-second frames are a flip-book of one shot rather than a picture of the reload after it.
