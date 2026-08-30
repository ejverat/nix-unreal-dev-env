{
  description = "Entorno de desarrollo reproducible para Unreal Engine 5.x (probado con 5.8) en NixOS/Linux";

  inputs = {
    # NixOS 26.05 (estable), alineado con tu sistema. Cambia a "nixos-unstable"
    # si quieres las últimas versiones de las herramientas.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ------------------------------------------------------------------
        # Dependencias de build/runtime que Unreal Engine necesita en Linux.
        # (buildInputs: sus librerías acaban en LD_LIBRARY_PATH del shell)
        # ------------------------------------------------------------------
        ueRuntimeDeps = with pkgs; [
          # Gráficos / GPU (OpenGL + Vulkan)
          mesa
          libglvnd
          vulkan-headers
          vulkan-loader
          vulkan-tools

          # Audio
          alsa-lib
          libpulseaudio
          jack2

          # Ventanas / input / Wayland / X11
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

          # Fuentes / texto
          fontconfig
          freetype

          # Input / dispositivos (libudev)
          udev

          # Compresión / imágenes / red / crypto / misc
          zlib
          libxml2
          libpng
          libjpeg
          libwebp
          sqlite
          openssl
          curl
          dbus
          icu                 # ICU: lo necesita el .NET de UE (GitDependencies/UBT)

          # CEF / GTK (navegador embebido del editor: EpicWebHelper)
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
          libgbm              # libgbm.so.1 (mesa, salida separada)
          libxext
          libffi
        ];

        # ------------------------------------------------------------------
        # Herramientas de compilación (nativeBuildInputs: en el PATH)
        # ------------------------------------------------------------------
        buildTools = with pkgs; [
          # Build system
          gnumake
          cmake
          ninja
          pkg-config
          gcc                 # libstdc++ y compilación de dependencias nativas
          gdb
          lldb
          patch

          # Utilidades que usan los scripts de UE (Setup.sh, etc.)
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
          m4
          autoconf
          automake
          libtool
          bison
          flex

          # UnrealBuildTool en UE 5.3+ usa .NET 8
          dotnet-sdk_8
        ];

        # ------------------------------------------------------------------
        # Herramientas de desarrollo (editor, LSP, comodidades)
        # ------------------------------------------------------------------
        devTools = with pkgs; [
          ripgrep
          fd
          fzf
          jq
          bear                # genera compile_commands.json para builds externos
        ];

        # ------------------------------------------------------------------
        # devShell "plano" (sin FHS): útil para el editor/LSP (clangd) y
        # tareas de C++ fuera del build de Unreal. Para COMPILAR UE usa el
        # shell FHS (mkUeFhsEnv), que resuelve los shebangs #!/bin/bash y
        # las rutas estándar (/lib, /usr/lib, /lib64/ld-linux-...).
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

              # Toolchain de C++ que usa Unreal (clang + lld)
              export CC=clang
              export CXX=clang++
              export LD=lld

              # Directorio raíz de Unreal (ajústalo a tu clon):
              # export UE_ROOT="$HOME/Projects/UnrealGames/UnrealEngine"

              printf '\n'
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\033[1;36m  Unreal Engine dev shell — %s\033[0m\n' "${name}"
              printf '\033[1;36m  clang:  %s\033[0m\n' "$(${clang}/bin/clang --version | head -n1)"
              printf '\033[1;36m  dotnet: %s\033[0m\n' "$(dotnet --version 2>/dev/null || echo 'n/d')"
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\n  Pasos típicos: Setup.sh -> GenerateProjectFiles.sh -> make\n\n'
            '';
          };

        # ------------------------------------------------------------------
        # Entorno FHS (buildFHSEnv): proporciona /bin/bash, /usr/bin/env,
        # /lib, /usr/lib y el linker dinámico estándar. Es OBLIGATORIO para
        # ejecutar Setup.sh / GenerateProjectFiles.sh / make de Unreal, cuyos
        # scripts usan shebang #!/bin/bash y descargan binarios precompilados
        # enlazados contra rutas FHS.
        #   .env  -> para `nix develop`
        #   (out) -> launcher `bin/<name>` para `nix run`
        # ------------------------------------------------------------------
        mkUeFhsEnv = { name, clang, clang-tools, lld }:
          pkgs.buildFHSEnv {
            inherit name;

            # Programas disponibles en /bin y /usr/bin
            targetPkgs = _: buildTools ++ devTools ++ [ clang clang-tools lld ];

            # Librerías disponibles en /lib y /usr/lib
            multiPkgs = _: ueRuntimeDeps;

            runScript = "bash";

            profile = ''
              export LANG=en_US.UTF-8
              export LC_ALL=en_US.UTF-8
              export CC=clang
              export CXX=clang++
              export LD=lld

              # .NET de UE (GitDependencies, UnrealBuildTool) falla sin ICU;
              # el modo invariant evita el crash "Couldn't find a valid ICU".
              export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

              # Ajusta la ruta de tu clon de Unreal:
              # export UE_ROOT="$HOME/Projects/UnrealGames/UnrealEngine"

              printf '\n'
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\033[1;36m  Unreal Engine FHS dev shell — %s\033[0m\n' "${name}"
              printf '\033[1;36m  clang:  %s\033[0m\n' "$(${clang}/bin/clang --version | head -n1)"
              printf '\033[1;36m  dotnet: %s\033[0m\n' "$(dotnet --version 2>/dev/null || echo 'n/d')"
              printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
              printf '\n  /bin/bash y /usr/bin/env disponibles. Ya puedes:\n'
              printf '    ./Setup.sh && ./GenerateProjectFiles.sh && make\n\n'
            '';
          };

      in
      {
        # Shell FHS (por defecto): para clonar y COMPILAR Unreal.
        # Nota: UE 5.x descarga su propio toolchain en Setup.sh (clang 20.x),
        # así que el clang 19 del shell es solo para trabajo C++ general.
        devShells.default = (mkUeFhsEnv {
          name = "ue5";
          clang = pkgs.llvmPackages_19.clang;
          clang-tools = pkgs.llvmPackages_19.clang-tools;
          lld = pkgs.llvmPackages_19.lld;
        }).env;

        # Shell plano (sin FHS), para el editor/LSP/clangd
        devShells.editor = mkUePlainShell {
          name = "ue5-editor";
          clang = pkgs.llvmPackages_19.clang;
          clang-tools = pkgs.llvmPackages_19.clang-tools;
          lld = pkgs.llvmPackages_19.lld;
        };

        # Launcher FHS para comandos puntuales: `nix run .# -- -c '...'`
        packages.default = mkUeFhsEnv {
          name = "ue5";
          clang = pkgs.llvmPackages_19.clang;
          clang-tools = pkgs.llvmPackages_19.clang-tools;
          lld = pkgs.llvmPackages_19.lld;
        };

        # Formateador para el propio flake
        formatter = pkgs.alejandra;
      });
}
