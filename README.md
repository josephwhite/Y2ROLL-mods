# Y2ROLL Mods

Mods for [Y2ROLL](https://store.steampowered.com/app/3459420/).

[Setup instructions](./docs/SETUP.md)

Individual mod folders:
- [josephwhite-ArchipelagoRandomizer](josephwhite-ArchipelagoRandomizer/)
- [josephwhite-player_skin](josephwhite-player_skins/)
- [josephwhite-mod_manager](josephwhite-mod_manager/)

## FAQ

*Q: Was AI used in the development of these mods?*

A: [Yes](docs\AI%20Disclosure.md).

*Q: Why does `patch_pck.py` exist?*

A: Y2ROLL's Godot export only loads files from its PCK file, never the loose game folder, so mods must be injected into the PCK directly.
GML's normal self-setup can't run properly because Y2ROLL ignores `override.cfg` (autoload/registration path).
So `patch_pck.py` does GML's registration job off-game: patches project.binary and copies mod files into the PCK.
This lets GML boot and load everything normally.

TL;DR, it's a workaround specific for Y2ROLL.
