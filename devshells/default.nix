{ pkgs }:
let
  common = with pkgs; [
    git
    pkg-config
    gnumake
    ripgrep
  ];
  mkShell = packages: pkgs.mkShell { packages = common ++ packages; };
in
{
  default = mkShell (
    with pkgs;
    [
      nixfmt
      statix
      deadnix
      shellcheck
      shfmt
    ]
  );
  python = mkShell (
    with pkgs;
    [
      python3
      uv
      ruff
      pyright
    ]
  );
  go = mkShell (
    with pkgs;
    [
      go
      gopls
      delve
      golangci-lint
    ]
  );
  bash = mkShell (
    with pkgs;
    [
      bashInteractive
      shellcheck
      shfmt
      bash-language-server
    ]
  );
  rust = mkShell (
    with pkgs;
    [
      rustc
      cargo
      rustfmt
      clippy
      rust-analyzer
      openssl
    ]
  );
  node = mkShell (
    with pkgs;
    [
      nodejs
      pnpm
      typescript
      typescript-language-server
    ]
  );
  cpp = mkShell (
    with pkgs;
    [
      gcc
      clang-tools
      cmake
      ninja
      gdb
    ]
  );
  systems = mkShell (
    with pkgs;
    [
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
    ]
  );
  # CPU-first: keep the Radeon graphics stack separate from GPU compute support.
  # Project-specific Python dependencies can instead be locked with uv.
  ai = mkShell [
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
    pkgs.uv
    pkgs.ruff
  ];
}
