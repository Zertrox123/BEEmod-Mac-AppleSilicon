#!/bin/bash
# Map compiler hook for BEEmod (BEE2.4) 4.36, the last release with a macOS
# build (Intel, runs under Rosetta).
#
# Install: copy this file to
#   ~/Library/Application Support/Portal 2 Natif/map-compiler-hook
# and make it executable. The app launcher then exports P2_MAP_COMPILER to it
# and P2_NATIVE_MAP_COMPILER to the bundled portal2-map-compiler.
#
# The game calls:  hook --images I --game-dir G --linux-root L --user-dir U --program P -- <args>
# Without a BEEmod export in G/bin, everything goes straight to the native
# compiler. With one, VBSP and VRAD go through BEEmod's macOS compilers
# (G/bin/vbsp_osx and vrad_osx). Those call back G/bin/vbsp_osx_original and
# vrad_osx_original: symlinks to this script, which then runs the native
# compiler.
#
# Files written by the game (preview.vmf, preview.bsp...) live in the user
# layer U; the native compiler sees them under G. Paths are translated G -> U
# for BEEmod and U -> G for the native compiler.

LOG="$HOME/Library/Logs/Portal2Natif-compiler.log"
log() { echo "[hook $(date '+%T')] $*" >>"$LOG"; }

self_name=$(basename "$0")
case "$self_name" in
    vbsp_osx_original|vrad_osx_original) MODE=original ;;
    *) MODE=hook ;;
esac

if [ "$MODE" = hook ]; then
    FIXED=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --images) FIXED+=("$1" "$2"); shift 2 ;;
            --game-dir) GAME=$2; FIXED+=("$1" "$2"); shift 2 ;;
            --linux-root) FIXED+=("$1" "$2"); shift 2 ;;
            --user-dir) USERDIR=$2; FIXED+=("$1" "$2"); shift 2 ;;
            --program) PROGRAM=$2; shift 2 ;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    { echo "=== $(date '+%F %T') program=$PROGRAM cwd=$PWD"; printf '%q ' "$@"; echo; } >>"$LOG"
    # Passed down to the "original" mode called by BEEmod.
    export P2_HOOK_FIXED_ARGS=$(printf '%q ' "${FIXED[@]}")
    export P2_HOOK_GAME="$GAME" P2_HOOK_USER="$USERDIR"
else
    GAME=$P2_HOOK_GAME; USERDIR=$P2_HOOK_USER
    eval "FIXED=($P2_HOOK_FIXED_ARGS)"
    case "$self_name" in vbsp_osx_original) PROGRAM=vbsp_linux ;; *) PROGRAM=vrad_dll.so ;; esac
    log "original $PROGRAM: $(printf '%q ' "$@")"
fi

NATIVE=${P2_NATIVE_MAP_COMPILER:?P2_NATIVE_MAP_COMPILER is not set}

# Game path (G/...) -> real file: the user layer if it is there.
to_host() {
    local p=$1 rel
    case "$p" in
        "$GAME"/*) rel=${p#"$GAME"/}
            if [ -e "$USERDIR/$rel" ] || [ -e "$USERDIR/$rel.vmf" ]; then echo "$USERDIR/$rel"; else echo "$p"; fi ;;
        *) echo "$p" ;;
    esac
}
# User layer file -> game path seen by the native compiler.
to_guest() {
    local p=$1
    case "$p" in "$USERDIR"/*) echo "$GAME/${p#"$USERDIR"/}" ;; *) echo "$p" ;; esac
}

run_native() {  # program, args...
    local program=$1; shift
    exec /usr/bin/arch -arm64 "$NATIVE" "${FIXED[@]}" --program "$program" -- "$@"
}

if [ "$MODE" = original ]; then
    args=(); for a in "$@"; do args+=("$(to_guest "$a")"); done
    run_native "$PROGRAM" "${args[@]}"
fi

BIN="$GAME/bin"
bee_ready() { [ -x "$BIN/vbsp_osx" ] && [ -x "$BIN/vrad_osx" ] && [ -f "$BIN/bee2/vbsp_config.cfg" ]; }

case "$PROGRAM" in
    vbsp_linux|vrad_dll.so)
        if ! bee_ready; then log "no BEEmod export: native compiler only"; run_native "$PROGRAM" "$@"; fi
        # BEEmod calls back <cwd>/<tool>_osx_original: this script.
        for tool in vbsp vrad; do
            ln -sf "$0" "$BIN/${tool}_osx_original"
        done
        # Valve's VBSP looks for instances under maps/styled/instances (Mac/Linux bug).
        mkdir -p "$GAME/sdk_content/maps/styled"
        # BEEmod's VRAD reads ../portal2/puzzles and ../portal2/screenshots from bin/;
        # the game writes them in the user layer.
        for sub in puzzles screenshots; do
            mkdir -p "$USERDIR/portal2/$sub"
            [ -e "$GAME/portal2/$sub" ] || [ -L "$GAME/portal2/$sub" ] || ln -s "$USERDIR/portal2/$sub" "$GAME/portal2/$sub"
        done
        # Only the last argument (the map) is translated; -game keeps the Steam data.
        args=("$@")
        last=$((${#args[@]} - 1))
        args[$last]=$(to_host "${args[$last]}")
        [ "$PROGRAM" = vbsp_linux ] && bee=vbsp_osx || bee=vrad_osx
        log "BEEmod $bee: $(printf '%q ' "${args[@]}")"
        cd "$BIN" || exit 1
        "$BIN/$bee" "${args[@]}" 2> >(tee -a "$LOG" >&2)
        status=$?
        log "BEEmod $bee exited ($status)"
        exit $status
        ;;
    *)
        run_native "$PROGRAM" "$@"
        ;;
esac
