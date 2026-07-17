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

## macOS controls and display

The macOS defaults avoid Control+Arrow, which is reserved by Mission Control
for switching Spaces. Hold Option with the arrow keys to rotate the camera, or
use `[` and `]` as dedicated rotation keys. Bindings remain customizable in the
in-game options.

KeeperFX keeps its original 8-bit, palette-based software renderer. On macOS,
a native Metal presenter uploads that indexed framebuffer as an `R8Uint`
texture, expands the original 6-bit VGA palette to its full range, and converts
it to linear sRGB. A conservative colour grade, adaptive luminance sharpening,
and stable palette dithering are then applied before an sRGB Metal attachment
performs the output transfer. High-contrast edges are excluded from sharpening
to preserve pixel-art UI. The game continues to render in logical macOS
coordinates while Metal scales to the Retina drawable's native pixels. The
presenter uses display synchronization and three resources in flight; the
original SDL surface path remains available as a fallback.

The native post-processing defaults can be tuned with macOS preferences. The
default values are `MetalSaturation=1.03`, `MetalContrast=1.015`,
`MetalSharpness=0.08`, and `MetalDither=0.75`. For example:

```sh
defaults write org.keeperfx.KeeperFX MetalSharpness -float 0
defaults write org.keeperfx.KeeperFX MetalSaturation -float 1
```

Delete an individual preference to restore its default. Changes take effect
the next time KeeperFX starts.

For crisp graphics, prefer resolutions that are integer multiples of the
original 320x200 frame, such as 1280x800 (4x) or 1600x1000 (5x). MetalFX is not
used: its spatial and temporal reconstruction targets lower-resolution 3D
render targets, while filtering KeeperFX's final palette image would soften
pixel art and the user interface.
