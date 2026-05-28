{
  description = "Pure-source Nix flake for Donut Browser with hourly automated updates";

  nixConfig = {
    extra-substituters = [ "https://hassiyyt.cachix.org" ];
    extra-trusted-public-keys = [
      "hassiyyt.cachix.org-1:GPb2J+eS5AyHtVF9zQ+cchuQJl65WrxpcrdYsSiDjno="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
    }:
    let
      rustVersion = "1.95.0";
      donutOverlay = final: prev: {
        donutbrowser =
          let
            rustToolchain = final.rust-bin.stable.${rustVersion}.default;
            baseRustPlatform = final.makeRustPlatform {
              cargo = rustToolchain;
              rustc = rustToolchain;
            };
            # Override fetchCargoVendor to use a patched fetch-cargo-vendor-util.py
            # that sets a User-Agent header. crates.io returns 403 for unidentified
            # clients, which breaks the upstream v1 util shipped in the pinned
            # nixpkgs (rev 15c6719). This works around the issue without bumping
            # nixpkgs and breaking the rest of the stack.
            rustPlatform = baseRustPlatform // {
              fetchCargoVendor = final.callPackage ./nix/fetch-cargo-vendor.nix { };
            };
          in
          final.callPackage ./package.nix {
            cargo = rustToolchain;
            rustc = rustToolchain;
            inherit rustPlatform;
          };
      };
      overlay = nixpkgs.lib.composeManyExtensions [
        rust-overlay.overlays.default
        donutOverlay
      ];
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    flake-utils.lib.eachSystem supportedSystems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          default = pkgs.donutbrowser;
          donutbrowser = pkgs.donutbrowser;
          "pnpm-deps" = pkgs.donutbrowser.passthru.pnpmDeps;
          "cargo-deps" = pkgs.donutbrowser.passthru.cargoDeps;
        };

        apps = {
          default = {
            type = "app";
            program = "${pkgs.donutbrowser}/bin/donutbrowser";
          };
          donutbrowser = {
            type = "app";
            program = "${pkgs.donutbrowser}/bin/donutbrowser";
          };
        };

        checks.default = pkgs.donutbrowser;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cachix
            gh
            jq
            nix
            nixpkgs-fmt
          ];
        };

        formatter = pkgs.nixpkgs-fmt;
      }
    )
    // {
      overlays.default = overlay;
    };
}
