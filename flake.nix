{
  description = "Zig dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    forEachSupportedSystem =
      f: nixpkgs.lib.genAttrs supportedSystems (
        system: f {
          pkgs = import nixpkgs { inherit system; };
          system = system;
        }
      );

  in
  {
    # ----------------------------------------------------------------------
    # 1. Development
    # ----------------------------------------------------------------------
    devShells = forEachSupportedSystem ({ pkgs, ... }: {
      default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          zig
          zls
          lldb
        ];
      };
    });
  };
}

