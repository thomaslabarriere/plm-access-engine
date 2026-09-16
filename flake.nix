{
  description = "PLM access engine (Haskell core) + cockpit (React/TypeScript)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      # A reproducible dev shell with the whole toolchain, matching how Aletiq
      # runs on NixOS: `nix develop` gives you ghc + cabal + hlint + node.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.ghc
            pkgs.cabal-install
            pkgs.hlint
            pkgs.nodejs_22
          ];
          shellHook = ''
            echo "plm-access-engine dev shell: engine/ (cabal) + cockpit/ (npm)"
          '';
        };
      });
    };
}
