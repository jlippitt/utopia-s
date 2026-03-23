# Utopia-S

In-progress multi-emulator in Zig

Available cores:

| System      | Status                                                                           |
|-------------|----------------------------------------------------------------------------------|
| Game Boy    | Very early stages                                                                |
| NES         | Playable. Supported mappers: NROM, UxROM, CNROM, AxROM, MMC1                     |
| Nintendo 64 | Some games playable. Many graphical glitches. Some games have frame rate issues. |

## How to build

### Linux

* Install [Zig 0.15.2](https://ziglang.org/download/)
* Install your distribution's equivalent of Ubuntu's `glsl-tools` (needed for `glslangValidator` in order to compile shaders)

```
zig build --release=safe
```

`utopia-cli` binary can then be found in the `./zig-out/bin` directory.

(Building with `--release=fast` may give slightly better frame rates, but use at your own risk)

### OS X

Not currently supported, but in theory should be relatively easy to do. Zig and `glslangValidator` can both be installed via
Homebrew. Extra shader build stage would need to be added to convert GLSL shaders into MSL shaders via
[SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross).

### Windows

You're on your own.

## How to run

```
utopia-cli <app-options> <system> <rom-path>
```

where `<system>` is one of `gb`, `nes` or `n64` (see above)

Available options:

| Option                          | Description                                                    | Default                    |
|---------------------------------|----------------------------------------------------------------|----------------------------|
| `-b, --bios-path <path>`        | Path where BIOS files are located (see below)                  | Same directory as ROM file |
| `-s, --save-path <path>`        | Path where save files are located (see below)                  | Same directory as ROM file |
| `-i, --save-interval <seconds>` | How often to sync save files to disk while emulator is running | 30 seconds                 |
| `-f, --full-screen`             | Start in full screen mode                                      |                            |
| `-n, --no-fps-limit`            | Disables FPS limiter (also disables audio)                     |                            |

### Bios files

Some cores require BIOS or boot ROM files

| System      | File name      | Required |
|-------------|----------------|----------|
| Game Boy    | `dmg_boot.bin` | Yes*     |
| Nintendo 64 | `pifdata.bin`  | Yes*     |

\* There are future plans to make this optional

These files are not provided by this project

### Save files

Save files are stored as `<rom-name>.sav` or `<rom-name>.<save_type>.sav`. Existing save files are loaded on start-up. New data
is synced to disk periodically as the application is running (see `--save-interval` option), and automatically when the application
closes.

## How to play

Game controller support is available (it must be plugged in when the application starts) as well keyboard controls for 2D systems:

| Button   | Equivalent Key |
|----------|----------------|
| A        | X              |
| B        | Z              |
| Select   | Space bar      |
| Start    | Enter          |
| D-Pad    | Arrow keys     |

Additional keyboard controls (all systems):

| Key    | Description                        |
|--------|------------------------------------|
| F11    | Toggle full screen mode on/off     |
| Escape | Save data and exit the application |
