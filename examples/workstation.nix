{
  # Fictional evaluation fixture. Replace these labels before an installation.
  networking.hostName = "example";
  time.timeZone = "Etc/UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  fileSystems."/" = {
    device = "/dev/disk/by-label/EXAMPLE";
    fsType = "ext4";
  };
  boot.loader.grub.enable = false;
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";

  users.users.example.isNormalUser = true;
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.example.home = {
      username = "example";
      homeDirectory = "/home/example";
      stateVersion = "26.05";
    };
  };
}
