{
  lib,
  stdenv,
  fetchFromGitHub,
  alsa-lib,
  fetchPnpmDeps,
  patchelf,
  pnpmConfigHook,
  pnpm,
  nodejs,
  cargo,
  cargo-tauri,
  rustc,
  rustPlatform,
  pkg-config,
  jq,
  moreutils,
  makeWrapper,
  wrapGAppsHook3,
  xdg-utils,
  xdotool,
  nspr,
  nss,
  libdrm,
  libgbm,
  libxkbcommon,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,
  libxshmfence,
  libxtst,
  libxi,
  libxrender,
  libxinerama,
  libxcursor,
  libxscrnsaver,
  fontconfig,
  freetype,
  fribidi,
  harfbuzz,
  expat,
  libglvnd,
  libgpg-error,
  e2fsprogs,
  gmp,
  zlib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cups,
  cairo,
  dbus,
  gdk-pixbuf,
  glib,
  gtk3,
  libsoup_3,
  openssl,
  systemd,
  pango,
  webkitgtk_4_1,
  gst_all_1,
  libayatana-appindicator,
}:

let
  pname = "donutbrowser";
  version = "0.29.4";
  srcHash = "sha256-UAo/W4C4WqAVrUajao+OWeKKl7yluDSLWjFzrTbf2ZA=";
  pnpmDepsHash = "sha256-LAoNiVGTtYEEOCcdRH0av/bg1QPw0/plyF84JlN6XPk=";
  cargoDepsHash = "sha256-DGlbSM9kt0Ap2vEBSg31ZUG+w900kaaXxPenHKM1XsA=";

  src = fetchFromGitHub {
    owner = "zhom";
    repo = "donutbrowser";
    tag = "v${version}";
    hash = srcHash;
  };

  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = pnpmDepsHash;
    # Large tarballs (next, @next/swc, @biomejs/cli) can exceed pnpm's default
    # 60s fetch timeout on slow CI links. Bump timeouts/retries so the frozen
    # install is resilient.
    pnpmInstallFlags = [
      "--fetch-timeout=600000"
      "--fetch-retries=5"
      "--fetch-retry-mintimeout=10000"
    ];
  };

  rawCargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    hash = cargoDepsHash;
    cargoRoot = "src-tauri";
  };

  cargoDeps = rawCargoDeps;

  runtimeLibs = [
    webkitgtk_4_1
    libsoup_3
    glib
    gtk3
    cairo
    gdk-pixbuf
    pango
    atk
    at-spi2-atk
    at-spi2-core
    dbus
    alsa-lib
    nss
    nspr
    libdrm
    libgbm
    libxkbcommon
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    libxshmfence
    libxtst
    libxi
    xdotool
    (lib.getLib cups)
    libxrender
    libxinerama
    libxcursor
    libxscrnsaver
    fontconfig
    freetype
    fribidi
    harfbuzz
    expat
    libglvnd
    libgpg-error
    e2fsprogs
    gmp
    zlib
    (lib.getLib systemd)
    stdenv.cc.cc.lib
    libayatana-appindicator
  ];

  runtimeLibPath = lib.makeLibraryPath runtimeLibs;
in
stdenv.mkDerivation {
  inherit pname version src pnpmDeps cargoDeps;
  cargoRoot = "src-tauri";

  patches = [
    ./patches/default-browser-feedback.patch
    ./patches/linux-runtime-prep.patch
    ./patches/nix-store-app-updates.patch
    ./patches/no-network-fonts.patch
    ./patches/preserve-manual-downloads.patch
    ./patches/quiet-sidecar-builds.patch
  ];

  nativeBuildInputs = [
    cargo
    cargo-tauri
    nodejs
    pnpm
    pnpmConfigHook
    pkg-config
    jq
    moreutils
    makeWrapper
    rustc
    rustPlatform.cargoSetupHook
    wrapGAppsHook3
  ];

  buildInputs = [
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    dbus
    alsa-lib
    gdk-pixbuf
    glib
    gtk3
    libsoup_3
    openssl
    pango
    webkitgtk_4_1
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
    xdotool
    (lib.getLib cups)
    nspr
    nss
    libdrm
    libgbm
    libxkbcommon
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    libxshmfence
    libxtst
    libxi
    libxrender
    libxinerama
    libxcursor
    libxscrnsaver
    fontconfig
    freetype
    fribidi
    harfbuzz
    expat
    libglvnd
    libgpg-error
    e2fsprogs
    gmp
    zlib
    (lib.getLib systemd)
    libayatana-appindicator
  ];

  prePatch = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
  '';

  postPatch = ''
    jq '
      .build.beforeBuildCommand = "" |
      .bundle.targets = ["deb"] |
      .bundle.externalBin = ["binaries/donut-proxy"] |
      .bundle.resources = ( .bundle.resources // {} | del(."binaries/xray-LICENSE.txt") )
    ' src-tauri/tauri.conf.json | sponge src-tauri/tauri.conf.json

    jq 'del(.scripts.prebuild)' package.json | sponge package.json
  '';

  buildPhase = ''
    runHook preBuild

    target="$(rustc -vV | sed -n 's/^host: //p')"

    mkdir -p dist
    if [ ! -f dist/index.html ]; then
      cat > dist/index.html <<'EOF'
<!DOCTYPE html>
<html><head></head><body></body></html>
EOF
    fi

    export DONUT_SIDECAR_BUILD=1
    cargo build --manifest-path src-tauri/Cargo.toml --release --bin donut-proxy
    unset DONUT_SIDECAR_BUILD

    install -Dm755 src-tauri/target/release/donut-proxy "src-tauri/binaries/donut-proxy-$target"

    pnpm exec next build

    (
      cd src-tauri
      cargo tauri build --bundles deb
    )

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"

    shopt -s nullglob
    debRoots=(src-tauri/target/release/bundle/deb/*/data/usr)
    shopt -u nullglob

    if [ "''${#debRoots[@]}" -eq 0 ]; then
      echo "No bundled deb payload found under src-tauri/target/release/bundle/deb" >&2
      exit 1
    fi

    cp -a "''${debRoots[0]}"/* "$out"/

    if [ -f "$out/share/applications/Donut.desktop" ]; then
      mv "$out/share/applications/Donut.desktop" "$out/share/applications/donutbrowser.desktop"
      ln -s donutbrowser.desktop "$out/share/applications/Donut.desktop"
    fi

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}
      --set NIX_LD ${stdenv.cc.bintools.dynamicLinker}
      --prefix NIX_LD_LIBRARY_PATH : ${runtimeLibPath}
      --prefix LD_LIBRARY_PATH : ${runtimeLibPath}
      --set-default MOZ_ENABLE_WAYLAND 1
      --set-default GDK_BACKEND wayland,x11
      --set DONUT_PATCHELF_BIN ${patchelf}/bin/patchelf
    )
  '';

  dontWrapGApps = false;

  passthru = {
    inherit cargoDeps pnpmDeps src;
    updateScript = ./scripts/update-version.sh;
  };

  meta = with lib; {
    description = "Open source anti-detect browser built from source";
    homepage = "https://github.com/zhom/donutbrowser";
    license = licenses.agpl3Only;
    mainProgram = "donutbrowser";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
