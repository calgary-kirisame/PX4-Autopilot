{
  description = "PX4-Autopilot SITL build environment for Gazebo";

  inputs = {
    # Match mission10 so PX4's in-tree plugins and the simulator runtime use
    # byte-identical Gazebo libraries.
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/1abff578f2919094ac076407c46658c0a0de41c9";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";
  };

  outputs = { self, nix-ros-overlay, nixpkgs }:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-ros-overlay.overlays.default ];
        };

        # Gazebo Harmonic as exposed to ros-gz-sim through the ROS vendor
        # packages. PX4 finds gz-sim 8 here and links against the same runtime
        # mission10 launches.
        gzEnv = with pkgs.rosPackages.jazzy; buildEnv {
          paths = [
            gz-sim-vendor
            gz-transport-vendor
            gz-msgs-vendor
            gz-math-vendor
          ];
        };
      in {
        devShells = nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          default = pkgs.mkShell {
            name = "px4-sitl";

            # SITL toolchain only; FMUv5 is built by the hosted workflow.
            packages = [
              pkgs.cmake
              pkgs.ninja
              pkgs.gnumake
              pkgs.git
              pkgs.gst_all_1.gstreamer
              pkgs.gst_all_1.gst-plugins-base
              pkgs.pkg-config
              pkgs.procps
              pkgs.python3
              pkgs.opencv
              pkgs.uv
              gzEnv
            ];

            shellHook = ''
              export PX4_VENV="$PWD/.px4-venv"
              export QT_QPA_PLATFORM=xcb

              if [ ! -e "$PX4_VENV/bin/activate" ]; then
                echo "[px4-sitl] bootstrapping python build deps -> $PX4_VENV"
                # pymavlink in PX4's requirements does not build on every
                # newer interpreter, so use the known-good version.
                uv venv --python 3.11 "$PX4_VENV"
                uv pip install --python "$PX4_VENV/bin/python" -r Tools/setup/requirements.txt
              fi
              # shellcheck disable=SC1091
              source "$PX4_VENV/bin/activate"
              # A nested mission10 ROS shell can otherwise make CMake choose
              # its Python, which does not contain PX4's build dependencies.
              export CMAKE_ARGS="-DPYTHON_EXECUTABLE=$PX4_VENV/bin/python3''${CMAKE_ARGS:+ $CMAKE_ARGS}"

              echo ""
              echo "px4-sitl shell  (gz Harmonic via ros-gz vendor, pinned to mission10)"
              echo "  Qt platform:          $QT_QPA_PLATFORM"
              echo "  headless SITL:        make px4_sitl gz_x500"
              echo "  connect to mission10: PX4_GZ_STANDALONE=1 make px4_sitl gz_x500"
              echo ""
            '';
          };
        };
      });

  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };
}
