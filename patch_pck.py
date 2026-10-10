"""
Patch Y2ROLL.pck for Godot Mod Loader.
- Adds missing class_name registrations to ECFG in project.binary
- Adds ModLoaderStore + ModLoader autoload entries to ECFG
- Injects mod_loader .gd source files into PCK
- Injects mod files into PCK

Requires:
    Python 3.6+
    Godot Mod Loader v6.3.0
    Y2ROLL (exe and pck)

Usage:
    python patch_pck.py --pck path/to/game.pck --modloader-dir path/to/addons
    python patch_pck.py --pck path/to/game.pck --modloader-dir path/to/addons --mod-dir path/to/mod [--mod-dir path/to/mod2 ...]
    python patch_pck.py --restore --pck path/to/game.pck

Notes:
    Q: Why does this script exist?
    A: The self setup for Godot Mod Loader, despite giving a success message, does not actually give Y2ROLL access to be moddable.
    Y2ROLL's pck is in a locked down state where it will only read files directly in res:// and won't read an arbitrary override.cfg file to allow classes from Godot Mod Loader (and other mods) to function.

    This script is shamelessly vibecoded.
"""

import argparse
import hashlib
import os
import shutil
import struct
import sys

PCK_HEADER_SIZE = 84
PCK_HEADER_MAGIC = b'GDPC'

# Godot Mod Loader
# https://github.com/GodotModding/godot-mod-loader/tree/v6.3.0
GODOT_MOD_LOADER_CLASSES = [
    # api/
    ('ModLoaderConfig',           'Object',    'res://addons/mod_loader/api/config.gd'),
    ('ModLoaderDeprecated',       'Node',      'res://addons/mod_loader/api/deprecated.gd'),
    ('ModLoaderLog',              'Node',      'res://addons/mod_loader/api/log.gd'),
    ('ModLoaderMod',              'Object',    'res://addons/mod_loader/api/mod.gd'),
    ('ModLoaderModManager',       'Reference', 'res://addons/mod_loader/api/mod_manager.gd'),
    ('ModLoaderUserProfile',      'Object',    'res://addons/mod_loader/api/profile.gd'),
    # internal/
    ('_ModLoaderCache',           'Reference', 'res://addons/mod_loader/internal/cache.gd'),
    ('_ModLoaderCLI',             'Reference', 'res://addons/mod_loader/internal/cli.gd'),
    ('_ModLoaderDependency',      'Reference', 'res://addons/mod_loader/internal/dependency.gd'),
    ('_ModLoaderFile',            'Reference', 'res://addons/mod_loader/internal/file.gd'),
    ('_ModLoaderGodot',           'Object',    'res://addons/mod_loader/internal/godot.gd'),
    ('ModLoaderUtils',            'Node',      'res://addons/mod_loader/internal/mod_loader_utils.gd'),
    ('_ModLoaderPath',            'Reference', 'res://addons/mod_loader/internal/path.gd'),
    ('_ModLoaderScriptExtension', 'Reference', 'res://addons/mod_loader/internal/script_extension.gd'),
    ('_ModLoaderSteam',           'Node',      'res://addons/mod_loader/internal/third_party/steam.gd'),
    # resources/
    ('ModConfig',                 'Resource',  'res://addons/mod_loader/resources/mod_config.gd'),
    ('ModData',                   'Resource',  'res://addons/mod_loader/resources/mod_data.gd'),
    ('ModManifest',               'Resource',  'res://addons/mod_loader/resources/mod_manifest.gd'),
    ('ModUserProfile',            'Resource',  'res://addons/mod_loader/resources/mod_user_profile.gd'),
    ('ModLoaderCurrentOptions',   'Resource',  'res://addons/mod_loader/resources/options_current.gd'),
    ('ModLoaderOptionsProfile',   'Resource',  'res://addons/mod_loader/resources/options_profile.gd'),
    # setup/
    ('ModLoaderSetupLog',         'Reference', 'res://addons/mod_loader/setup/setup_log.gd'),
    ('ModLoaderSetupUtils',       'Reference', 'res://addons/mod_loader/setup/setup_utils.gd'),
    # third-party
    ('JSONSchema',                'Reference', 'res://addons/JSON_Schema_Validator/json_schema_validator.gd'),
]

