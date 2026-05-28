{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
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
  runCommand,
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
}:

let
  pname = "donutbrowser";
  version = "0.24.4";
  srcHash = "sha256-lYKBKD3uO6XoS1O0yN0VdhzWagu8ejukvx/L+2Xa4a8=";
  pnpmDepsHash = "sha256-oITwfGNy/ZnHQLBrBEifjOi8VfUpD2OHhcsyqX+0eQ4=";
  cargoDepsHash = "sha256-Ur9K9KeGSHD2ODeuANyFv+z6mddbsS2WpWZZj0m0F7A=";
  playwrightDriverVersion = "1.57.0";
  playwrightDriverHash = "sha256-Z/l4EEYEIpKZsIyK5BufxJsgtdbX3WDCNIoj8qvJlJ8=";
  playwrightDriverReleaseSegment =
    if
      lib.hasInfix "next" playwrightDriverVersion
      || lib.hasInfix "alpha" playwrightDriverVersion
      || lib.hasInfix "beta" playwrightDriverVersion
    then
      "/next"
    else
      "";

  src = fetchFromGitHub {
    owner = "zhom";
    repo = "donutbrowser";
    tag = "v${version}";
    hash = srcHash;
  };

  playwrightDriverZip = fetchurl {
    url = "https://playwright.azureedge.net/builds/driver${playwrightDriverReleaseSegment}/playwright-${playwrightDriverVersion}-linux.zip";
    hash = playwrightDriverHash;
  };

  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = pnpmDepsHash;
  };

  rawCargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    hash = cargoDepsHash;
    cargoRoot = "src-tauri";
  };

  cargoDeps = runCommand "${pname}-${version}-cargo-deps" { } ''
    cp -a ${rawCargoDeps} "$out"
    chmod -R u+w "$out"

    playwright_vendor_dir="$(
      find "$out" -path '*/playwright-*/src/build.rs' -print -quit
    )"
    if [ -z "$playwright_vendor_dir" ]; then
      echo "Could not find vendored playwright-rust build.rs under cargo deps" >&2
      exit 1
    fi
    playwright_vendor_dir="$(dirname "$playwright_vendor_dir")"

    if [ ! -d "$playwright_vendor_dir/imp/core" ]; then
      echo "Unexpected playwright-rust layout: missing src/imp/core" >&2
      exit 1
    fi

    cat > "$playwright_vendor_dir/build.rs" <<'EOF'
use std::{
    env, fmt, fs,
    fs::File,
    path::{Path, PathBuf, MAIN_SEPARATOR},
};

const DRIVER_VERSION: &str = "${playwrightDriverVersion}";

fn main() {
    let out_dir: PathBuf = env::var_os("OUT_DIR").unwrap().into();
    let dest = out_dir.join("driver.zip");
    let platform = PlaywrightPlatform::default();
    fs::write(out_dir.join("platform"), platform.to_string()).unwrap();
    println!("cargo:rerun-if-env-changed=PLAYWRIGHT_DRIVER_ZIP");
    if let Some(path) = env::var_os("PLAYWRIGHT_DRIVER_ZIP") {
        fs::copy(path, &dest).unwrap();
    } else {
        download(&url(platform), &dest);
    }
    println!("cargo:rerun-if-changed=src/build.rs");
    println!("cargo:rustc-env=SEP={}", MAIN_SEPARATOR);
}

#[cfg(all(not(feature = "only-for-docs-rs"), not(unix)))]
fn download(url: &str, dest: &Path) {
    let mut resp = reqwest::blocking::get(url).unwrap();
    let mut dest = File::create(dest).unwrap();
    resp.copy_to(&mut dest).unwrap();
}

#[cfg(all(not(feature = "only-for-docs-rs"), unix))]
fn download(url: &str, dest: &Path) {
    let cache_dir: &Path = "/tmp/build-playwright-rust".as_ref();
    let cached = cache_dir.join("driver.zip");
    if cfg!(debug_assertions) {
        let maybe_metadata = cached.metadata().ok();
        let cache_is_file = || {
            maybe_metadata
                .as_ref()
                .map(fs::Metadata::is_file)
                .unwrap_or_default()
        };
        let cache_size = || {
            maybe_metadata
                .as_ref()
                .map(fs::Metadata::len)
                .unwrap_or_default()
        };
        if cache_is_file() && cache_size() > 10000000 {
            fs::copy(cached, dest).unwrap();
            return;
        }
    }
    let mut resp = reqwest::blocking::get(url).unwrap();
    let mut dest_file = File::create(dest).unwrap();
    resp.copy_to(&mut dest_file).unwrap();
    if cfg!(debug_assertions) {
        fs::create_dir_all(cache_dir).unwrap();
        fs::copy(dest, cached).unwrap();
    }
}

fn size(p: &Path) -> u64 {
    let maybe_metadata = p.metadata().ok();
    let size = maybe_metadata
        .as_ref()
        .map(fs::Metadata::len)
        .unwrap_or_default();
    size
}

#[cfg(feature = "only-for-docs-rs")]
fn download(_url: &str, dest: &Path) {
    File::create(dest).unwrap();
}

