#!/usr/bin/env python3
"""Teach an installed "Portal 2 Natif.app" (source-recomp) to use BEEmod.

Two small changes, both idempotent:

1. Contents/MacOS/launcher: export P2_MAP_COMPILER to the map compiler hook
   (~/Library/Application Support/Portal 2 Natif/map-compiler-hook) when it
   exists, and P2_NATIVE_MAP_COMPILER to the bundled portal2-map-compiler.
2. Contents/Resources/puzzlemaker.py: rewrite plain relative search paths such
   as `Game "BEE2"` (added by BEEmod's export) to `|gameinfo_path|../BEE2`.
   The engine resolves relative paths from bin/, not from the game root, and
   on a case-insensitive disk bin/BEE2 is BEEmod's own bin/bee2 config folder:
   without this, the palette shows purple placeholder icons.

The app is then signed again ad hoc. Rebuilding the app with source-recomp's
make_app.py undoes these changes: run this script again, or apply
patches/source-recomp-beemod.patch to the source-recomp checkout.

usage: patch-portal2-natif.py [path/to/Portal 2 Natif.app]
"""
import re
import shlex
import subprocess
import sys
from pathlib import Path

HOOK_MARKER = 'MAP_COMPILER_HOOK='
ANCHOR_MARKER = 'def anchor_relative_game_paths'

HOOK_BLOCK = '''# Optional custom map compiler (BEEmod): it receives the native compiler's
# arguments; the native compiler's path is in P2_NATIVE_MAP_COMPILER.
MAP_COMPILER_HOOK={hook}
if [ -z "$P2_MAP_COMPILER" ] && [ -x "$MAP_COMPILER_HOOK" ]; then
    export P2_MAP_COMPILER="$MAP_COMPILER_HOOK" P2_NATIVE_MAP_COMPILER="$HERE/portal2-map-compiler"
fi
'''

ANCHOR_FUNCTION = '''def anchor_relative_game_paths(data, game_dir):
    """Rewrite plain relative search paths (Game "BEE2", added by BEEmod) to
    |gameinfo_path|../NAME. Source resolves them from the executable's
    directory, which is bin/ here, not the game root; and on a
    case-insensitive disk bin/BEE2 is BEEmod's own bin/bee2 config folder."""
    pattern = re.compile(rb'(?im)^([ \\t]*"?Game"?[ \\t]+)"?([A-Za-z0-9_\\-. ]+?)"?[ \\t]*$')

    def fix(match):
        name = match[2].decode('utf-8', 'replace')
        if not name.strip():
            return match[0]
        existing = {p.name.casefold(): p.name for p in Path(game_dir).iterdir() if p.is_dir()}
        real = existing.get(name.casefold())
        if real is None:
            return match[0]
        return match[1] + b'|gameinfo_path|../' + real.encode()

    return pattern.sub(fix, data)


'''


def default_app():
    return Path.home() / 'Applications' / 'Portal 2 Natif.app'


def patch_launcher(launcher, hook):
    text = launcher.read_text()
    if HOOK_MARKER in text:
        return False
    anchor = re.search(r'^export SteamAppId=.*$', text, re.M)
    if not anchor:
        raise SystemExit(f'{launcher}: unknown launcher layout (no "export SteamAppId=" line)')
    block = HOOK_BLOCK.format(hook=shlex.quote(str(hook)))
    text = text[:anchor.end() + 1] + block + text[anchor.end() + 1:]
    launcher.write_text(text)
    return True


def patch_puzzlemaker(script):
    text = script.read_text()
    if ANCHOR_MARKER in text:
        return False
    if 'def prepare_puzzlemaker(' not in text:
        raise SystemExit(f'{script}: unknown layout (no prepare_puzzlemaker)')
    if not re.search(r'^from pathlib import Path', text, re.M):
        text = re.sub(r'^(import re\n)', r'\1from pathlib import Path\n', text, count=1, flags=re.M)
        if 'from pathlib import Path' not in text:
            text = 'from pathlib import Path\n' + text
    text = text.replace('def prepare_puzzlemaker(', ANCHOR_FUNCTION + 'def prepare_puzzlemaker(', 1)
    # Apply the rewrite right before the user copy of gameinfo.txt is written.
    call = re.search(r'^(\s*)target\.parent\.mkdir\(parents=True, exist_ok=True\)\s*$', text, re.M)
    if not call:
        raise SystemExit(f'{script}: unknown layout (no target.parent.mkdir in prepare_puzzlemaker)')
    indent = call[1]
    text = text[:call.start()] + f'{indent}data = anchor_relative_game_paths(data, game_dir)\n' + text[call.start():]
    script.write_text(text)
    return True


def main():
    app = Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else default_app()
    launcher = app / 'Contents/MacOS/launcher'
    script = app / 'Contents/Resources/puzzlemaker.py'
    if not launcher.is_file():
        raise SystemExit(f'{app} not found or not a source-recomp app (no Contents/MacOS/launcher)')
    if not (app / 'Contents/MacOS/portal2-map-compiler').is_file():
        print('warning: this app has no map compiler: rebuild it with ./setup.sh --puzzle-maker '
              '(Build and Play needs it)', file=sys.stderr)
    hook = Path.home() / 'Library/Application Support/Portal 2 Natif/map-compiler-hook'
    changed = patch_launcher(launcher, hook)
    if script.is_file():
        changed = patch_puzzlemaker(script) or changed
    else:
        print(f'warning: {script} not found: palette icons may stay purple', file=sys.stderr)
    if changed:
        subprocess.run(['codesign', '--force', '--sign', '-', str(launcher)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f'patched: {app}')
    else:
        print(f'already patched: {app}')


if __name__ == '__main__':
    main()
