{ pkgs, ... }:
{
  imports = [
    ./boot-baseline.nix
    ./tailscale.nix
  ];

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  time.timeZone = "Asia/Kolkata";
  i18n.defaultLocale = "en_IN";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IN";
    LC_IDENTIFICATION = "en_IN";
    LC_MEASUREMENT = "en_IN";
    LC_MONETARY = "en_IN";
    LC_NAME = "en_IN";
    LC_NUMERIC = "en_IN";
    LC_PAPER = "en_IN";
    LC_TELEPHONE = "en_IN";
    LC_TIME = "en_IN";
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
      # The laptop has 7 GiB usable RAM and no swap.
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
