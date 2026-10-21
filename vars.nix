# Per-machine identity. Every module reads these instead of hardcoding them,
# so a fork only needs to edit this file. Private values such as the git
# email stay out of the repository entirely (see home/rugbedbugg/git.nix).
{
  username = "rugbedbugg";
  hostname = "Oxide1-6";
  # Shown by ly at login and on the ly-lock screen.
  displayName = "Oxide1-6";
  # Public commit author name. The email and signing key come from the
  # untracked ~/.config/git/identity file.
  gitName = "rugbedbugg";
}
