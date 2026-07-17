# Native macOS build

KeeperFX can run natively on Apple Silicon. The macOS build uses the existing
POSIX and SDL code paths and produces an arm64 Mach-O executable; Wine and
Rosetta are not involved.

## Prerequisites

Install Xcode command-line tools and the build dependencies:

```sh
brew install cmake pkgconf sdl2 sdl2_mixer sdl2_net sdl2_image ffmpeg \
  openal-soft luajit libspng minizip miniupnpc libnatpmp curl
```

The makefile downloads pinned sources for Astronomy Engine, CentiJSON, and
ENet6 and builds those three libraries locally for arm64.

## Build

```sh
make -f macos.mk -j"$(sysctl -n hw.logicalcpu)"
make -f macos.mk app
```

The executable is written to `bin/keeperfx` and the self-contained app bundle
to `bin/KeeperFX.app`. The app includes its non-system dynamic libraries and is
ad-hoc signed by default. A Developer ID build can be created with
`CODESIGN_IDENTITY`; distribution also requires Apple's normal notarization
workflow.

## Game data

KeeperFX still requires the original Dungeon Keeper files as proof of
ownership. Install the complete KeeperFX data set and the required original
files in:

```text
~/Library/Application Support/KeeperFX
```

The required original files are listed in
`docs/files_required_from_original_dk.txt`. They can be copied from an original
CD or a legitimately purchased digital edition.
