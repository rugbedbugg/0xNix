{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting
      bind \ch backward-kill-word
    '';
    shellAbbrs = {
      ll = "ls -lah";
      gs = "git status";
      # Plain `nixos-rebuild switch` falls back to /etc/nixos/configuration.nix
      # and builds the stock system — always go through the flake.
      rebuild = "sudo nixos-rebuild switch --flake ~/0xNix#nixos";
    };
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = true;
  };
  # starship.toml: ◎ prompt, directory and git branch/status on the right,
  # git line counts above when they're nonzero. No Nerd Font icons — only
  # plain Unicode shapes, which the VGA font covers except a few rarely
  # shown ones (the nix-shell marks ✶ ⌽ ⌾, git's deleted ✕, the username ⭘,
  # and two language labels), and those fall back to another font.
  #
  # Nothing in the scrollback may be a full-width line: foot re-wraps those
  # onto two rows whenever the window narrows (tiling a new window beside
  # it), pushing all earlier output down. So:
  # - Transient prompt: once a command runs, its prompt is redrawn as just
  #   "◎ command", dropping the right-side text and the git line-count row.
  # - The line-count row is left-aligned. Padded out to the right edge (as
  #   upstream does with $fill), the terminal marks that row as running on
  #   into the next, and the mark outlives the transient redraw as a blank
  #   row after every past command once re-wrapped.
  # The live prompt is fish's own to redraw on resize.
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableTransience = true;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };
  # The default replacement is a green ❯; keep the prompt's own ◎ (or the
  # failed-command ○) instead. No right-side replacement: it stays empty.
  # Starship passes the last status etc. as arguments; forward them.
  programs.fish.functions.starship_transient_prompt_func = "starship module character $argv";
}