fn url(platform: PlaywrightPlatform) -> String {
    let next = if DRIVER_VERSION.contains("next")
        || DRIVER_VERSION.contains("alpha")
        || DRIVER_VERSION.contains("beta")
    {
        "/next"
    } else {
        ""
    };
    format!(
        "https://playwright.azureedge.net/builds/driver{}/playwright-{}-{}.zip",
        next, DRIVER_VERSION, platform
    )
}

#[derive(Clone, Copy)]
enum PlaywrightPlatform {
    Linux,
    Win32,
    Win32x64,
    Mac,
}

impl fmt::Display for PlaywrightPlatform {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Linux => write!(f, "linux"),
            Self::Win32 => write!(f, "win32"),
            Self::Win32x64 => write!(f, "win32_x64"),
            Self::Mac => write!(f, "mac"),
        }
    }
}

impl Default for PlaywrightPlatform {
    fn default() -> Self {
        match env::var("CARGO_CFG_TARGET_OS").as_deref() {
            Ok("linux") => return PlaywrightPlatform::Linux,
            Ok("macos") => return PlaywrightPlatform::Mac,
            _ => (),
        };
        if env::var("CARGO_CFG_WINDOWS").is_ok() {
            if env::var("CARGO_CFG_TARGET_POINTER_WIDTH").as_deref() == Ok("64") {
                PlaywrightPlatform::Win32x64
            } else {
                PlaywrightPlatform::Win32
            }
        } else if env::var("CARGO_CFG_UNIX").is_ok() {
            PlaywrightPlatform::Linux
        } else {
            panic!("Unsupported plaform");
        }
    }
}
EOF

    cat > "$playwright_vendor_dir/imp/core/driver.rs" <<'EOF'
use crate::imp::prelude::*;
use std::{env, fs, io};
use zip::{result::ZipError, ZipArchive};

#[derive(Debug, Clone, PartialEq)]
pub struct Driver {
    path: PathBuf,
}

impl Driver {
    const ZIP: &'static [u8] = include_bytes!(concat!(env!("OUT_DIR"), env!("SEP"), "driver.zip"));
    const PLATFORM: &'static str = include_str!(concat!(env!("OUT_DIR"), env!("SEP"), "platform"));

    pub fn install() -> io::Result<Self> {
        let this = Self::new(Self::default_dest());
        if !this.path.is_dir() {
            this.prepare()?;
        }
        Ok(this)
    }

    pub fn new<P: Into<PathBuf>>(path: P) -> Self {
        Self { path: path.into() }
    }

    pub fn prepare(&self) -> Result<(), ZipError> {
        fs::create_dir_all(&self.path)?;
        let mut a = ZipArchive::new(io::Cursor::new(Self::ZIP))?;
        a.extract(&self.path)
    }

    pub fn default_dest() -> PathBuf {
        let base: PathBuf = dirs::cache_dir().unwrap_or_else(env::temp_dir);
        let dir: PathBuf = [
            base.as_os_str(),
            "ms-playwright".as_ref(),
            "playwright-rust".as_ref(),
            "driver".as_ref(),
        ]
        .iter()
        .collect();
        dir
    }

    pub fn platform(&self) -> Platform {
        match Self::PLATFORM {
            "linux" => Platform::Linux,
            "mac" => Platform::Mac,
            "win32" => Platform::Win32,
            "win32_x64" => Platform::Win32x64,
            _ => unreachable!(),
        }
    }

    pub fn executable(&self) -> PathBuf {
        if let Some(node) = env::var_os("PLAYWRIGHT_NODEJS_PATH") {
            return node.into();
        }

        match self.platform() {
            Platform::Linux | Platform::Mac => self.path.join("node"),
            Platform::Win32 | Platform::Win32x64 => self.path.join("node.exe"),
        }
    }

    pub fn cli_script(&self) -> PathBuf {
        self.path.join("package").join("cli.js")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Platform {
    Linux,
    Win32,
    Win32x64,
    Mac,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn install() {
        let _driver = Driver::install().unwrap();
    }
}
EOF
  '';

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
  ];

  prePatch = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
  '';

  postPatch = ''
    jq '
      .build.beforeBuildCommand = "" |
      .bundle.targets = ["deb"]
    ' src-tauri/tauri.conf.json | sponge src-tauri/tauri.conf.json

    jq 'del(.scripts.prebuild)' package.json | sponge package.json
  '';

  buildPhase = ''
    runHook preBuild

    target="$(rustc -vV | sed -n 's/^host: //p')"
    export PLAYWRIGHT_DRIVER_ZIP="${playwrightDriverZip}"
    export STABLE_RELEASE=1

    mkdir -p dist
    if [ ! -f dist/index.html ]; then
      cat > dist/index.html <<'EOF'
<!DOCTYPE html>
<html><head></head><body></body></html>
EOF
    fi

    export DONUT_SIDECAR_BUILD=1
    cargo build --manifest-path src-tauri/Cargo.toml --release --bin donut-proxy --bin donut-daemon
    unset DONUT_SIDECAR_BUILD

    install -Dm755 src-tauri/target/release/donut-proxy "src-tauri/binaries/donut-proxy-$target"
    install -Dm755 src-tauri/target/release/donut-daemon "src-tauri/binaries/donut-daemon-$target"

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
      --set PLAYWRIGHT_NODEJS_PATH ${nodejs}/bin/node
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
