# Y2ROLL Mod Setup Guide

Install mods for Y2ROLL using Godot Mod Loader v6.3.0.

## Prerequisites

- [Y2ROLL (Steam)](https://store.steampowered.com/app/3459420/)
- [This repository cloned or downloaded to a local folder](https://github.com/josephwhite/Y2ROLL-mods).
- Godot Mod Loader v6.3.0 - `godot-mod-loader_v6.3.0_self-setup.zip` from the [GitHub release](https://github.com/GodotModding/godot-mod-loader/releases/tag/v6.3.0)
- Python 3.6+

## Installation

### Step 1: Extract the GML Source

The mod loader needs its `.gd` source files injected into the game's PCK. Godot 3 export builds cannot load scripts from the filesystem at runtime.

1. Extract the `addons` folder from the Godot Mod Loader next to the Y2ROLL executable[^1].

2. Note the full path to the `addons/` folder. You will need it in Step 2.

### Step 2: Patch the Game

Open a terminal in this project's root and run:
```
python patch_pck.py --pck "<path_to_Y2ROLL.pck>" --modloader-dir "<path_to_addons>" --game-dir "<path_to_game>" --mod-dir "<path_to_mod_folder>" --mod-dir "<path_to_mod_folder_2>"
```

Pass `--mod-dir` once per mod to install. All three mods must be specified:

#### Example

Windows:
```
python patch_pck.py --pck "C:\SteamLibrary\steamapps\common\Y2ROLL\Y2ROLL.pck" --modloader-dir "C:\SteamLibrary\steamapps\common\Y2ROLL\addons" --game-dir "C:\SteamLibrary\steamapps\common\Y2ROLL" --mod-dir "C:\repos\Y2ROLL_AP\josephwhite-ArchipelagoRandomizer" --mod-dir "C:\repos\Y2ROLL_AP\josephwhite-mod_manager" --mod-dir "C:\repos\Y2ROLL_AP\josephwhite-player_skins"
```

Linux:
```
python patch_pck.py --pck "~/SteamLibrary/steamapps/common/Y2ROLL/Y2ROLL.pck" --modloader-dir "~/SteamLibrary/steamapps/common/Y2ROLL/addons" --game-dir "~/SteamLibrary/steamapps/common/Y2ROLL" --mod-dir "~/Y2ROLL_AP/josephwhite-ArchipelagoRandomizer" --mod-dir "~/Y2ROLL_AP/josephwhite-mod_manager" --mod-dir "~/Y2ROLL_AP/josephwhite-player_skins"
```


#### Arguments

| Argument | What to point it at |
|---|---|
| `--pck` | `Y2ROLL.pck` inside your game install directory |
| `--modloader-dir` | The `addons/` folder from the extracted GML zip. Defaults to the game's `addons/` dir (if GML self-setup was already run) |
| `--game-dir` | Your Y2ROLL install directory (where `Y2ROLL.exe` lives) |
| `--mod-dir` | Path to a mod folder. Pass multiple times for multiple mods. |

#### What it does

1. Backs up `Y2ROLL.pck` to `Y2ROLL.pck.bak` (first run only)
2. Registers missing script classes in the game's `project.binary` (24 GML classes + 36 embedded GodotAP classes)
3. Adds `ModLoaderStore` + `ModLoader` autoload entries so the mod loader starts automatically
4. Injects all mod loader `.gd` source files into the PCK
5. Injects all mod files into the PCK
6. Rebuilds and verifies the PCK

#### Restoring the original PCK

```
python patch_pck.py --restore --pck "<path_to_Y2ROLL.pck>"
```

### Step 3: Verify

Launch Y2ROLL normally, then open the mod loader log:

|**OS**|**Path**|
|-|-|
|Windows|`%APPDATA%\Godot\app_userdata\Y2ROLL\logs\modloader.log`|
|Linux|`~/.local/share/godot/app_userdata/Y2ROLL/logs/modloader.log`|

Look for these two lines:

```
SUCCESS ModLoader:Loader: DONE: Completely finished loading mods
SUCCESS ModLoader:Loader: DONE: Installed all script extensions
```

If both appear, the mods are working. 

You should see a **Mod Manager** entry in the Options menu — open it to see a toggle for each installed mod.

[^1]: Technically, you can extract the addons folder anywhere on your machine like `C:\GML` on Windows or `/home/<user>/GML` on Linux. This guide recommends extracting next to game's executable for simplicity and following GML's [self setup conventions](https://wiki.godotmodding.com/guides/integration/mod_loader_self_setup/).

## Updating

After any change to mod files, restore the original PCK then re-patch:

```
python patch_pck.py --restore --pck "<path_to_Y2ROLL.pck>"
python patch_pck.py --pck "<path_to_Y2ROLL.pck>" --modloader-dir "<path_to_addons>" --game-dir "<path_to_game>" --mod-dir "<mod_1>" --mod-dir "<mod_2>" --mod-dir "<mod_3>"
```

## Mod Configuration

Configure mods in-game via the mod manager (Options → Mod Manager → Info), or edit the JSON file directly.

Config values are saved to `settings.json` (not the GML-managed `default.json`, which has a regeneration bug). 

`user://` maps to the game's Godot app data dir:
|OS|Path|
|-|-|
|Windows|`%APPDATA%\Godot\app_userdata\Y2ROLL\configs\<mod_id>\settings.json`|
|Linux|`~/.local/share/godot/app_userdata/Y2ROLL/configs/<mod_id>/settings.json`|
---

## Troubleshooting

**Mod not loading / `manifest_id` is `"-"`** — Re-run the patch. The PCK is a snapshot of your files at patch time.

**`not enough arguments for format string`** — Your `manifest.json` may have malformed fields. Verify it's valid JSON with all required keys.

**Missing `SUCCESS` lines in log** — The patch didn't work. Restore, re-patch, and check `patch_pck.py` output for errors.

**`Parse Error: Unexpected EOL at String`** — A stray quote character in a GDScript file. Open the file referenced in the error and fix the line.

**Config values reset to defaults** — These mods bypass the GML config system and read/write `user://configs/<mod_id>/settings.json` directly. If values reset, the file is missing or malformed — check `%APPDATA%\Godot\app_userdata\Y2ROLL\configs\` (Windows) or `~/.local/share/godot/app_userdata/Y2ROLL/configs/` (Linux) and re-save from the mod manager. On first launch, mods fall back to schema defaults (player_skins reads the manifest config_schema).
