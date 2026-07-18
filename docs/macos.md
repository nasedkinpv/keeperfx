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

Run the bundled build with:

```sh
open bin/KeeperFX.app
```

Use the app bundle for testing and distribution. It includes the SDL3 runtime
used by Homebrew's current SDL2 compatibility library; running a copied bare
executable without its Homebrew libraries can otherwise fail with an SDL3 load
error. The raw `bin/keeperfx` executable remains useful for development.

## Game data

KeeperFX still requires the original Dungeon Keeper files as proof of
ownership. The app bundle reads the complete KeeperFX data set and the required
original files from:

```text
~/Library/Application Support/KeeperFX
```

The required original files are listed in
`docs/files_required_from_original_dk.txt`. They can be copied from an original
CD or a legitimately purchased digital edition.

The raw executable uses its current working directory. Set
`KEEPERFX_DATA_DIR` to use the app's data directory while debugging it:

```sh
KEEPERFX_DATA_DIR="$HOME/Library/Application Support/KeeperFX" bin/keeperfx
```

Runtime settings, saves, and `keeperfx.log` are written to the same data
directory.

## macOS controls and display

The macOS defaults avoid Control+Arrow, which is reserved by Mission Control
for switching Spaces. Hold Option with the arrow keys to rotate the camera, or
use `[` and `]` as dedicated rotation keys. Bindings remain customizable in the
in-game options.

Windowed modes use KeeperFX's `w32` video-mode suffix. For example, these
`keeperfx.cfg` values offer a 960x600 (3x) windowed game mode:

```ini
FRONTEND_RES=640x480w32 960x600w32 960x600w32
INGAME_RES=960x600w32
```

Select a configured windowed resolution in Graphics Options to leave
fullscreen.

KeeperFX keeps its original 8-bit, palette-based software renderer. On macOS,
a native Metal presenter uploads that indexed framebuffer as an `R8Uint`
texture, expands the original 6-bit VGA palette to its full range, and converts
it to linear sRGB. Neutral colour, adaptive luminance sharpening, and stable
palette dithering are then applied before an sRGB Metal attachment performs the
output transfer. High-contrast edges are excluded from sharpening to preserve
pixel-art UI. The game continues to render in logical macOS
coordinates while Metal scales to the Retina drawable's native pixels. The
presenter uses display synchronization and three resources in flight; the
original SDL surface path remains available as a fallback.

The native post-processing defaults can be tuned with macOS preferences. The
default values are `MetalSaturation=1.0`, `MetalContrast=1.0`,
`MetalSharpness=0.08`, and `MetalDither=0.75`. For example:

```sh
defaults write org.keeperfx.KeeperFX MetalSharpness -float 0
defaults write org.keeperfx.KeeperFX MetalSaturation -float 1
```

Delete an individual preference to restore its default. Changes take effect
the next time KeeperFX starts.

```sh
defaults delete org.keeperfx.KeeperFX MetalSaturation
defaults delete org.keeperfx.KeeperFX MetalContrast
```

KeeperFX's source art is SDR, so the presenter deliberately keeps it in the
standard 0.0-to-1.0 sRGB range instead of stretching it into macOS EDR. The
in-game brightness control applies the same black-point-aware, hue-preserving
palette tone curve on Metal and SDL renderers. This keeps the darkest palette
entries black instead of lifting them into a green cast.

For crisp graphics, prefer resolutions that are integer multiples of the
original 320x200 frame, such as 1280x800 (4x) or 1600x1000 (5x). MetalFX is not
used: its spatial and temporal reconstruction targets lower-resolution 3D
render targets, while filtering KeeperFX's final palette image would soften
pixel art and the user interface.