# GodotAP (embedded in josephwhite-ArchipelagoRandomizer/godot_ap/, branch downpatch-3.6.0)
# 36 classes mirrored from GodotAP project.godot `_global_script_classes`.
# Only registered when the AP mod is included in `--mod-dir`.
# https://github.com/josephwhite/GodotAP/tree/downpatch-3.6.0/godot_ap
ARCHIPELAGO_RANDOMIZER_CLASSES = [
    ('AP',                        'Node',        'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/autoloads/archipelago.gd'),
    ('APColors',                  'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/ap_colors.gd'),
    ('APConfigManager',           'Node',        'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/managers/configs.gd'),
    ('APCredentials',             'Node',        'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/connect_creds.gd'),
    ('APLocation',                'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/ap_location.gd'),
    ('APLock',                    'Node',        'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/ap_lock.gd'),
    ('APSaveManager',             'Node',        'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/managers/saves.gd'),
    ('BaseConsole',               'Control',     'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/console/base_console.gd'),
    ('CommandManager',            'Node',        'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/managers/command_manager.gd'),
    ('ConnectionInfo',            'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/connection_info.gd'),
    ('ConsoleCommand',            'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/console_command.gd'),
    ('ConsoleContainer',          'VBoxContainer', 'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/console_container.gd'),
    ('ConsoleFoldableContainer',  'VBoxContainer', 'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/console/foldable_container.gd'),
    ('ConsoleHFlow',              'Container',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/console/console_hflow.gd'),
    ('ConsoleLabel',              'Label',       'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/console/console_label.gd'),
    ('ConsoleWindowContainer',    'PanelContainer', 'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/console_window_container.gd'),
    ('CustomLabel',               'Panel',       'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/custom_containers/custom_label.gd'),
    ('DataCache',                 'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/datacache.gd'),
    ('FontStorage',               'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/util/font_storage.gd'),
    ('GUI',                       'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/managers/gui.gd'),
    ('GodotAPMain',               'ColorRect',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/godotap_main.gd'),
    ('HintsTab',                  'MarginContainer', 'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/hints_tab.gd'),
    ('NetworkHint',               'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/network_hint.gd'),
    ('NetworkItem',               'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/network_item.gd'),
    ('NetworkPlayer',             'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/network_player.gd'),
    ('NetworkSlot',               'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/network_slot.gd'),
    ('SaveFile',                  'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/save_file.gd'),
    ('SignalChooser',             'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/util/signal_chooser.gd'),
    ('SliderBox',                 'MarginContainer', 'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/slider_box.gd'),
    ('Spacing',                   'Control',     'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/console/spacing.gd'),
    ('StringBar',                 'Control',     'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/autofill_bar.gd'),
    ('ThemeBox',                  'CheckBox',    'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/theme_box.gd'),
    ('ThemeManager',              'MarginContainer', 'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/theme_manager.gd'),
    ('TypingBar',                 'LineEdit',    'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ui/typing_bar.gd'),
    ('Util',                      'Reference',   'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/util/util.gd'),
    ('Version',                   'Resource',    'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/godot_ap/ap_files/version.gd'),
]

ARCHIPELAGO_RANDOMIZER_CLASS_NAMES = {
    name for name, _, _ in ARCHIPELAGO_RANDOMIZER_CLASSES
}

AUTOLOAD_ENTRIES = [
    ('autoload/ModLoaderStore', '*res://addons/mod_loader/mod_loader_store.gd'),
    ('autoload/ModLoader',      '*res://addons/mod_loader/mod_loader.gd'),
]

# GodotAP assets that are not runtime-loadable in the Y2ROLL export and must be excluded from injection.
GODOTAP_THEMES_PREFIX = 'godot_ap/ui/themes/'


def is_mod_file_excluded(mod_rel):
    """
    True if a mod file must not be injected into the PCK.
    """
    if mod_rel.endswith('.import') or mod_rel.endswith('.imported'):
        return True
    if mod_rel.startswith(GODOTAP_THEMES_PREFIX):
        return True
    if mod_rel.startswith('godot_ap/ui/refresh.png') or mod_rel.startswith('godot_ap/ui/refresh_hov.png') or mod_rel.startswith('godot_ap/ui/refresh_pressed.png'):
        return True
    return False


def parse_args():
    parser = argparse.ArgumentParser(
        description='Patch Y2ROLL.pck for Godot Mod Loader v6.3.0.')
    parser.add_argument('--restore', action='store_true',
                        help='Restore PCK from backup')
    parser.add_argument('--pck', default=None,
                        help='Path to Y2ROLL.pck')
    parser.add_argument('--modloader-dir', default=None,
                        help='Path to GML addons/ folder (extracted from 3.x-dev.zip)')
    parser.add_argument('--mod-dir', action='append', default=None,
                        help='Path to mod folder (namespace-name). Can be specified multiple times. Omit to load Godot Mod Loader only.')
    parser.add_argument('--verbose', action='store_true',
                        help='Print per-file injection details')
    return parser.parse_args()


# Variant codec
def decode_variant(d, p):
    """
    Deserialize one Godot Variant from bytes `d` at offset `p`;
    Return value and new offset.
    """
    vtype = struct.unpack_from('<I', d, p)[0]; p += 4
    if vtype == 0: return None, p
    elif vtype == 1:
        val = struct.unpack_from('<I', d, p)[0]; p += 4
        return bool(val), p
    elif vtype == 2:
        val = struct.unpack_from('<i', d, p)[0]; p += 4
        return val, p
    elif vtype == 3:
        val = struct.unpack_from('<f', d, p)[0]; p += 4
        return val, p
    elif vtype == 4:
        slen = struct.unpack_from('<I', d, p)[0]; p += 4
        s = d[p:p+slen].decode('utf-8'); p += slen
        pad = (4 - (slen % 4)) % 4; p += pad
        return s, p
    elif vtype == 18:
        cnt = struct.unpack_from('<I', d, p)[0]; p += 4
        dct = {}
        for _ in range(cnt):
            k, p = decode_variant(d, p)
            v, p = decode_variant(d, p)
            dct[k] = v
        return dct, p
    elif vtype == 19:
        cnt = struct.unpack_from('<I', d, p)[0]; p += 4
        arr = []
        for _ in range(cnt):
            elem, p = decode_variant(d, p)
            arr.append(elem)
        return arr, p
    elif vtype == 20:
        cnt = struct.unpack_from('<I', d, p)[0]; p += 4
        arr = list(d[p:p+cnt]); p += cnt
        pad = (4 - (cnt % 4)) % 4; p += pad
        return arr, p
    elif vtype == 23:
        cnt = struct.unpack_from('<I', d, p)[0]; p += 4
        arr = []
        for _ in range(cnt):
            s, p = decode_variant(d, p)
            arr.append(s)
        return arr, p
    else:
        raise ValueError(f'Unknown variant type {vtype} at offset {p-4}')


def encode_variant(value):
    """
    Serialize a Python value into a Godot Variant byte string (None/bool/int/float/str/dict/list).
    """
    if value is None:
        return struct.pack('<I', 0)
    elif isinstance(value, bool):
        return struct.pack('<I', 1) + struct.pack('<I', int(value))
    elif isinstance(value, int):
        return struct.pack('<I', 2) + struct.pack('<i', value)
    elif isinstance(value, float):
        return struct.pack('<I', 3) + struct.pack('<f', value)
    elif isinstance(value, str):
        encoded = value.encode('utf-8')
        slen = len(encoded)
        pad = (4 - (slen % 4)) % 4
        return struct.pack('<I', 4) + struct.pack('<I', slen) + encoded + b'\x00' * pad
    elif isinstance(value, dict):
        result = struct.pack('<I', 18) + struct.pack('<I', len(value))
        for k, v in value.items():
            result += encode_variant(k) + encode_variant(v)
        return result
    elif isinstance(value, list):
        result = struct.pack('<I', 19) + struct.pack('<I', len(value))
        for elem in value:
            result += encode_variant(elem)
        return result
    else:
        raise ValueError(f'Cannot encode type {type(value)}')


# ECFG codec
def parse_ecfg(data):
    """
    Parse a Godot project.binary ECFG blob into a list of (key, value) byte pairs.
    """
    if data[:4] != b'ECFG':
        raise ValueError(f'Bad ECFG magic: {data[:4]}')
    pos = 4
    count = struct.unpack_from('<I', data, pos)[0]; pos += 4
    entries = []
    for _ in range(count):
        klen = struct.unpack_from('<I', data, pos)[0]; pos += 4
        key = data[pos:pos+klen].decode('utf-8'); pos += klen
        vlen = struct.unpack_from('<I', data, pos)[0]; pos += 4
        val = data[pos:pos+vlen]; pos += vlen
        entries.append((key, val))
    return entries


def build_ecfg(entries):
    """
    Serialize (key, value) byte pairs into a Godot ECFG blob.
    """
    result = b'ECFG'
    result += struct.pack('<I', len(entries))
    for key, val in entries:
        key_bytes = key.encode('utf-8')
        result += struct.pack('<I', len(key_bytes))
        result += key_bytes
        result += struct.pack('<I', len(val))
        result += val
    return result


def patch_project_binary_data(data, class_list):
    """
    Register class_names + autoloads in project.binary and strip stale AP classes.
    return new blob and counts.
    """
    entries = parse_ecfg(data)
    val0 = entries[0][1]
    assert entries[0][0] == '_global_script_classes'
    classes, _ = decode_variant(val0, 0)
    val1 = entries[1][1]
    assert entries[1][0] == '_global_script_class_icons'
    icons, _ = decode_variant(val1, 0)

    known = set(c['class'] for c in classes)
    added_classes = 0
    for name, base, path in class_list:
        if name not in known:
            classes.append({'base': base, 'class': name, 'language': 'GDScript', 'path': path})
            icons[name] = ''
            added_classes += 1

    # Strip GodotAP class registrations left over from a previous patch when the AP mod is no longer injected.
    # ECFG would point to scripts that don't exist in the PCK, causing Godot to error at boot.
    removed_classes = 0
    stale_ap = ARCHIPELAGO_RANDOMIZER_CLASS_NAMES - set(name for name, _, _ in class_list)
    if stale_ap:
        kept = [c for c in classes if c['class'] not in stale_ap]
        removed_classes = len(classes) - len(kept)
        classes = kept
        for name in stale_ap:
            icons.pop(name, None)

    added_autoloads = 0
    known_keys = set(e[0] for e in entries)
    autoload_insert_pos = 0
    for i, (key, _) in enumerate(entries):
        if key.startswith('autoload/'):
            autoload_insert_pos = i
            break
    for key, val in AUTOLOAD_ENTRIES:
        if key not in known_keys:
            entries.insert(autoload_insert_pos, (key, encode_variant(val)))
            autoload_insert_pos += 1
            added_autoloads += 1

    if added_classes == 0 and added_autoloads == 0 and removed_classes == 0:
        return data, 0, 0, 0

    entries[0] = ('_global_script_classes', encode_variant(classes))
    entries[1] = ('_global_script_class_icons', encode_variant(icons))
    new_data = build_ecfg(entries)
    return new_data, added_classes, added_autoloads, removed_classes


# PCK codec
def parse_pck(path):
    """
    Parse a Godot 3 PCK file into header bytes, entry dicts, and per-path file blobs.
    """
    raw = open(path, 'rb').read()
    if raw[:4] != PCK_HEADER_MAGIC:
        raise ValueError(f'Bad PCK magic: {raw[:4]}')
    header = bytearray(raw[:PCK_HEADER_SIZE])
    file_count = struct.unpack_from('<I', raw, PCK_HEADER_SIZE)[0]
    entries = []
    pos = PCK_HEADER_SIZE + 4
    for i in range(file_count):
        table_offset = pos
        path_len = struct.unpack_from('<I', raw, pos)[0]; pos += 4
        path = raw[pos:pos+path_len].decode('ascii').rstrip('\x00'); pos += path_len
        offset = struct.unpack_from('<Q', raw, pos)[0]; pos += 8
        size = struct.unpack_from('<Q', raw, pos)[0]; pos += 8
        md5 = bytes(raw[pos:pos+16]); pos += 16
        entries.append({
            'path': path, 'path_len': path_len,
            'offset': offset, 'size': size, 'md5': md5,
            'table_size': pos - table_offset,
        })

    file_blobs = {}
    for e in entries:
        file_blobs[e['path']] = raw[e['offset']:e['offset']+e['size']]

    return header, entries, file_blobs


def build_pck(header, entries, file_blobs):
    """
    Rebuild a PCK file from header, entry list, and file blobs with recomputed offsets.
    """
    out = bytearray(header)
    out += struct.pack('<I', len(entries))
    for e in entries:
        path_bytes = e['path'].encode('ascii')
        pad = e['path_len'] - len(path_bytes)
        if pad > 0:
            path_bytes += b'\x00' * pad
        out += struct.pack('<I', e['path_len'])
        out += path_bytes
        out += struct.pack('<Q', e['offset'])
        out += struct.pack('<Q', e['size'])
        out += e['md5']
    for e in entries:
        out += file_blobs[e['path']]
    return bytes(out)


# Main
def main():
    args = parse_args()
    
    pck_path = args.pck
    modloader_dir = args.modloader_dir
    mod_dirs = args.mod_dir or []

    ap_mod_dir = next(
        (md for md in mod_dirs
         if os.path.basename(md) == 'josephwhite-ArchipelagoRandomizer'
         and os.path.isdir(os.path.join(md, 'godot_ap'))),
        None)
    class_list = GODOT_MOD_LOADER_CLASSES + (ARCHIPELAGO_RANDOMIZER_CLASSES if ap_mod_dir else [])

    if args.restore:
        bak = pck_path + '.bak'
        if not os.path.exists(bak):
            print(f'No backup: {bak}')
            sys.exit(1)
        shutil.copy2(bak, pck_path)
        print(f'Restored {pck_path}')
        return

    if ap_mod_dir:
        print(f'AP mod present: {ap_mod_dir} ({len(ARCHIPELAGO_RANDOMIZER_CLASSES)} GodotAP classes will be registered)')
    else:
        print('AP mod absent: GodotAP classes skipped, stale registrations stripped')

    if not os.path.exists(pck_path):
        print(f'PCK not found: {pck_path}')
        sys.exit(1)

    bak_path = pck_path + '.bak'
    if not os.path.exists(bak_path):
        print(f'Creating backup: {bak_path}')
        shutil.copy2(pck_path, bak_path)
    else:
        print(f'Backup exists: {bak_path}')

    print(f'\nParsing PCK: {pck_path}')
    header, entries, file_blobs = parse_pck(pck_path)
    print(f'  {len(entries)} files, {os.path.getsize(pck_path)} bytes')

    pb_entry = None
    for e in entries:
        if e['path'] == 'res://project.binary':
            pb_entry = e
            break
    if pb_entry is None:
        print('ERROR: project.binary not found'); sys.exit(1)

    print(f'\nproject.binary: {pb_entry["size"]} bytes')
    entries_in_ecfg = parse_ecfg(file_blobs['res://project.binary'])
    classes, _ = decode_variant(entries_in_ecfg[0][1], 0)
    print(f'  {len(classes)} classes')

    print('\nPatching project.binary...')
    patched_pb, added_classes, added_autoloads, removed_classes = patch_project_binary_data(file_blobs['res://project.binary'], class_list)
    if added_classes == 0 and added_autoloads == 0 and removed_classes == 0:
        print('  Already patched.')
    else:
        print(f'  Added {added_classes} classes, removed {removed_classes} classes, {added_autoloads} autoloads. {pb_entry["size"]} -> {len(patched_pb)} bytes')
        file_blobs['res://project.binary'] = patched_pb
        pb_entry['size'] = len(patched_pb)

    print('\nInjecting mod_loader source files...')
    existing_paths = set(e['path'] for e in entries)
    injected = 0
    for root, dirs, files in os.walk(modloader_dir):
        dirs[:] = [d for d in dirs if d != 'vendor']
        for fname in files:
            if fname in ('LICENSE',):
                continue
            abs_path = os.path.join(root, fname)
            rel = os.path.relpath(abs_path, modloader_dir).replace('\\', '/')
            pck_path_str = 'res://addons/' + rel
            fdata = open(abs_path, 'rb').read()
            if pck_path_str in existing_paths:
                file_blobs[pck_path_str] = fdata
                for e in entries:
                    if e['path'] == pck_path_str:
                        e['size'] = len(fdata)
                        e['md5'] = hashlib.md5(fdata).digest()
                        break
                injected += 1
                if args.verbose:
                    print(f'  ~ {pck_path_str} ({len(fdata)} bytes) [updated]')
                continue
            full_path = pck_path_str
            path_bytes_len = len(full_path.encode('ascii'))
            padded_len = path_bytes_len + (4 - path_bytes_len % 4) % 4
            if padded_len < path_bytes_len + 1:
                padded_len += 4
            entry = {
                'path': pck_path_str,
                'path_len': padded_len,
                'offset': 0,
                'size': len(fdata),
                'md5': hashlib.md5(fdata).digest(),
                'table_size': 4 + padded_len + 8 + 8 + 16,
            }
            entries.append(entry)
            file_blobs[pck_path_str] = fdata
            injected += 1
            if args.verbose:
                print(f'  + {pck_path_str} ({len(fdata)} bytes)')
    print(f'  {injected} files injected')

    print('\nInjecting mod files into PCK...')
    existing_paths = set(e['path'] for e in entries)
    mod_injected = 0
    for mod_dir in mod_dirs:
        mod_id = os.path.basename(mod_dir)
        print(f'  Mod: {mod_id}')
        for root, dirs, files in os.walk(mod_dir):
            dirs[:] = [d for d in dirs if d not in ('.git', '.import')]
            for fname in files:
                abs_path = os.path.join(root, fname)
                mod_rel = os.path.relpath(abs_path, mod_dir).replace('\\', '/')
                if is_mod_file_excluded(mod_rel):
                    continue
                pck_path_str = 'res://mods-unpacked/' + mod_id + '/' + mod_rel
                fdata = open(abs_path, 'rb').read()
                if pck_path_str in existing_paths:
                    file_blobs[pck_path_str] = fdata
                    for e in entries:
                        if e['path'] == pck_path_str:
                            e['size'] = len(fdata)
                            e['md5'] = hashlib.md5(fdata).digest()
                            break
                    mod_injected += 1
                    if args.verbose:
                        print(f'    ~ {pck_path_str} ({len(fdata)} bytes) [updated]')
                    continue
                full_path = pck_path_str
                path_bytes_len = len(full_path.encode('ascii'))
                padded_len = path_bytes_len + (4 - path_bytes_len % 4) % 4
                if padded_len < path_bytes_len + 1:
                    padded_len += 4
                entry = {
                    'path': pck_path_str,
                    'path_len': padded_len,
                    'offset': 0,
                    'size': len(fdata),
                    'md5': hashlib.md5(fdata).digest(),
                    'table_size': 4 + padded_len + 8 + 8 + 16,
                }
                entries.append(entry)
                file_blobs[pck_path_str] = fdata
                mod_injected += 1
                if args.verbose:
                    print(f'    + {pck_path_str} ({len(fdata)} bytes)')
    print(f'  {mod_injected} mod files injected')

    if not ap_mod_dir:
        stale_prefix = 'res://mods-unpacked/josephwhite-ArchipelagoRandomizer/'
        stale_count = sum(1 for e in entries if e['path'].startswith(stale_prefix))
        if stale_count:
            entries[:] = [e for e in entries if not e['path'].startswith(stale_prefix)]
            print(f'  Removed {stale_count} stale AP mod files from PCK')

    print('\nCalculating offsets...')
    pos = PCK_HEADER_SIZE + 4
    for e in entries:
        pos += e['table_size']
    data_start = pos
    data_pos = data_start
    for e in entries:
        e['offset'] = data_pos
        data_pos += e['size']
    total_size = data_pos
    print(f'  File table: {data_start} bytes. Data starts at: {data_start}. Total: {total_size}')

    print('\nRebuilding PCK...')
    new_pck = build_pck(header, entries, file_blobs)
    print(f'  Original: {os.path.getsize(pck_path)} bytes')
    print(f'  New:      {len(new_pck)} bytes')
    assert len(new_pck) == total_size, f'Size mismatch: {len(new_pck)} != {total_size}'

    with open(pck_path, 'wb') as f:
        f.write(new_pck)
    print(f'\nWrote: {pck_path}')

    print('\nVerifying...')
    h2, entries2, fd2 = parse_pck(pck_path)
    print(f'  {len(entries2)} files in patched PCK')
    for e in entries2:
        if e['path'] == 'res://project.binary':
            ecfg2 = parse_ecfg(fd2['res://project.binary'])
            cls2, _ = decode_variant(ecfg2[0][1], 0)
            print(f'  project.binary: {len(cls2)} classes')
            for c in cls2:
                if args.verbose:
                    print(f'    {c["class"]} (extends {c["base"]})')
            autoloads = [(k, decode_variant(v, 0)[0]) for k, v in ecfg2 if k.startswith('autoload/')]
            print(f'  autoloads: {len(autoloads)}')
            for k, v in autoloads:
                if args.verbose:
                    print(f'    {k} = {v}')
            break
    ml_count = sum(1 for e in entries2 if 'addons/mod_loader' in e['path'])
    print(f'  mod_loader files in PCK: {ml_count}')

    print('\nDone! Launch Y2ROLL to test.')


if __name__ == '__main__':
    main()
