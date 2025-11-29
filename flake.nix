{
  description = "A Nix-flake for a minecraft modding dev environment.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
            jre' = pkgs.jre.override {
              enableJavaFX = true;
            };
            linuxRuntimePackages = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [
              # JavaFX GTK and Prism libraries.
              libGL
              gtk3
              fontconfig
              glib
              libX11
              libXext
              libXxf86vm
              libXtst
              libxcb
              # AWT through javafx.swing.
              libXi
              libXrender
            ]);
            linuxDialogPackages = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [
              zenity
            ]);
            buildPackages = with pkgs; [
              gradle
              jre'
              openjdk
            ];
            linuxGtkEnvironment = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
              export GTK_MODULES=
              export GTK_PATH=
              export GSETTINGS_SCHEMA_DIR="${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas"
            '';
            devPackages = buildPackages ++ linuxRuntimePackages ++ linuxDialogPackages;
            mcaselectorRun = pkgs.writeShellScriptBin "mcaselector" ''
              set -euo pipefail

              if [ ! -f build.gradle ] || [ ! -x gradlew ]; then
                echo "nix run must be started from the MCA Selector source directory." >&2
                exit 1
              fi

              export JAVA_HOME="${pkgs.openjdk}"
              export PATH="${pkgs.lib.makeBinPath (buildPackages ++ linuxDialogPackages)}:$PATH"
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath linuxRuntimePackages}:''${LD_LIBRARY_PATH:-}"
              ${linuxGtkEnvironment}

              ./gradlew installDist
              exec ./build/install/mcaselector/bin/mcaselector "$@"
            '';
          in
          f {
            inherit
              pkgs
              buildPackages
              linuxRuntimePackages
              linuxDialogPackages
              devPackages
              linuxGtkEnvironment
              mcaselectorRun
              ;
          }
        );

    in
    {
      packages = forEachSupportedSystem (
        { mcaselectorRun, ... }:
        {
          default = mcaselectorRun;
        }
      );

      apps = forEachSupportedSystem (
        { mcaselectorRun, ... }:
        {
          default = {
            type = "app";
            program = "${mcaselectorRun}/bin/mcaselector";
          };
        }
      );

      devShells = forEachSupportedSystem (
        { pkgs, devPackages, linuxRuntimePackages, linuxGtkEnvironment }:
        {
          default = pkgs.mkShell {
            packages = devPackages;
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath linuxRuntimePackages; # Set up the library path for linking
            JAVA_HOME = pkgs.openjdk;
            shellHook = linuxGtkEnvironment;
          };
        }
      );
    };
}
