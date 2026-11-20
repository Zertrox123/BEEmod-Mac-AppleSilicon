#!/bin/bash
# Replace BEEmod 4.36's bundled Tcl/Tk 8.6.8 with Tcl/Tk 8.6.10.
#
# On current macOS, Tk 8.6.8 draws empty white windows, and Tk 8.6.16 loops
# forever in `update` while BEEmod builds its window. Tk 8.6.10 works. It is
# taken from the official python.org "python-3.9.1-macos11.0.pkg" (expanded
# with pkgutil, never installed): the x86_64 slices of libtcl8.6/libtk8.6, with
# their install names set to @loader_path, plus the tcl8.6, tk8.6 and tcl8
# script folders (tcl8 holds msgcat, needed when BEEmod starts from Finder).
#
# usage: fix-tk.sh <BEEmod folder> <python-3.9.1-macos11.0.pkg>
set -euo pipefail

BEE=${1:?usage: fix-tk.sh <BEEmod folder> <python-3.9.1-macos11.0.pkg>}
PKG=${2:?usage: fix-tk.sh <BEEmod folder> <python-3.9.1-macos11.0.pkg>}
[ -x "$BEE/BEE2" ] || { echo "error: $BEE/BEE2 not found" >&2; exit 1; }
[ -f "$PKG" ] || { echo "error: $PKG not found" >&2; exit 1; }

current=$(otool -L "$BEE/libtk8.6.dylib" 2>/dev/null | awk 'NR==2 {print $NF}' | tr -d ')')
if [ "$current" = "8.6.10" ] && [ -d "$BEE/tcl8" ]; then
    echo "Tk 8.6.10 already installed in $BEE"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/beemod-tk.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
echo "Expanding $(basename "$PKG")..."
pkgutil --expand-full "$PKG" "$WORK/pkg"
LIB="$WORK/pkg/Python_Framework.pkg/Payload/Versions/3.9/lib"
for f in libtcl8.6.dylib libtk8.6.dylib tcl8.6 tk8.6 tcl8; do
    [ -e "$LIB/$f" ] || { echo "error: $f missing from the package" >&2; exit 1; }
done

# Keep BEEmod's original files once, so uninstall.sh can put them back.
if [ ! -d "$BEE/_tk868_backup" ]; then
    mkdir "$BEE/_tk868_backup"
    for f in libtcl8.6.dylib libtk8.6.dylib tcl tk; do
        [ -e "$BEE/$f" ] && cp -R "$BEE/$f" "$BEE/_tk868_backup/"
    done
fi

for lib in libtcl8.6.dylib libtk8.6.dylib; do
    lipo -thin x86_64 "$LIB/$lib" -output "$WORK/$lib"
    install_name_tool -id "@loader_path/$lib" "$WORK/$lib" 2>/dev/null
    codesign --force --sign - "$WORK/$lib" 2>/dev/null
    cp "$WORK/$lib" "$BEE/$lib"
done
rm -rf "$BEE/tcl" "$BEE/tk" "$BEE/tcl8"
cp -R "$LIB/tcl8.6" "$BEE/tcl"
cp -R "$LIB/tk8.6" "$BEE/tk"
cp -R "$LIB/tcl8" "$BEE/tcl8"
echo "Tk 8.6.10 installed in $BEE"
