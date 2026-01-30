{
  description = "LG TV Remote - Cross-platform system tray application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" ];
        };

        # Common build inputs for Tauri
        buildInputs = with pkgs; [
          # Tauri dependencies
          webkitgtk_4_1
          gtk3
          cairo
          gdk-pixbuf
          glib
          dbus
          openssl
          librsvg
          
          # For system tray
          libappindicator-gtk3
        ];

        nativeBuildInputs = with pkgs; [
          rustToolchain
          pkg-config
          
          # For icon generation
          librsvg
          imagemagick
          
          # Tauri CLI (installed via cargo)
          cargo-tauri
        ];

        # Runtime library path for system tray
        runtimeLibs = with pkgs; [
          libappindicator-gtk3
          libayatana-appindicator
        ];

      in {
        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;
          
          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}:$LD_LIBRARY_PATH"
            echo "LG TV Remote development environment"
            echo ""
            echo "Commands:"
            echo "  cargo tauri dev    - Run in development mode"
            echo "  cargo tauri build  - Build for production"
            echo "  ./generate-icons.sh - Generate icon files"
            echo ""
          '';
          
          # Required for Tauri
          WEBKIT_DISABLE_COMPOSITING_MODE = "1";
        };

        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "lgtv-tray";
          version = "1.0.0";
          
          src = ./src-tauri;
          
          cargoLock = {
            lockFile = ./src-tauri/Cargo.lock;
          };
          
          inherit buildInputs;
          nativeBuildInputs = nativeBuildInputs ++ [ pkgs.makeWrapper ];
          
          postInstall = ''
            wrapProgram $out/bin/lgtv-tray \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath buildInputs}"
          '';
        };
      }
    );
}
