# BEEmod on Apple Silicon Macs

Run **BEEmod (BEE2.4) 4.36** on an Apple Silicon Mac and use its items in the
Portal 2 Puzzle Maker, with **Build and Play** and **Workshop publishing**
working, through the native **Portal 2 Natif** app from
[source-recomp](https://github.com/kanapitsas/source-recomp).

One script sets everything up:

```sh
git clone https://github.com/Zertrox123/BEEmod-Mac-AppleSilicon.git
cd BEEmod-Mac-AppleSilicon
./install.sh
```

Then open **BEEmod**, pick your items, click **Export**, and start
**Portal 2 Natif** > *Create Test Chambers*.

> Unofficial community project, not affiliated with Valve or the BEEmod team.
> Nothing from Valve or BEEmod is in this repository: BEEmod and the Tcl/Tk
> libraries are downloaded from their official releases on your Mac, and their
> SHA-256 is checked.

## Why this is needed

Portal 2 on macOS is a 32-bit Intel game. Recent Macs cannot run it, and
Valve's macOS map compilers (`vbsp_osx`, `vvis_osx`, `vrad_osx`) are no longer
shipped. [source-recomp](https://github.com/kanapitsas/source-recomp) rebuilds
Portal 2 and its map compilers natively for Apple Silicon. BEEmod 4.36 (the
last version with a macOS build) still needs several fixes on top of that:

| Problem | Fix |
|---|---|
| BEEmod is an Intel app | Runs under Rosetta 2 (`BEEmod.app`) |
| Tcl/Tk 8.6.8 draws **blank white windows** on current macOS (and 8.6.16 hangs on start) | Replaced with Tcl/Tk **8.6.10**, extracted from the official python.org 3.9.1 package |
| `msgcat` error / `'NoneType' object has no attribute 'lower'` when started from Finder | `tcl8` folder added, and the app sets a locale |
| The game picker only accepts `.exe` files | `games.cfg` written for you |
| BEEmod's compilers call Valve's missing `vbsp_osx_original`/`vrad_osx_original` | A map compiler hook routes them to Portal 2 Natif's native compilers |
| Game and user files live in two layers in Portal 2 Natif | The hook translates paths and links `portal2/puzzles` and `portal2/screenshots` |
| **Purple placeholder icons** in the editor palette | `Game "BEE2"` in `gameinfo.txt` is anchored to the game root (on a case-insensitive disk, `bin/BEE2` is BEEmod's `bin/bee2` config folder) |

## Requirements

- An Apple Silicon Mac. Intel Macs can run BEEmod natively, but the hook and
  the Tk fix still apply.
- **Rosetta 2**: `softwareupdate --install-rosetta --agree-to-license`
- The **Xcode Command Line Tools**: `xcode-select --install`
- **Portal 2** installed with Steam, which you must own.
- **Portal 2 Natif** built with the Puzzle Maker compilers. In a
  [source-recomp](https://github.com/kanapitsas/source-recomp) checkout, run
  `./setup.sh --game portal2 --puzzle-maker`, or tick *Puzzle Maker* in its
  installer. This gives you `~/Applications/Portal 2 Natif.app`.
- About 1.2 GB of free space: 370 MB of downloads, kept in a cache, plus BEEmod
  and its items.

## What `install.sh` does

1. Checks the Mac, Rosetta and the tools, and finds Portal 2
   (`~/Library/Application Support/Steam/steamapps/common/Portal 2`).
2. Downloads and checks (SHA-256):
   - `BEE2_4.36.0_mac_old.zip` (BEEmod application)
   - `BEE2_v4.36.0_packages_old.zip` (BEEmod items)
   - `python-3.9.1-macos11.0.pkg` (used only as a source of Tcl/Tk 8.6.10, and never installed)
3. Unpacks BEEmod into `~/BEE2.4` and swaps its Tcl/Tk (the originals are kept
   in `~/BEE2.4/_tk868_backup`).
4. Writes `~/Library/Preferences/BEEMOD2/config/games.cfg`.
5. Installs the hook at
   `~/Library/Application Support/Portal 2 Natif/map-compiler-hook`, then
   patches `Portal 2 Natif.app` so that it uses the hook and fixes the
   palette icons. The script re-signs the app ad hoc.
6. Creates `BEEmod.app` in `/Applications`, or in `~/Applications` if
   `/Applications` is not writable.

Every step can be run again. Your BEEmod settings and palettes are kept.

Options:

```
./install.sh --dir ~/BEE2.4                     # where BEEmod goes
             --game "/path/to/Portal 2"          # Portal 2 folder, if not found
             --portal2-app "/path/to/Portal 2 Natif.app"
             --apps-dir ~/Applications           # where BEEmod.app goes
             --downloads DIR                     # download cache
             --no-app                            # do not create BEEmod.app
```

## Using it

1. Quit Portal 2 Natif.
2. Open **BEEmod**, choose a style and items, and click **Export**. BEEmod
   writes into the Steam Portal 2 folder.
3. Open **Portal 2 Natif**, then *Create Test Chambers*. BEEmod's items are in
   the palette.
4. **Build and Play** compiles with BEEmod's VBSP and VRAD, which call the
   native compilers. **Publish to the Workshop** works too.

The compiler log is in `~/Library/Logs/Portal2Natif-compiler.log`. BEEmod's
own log is in `~/BEE2.4/logs/`.

## If you rebuild Portal 2 Natif

`make_app.py` (source-recomp) writes a fresh app, which undoes the patch from
step 5. Run `./install.sh` again (it is quick), or use one of these options:

- `python3 scripts/patch-portal2-natif.py "~/Applications/Portal 2 Natif.app"`
- Apply [`patches/source-recomp-beemod.patch`](patches/source-recomp-beemod.patch)
  to your source-recomp checkout (`git apply`) so that every rebuild includes
  it. The patch also adds tests and documentation.

## Troubleshooting

| Symptom | What to do |
|---|---|
| BEEmod windows are empty or white | Tk was not replaced: run `./install.sh` again. |
| BEEmod stays on its splash screen | Same cause (Tk 8.6.16 hang): run `./install.sh` again. |
| "Build error" in the editor | Read `~/Library/Logs/Portal2Natif-compiler.log`. Some BEEmod items can make the map leak or fail. Remove the last item you added and try again. |
| Purple icons in the palette | Export again from BEEmod, then restart Portal 2 Natif. If they stay purple, run `./install.sh` again (the app patch was undone). |
| BEEmod items vanished from the game | Steam's *Verify integrity of game files* removes BEEmod's export: export again. |
| `Rosetta 2 is not installed` | `softwareupdate --install-rosetta --agree-to-license` |

## Uninstall

```sh
./uninstall.sh
```

The script asks before each step and moves files to the Trash. BEEmod's export
stays in the Portal 2 folder until you run *Verify integrity of game files* in
Steam.

## Files

```
install.sh                       one-step installer
uninstall.sh                     removes what install.sh added
scripts/fix-tk.sh                Tcl/Tk 8.6.8 -> 8.6.10 for BEEmod
scripts/map-compiler-hook.sh     routes BEEmod's compilers to Portal 2 Natif's
scripts/patch-portal2-natif.py   patches an installed Portal 2 Natif.app
patches/source-recomp-beemod.patch  the same support for a source-recomp checkout
```

## License

[MIT](LICENSE) for the files in this repository. BEEmod, Portal 2, Tcl/Tk and
Python keep their own licenses. They are downloaded from their official
sources, not redistributed here. Portal, Portal 2 and Steam are trademarks of
Valve Corporation.
