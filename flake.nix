{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
  };

  outputs = {
    self,
    flake-utils,
    naersk,
    nixpkgs,
    rust-overlay,
    git-hooks-nix,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = (import nixpkgs) {
          inherit system overlays;
        };
        naersk' = pkgs.callPackage naersk {};
        pre-commit-check = git-hooks-nix.lib.${system}.run {
          src = ./.;
          hooks = {
            alejandra.enable = true;
            commitizen.enable = true;
            flake-checker.enable = true;
            rustfmt.enable = true;
          };
        };
        buildInputs = with pkgs; [
          vulkan-loader
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          alsa-lib
          udev
          pkg-config
        ];
        nativeBuildInputs = with pkgs; [
          libxkbcommon
          (rust-bin.selectLatestNightlyWith
            (toolchain:
              toolchain.default.override {
                extensions = ["rust-src" "clippy"];
              }))
        ];
        all_deps = with pkgs;
          [
            cargo-flamegraph
            cargo-expand
            nixpkgs-fmt
            cmake
          ]
          ++ buildInputs
          ++ nativeBuildInputs;
      in rec {
        # For `nix build` & `nix run`:
        defaultPackage = packages.bevy_template;
        packages = {
          bevy_template = naersk'.buildPackage {
            inherit buildInputs nativeBuildInputs;
            src = ./.;
            postInstall = ''
              cp -r assets $out/bin/
            '';
            # Disables dynamic linking when building with Nix
            cargoBuildOptions = x: x ++ ["--no-default-features"];
          };
        };

        checks.default = pre-commit-check;

        # For `nix develop`:
        devShell = pkgs.mkShell {
          nativeBuildInputs = all_deps;
          buildInputs = pre-commit-check.enabledPackages;
          shellHook = ''
            ${pre-commit-check.shellHook}
            export CARGO_MANIFEST_DIR=$(pwd)
            export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.lib.makeLibraryPath all_deps}"
          '';
        };
      }
    );
}
