{
  description = "Systems programming project with LLVM and debugging tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          pkg-config
          gnumake
          clang
          llvm
          lldb
          gdb
          binutils
          linuxHeaders
          strace
          ltrace
          valgrind
          cmake
          ninja
        ];
      };
    };
}
