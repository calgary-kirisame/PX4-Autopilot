{
  description = "PX4-Autopilot SITL build environment for Gazebo";

  inputs = {
    # Pinned to the SAME revision in mission10, so the gz that PX4's in-tree plugins build against is byte-identical to the gz mission10's `.#sim` runs.
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

        # Gazebo (Harmonic) exposed exactly the way ros-gz-sim consumes it: via
        # the ROS gz *vendor* packages. PX4's gz plugins do find_package(gz-sim 8)
        # against these, so the compiled plugin matches the runtime gz that
        # mission10 launches from its own overlay.
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

            # nix provides the ENVIRONMENT; `make px4_sitl` still builds the
            # firmware in-tree. PX4 never becomes a nix derivation (matches the
            # mission10 philosophy). SITL toolchain only — no arm-gcc / dtc /
            # genromfs (those are hardware-target deps, deliberately omitted).
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

            # unforunately, ogre2 refuses to work in wayland! if you must avoid xwayland, use the ogre1 renderer
            shellHook = ''
              export PX4_VENV="$PWD/.px4-venv"
              export QT_QPA_PLATFORM=xcb

              if [ ! -e "$PX4_VENV/bin/activate" ]; then
                echo "[px4-sitl] bootstrapping python build deps -> $PX4_VENV"
                # pymavlink (in requirements.txt) fails to build on >=3.12; pin
                uv venv --python 3.11 "$PX4_VENV"
                uv pip install --python "$PX4_VENV/bin/python" -r Tools/setup/requirements.txt
              fi
              # shellcheck disable=SC1091
              source "$PX4_VENV/bin/activate"
              # when nested inside the mission10 ros shell, its CMAKE_PREFIX_PATH
              # outranks PATH in find_program and cmake picks the ros python
              # (no kconfiglib); pin the interpreter explicitly
              export CMAKE_ARGS="-DPYTHON_EXECUTABLE=$PX4_VENV/bin/python3''${CMAKE_ARGS:+ $CMAKE_ARGS}"

              echo ""
              echo "px4-sitl shell  (gz Harmonic via ros-gz vendor, pinned to mission10's overlay rev)"
              echo "  Qt platform:          $QT_QPA_PLATFORM  (keeps Ogre2 stable on Wayland sessions)"
              echo "  headless SITL:        make px4_sitl gz_x500"
              echo "  connect to standalone gz (mission10 launches gz, PX4 attaches):"
              echo "                        PX4_GZ_STANDALONE=1 make px4_sitl gz_x500"
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
