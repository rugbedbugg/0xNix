{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  # Untracked file holding user.email and user.signingkey. Git reads it at
  # runtime, so the values never enter the repository or the Nix store.
  identity = "${config.xdg.configHome}/git/identity";
in
{
  # Git, the GitHub CLI and the GnuPG setup that signs commits. The system
  # module installs git separately so root shells have it too.
  programs.gh.enable = true;

  # Every commit and tag is signed with the ed25519 key carried over from
  # the Arch install. The keyring stays mutable in ~/.gnupg; only gpg.conf
  # and gpg-agent.conf are declared here.
  programs.git = {
    enable = true;
    signing = {
      # Leave the key to the identity file.
      key = null;
      format = "openpgp";
      signByDefault = true;
    };
    includes = [ { path = identity; } ];
    settings = {
      user.name = vars.gitName;
      init.defaultBranch = "main";
      pull.rebase = false;
    };
    # AI coding agent state, kept out of every repository without touching
    # each repo's own .gitignore.
    ignores = [
      "**/.claude/"
      "**/.codex/"
      "**/.cursor/"
      "**/.gemini/"
      "**/.continue/"
      "**/.windsurf/"
      "**/.roo/"
      "**/.cline/"
      "**/.kiro/"
      "**/.amazonq/"
      "**/.superpowers/"
      "**/.aider*"
    ];
  };

  programs.gpg.enable = true;

  # Curses pinentry keeps passphrase prompts in the terminal; the fish
  # integration exports GPG_TTY so it knows where to draw. Cache lifetimes
  # match the Arch agent: one hour, two at most.
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-curses;
    defaultCacheTtl = 3600;
    maxCacheTtl = 7200;
  };

  # Warn on every switch until the identity file exists. Without it git
  # refuses to commit and has no key to sign with.
  home.activation.gitIdentity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f ${lib.escapeShellArg identity} ]; then
      echo "warning: ${identity} is missing. Create it with user.email and user.signingkey (see README)." >&2
    fi
  '';
}
