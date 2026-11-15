{ pkgs }:
{
  # Shell for working on this repo. Language toolchains live in templates/.
  default = pkgs.mkShell {
    packages = with pkgs; [
      nixfmt
      statix
      deadnix
      shellcheck
      shfmt
    ];
  };
}
