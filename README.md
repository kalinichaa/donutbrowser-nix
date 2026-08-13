# donutbrowser-nix

Pure-source Nix flake for [Donut Browser](https://github.com/zhom/donutbrowser).

This flake exposes:

- `packages.<system>.{default,donutbrowser}`
- `apps.<system>.{default,donutbrowser}`
- `checks.<system>.default`
- `overlays.default`

## Requirements

- Linux with flakes enabled
- Supported systems:
  - `x86_64-linux`
  - `aarch64-linux`

## Try Without Installing

Run directly from GitHub:

```bash
nix run github:kalinichaa/donutbrowser-nix#donutbrowser
```

Run from a local checkout:

```bash
nix run .#donutbrowser
```

## Install For One User

Install into your current user profile from GitHub:

```bash
nix profile install github:kalinichaa/donutbrowser-nix#donutbrowser
```

Install from a local checkout:

```bash
nix profile install .#donutbrowser
```

The installed executable is:

```bash
donutbrowser
```

## Install System-Wide On NixOS

Add the flake as an input in your `flake.nix`:

```nix
{
  inputs.donutbrowser.url = "github:kalinichaa/donutbrowser-nix";
}
```

Then install it system-wide:

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.donutbrowser.packages.${pkgs.system}.donutbrowser
  ];
}
```

### Optional Overlay Style

If you prefer using `pkgs.donutbrowser`:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.donutbrowser.overlays.default ];
}
```

Then:

```nix
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.donutbrowser ];
}
```

## Install With Home Manager

Add the same flake input:

```nix
{
  inputs.donutbrowser.url = "github:kalinichaa/donutbrowser-nix";
}
```

Then add the package to `home.packages`:

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.donutbrowser.packages.${pkgs.system}.donutbrowser
  ];
}
```

### Optional Overlay Style

If you already use overlays in Home Manager:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.donutbrowser.overlays.default ];
}
```

Then:

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.donutbrowser ];
}
```

## Flake Usage In Another `flake.nix`

You can reference this flake from another flake in any of these ways:

From GitHub:

```nix
inputs.donutbrowser.url = "github:kalinichaa/donutbrowser-nix";
```

From a local checkout:

```nix
inputs.donutbrowser.url = "path:/home/h/dev/donutbrowser-nix";
```

Or from the current directory while working inside the repo:

```bash
nix build .#donutbrowser
nix run .#donutbrowser
nix flake check
```

## Updating Nix Installs

When Donut Browser is launched from the Nix store, upstream app updates are applied through Nix instead of the in-app `.deb`/`.rpm` installer. Update the flake input in the consuming configuration, then rebuild or switch that profile:

```bash
nix flake update donutbrowser --flake /path/to/config
```

## Using Cachix

### With Cachix Automatically

This flake already declares:

- `https://hassiyyt.cachix.org`
- `hassiyyt.cachix.org-1:GPb2J+eS5AyHtVF9zQ+cchuQJl65WrxpcrdYsSiDjno=`

If your Nix setup accepts flake-provided cache settings, `nix run`, `nix build`, `nix profile install`, NixOS, and Home Manager can use the cache automatically.

### Without Cachix Or Without Trusting Flake Config

The flake still works without Cachix, but builds will be slower because more work happens locally.

If you want to trust the cache globally instead of relying on flake config, add this to your Nix settings:

```nix
{
  nix.settings = {
    extra-substituters = [ "https://hassiyyt.cachix.org" ];
    extra-trusted-public-keys = [
      "hassiyyt.cachix.org-1:GPb2J+eS5AyHtVF9zQ+cchuQJl65WrxpcrdYsSiDjno="
    ];
  };
}
```

## Wayland And Xorg

The package wrapper is tuned for Linux desktop use and sets:

- `NIX_LD`
- `NIX_LD_LIBRARY_PATH`
- `LD_LIBRARY_PATH`
- `PLAYWRIGHT_NODEJS_PATH`
- `DONUT_PATCHELF_BIN`
- `MOZ_ENABLE_WAYLAND=1` by default
- `GDK_BACKEND=wayland,x11` by default

Managed browser binaries such as Wayfern and Camoufox are launched on NixOS through the package-provided runtime setup, so a separate system `programs.nix-ld` configuration is not required.

### Wayland

For Wayland sessions, the default launch path is recommended:

```bash
donutbrowser
```

If you want to force a pure Wayland launch check:

```bash
env -u DISPLAY GDK_BACKEND=wayland donutbrowser
```

### Xorg / X11

Xorg is supported too. In many X11 sessions, the default launch path already works:

```bash
donutbrowser
```

If you want to force X11 explicitly:

```bash
env GDK_BACKEND=x11 MOZ_ENABLE_WAYLAND=0 donutbrowser
```

## Flake Outputs

This repository exports:

- `packages.<system>.default`
- `packages.<system>.donutbrowser`
- `packages.<system>.pnpm-deps`
- `packages.<system>.cargo-deps`
- `apps.<system>.default`
- `apps.<system>.donutbrowser`
- `checks.<system>.default`
- `overlays.default`

## Development

Build exactly what CI builds:

```bash
nix build .#donutbrowser --print-build-logs
```

Run the packaged app locally:

```bash
nix run .#donutbrowser
```

Check the flake for the current system:

```bash
nix flake check
```

Update to the latest upstream Donut Browser release:

```bash
./scripts/update-version.sh
```

Check whether a newer release exists:

```bash
./scripts/update-version.sh --check
```

Refresh carried packaging patches against a specific upstream release. This uses your local `~/dev/donutbrowser` checkout if present, otherwise it clones upstream automatically:

```bash
./scripts/refresh-patches.sh --version 0.20.4
```

Repository automation and required GitHub settings are documented in [`./.github/REPOSITORY_SETTINGS.md`](./.github/REPOSITORY_SETTINGS.md).
