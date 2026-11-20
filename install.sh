#!/bin/bash
# BEEmod (BEE2.4) 4.36 on Apple Silicon Macs, with Build and Play and Workshop
# publishing through the native "Portal 2 Natif" app (source-recomp).
#
# What it does (every step can be run again safely):
#   1. checks the Mac (Apple Silicon, Rosetta 2) and finds Portal 2;
#   2. downloads BEEmod 4.36 (application + item packages) and the python.org
#      package that provides Tcl/Tk 8.6.10, and checks their SHA-256;
#   3. unpacks BEEmod and replaces its Tcl/Tk 8.6.8 (blank windows on current
#      macOS) with 8.6.10;
#   4. writes BEEmod's games.cfg (its game picker only accepts .exe files);
#   5. installs the map compiler hook and patches "Portal 2 Natif.app";
#   6. creates BEEmod.app (runs BEEmod under Rosetta).
#
# usage: ./install.sh [--dir DIR] [--game "PORTAL 2 FOLDER"] [--portal2-app APP]
#                     [--apps-dir DIR] [--downloads DIR] [--no-app]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BEE_DIR="$HOME/BEE2.4"
GAME_DIR=""
P2_APP="$HOME/Applications/Portal 2 Natif.app"
APPS_DIR="/Applications"
DOWNLOADS="$HOME/Library/Caches/BEEmod-Mac-AppleSilicon"
MAKE_APP=1

BEE_URL="https://github.com/BEEmod/BEE2.4/releases/download/2.4.36.1_/BEE2_4.36.0_mac_old.zip"
BEE_SHA="c366c51e3e69b50e7f590184d602304530552ecf958afee768872794def57ca8"
PACKAGES_URL="https://github.com/BEEmod/BEE2-items/releases/download/v4.36.0/BEE2_v4.36.0_packages_old.zip"
PACKAGES_SHA="0a85f113a510be7655f02f9a356bb860707a91f3ad39bf3707c5a7ab418ff38e"
PYTHON_URL="https://www.python.org/ftp/python/3.9.1/python-3.9.1-macos11.0.pkg"
PYTHON_SHA="8f8782d278e3926566cba11182453379568dc98d82adde9ef38e28439d46f736"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [ $# -gt 0 ]; do
    case "$1" in
        --dir) BEE_DIR=$2; shift 2 ;;
        --game) GAME_DIR=$2; shift 2 ;;
        --portal2-app) P2_APP=$2; shift 2 ;;
        --apps-dir) APPS_DIR=$2; shift 2 ;;
        --downloads) DOWNLOADS=$2; shift 2 ;;
        --no-app) MAKE_APP=0; shift ;;
        -h|--help) usage 0 ;;
        *) echo "unknown option: $1" >&2; usage 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

# ------------------------------------------------------------------ 1. checks
step "Checking this Mac"
[ "$(uname -s)" = Darwin ] || die "macOS only"
[ "$(uname -m)" = arm64 ] || echo "note: not an Apple Silicon Mac; BEEmod runs natively on Intel, the rest still applies"
if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
    die "Rosetta 2 is not installed. Install it with:
    softwareupdate --install-rosetta --agree-to-license
then run ./install.sh again."
fi
for tool in curl unzip shasum pkgutil lipo install_name_tool codesign sips python3; do
    command -v "$tool" >/dev/null || die "$tool not found (install the Xcode Command Line Tools: xcode-select --install)"
done

if [ -z "$GAME_DIR" ]; then
    for candidate in "$HOME/Library/Application Support/Steam/steamapps/common/Portal 2"; do
        [ -f "$candidate/portal2/gameinfo.txt" ] && GAME_DIR=$candidate && break
    done
fi
[ -n "$GAME_DIR" ] && [ -f "$GAME_DIR/portal2/gameinfo.txt" ] ||
    die "Portal 2 not found. Install it with Steam, or pass --game \"/path/to/Portal 2\""
echo "Portal 2: $GAME_DIR"
if [ -d "$P2_APP" ]; then
    echo "Portal 2 Natif: $P2_APP"
else
    echo "warning: $P2_APP not found. BEEmod will install, but Build and Play needs"
    echo "         Portal 2 Natif built with the Puzzle Maker (see README)."
fi

# --------------------------------------------------------------- 2. downloads
step "Downloading BEEmod 4.36 and Tcl/Tk 8.6.10 (about 370 MB, kept in $DOWNLOADS)"
mkdir -p "$DOWNLOADS"
fetch() {  # url sha256 -> path
    local url=$1 sha=$2 file="$DOWNLOADS/$(basename "$1")"
    if [ -f "$file" ] && echo "$sha  $file" | shasum -a 256 -c --status; then
        echo "  cached: $(basename "$file")" >&2
    else
        echo "  downloading $(basename "$file")..." >&2
        curl -fL --retry 3 --progress-bar -o "$file.part" "$url"
        mv "$file.part" "$file"
        echo "$sha  $file" | shasum -a 256 -c --status ||
            { rm -f "$file"; die "SHA-256 mismatch for $(basename "$file")"; }
    fi
    echo "$file"
}
BEE_ZIP=$(fetch "$BEE_URL" "$BEE_SHA")
PACKAGES_ZIP=$(fetch "$PACKAGES_URL" "$PACKAGES_SHA")
PYTHON_PKG=$(fetch "$PYTHON_URL" "$PYTHON_SHA")

