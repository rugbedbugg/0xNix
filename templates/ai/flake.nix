{
  description = "CPU-first data science and machine learning project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        # CPU-first: keep the Radeon graphics stack separate from GPU compute
        # support. Project-specific Python dependencies can instead be locked
        # with uv.
        packages =
          (with pkgs; [
            git
            pkg-config
            gnumake
            ripgrep
            uv
            ruff
          ])
          ++ [
            (pkgs.python3.withPackages (
              p: with p; [
                numpy
                scipy
                pandas
                scikit-learn
                matplotlib
                jupyterlab
                torch
              ]
            ))
          ];
      };
    };
}
