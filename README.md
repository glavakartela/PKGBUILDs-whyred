# PKGBUILDs for Xiaomi Redmi Note 5 Pro (whyred)

Packages for the mainline SDM636 / Adreno 509 setup.

| Package | Purpose |
|---|---|
| `linux-qcom-sdm636-whyred` | kernel |
| `device-xiaomi-whyred` | device config, firmware loader, UCM |
| `firmware-xiaomi-whyred` | firmware |
| `mesa-a5xx` | Mesa/GL + experimental Adreno 5xx Turnip ICD |
| `libcamera-whyred` | libcamera with SDM660 sensor properties |
| `whyred-venus` | Venus playback service, bookmarklet, clipboard watcher |
| `whyred-audio` | TAS2557/microphone routing helpers |

## Build

```sh
cd mesa-a5xx && makepkg -si
cd whyred-venus && makepkg -si
cd whyred-audio && makepkg -si
```

`mesa-a5xx` installs the test Turnip under `/usr/lib/turnip-a5xx` and
replaces the freedreno ICD, matching the existing whyred setup.  Back up
the stock Mesa/freedreno package before installing.

## Notes

- `libcamera-whyred` tracks the `sdm660-sensors` branch; it is a WIP
  package for the camera stack.
- `whyred-venus` installs user units under `/usr/lib/systemd/user`; enable
  them per user.  The Firefox bookmark service is a system unit.
- The TAS2557 v4 kernel patches and the whyred DT patch are not part of
  these packages; see the `whyred-mainline` branches and
  `7.2-whyred-audio-v4`.
