# Y2ROLL Mod Manager

`josephwhite-mod_manager`

In-game mod manager menu for Y2ROLL. 

- Enable/Disable mods.
- Edit configs.
- Applies config changes without restarting.

## Setup

[Here](../SETUP.md).

Mod Manager can be found at the bottom of the Options Menu.

## Config UI

Mods expose options via `manifest.json` → `extra.godot.config_schema` (JSON Schema):

| type | control |
|---|---|
| `boolean` | CheckBox |
| `number` / `integer` | HSlider (`minimum`/`maximum`/`multipleOf`; integer default 0–100) |
| `string` | LineEdit |
| `string` + `enum` | Cycle Button |
| `string` + `format:"color"` | Color picker popup (R/G/B 0–255, A 0–100 sliders + hex, saves as `#rrggbbaa`) |
| `object` | warning label (nested objects unsupported) |

### Extra properties
- `hidden: true` omits a property from the UI. 
