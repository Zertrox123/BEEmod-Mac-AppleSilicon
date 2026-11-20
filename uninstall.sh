#!/bin/bash
# Removes what install.sh added. Asks before each step; files go to the Trash.
#
# usage: ./uninstall.sh [--dir DIR] [--game "PORTAL 2 FOLDER"]
#
# Portal 2 Natif.app keeps its small launcher change: without the hook file it
# does nothing. Rebuild the app with source-recomp to drop it completely.
set -euo pipefail

BEE_DIR="$HOME/BEE2.4"
GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Portal 2"
while [ $# -gt 0 ]; do
    case "$1" in
        --dir) BEE_DIR=$2; shift 2 ;;
        --game) GAME_DIR=$2; shift 2 ;;
        *) echo "usage: ./uninstall.sh [--dir DIR] [--game DIR]" >&2; exit 2 ;;
    esac
done

ask() { local a=""; printf '%s [y/N] ' "$1"; read -r a || true; case "$a" in y|Y|yes|o|O|oui) return 0 ;; *) return 1 ;; esac; }
trash() {
    local dest="$HOME/.Trash/$(basename "$1")"
    [ -e "$dest" ] && dest="$dest $(date +%Y-%m-%d\ %H.%M.%S)"
    mv "$1" "$dest" && echo "  moved to the Trash: $1"
}

HOOK="$HOME/Library/Application Support/Portal 2 Natif/map-compiler-hook"
if [ -e "$HOOK" ] && ask "Remove the map compiler hook (Build and Play goes back to the plain compiler)?"; then
    trash "$HOOK"
fi
for tool in vbsp_osx_original vrad_osx_original; do
    if [ -L "$GAME_DIR/bin/$tool" ]; then rm "$GAME_DIR/bin/$tool"; fi
done

for app in /Applications/BEEmod.app "$HOME/Applications/BEEmod.app"; do
    if [ -e "$app" ] && ask "Remove $app?"; then trash "$app"; fi
done

if [ -d "$BEE_DIR" ] && ask "Remove BEEmod itself ($BEE_DIR, with its palettes and settings)?"; then
    trash "$BEE_DIR"
elif [ -d "$BEE_DIR/_tk868_backup" ] && ask "Put BEEmod's original Tcl/Tk 8.6.8 back?"; then
    rm -rf "$BEE_DIR/tcl" "$BEE_DIR/tk" "$BEE_DIR/tcl8"
    cp -R "$BEE_DIR/_tk868_backup/." "$BEE_DIR/"
    rm -rf "$BEE_DIR/_tk868_backup"
    echo "  restored"
fi

CFG="$HOME/Library/Preferences/BEEMOD2"
[ -d "$CFG" ] && ask "Remove BEEmod's preferences ($CFG)?" && trash "$CFG"
CACHE="$HOME/Library/Caches/BEEmod-Mac-AppleSilicon"
[ -d "$CACHE" ] && ask "Remove the downloads cache ($CACHE, about 370 MB)?" && trash "$CACHE"

cat <<EOF

BEEmod's export is still in the Portal 2 folder ($GAME_DIR: bin/, bee2/, portal2/).
To remove it, use "Verify integrity of game files" in Steam (Portal 2 >
Properties > Installed Files).
EOF
