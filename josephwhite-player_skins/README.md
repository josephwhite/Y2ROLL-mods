# Y2ROLL Player Skins

`josephwhite-player_skins` 

Customize your marble: solid-color tint or a custom image.

## Setup

[Here](../SETUP.md).

## Skin Options

- Default
- Solid Color
    - `#rrggbb`
    - `#rrggbbaa`
    - Transparent/alpha does NOT hide the marble (shader is opaque)
- Custom Image
    - Path to image
        - Absolute path (`C:\...`)
        - `user://...`
    - Formats: PNG, JPEG, WebP, BMP, TGA, TIFF, DDS
    - Smooth Filtering
- Invisible
    - Hides the marble

## Texture tips
- For the best N64 look, use 32×32px to 256×256px pixel art with Smooth Filtering off.
- Utilize seamless/tiling patterns.
- Invalid image paths/formats silently falls back to the default. 

## Config

|System|Config Path|
|-|-|
|Godot|`user://configs/josephwhite-player_skins/settings.json`|
|Windows|`%APPDATA%\Godot\app_userdata\Y2ROLL\...`|
|Linux|`~/.local/share/godot/app_userdata/Y2ROLL/...`|
