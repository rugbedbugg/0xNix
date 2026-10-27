{ pkgs, ... }:
{
  programs.gh.enable = true;
  programs.git = {
    enable = true;
    settings.init.defaultBranch = "main";
    settings.pull.rebase = false;
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
