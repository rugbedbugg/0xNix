{ pkgs, vars, ... }:
let
  locale = vars.locale or "en_IN";
in
{
  imports = [
    ./boot-baseline.nix
    ./security.nix
    ./tailscale.nix
  ];

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  time.timeZone = vars.timeZone or "Asia/Kolkata";
  i18n.defaultLocale = locale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = locale;
    LC_IDENTIFICATION = locale;
    LC_MEASUREMENT = locale;
    LC_MONETARY = locale;
    LC_NAME = locale;
    LC_NUMERIC = locale;
    LC_PAPER = locale;
    LC_TELEPHONE = locale;
    LC_TIME = locale;
  };
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  # Stock VGA 8x16: the kernel's own built-in font, pinned explicitly.
  console.font = "default8x16";

  # zram: compressed in-RAM swap. Chosen over a swapfile for a laptop with
  # modest RAM and an SSD — no disk wear, no hibernation/resume setup needed.
  zramSwap.enable = true;

  # /tmp sits on the SSD, not in RAM, so build leftovers would pile up across
  # reboots. Empty it at every boot.
  boot.tmp.cleanOnBoot = true;

  nixpkgs.config.allowUnfree = true;
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      sandbox = true;
      # The laptop has 7 GiB usable RAM.
      max-jobs = 2;
      cores = 2;
      # Keep build-only tools like gcc through garbage collection, so a
      # rebuild doesn't need to download them again.
      keep-outputs = true;
    };
    gc.automatic = false;
  };
  environment.systemPackages = with pkgs; [
    git
    curl
    pciutils
    usbutils
  ];
}
