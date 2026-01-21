{
  description = "LG TV Remote - KDE Plasma 6 Widget";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              kdePackages.kpackage
              (python3.withPackages (ps: with ps; [
                websockets
              ]))
            ];

            shellHook = ''
              echo "═══════════════════════════════════════════════════════"
              echo "  LG TV Remote - Development Shell"
              echo "═══════════════════════════════════════════════════════"
              echo ""
              echo "Install the widget:"
              echo "  cd plasmoid && ./install.sh"
              echo ""
              echo "Test widget:"
              echo "  plasmawindowed com.codekitties.lgtv.remote"
              echo "═══════════════════════════════════════════════════════"
            '';
          };
        });
    };
}
