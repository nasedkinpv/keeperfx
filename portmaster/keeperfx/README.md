# KeeperFX for PortMaster

Native AArch64 KeeperFX build for ROCKNIX and other PortMaster systems. The
engine is open source, but a legal Dungeon Keeper data set is required.

Copy the KeeperFX data directories (`campgns`, `creatrs`, `data`, `fxdata`,
`ldata`, `levels`, `music`, `sound`, and optionally `mods`, `multiplayer`, and
`save`) into `/roms/ports/keeperfx/`. Copy `keeperfx.cfg` there as well.

The launcher passes PortMaster's SDL controller mapping directly to KeeperFX.
KeeperFX has native controller support: left stick moves the camera, right
stick moves the pointer, triggers click, D-pad navigates UI, and Start opens
the pause menu.

The included configuration uses an explicit 720x720 SDL window for the
frontend, movies, and game. On direct KMS/DRM output this fills the RGB30 panel
and avoids relying on a desktop display mode that is not always exposed.

Build the AArch64 binary and its four bundled compatibility libraries from the
repository root:

```sh
docker build -f docker/portmaster-aarch64.Dockerfile \
  --build-arg GIT_REVISION="$(git rev-parse --short HEAD)" \
  --output type=local,dest=/tmp/keeperfx-portmaster .
```
