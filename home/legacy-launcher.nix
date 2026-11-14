# Legacy Launcher, a Minecraft launcher. The jar here is only its bootstrap.
# The bootstrap fetches the launcher into ~/.tlauncher, and the launcher
# fetches Mojang's Java builds for each game version. Those are built for a
# regular Linux layout, so everything runs in an FHS environment. Game data
# stays in ~/.tlauncher and ~/.minecraft.
{ pkgs, ... }:
let
  pname = "legacy-launcher";
  version = "1.40.3";

  # A rolling download that always serves the newest bootstrap. A new release
  # fails this hash until it is bumped. The bootstrap checks for a newer copy
  # of itself at start and cannot replace the store copy. The launcher behind
  # it updates itself in ~/.tlauncher.
  bootstrap = pkgs.fetchurl {
    name = "legacy-launcher-bootstrap-${version}.jar";
    url = "https://dl.llaun.ch/legacy/bootstrap";
    hash = "sha256-Cbp1F8ipsweA/5pt4jC4kFJHg1rg2pFNZpkeKztLbE4=";
  };

  # The bootstrap jar carries no icon. This one comes from the Flathub build.
  icon = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/flathub/ch.tlaun.TL/a595f78083ce30dab16e6199e072d91476b71c55/ch.tlaun.TL.256x256.png";
    hash = "sha256-I5Ccy1ph9gfzVXQ831U3meAz/KrBZTiyfxywqAqn+qM=";
  };

  desktopItem = pkgs.makeDesktopItem {
    name = pname;
    exec = pname;
    icon = pname;
    desktopName = "Legacy Launcher";
    comment = "Minecraft launcher";
    categories = [ "Game" ];
    startupWMClass = "org-springframework-boot-loader-PropertiesLauncher";
  };

  launcher = pkgs.buildFHSEnv {
    inherit pname version;
    # A library path from the caller would load libraries built for a
    # different glibc than the one inside the environment.
    runScript = pkgs.writeShellScript "legacy-launcher" ''
      unset LD_LIBRARY_PATH
      exec java -jar ${bootstrap} "$@"
    '';
    # The JDK runs the launcher. The rest is what Mojang's Java builds and the
    # game's native libraries load.
    targetPkgs =
      p: with p; [
        jdk21
        alsa-lib
        flite
        fontconfig
        freetype
        libGL
        libglvnd
        libpulseaudio
        libx11
        libxcb
        libxcursor
        libxext
        libxi
        libxinerama
        libxkbcommon
        libxrandr
        libxrender
        libxtst
        libxxf86vm
        openal
        udev
        wayland
        zlib
      ];
    extraInstallCommands = ''
      install -Dm644 ${icon} $out/share/icons/hicolor/256x256/apps/${pname}.png
      cp -r ${desktopItem}/share/applications $out/share
    '';
  };
in
{
  home.packages = [ launcher ];
}
