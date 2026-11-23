{
  pkgs,
  lib,
  ...
}:
let
  # leetctl is not in nixpkgs. Its fork of leetcode-cli adds the curated problem
  # sets and the review deck, which is the reason to carry it here at all.
  # Upstream builds it with naersk against a pinned Rust toolchain. The crate on
  # crates.io ships the same sources, the sets and a lock file, so the stock
  # builder packages it without pulling more inputs into the flake.
  leetctl = pkgs.rustPlatform.buildRustPackage rec {
    pname = "leetctl";
    version = "0.4.0";

    src = pkgs.fetchCrate {
      inherit pname version;
      hash = "sha256-c9SsZEiDbxGhtrdS+dYlSKx4pfWaGIdqVrBrR7mIexA=";
    };

    cargoHash = "sha256-rY1D21XQqZBUKO7/4ycWlHtuTcsODNZZ5mT4hAlD7yQ=";

    nativeBuildInputs = with pkgs; [
      # BoringSSL is built from source, because LeetCode's judge sits behind
      # Cloudflare and only answers a request that looks like Chrome's TLS and
      # HTTP/2 fingerprint.
      cmake
      # boring-sys runs `git init` inside its own output directory.
      git
      perl
      pkg-config
      # bindgen reads BoringSSL's headers through libclang.
      rustPlatform.bindgenHook
    ];

    # Two display tests compare plain text against a renderer that bolds the
    # number and the percent sign separately. The sandbox makes `colored` think
    # it has a terminal, so the escapes break the substring match.
    preCheck = ''
      export NO_COLOR=1
    '';

    meta = {
      description = "LeetCode from the command line, with curated problem sets";
      homepage = "https://github.com/siansiansu/leetctl";
      license = lib.licenses.mit;
      mainProgram = "leetctl";
    };
  };
in
{
  # Everything leetctl stores lives in ~/.leetcode, including leetcode.toml.
  # The file is left to the program. It rewrites the language on `edit --lang`,
  # so a read-only link from this repo would fail on the first such change.
  home.packages = [ leetctl ];
}
