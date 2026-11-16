{
  pkgs,
  ...
}:
{
  # Keep the Git hosting clients beside the Git configuration.
  programs.gh.enable = true;
  home.packages = [ pkgs.glab ];

  programs.git = {
    enable = true;
    settings = {
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
}
