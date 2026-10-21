{
  pkgs,
  host,
  vars,
}:
let
  cfg = host.config;
  home = cfg.home-manager.users.${vars.username};
  # Storage and boot settings this machine depends on. Any change to them
  # fails the check, so a future edit can't silently break booting.
  protected = {
    filesystems = builtins.mapAttrs (_: fs: {
      inherit (fs) device fsType options;
    }) cfg.fileSystems;
    inherit (cfg) swapDevices;
    kernelParams = cfg.boot.kernelParams;
    loader = {
      inherit (cfg.boot.loader) timeout;
      inherit (cfg.boot.loader.efi) canTouchEfiVariables efiSysMountPoint;
      inherit (cfg.boot.loader.systemd-boot)
        enable
        configurationLimit
        consoleMode
        editor
        graceful
        extraEntries
        extraFiles
        ;
    };
    stateVersion = cfg.system.stateVersion;
  };
  expected = {
    filesystems = {
      "/" = {
        device = "/dev/disk/by-uuid/c5eea5f0-bc9e-4011-95a0-03e0a231a429";
        fsType = "ext4";
        options = [ "x-initrd.mount" ];
      };
      "/boot" = {
        device = "/dev/disk/by-uuid/D1D5-BFD8";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };
    };
    swapDevices = [ ];
    kernelParams = [
      "root=fstab"
      "loglevel=4"
      "lsm=landlock,yama,bpf"
    ];
    # The boot menu keeps three entries.
    loader = {
      timeout = 5;
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
      enable = true;
      configurationLimit = 3;
      consoleMode = "keep";
      editor = true;
      graceful = false;
      extraEntries = { };
      extraFiles = { };
    };
    stateVersion = "26.05";
  };
  # The kernel follows linuxPackages_latest, so only its floor is pinned. The
  # Wi-Fi card needs 7.2 or newer. The initrd must keep every module the
  # hardware scan listed. nixpkgs adds its own modules on top.
  hardwareInitrd = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "uas"
    "sd_mod"
  ];
  safety =
    assert protected == expected;
    assert pkgs.lib.versionAtLeast cfg.boot.kernelPackages.kernel.version "7.2";
    assert pkgs.lib.all (m: builtins.elem m cfg.boot.initrd.availableKernelModules) hardwareInitrd;
    assert pkgs.lib.hasInfix "title NixOS $gen" cfg.boot.loader.systemd-boot.extraInstallCommands;
    assert
      builtins.hashFile "sha256" ../hosts/nixos/hardware-configuration.nix
      == "f2259cfbb7793b365dc62171a9d527f163c58fe97db141d699563b38f7d5d11a";
    assert cfg.networking.firewall.enable;
    assert cfg.networking.firewall.allowedTCPPorts == [ ];
    assert cfg.networking.firewall.allowedUDPPorts == [ ];
    assert cfg.nix.settings.sandbox;
    assert !cfg.nix.gc.automatic;
    assert !cfg.services.displayManager.autoLogin.enable;
    assert cfg.programs.hyprland.withUWSM;
    assert !home.wayland.windowManager.hyprland.systemd.enable;
    assert cfg.security.pam.services ? ly-lock;
    protected;
in
{
  configuration-safety = pkgs.writeText "configuration-safety.json" (builtins.toJSON safety);
  system = cfg.system.build.toplevel;
  home = home.home.activationPackage;
  desktop-config =
    pkgs.runCommand "desktop-config-check"
      {
        nativeBuildInputs = [
          pkgs.lua5_5
          pkgs.python3
          pkgs.hyprland
        ];
      }
      ''
        luac -p ${home.xdg.configFile."hypr/hyprland.lua".source}
        python -m json.tool ${home.xdg.configFile."waybar/config".source} >/dev/null
        export XDG_RUNTIME_DIR="$TMPDIR/runtime"
        export XDG_CACHE_HOME="$TMPDIR/cache"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
        chmod 700 "$XDG_RUNTIME_DIR"
        # This upstream mode parses configuration without starting a compositor.
        Hyprland --verify-config --config ${home.xdg.configFile."hypr/hyprland.lua".source}
        touch "$out"
      '';
}
