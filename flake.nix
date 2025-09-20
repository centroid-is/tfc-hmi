{
description = "Flutter dev environment";
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  flake-utils.url = "github:numtide/flake-utils";
};
outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      devShell =
        with pkgs; mkShell rec {
          buildInputs = [
            flutter
            pkg-config
            libsecret
            gtk3
            jsoncpp
          ];
                    
          # Set library paths for runtime
          LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
          
          shellHook = ''
            export LD_LIBRARY_PATH="${lib.makeLibraryPath buildInputs}:$LD_LIBRARY_PATH"
            echo "libsecret library path: ${libsecret}/lib"
            echo "LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
          '';
        };
    });
}
