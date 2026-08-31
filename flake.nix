{
  description = "Reproducible Unreal Engine 5.x development environment (tested with 5.8) on NixOS/Linux";

  inputs = {
    # NixOS 26.05 (stable). Switch to "nixos-unstable" if you want the
    # latest versions of the tools.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ------------------------------------------------------------------
        # Build/runtime dependencies that Unreal Engine needs on Linux.
        # (buildInputs: their libraries end up in the shell's LD_LIBRARY_PATH)
        # ------------------------------------------------------------------
        ueRuntimeDeps = with pkgs; [
          # Graphics / GPU (OpenGL + Vulkan)
          mesa
          libglvnd
          vulkan-headers
          vulkan-loader
          vulkan-tools

          # Audio
          alsa-lib
          libpulseaudio
          jack2

          # Windowing / input / Wayland / X11
          SDL2
          wayland
          wayland-protocols
          libxkbcommon
          libx11
          libxcursor
          libxrandr
          libxi
          libxinerama
          libxscrnsaver
          libxfixes
          libxxf86vm
          libxrender
          libxcomposite
          libxdamage
          libxtst
          libxcb

          # Fonts / text
          fontconfig
          freetype

          # Input / devices (libudev)
          udev

          # Compression / images / networking / crypto / misc
          zlib
          libxml2
          libpng
          libjpeg
          libwebp
          sqlite
          openssl
          curl
          dbus
          icu                 # ICU: required by UE's .NET tooling (GitDependencies/UBT)

          # CEF / GTK (the editor's embedded browser: EpicWebHelper)
          glib
          gtk3
          gdk-pixbuf
          at-spi2-core        # libatk / libatspi / libatk-bridge
          cairo
          pango
          harfbuzz
          fribidi
          nss                 # libnss3 / libnssutil3 / libsmime3
          nspr                # libnspr4
          expat
          libdrm
          libgbm              # libgbm.so.1 (mesa, separate output)
          libxext
          libffi
        ];

        # ------------------------------------------------------------------
        # Build tools (nativeBuildInputs: available on PATH)
        # ------------------------------------------------------------------
        buildTools = with pkgs; [
          # Build system
          gnumake
          cmake
          ninja
          pkg-config
          gcc                 # libstdc++ and native dependency compilation
          gdb
          lldb
          patch

          # Utilities used by UE's scripts (Setup.sh, etc.)
          git
          git-lfs
          python3
          perl
          bashInteractive
          gawk
          gnused
          gnugrep
          gnutar
          gzip
          xz
          unzip
          zip
          which
          file
          util-linux         # lscpu (UBT queries logical/physical core counts on Linux)
          xdg-user-dirs      # avoids "xdg-user-dir: command not found" in the editor
          m4
          autoconf
          automake
          libtool
          bison
          flex

          # UnrealBuildTool in UE 5.3+ uses .NET 8
          dotnet-sdk_8
        ];

        # ------------------------------------------------------------------
        # Developer tools (editor, LSP, conveniences)
        # ------------------------------------------------------------------
        devTools = with pkgs; [
          ripgrep
          fd
          fzf
          jq
          bear                # generates compile_commands.json for external builds
        ];

        # ------------------------------------------------------------------
        # Plain (non-FHS) devShell: useful for the editor/LSP (clangd) and
        # C++ work outside Unreal's build. To BUILD Unreal use the FHS shell
        # (mkUeFhsEnv), which provides #!/bin/bash shebangs and standard paths
        # (/lib, /usr/lib, /lib64/ld-linux-...).
        # ------------------------------------------------------------------
        mkUePlainShell = { name, clang, clang-tools, lld }:
          pkgs.mkShell {
            inherit name;

            nativeBuildInputs =
              buildTools ++ devTools ++ [ clang clang-tools lld ];

            buildInputs = ueRuntimeDeps;

            shellHook = ''
              export LANG=en_US.UTF-8
              export LC_ALL=en_US.UTF-8
              export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"

              # C++ toolchain used by Unreal (clang + lld)
              export CC=clang
              export CXX=clang++
              export LD=lld

              # Unreal root directory (adjust to your clone):
              # export UE_ROOT="$HOME/Projects/UnrealGames/UnrealEngine"

              printf '\n'
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\033[1;36m  Unreal Engine dev shell — %s\033[0m\n' "${name}"
              printf '\033[1;36m  clang:  %s\033[0m\n' "$(${clang}/bin/clang --version | head -n1)"
              printf '\033[1;36m  dotnet: %s\033[0m\n' "$(dotnet --version 2>/dev/null || echo 'n/d')"
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\n  Typical steps: Setup.sh -> GenerateProjectFiles.sh -> make\n\n'
            '';
          };

        # ------------------------------------------------------------------
        # FHS environment (buildFHSEnv): provides /bin/bash, /usr/bin/env,
        # /lib, /usr/lib and the standard dynamic linker. REQUIRED to run
        # Unreal's Setup.sh / GenerateProjectFiles.sh / make, whose scripts
        # use #!/bin/bash shebangs and download prebuilt binaries linked
        # against FHS paths.
        #   .env  -> for `nix develop`
        #   (out) -> `bin/<name>` launcher for `nix run`
        # ------------------------------------------------------------------
        mkUeFhsEnv = { name, clang, clang-tools, lld }:
          pkgs.buildFHSEnv {
            inherit name;

            # Programs available in /bin and /usr/bin
            targetPkgs = _: buildTools ++ devTools ++ [ clang clang-tools lld ];

            # Libraries available in /lib and /usr/lib
            multiPkgs = _: ueRuntimeDeps;

            runScript = "bash";

            profile = ''
              export LANG=en_US.UTF-8
              export LC_ALL=en_US.UTF-8
              export CC=clang
              export CXX=clang++
              export LD=lld

              # UE's .NET tooling (GitDependencies, UnrealBuildTool) fails
              # without ICU; invariant mode avoids the
              # "Couldn't find a valid ICU" crash.
              export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

              # Unreal root directory (adjust to your clone):
              # export UE_ROOT="$HOME/Projects/UnrealGames/UnrealEngine"

              printf '\n'
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\033[1;36m  Unreal Engine FHS dev shell — %s\033[0m\n' "${name}"
              printf '\033[1;36m  clang:  %s\033[0m\n' "$(${clang}/bin/clang --version | head -n1)"
              printf '\033[1;36m  dotnet: %s\033[0m\n' "$(dotnet --version 2>/dev/null || echo 'n/d')"
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\n  /bin/bash and /usr/bin/env are available. You can now:\n'
              printf '    ./Setup.sh && ./GenerateProjectFiles.sh && make\n\n'
            '';
          };

      in
      {
        # FHS shell (default): for cloning and BUILDING Unreal.
        # Note: UE 5.x downloads its own toolchain in Setup.sh (clang 20.x),
        # so the shell's clang 19 is only for general C++ work.
        devShells.default = (mkUeFhsEnv {
          name = "ue5";
          clang = pkgs.llvmPackages_19.clang;
          clang-tools = pkgs.llvmPackages_19.clang-tools;
          lld = pkgs.llvmPackages_19.lld;
        }).env;

        # Plain shell (no FHS), for the editor/LSP/clangd
        devShells.editor = mkUePlainShell {
          name = "ue5-editor";
          clang = pkgs.llvmPackages_19.clang;
          clang-tools = pkgs.llvmPackages_19.clang-tools;
          lld = pkgs.llvmPackages_19.lld;
        };

        # FHS launcher for one-off commands: `nix run .# -- -c '...'`
        packages.default = mkUeFhsEnv {
          name = "ue5";
          clang = pkgs.llvmPackages_19.clang;
          clang-tools = pkgs.llvmPackages_19.clang-tools;
          lld = pkgs.llvmPackages_19.lld;
        };

        # Formatter for the flake itself
        formatter = pkgs.alejandra;
      });
}
