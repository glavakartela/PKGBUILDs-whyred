# PKGBUILDs for Xiaomi Redmi Note 5 Pro (whyred)

Packages for the mainline SDM636 / Adreno 509 setup.

| Package | Purpose |
|---|---|
| `sdm660-linux` | kernel from `sdm660-mainline/linux` (`qcom-sdm660-7.2.y`) |
| `sdm660-linux-whyred` | kernel from `glavakartela/whyred-mainline` (`7.2-cpu-osm`) |
| `device-xiaomi-whyred` | device config, firmware loader, UCM |
| `firmware-xiaomi-whyred` | firmware |
| `sdm660-mesa-a5xx` | Mesa/GL + experimental Adreno 5xx Turnip ICD |
| `sdm660-libcamera` | libcamera with SDM660 sensor properties |
| `sdm660-venus` | Venus playback service, bookmarklet, clipboard watcher |
| `sdm660-audio` | TAS2557/microphone routing helpers |
| `sdm660-sensors` | Qualcomm Sensor Core udev rules (accelerometer, light, proximity) |

The CI also rebuilds the existing `device-xiaomi-whyred`,
`firmware-xiaomi-whyred`, `bootmac`, `buffyboard`, `pd-mapper`,
`qbootctl`, `qcom-diag`, `qrtr`, `rmtfs` and `tqftpserv` packages.

## Build

```sh
cd sdm660-mesa-a5xx && makepkg -si
cd sdm660-venus && makepkg -si
cd sdm660-audio && makepkg -si
```

`sdm660-mesa-a5xx` installs the test Turnip under `/usr/lib/turnip-a5xx`
and replaces the freedreno ICD, matching the existing whyred setup.  Back
up the stock Mesa/freedreno package before installing.

Both kernel packages install the same boot/module files and conflict with
each other; install the one you want.

## Auto-update and CI

PKGBUILDs with

```sh
# AutoUpdate: <owner/repo> <branch>
```

are updated by `scripts/autoupdate.sh`: `_commit` is replaced with the
branch head, `pkgrel` gets a UTC timestamp, and the change is committed
with `[skip ci]`.

The GitHub Actions workflow discovers every directory with a `PKGBUILD`,
builds it in an Arch Linux ARM container on `ubuntu-24.04-arm`, then
publishes the packages to
<https://github.com/glavakartela/whyred-alarm> (GitHub Pages pacman
repository).

Create a fine-grained PAT with **Contents: read/write** on
`glavakartela/whyred-alarm` and add it as the repository secret
`WHYRED_ALARM_TOKEN`.  The workflow uses the normal `GITHUB_TOKEN` for
auto-update commits in this repository.  Scheduled runs happen every six
hours; a push to `main` triggers a build too.

Pacman:

```conf
[whyred]
SigLevel = Optional
Server = https://glavakartela.github.io/whyred-alarm/repo/
```

## Notes

- `sdm660-libcamera` tracks the `sdm660-sensors` branch; it is WIP for the
  camera stack.
- `sdm660-venus` installs user units under `/usr/lib/systemd/user`; enable
  them per user.  The Firefox bookmark service is a system unit.
- `sdm660-sensors` uses the Arch `libssc` and `iio-sensor-proxy` packages.
  It adds the missing `ssc-proximity` and `ssc-accel` udev tags for the
  whyred ADSP; test with `ssccli` and `monitor-sensor`.
- The TAS2557 v4 kernel patches and the whyred DT patch are in the
  `whyred-mainline` branches and `opencode/audio-v4-patches`, not in these
  packages.