# ---------------------------------------------------------------- 3. BEEmod
step "Installing BEEmod into $BEE_DIR"
mkdir -p "$BEE_DIR"
if [ ! -x "$BEE_DIR/BEE2" ]; then
    unzip -q -o "$BEE_ZIP" -d "$BEE_DIR"
else
    echo "  BEEmod already unpacked (kept: your settings and palettes stay)"
fi
if [ ! -d "$BEE_DIR/packages" ]; then
    unzip -q -o "$PACKAGES_ZIP" -d "$BEE_DIR"
else
    echo "  item packages already there"
fi
chmod +x "$BEE_DIR/BEE2" "$BEE_DIR/compiler/vbsp_osx" "$BEE_DIR/compiler/vrad_osx"
mkdir -p "$BEE_DIR/logs"
xattr -dr com.apple.quarantine "$BEE_DIR" 2>/dev/null || true
"$HERE/scripts/fix-tk.sh" "$BEE_DIR" "$PYTHON_PKG"

# ------------------------------------------------------------- 4. games.cfg
step "Pointing BEEmod at Portal 2"
CFG="$HOME/Library/Preferences/BEEMOD2/config/games.cfg"
mkdir -p "$(dirname "$CFG")"
python3 - "$CFG" "$GAME_DIR" <<'PY'
import sys
from pathlib import Path
cfg, game = Path(sys.argv[1]), sys.argv[2]
lines = cfg.read_text().splitlines() if cfg.exists() else []
out, in_section, found, wrote_dir = [], False, False, False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        if in_section and not wrote_dir:
            out.append(f'dir = {game}'); wrote_dir = True
        in_section = stripped == '[Portal 2]'
        found = found or in_section
    elif in_section and stripped.lower().startswith('dir'):
        out.append(f'dir = {game}'); wrote_dir = True
        continue
    out.append(line)
if in_section and not wrote_dir:
    out.append(f'dir = {game}')
if not found:
    out = ['[Portal 2]', 'steamid = 620', f'dir = {game}'] + ([''] + out if out else [])
cfg.write_text('\n'.join(out) + '\n')
print(f'  {cfg}')
PY

# ------------------------------------------------------ 5. hook + Portal 2 Natif
step "Installing the map compiler hook"
HOOK_DIR="$HOME/Library/Application Support/Portal 2 Natif"
mkdir -p "$HOOK_DIR"
install -m 755 "$HERE/scripts/map-compiler-hook.sh" "$HOOK_DIR/map-compiler-hook"
echo "  $HOOK_DIR/map-compiler-hook"
if [ -d "$P2_APP" ]; then
    python3 "$HERE/scripts/patch-portal2-natif.py" "$P2_APP"
fi

# ---------------------------------------------------------------- 6. BEEmod.app
if [ "$MAKE_APP" = 1 ]; then
    step "Creating BEEmod.app"
    [ -w "$APPS_DIR" ] || APPS_DIR="$HOME/Applications"
    mkdir -p "$APPS_DIR"
    APP="$APPS_DIR/BEEmod.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cat >"$APP/Contents/MacOS/BEEmod" <<EOF
#!/bin/bash
# Runs BEEmod 4.36 (Intel) under Rosetta from its folder.
# Finder gives no LANG, and BEEmod's Python 3.6 fails without a locale.
export LANG="\${LANG:-en_US.UTF-8}" LC_ALL="\${LC_ALL:-\${LANG:-en_US.UTF-8}}"
cd $(printf '%q' "$BEE_DIR") || exit 1
mkdir -p logs
exec /usr/bin/arch -x86_64 ./BEE2 >>logs/launcher.log 2>&1
EOF
    chmod +x "$APP/Contents/MacOS/BEEmod"
    cat >"$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BEEmod</string>
<key>CFBundleIdentifier</key><string>io.github.beemod-mac-applesilicon.launcher</string>
<key>CFBundleName</key><string>BEEmod</string>
<key>CFBundleDisplayName</key><string>BEEmod</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>4.36</string>
<key>CFBundleVersion</key><string>4.36</string>
<key>CFBundleIconFile</key><string>BEE2</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
EOF
    sips -s format icns "$BEE_DIR/BEE2.ico" --out "$APP/Contents/Resources/BEE2.icns" >/dev/null 2>&1 ||
        echo "  (icon conversion failed: the app keeps the default icon)"
    codesign --force --deep --sign - "$APP" 2>/dev/null || true
    echo "  $APP"
fi

cat <<EOF

Done.
  1. Quit Portal 2 Natif if it is running.
  2. Open BEEmod, choose your items and style, then click Export.
  3. Open Portal 2 Natif > Create Test Chambers. Build and Play and
     Publish to the Workshop now go through BEEmod's compilers.

Log of the compilers: ~/Library/Logs/Portal2Natif-compiler.log
Do not "Verify integrity of game files" in Steam: it removes BEEmod's export
(export again from BEEmod if you do).
EOF
