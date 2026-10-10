# What a shot looks and sounds like

`ZeeShotFx` is a tracer, a flash with a light, a spark and a puff on what was hit, and a report from `ZeeWeaponSound`. Never built on a server, never played on a replayed tick.

## Decisions, each the obvious alternative being wrong

- **The tracer ends where a presentation raycast from the eye says**, not where the server's hit registration did. A client does not know what lag-compensated hitboxes decided and must not wait to be told. It is traced from the eye (where the shot really started) and drawn from the muzzle (where the picture should leave).
- **Tracers and impacts are sized by distance from the camera.** A tracer is seen almost end-on, and 2 cm at 30 m is one pixel (a sniper shot drew as a yellow fleck).
- **Billboards need a texture and `billboard_keep_scale`.** A quad with no texture is a square of light, and a billboard ignores its node's scale without the flag (the first flash was a pale square a tenth of the screen across).
- **A world model whose carrier has a first-person rig with effects stays quiet** (`_carrier_draws_its_own`). A game that drives every player's world model from the replicated counter, its own player's included, would otherwise hear every one of its own shots twice.
- `ZeeViewModel.model_ready` is where a game could hang its own flash, but a game should not need to: the pack draws the shot.

## Sounds are baked

There is no CC0 set of twenty-seven matched weapon reports to vendor. dot-audio's synthesiser is right for a placeholder of anything and wrong for twenty-seven weapons that should be told apart, so `ZeeWeaponSound` layers a band-passed crack, a swept body and a low-passed tail per class, deterministically, so the suite can assert about the bytes. `set_stream(id_or_class, stream)` puts a recording in front of it one weapon at a time. A second pack adds classes with `set_class` ([design](design.md#a-second-pack-adds-to-this-one)).

**A reload is heard**: `ZeeWeaponSound.RELOAD_OUT` when the arsenal starts one and `RELOAD_IN` when it finishes, played at the carrier through `ZeeShotFx.play_reload` and announced as `ZeeWeaponRig.reload_sound`. Same rule as a report: never on a server, never on a replayed tick.

## Seeing a shot on a machine with no hands

`zee_range -- --weapon smg --fire --capture <prefix>` pulls the trigger itself and saves six frames counted from the first shot, with the clock slowed twenty times, so that a software renderer's tenth-of-a-second frames are a flip-book of one shot rather than a picture of the reload after it.
