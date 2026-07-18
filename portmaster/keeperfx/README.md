# KeeperFX for PortMaster

Native AArch64 KeeperFX build for ROCKNIX and other PortMaster systems. The
engine is open source, but a legal Dungeon Keeper data set is required. The
package targets AArch64 systems with glibc 2.39 or newer and does not include
copyrighted game data.

## Build

Build the binary and its four compatibility libraries from the repository
root:

```sh
docker build -f docker/portmaster-aarch64.Dockerfile \
  --build-arg GIT_REVISION="$(git rev-parse --short HEAD)" \
  --output type=local,dest=/tmp/keeperfx-portmaster .
```

The output contains `keeperfx.aarch64` and `libs.aarch64/`. Install those with
the files under `portmaster/keeperfx/` so the device has this layout:

```text
/roms/ports/
├── KeeperFX.sh
└── keeperfx/
    ├── keeperfx.aarch64
    ├── keeperfx.cfg
    ├── libs.aarch64/
    └── game data directories
```

## Game data

Copy the KeeperFX data directories (`campgns`, `creatrs`, `data`, `fxdata`,
`ldata`, `levels`, `music`, `sound`, and optionally `mods`, `multiplayer`, and
`save`) into `/roms/ports/keeperfx/`. Copy `keeperfx.cfg` there as well.

## Controller

The launcher passes PortMaster's SDL controller mapping directly to KeeperFX.
The defaults are:

| Input | Action |
|---|---|
| Left stick | Move the camera |
| Right stick | Move the pointer |
| R2 / L2 | Left click / right click |
| D-pad | Navigate buttons and tabs |
| A + D-pad up/down | Zoom in/out |
| A + D-pad left/right | Rotate clockwise/counter-clockwise |
| Left stick click | Toggle the map |
| X / Y | Jump to a fight / Dungeon Heart |
| L1 / R1 | Previous/next possession instance |
| Start | Pause or close the active pause menu |
| Start + Back | Exit KeeperFX |

Controller chords remain active after D-pad navigation, so zoom and rotation
do not require moving the pointer away from a UI button first.

## Square display layout

The included configuration uses an explicit 720x720 SDL window for the
frontend, movies, and game. On direct KMS/DRM output this fills the RGB30 panel
and avoids relying on a desktop display mode that is not always exposed.

At 720x720, and automatically on similarly square or portrait displays at
least 720 pixels wide, the vertical status panel becomes a compact 80-pixel
bottom strip. The minimap keeps its original size and overlaps the lower-left
of the game view; catalog, creature, query, and activity controls are aligned
to its right. Event icons stack above the minimap, while bottom dialogs and
tooltips stay above the strip. Wider displays retain KeeperFX's original side
panel.

## Runtime notes

The supplied `keeperfx.cfg` skips startup movies and disables edge scrolling,
which is awkward with a controller. Brightness uses the same black-point-aware,
hue-preserving palette curve as the macOS Metal build, preventing near-black
green palette entries from being amplified.

PortMaster launcher output is written to `/roms/ports/keeperfx/log.txt`; engine
diagnostics are written to `/roms/ports/keeperfx/keeperfx.log`. User settings,
including gamma and minimap zoom, are stored in
`/roms/ports/keeperfx/save/settings.toml`.
