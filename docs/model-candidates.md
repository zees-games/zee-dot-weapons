# Model candidates for distinct silhouettes

Researched 2026-10-15 for nightly item fgr-weapons-unique-1. Nothing here is downloaded or vendored yet.

**Used, 2026-10-19:** the twelve real-world guns are kitbashes built by `art-src/guns/` from Quaternius Ultimate Low Poly Guns (CC0) and Kenney Blaster Kit (CC0) parts, recoloured and reshaped with parts of our own; `assets/low-poly-guns/LICENSE.txt` lists the parts per gun. The other candidates below were not used.

## Current models

Every zee weapon already points at a different Kenney Blaster Kit file (CC0), so no two share a file. The "shared SMG look" is stylistic: the Blaster Kit is one toy-blaster family with the same boxy body, stock and magazine. Melee uses Kenney Survival Kit tools and knives. Grenades use Blaster Kit grenade-a and grenade-b.

Sidearms: Dart Pistol blaster-k, Revolver blaster-o, Machine Pistol blaster-c, Derringer blaster-b. Primary: SMG blaster-i, Carbine blaster-m, Assault Rifle blaster-q, Bullpup blaster-r, Battle Rifle blaster-g, Burst Rifle blaster-n, Shotgun blaster-j, Drum Shotgun blaster-l, Marksman Rifle blaster-p. Heavy: Sniper blaster-e, Minigun blaster-f, Launcher blaster-a, Beamer blaster-h, Charge Rifle blaster-d.

zed-dot-weapons uses Kenney Weapon Pack (CC0) files, all different: pistol, pistolSilencer, uzi, uziLongSilencer (Tactical SMG, same body as uzi plus a silencer), shotgun, shotgunShort, sniperSand, machinegun, machinegunLauncher, rocketlauncherModern, flamethrower_long, grenadeVintage. The closest pairs are uzi and Tactical SMG, and pistol and Silenced Pistol.

## Candidate sources (all CC0)

| Source | Author | Licence | Format | Size | URL |
| --- | --- | --- | --- | --- | --- |
| Ultimate Low Poly Guns (40 models: pistols, SMGs, rifles, shotguns, snipers) | Quaternius | CC0 | FBX, OBJ, Blend (no glTF; convert) | 7.4 MB | https://opengameart.org/content/low-poly-guns-pack and https://quaternius.itch.io/50-lowpoly-guns |
| CC0 Flat Guns West (10 rigged US/European style guns) | Pichuliru | CC0 | GLB, FBX, OBJ, Blend | 1.9 MB | https://opengameart.org/content/cc0-flat-guns-west |
| CC0 Flat Guns East (10 rigged Russian style guns) | Pichuliru | CC0 | GLB, FBX, OBJ, Blend | 1.5 MB | https://opengameart.org/node/137087 |
| Oldschool AFPS Weapons (9: pistol, shotgun, sniper, rocket launcher) | Drummyfish | CC0 per listing, verify | textured, low poly | small | https://opengameart.org/content/oldschool-afps-weapons |
| 3D Weapons Pack (7 guns, 3 bullets, untextured) | mehrasaur | CC0 | OBJ, Blend | small | https://opengameart.org/content/3d-weapons-pack |

Rejected: Zsky "Guns Pack" (CC-BY 4.0 only), rgsdev Weapons Pack Low Poly (no redistribution), paid Fab and BuiltByBit packs.

## Suggested mapping (by type; individual model names inside the packs were not listed on the pages and are unverified until the zips are opened)

| Weapon | Best candidate |
| --- | --- |
| SMG, Machine Pistol | Quaternius SMG models (compact, folding or short stock), or Flat Guns West SMG |
| Carbine, Assault Rifle, Battle Rifle, Burst Rifle | Quaternius rifle models plus Flat Guns East assault rifles (long, curved magazine), so each gets a different stock and magazine shape |
| Bullpup | Quaternius or Flat Guns bullpup type, if present |
| Shotgun, Drum Shotgun | Quaternius pump shotgun, Flat Guns West shotgun (drum: nothing confirmed) |
| Marksman Rifle, Sniper | Quaternius sniper and AWP-type models, Drummyfish sniper |
| Revolver, Derringer, Dart Pistol | Quaternius pistols and revolver, Drummyfish pistol |
| Launcher | Drummyfish rocket launcher, Kenney Weapon Pack rocketlauncherModern |

## No good match found

Minigun, Beamer, Charge Rifle (sci-fi), Drum Shotgun, Derringer, Dart Pistol (toy look). Keep the Kenney Blaster Kit models for these; they suit the sci-fi weapons. Next step: download the Quaternius and Pichuliru zips into ~/Downloads/research/weapons/, open them to name each model, then finalise this table.
