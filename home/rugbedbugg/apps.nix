{ pkgs-unstable, aws-agent-toolkit, ... }:
let
  # Upstream's release binary. The nixpkgs package compiles the whole Rust
  # tree and Hydra does not cache it. Wayland, xkbcommon, GL and X11 are
  # loaded at run time, so they go on LD_LIBRARY_PATH next to dbus for the
  # portal. The tarball's portable marker file stays out of $out so the data
  # location matches the nixpkgs package. Bump version and hash together on
  # each release. The hash is in the release's checksums.txt.
  zapfastBin = pkgs-unstable.stdenv.mkDerivation rec {
    pname = "zapfast";
    version = "0.21.1";

    src = pkgs-unstable.fetchurl {
      url = "https://github.com/crmne/zapfast/releases/download/v${version}/zapfast-v${version}-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-x+5vg3BxWKSbiXCkwjbczI4dP52IrHP/g5uI8h5dAVA=";
    };

    nativeBuildInputs = [
      pkgs-unstable.autoPatchelfHook
      pkgs-unstable.makeWrapper
    ];

    buildInputs = [
      pkgs-unstable.alsa-lib
      pkgs-unstable.pipewire
      pkgs-unstable.stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 zapfast $out/bin/zapfast
      install -Dm644 packaging/applications/zapfast.desktop \
        $out/share/applications/zapfast.desktop
      install -Dm644 packaging/icons/zapfast.svg \
        $out/share/icons/hicolor/scalable/apps/zapfast.svg
      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/zapfast \
        --prefix LD_LIBRARY_PATH : ${
          pkgs-unstable.lib.makeLibraryPath [
            pkgs-unstable.dbus.lib
            pkgs-unstable.libGL
            pkgs-unstable.libx11
            pkgs-unstable.libxcursor
            pkgs-unstable.libxi
            pkgs-unstable.libxkbcommon
            pkgs-unstable.libxrandr
            pkgs-unstable.wayland
          ]
        }
    '';

    meta.mainProgram = "zapfast";
  };

  # Upstream's static release binary. The nixpkgs build fails in aws-lc-sys
  # at 0.167.0 and would fail every rebuild with it. The sandbox runs bwrap
  # from bubblewrap below. Bump version and hash together on each release.
  # The hash is the release asset's digest. Switch back to
  # pkgs-unstable.codex once cache.nixos.org has it.
  codexBin = pkgs-unstable.stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.167.0";

    src = pkgs-unstable.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-nWSDYQbVs3TpDuRFTH683nynEGVYvX5Bo0ufJuvaJRo=";
    };

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 codex-x86_64-unknown-linux-musl $out/bin/codex
      runHook postInstall
    '';

    meta.mainProgram = "codex";
  };

  asmExec = pkgs-unstable.writeShellApplication {
    name = "asm-exec";
    runtimeInputs = [
      pkgs-unstable.python3
      pkgs-unstable.awscli2
    ];
    text = ''
      exec python3 ${aws-agent-toolkit}/plugins/aws-core/skills/aws-secrets-manager/references/asm-exec "$@"
    '';
  };
in
{
  # Packages that change often and have no other config in this repo. They
  # come from the unstable set, so `nix flake update nixpkgs-unstable` and a
  # rebuild move them. The two upstream binaries above are the exception.
  # Bump their version and hash by hand.
  #
  # Qt apps stay out of this list. The Qt theme only applies to apps built
  # against the same Qt as its plugin, and the unstable set usually carries a
  # newer one. checks/qt-theme.nix fails when a second Qt version appears.
  home.packages =
    (with pkgs-unstable; [
      claude-code
      opencode
      antigravity-cli
      # Codex looks these up on PATH at runtime. It sandboxes commands with
      # bwrap, its Codex Security MCP server runs on node and the Tableau
      # plugin's startup hook builds a python3 venv.
      bubblewrap
      nodejs
      python3
    ])
    ++ [ codexBin ]
    # Keybinds launch vesktop, zapfast, youtube-tui and microsoft-edge from
    # the home profile.
    ++ (with pkgs-unstable; [
      vesktop
      firefox
      google-chrome
      microsoft-edge
      # Both reach YouTube through yt-dlp, which breaks when YouTube changes.
      mpv
      youtube-tui
    ])
    ++ [
      asmExec
      zapfastBin
    ];
}
