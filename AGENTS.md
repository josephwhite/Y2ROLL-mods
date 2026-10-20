# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## Sections
- [`josephwhite-ArchipelagoRandomizer`](#josephwhite-ArchipelagoRandomizer): Archipelago Multiworld Randomizer integration
- [`josephwhite-mod_manager`](#josephwhite-mod_manager): GUI mod and config manager in Options menu
- [`josephwhite-player_skins`](#josephwhite-player_skins): Custom marble color/texture

## Code Style
Follow Godot's GDScript style guide for all GDScript code (pin the Godot 3.6 docs, not 4.x).

## Build & Verify

```ps1
# Install mods (2 mod directories specified)
python patch_pck.py --pck "<path-to-y2roll.pck>" --modloader-dir "<path-to-gml-addons>" --mod-dir "<path-to-mod-dir>" --mod-dir "<path-to-another-mod-dir>"
# Restore Y2ROLL 
python patch_pck.py --restore --pck "<path-to-y2roll.pck>"
```

Verify after launch.
- Clean log = no `SCRIPT ERROR` lines.
- `DONE: Loaded all meta data`.

 Direct `Start-Process y2roll.exe` stalls. Launch via Steam.

Log locations (`user://` = Godot app data dir):
- Windows: `%APPDATA%\Godot\app_userdata\Y2ROLL\logs\godot.log`
- Linux: `~/.local/share/godot/app_userdata/Y2ROLL/logs/godot.log`

## Tools

- `pwsh`
- [`pre-commit`](pre-commit-config.yaml)

### Commands
#### pre-commit
```bash
# Setup pre-commit
pip install pre-commit
pre-commit install
pre-commit install-hooks # pre-build the gdtoolkit 3.6.0 env

# Run pre-commit
pre-commit run
```
#### Packaging mods to zip
```ps1
.\build.ps1
```
## Critical Constraints

- Godot 3 export build never loads from the unpacked tree. All mod files must be injected into the PCK via `patch_pck.py`.
- **Config bypass** — GML config bugs (see BUGS.md) are bypassed by reading/writing `settings.json` directly via `File` API (`user://configs/<mod_id>/settings.json`). Keep config schemas flat (nested objects unsupported → dot-path naming).
- **ScrollContainer must have exactly one child** — switch views by reparenting, not `visible` (Godot 3 sizes scroll range from ALL children's min-size, no visibility check).
- **Compiled menus: reader-proof only** — runtime menus are `.gdc` bytecode. State like `options_menu.focused_menu_index` persists stale across in-session opens and has no `setget` — child setters, `Object.set()`, and shadow re-arms never intercept base internals (all proven dead). Fix reads, not writes. `.gdc` method overrides can silently never dispatch (`_set_submenu_menu_open` override, observed 2026-09-22) — prefer connecting a signal the game already emits: clamp `focused_menu_index` on `visibility_changed` (fires during `set_visible`, before the compiled nav walk). Never pad `%Buttons` with fabricated items — the compiled nav probes consecutive indexes and needs a real item with a `FOCUS_ALL` child per index (bare Controls → `Could not find valid focus target` + native crash). Overlay panels must grab focus on open (`focus_mode = ALL`) or Esc hits the menu behind them.

## josephwhite-ArchipelagoRandomizer

Archipelago integration mod for Y2ROLL.

### Architecture

**Entry point:** `mod_main.gd` connects to `tree.node_added` in `_ready()`, dispatches to handlers based on node type. Config read from `settings.json` via `_load_custom_config()` helper.

**GodotAP embed**:
- Vendored from [repo](https://github.com/josephwhite/GodotAP/commits/downpatch-3.6.0/)
    - Current commit pinned: `05da351`
- **Do NOT hand-patch the vendored `godot_ap/`** — it is a byte copy of upstream so future pulls apply cleanly. Re-sync from a real SHA and re-verify hashes on every pull.
    - No local edits here. Report bugs/feature asks to upstream or change vendor source.
- **Bootstrap** — `call_deferred("_bootstrap_ap")` adds an `archipelago.tscn` instance as a **direct root child** named `"Archipelago"` (mod nodes live under `ModLoader`, so `self.add_child` fails `Util._get_ap()`'s root lookup). Deferred because sync `root.add_child` in `_ready()` hits root's blocked state (node.cpp:1328) and silently drops the node. Logs `is_inside_tree()` success/failure.
- **casus gate**
    - `casus.DISABLE_BITWISE_OPERATIONS = true` at bootstrap. **Required — without it the three stock bit-op fallbacks in `util.gd` crash the custom build.**
- **ECFG registration** — `patch_pck.py` registers GML + GodotAP global `class_name`s in `project.binary`. If AP is absent, stale AP registrations AND stale AP mod files from an earlier patch are stripped. No collisions with the game's classes.
- **Injection exclusions** — `patch_pck.py` `is_mod_file_excluded()` skips `.import`/`.imported`, `godot_ap/ui/themes/`, `godot_ap/ui/refresh*.png`, `.git`/`.import` dirs (raw PNGs/themes not runtime-loadable in the PCK).
- **Boot smoke test** — AP `_ready()` calls `_create_socket()` → `WebSocketClient.new()`. Clean boot log = module present; a `SCRIPT ERROR` on that line = WebSocketClient missing from export (hard blocker for networking). Expected TLS `-29184` ERR_PRINT only on live connect (wss→ws fallback, normal).

**Connect menu** (`menus/ap_connect_menu.tscn` + `.gd`, injected by `_inject_ap_button`):
- Button-triggered — `AP` Button appended to CampaignMenu `Items/BottomBar` (`focus_mode = FOCUS_NONE`; click-only v1). Panel instanced as last child of CampaignMenu; duplicate guarded via `has_node("APConnectPanel")`.
- **CampaignMenu focus model** — single-Control focus UI (`set_is_menu_open()` → `self.grab_focus()`). Panel root must set `focus_mode = ALL` + grab focus on open, else Esc closes the campaign menu behind the overlay. `hide` → parent `grab_focus()`; `visibility_changed` auto-hides panel. Esc while a LineEdit has focus: first Esc releases it, second closes.
- Views — disconnected: 4 fields + Connect/Disconnect/Back, status from `connect_step`, errors from `connectionrefused`. Connected (button reads `AP✓`): fields hidden, Disconnect enabled.
- All LineEdits `text_entered` → `_on_connect_pressed`. Disconnected idle StatusLabel shows "Enter server details, then press CONNECT." hint.

### Key facts

**Background Viewport** is named `BackgroundContainer` (ViewportContainer) and `BackgroundViewport` (Viewport, unique_name). Background scenes loaded via `BackgroundHelper.get_scene_path(theme)`.

- **Moon nodes** exist in 3 backgrounds:
    - `purple_mountains.tscn` (MoonOrigin/Moon)
    - `night_city.tscn` (MoonOrigin/Moon)
    - `starry_space.tscn` (direct child)

**Floor materials** — use `n64_lit.shader` with `checker_marble.webp` albedo. Shader has `uv_pan_velocity` uniform in `vertex()`. `BackgroundHelper.override_level_geometry_materials_for_theme()` swaps materials per theme.

**SpatialMaterial** does NOT support `set_shader_param()`. Use `.albedo_color` directly.

**KillPlane** — `player_fell_out` signal available. Hook it when detected in `_on_node_added`.

### Config

Config read from `user://configs/josephwhite-ArchipelagoRandomizer/settings.json` (bypasses GML default.json regeneration bug).

## josephwhite-mod_manager

[`README.md`](./josephwhite-mod_manager/README.md)

### Architecture

**Entry point:** `mod_main.gd` connects to `tree.node_added`, detects when the OptionsMenu (`initialize()` method + parent named `"MainMenu"`) appears, then calls `_inject_mod_manager_button`. Guard: `node.get_parent().name == "MainMenu"` (PauseMenu's OptionsMenu also has `initialize()` — injecting there segfaulted).

**Injection flow:**
1. Add "MODS" separator label + "Mod Manager" toggle button to `%Buttons`
2. Wire focus/sfx/description effects same way game does for its own buttons
3. Instance the panel scene (`mod_manager_panel.tscn`), add it to MainMenu

**Injection flow (single path):**
- `mod_main.gd` — active path. Uses `node_added` signal + `call_deferred`
- The installed script extension is `extensions/options_menu_fix.gd` (`_get_button` override only). The former `options_menu_extension.gd` backup path was deleted — it was never installed and duplicated the same injection.

**Panel** (`scenes/mod_manager_panel.gd`):
- Two views: mod list (enabled/disabled) and config/info view
- Back button navigates config→list or closes; with `_changes_made`/`_config_dirty` shows confirm (actions `"back"`/`"restart"` in `_on_confirm_discard`)
- Status label never claims config needs a restart — Mod Manager hot-writes `settings.json` on Save (`_on_save_config`, `File.WRITE`); mods pick it up at the next Campaign Menu entry (`_refresh_config`/AP tag sync)
- Info view shows name/version/author/description at top, config controls below
- Focus neighbor chain wired from back button to first enabled CheckBox

**Layout rules (keep):**
- Game viewport 320x240, stretch_shrink=3; fonts: title=12, button=18, author-name=10, options-title=14. `ui_font_scale` (%) scales ALL panel fonts via `_recalc_ui_fonts()` + `_apply_ui_fonts()` (after each populate).
- `h-scrollbar = overflow reveal mechanism` — ScrollContainer only shows the bar when a child `rect_min_size` exceeds the viewport. Config string LineEdits use `expand_to_text_length = true` — do NOT toggle off (long values clip invisibly).
- Repopulate views by `remove_child()` + `free()` (never `queue_free()`), and never `free()` a button inside its own `pressed` handler (use `Object.CONNECT_DEFERRED` for confirm/cancel) — details: BUGS.md.
- `_current_view` must stay in sync with the visible view (`_show_list_view()`/`_show_config_view()` set it first).
- Color modal is a plain-VBox PopupPanel (no ScrollContainer), sized via `popup_centered(get_combined_minimum_size())` floored at `Vector2(170, 150)`.
- **Stale focus index: reader-proofed** — `options_menu.focused_menu_index` persists stale across opens (no `setget`; all write-side clamping is dead, details: BUGS.md). `mod_main.gd` connects the options node's `visibility_changed` (`_on_options_visibility` → `_clamp_focused_index`): on open it clamps the index to `%Buttons` child count via `Object.set()` — fires synchronously before the compiled nav walk. Pad-free, zero layout impact. Clamping alone is **not** enough: `menu_index` is read AFTER `add_child` (the old pre-add count pointed at the `MODS` separator one slot up) and `options_menu_fix.gd` `_get_button` skips indexes with no `FOCUS_ALL` child (walks outward) instead of returning null to the compiled nav — a null there is the native-crash vector.

### Config schema

Properties in `manifest.json` `extra.godot.config_schema`:
- `type`: `boolean`, `number`, `integer`, `string`, or `object`
- `title`: display label
- `default`: initial value
- `enum`: cycle values (for string type)
- `minimum`, `maximum`, `multipleOf`: slider bounds (for number/integer type; integer defaults to 0–100, number to 0–1)
- `exclusiveMinimum`, `exclusiveMaximum`: exclusive slider bounds — min clamps to `exclusiveMinimum + step`, max to `exclusiveMaximum - step`
- `format`: `"color"` for string type → color picker with alpha
- `hidden`: `true` omits the property from the config UI. Hidden values are carried through on Save (`_on_save_config` merges current data), never dropped.

UI rendering: boolean→CheckBox, number→HSlider, integer→HSlider (int step), string+enum→cycle Button, string format:"color"→Button + custom PopupPanel (R 0–255, G 0–255, B 0–255, A 0–100 sliders + hex LineEdit, saves `#rrggbbaa`), string→LineEdit

Mod-manager own config: `ui_font_scale` (integer % slider) + `mod_name_column_width` (integer px slider) — loaded into `_display_settings`, applied at populate time. `mod_name_column_width` = floor on the mod-list name label (`autowrap = true`, `rect_min_size.x`); if set above panel width the row overflows → h-scroll appears.

**Hex reorder** — this mod saves `RRGGBBAA` (alpha last) while Godot 3 emits `AARRGGBB`; reorder via `substr(2, 6) + substr(0, 2)`. 6-digit RGB strings pass straight through.

## josephwhite-player_skins

[`README.md`](./josephwhite-player_skins/README.md)

### Key constraints

- Player is per-level instance; skin re-applies on every level load. Material is a shared resource — `set_shader_param()` persists across levels.
- Config changes apply on the NEXT level load — saving does not restyle the current level; restart the level to preview.
- Invalid path / unsupported format → silently falls back to default texture.
- Mod manager renders `type: "string"` as LineEdit (keyboard required); controller-only users edit `settings.json` directly.
- `Invisible` mode = `player.visible = false` toggle (`Spatial.visible` exists in Godot 3.6; hides mesh + particles, physics unaffected); every non-Invisible mode re-asserts `player.visible = true` before material work, so restore survives early returns.

## References

### Godot
- [Godot 3.6 Docs](https://docs.godotengine.org/en/3.6)
    - [GDScript Style Guide](https://docs.godotengine.org/en/3.6/tutorials/scripting/gdscript/gdscript_styleguide.html)
### Godot Addons/Libs/Tools
- [GodotAP (3.6 downpatch)](https://github.com/josephwhite/GodotAP/tree/downpatch-3.6.0)
- [GDScript Toolkit](https://github.com/Scony/godot-gdscript-toolkit/tree/3.x)
    - [gdlint Docs](https://github.com/Scony/godot-gdscript-toolkit/wiki/3.-Linter) (linter only; no formatter is run)
### Y2ROLL
- [Dev tool for creating custom Y2ROLL levels](https://codeberg.org/MenacingMecha/y2r-level-compiler)
- [APWORLD for Y2ROLL Archipelago Mod](https://github.com/josephwhite/Archipelago/tree/y2roll/worlds/y2roll)
