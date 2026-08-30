# Unreal Engine dev environment (Nix)

Entorno de desarrollo **reproducible** con [Nix flakes](https://nixos.wiki/wiki/Flakes)
para programar en **Unreal Engine 5.x** (probado con **5.8.2**) compilado desde
fuente en **NixOS / Linux**.

## Requisitos previos

- **Nix** con *flakes* habilitado (en NixOS ya está). Para otras distros:
  https://nixos.wiki/wiki/Flakes#Enable_flakes
- **Acceso al código fuente de Unreal**: vincula tu cuenta de Epic Games con
  GitHub (https://www.unrealengine.com/account/connections) y únete a la
  organización `EpicGames`. El repo es privado y sin esto el `git clone`
  fallará.

## Replicar en otro equipo (desde cero)

```bash
# 1. Clona este repositorio
git clone <URL-de-este-repo> ~/Projects/UnrealGames
cd ~/Projects/UnrealGames

# 2. Entra al shell FHS (la primera vez tarda: descarga el toolchain y las
#    librerías, y construye el rootfs FHS ~600 paquetes)
nix develop

# 3. Clona y compila Unreal (dentro del shell FHS)
git clone https://github.com/EpicGames/UnrealEngine.git
cd UnrealEngine
./Setup.sh                 # descarga dependencias + toolchain de Epic (~10-20 GB)
./GenerateProjectFiles.sh  # genera el Makefile
make                       # compila el editor (varias horas)
```

> 💡 La compilación es incremental: si se interrumpe, vuelve a ejecutar `make`
> y continúa donde quedó.

## Los dos shells

| Comando | Qué es | Para qué |
|---|---|---|
| `nix develop` | Shell **FHS** (por defecto) | Clonar y **compilar** Unreal |
| `nix develop .#editor` | Shell plano (sin FHS) | Editor, clangd, tareas C++ |

### Por qué hace falta el shell FHS

Los scripts de Unreal usan el *shebang* `#!/bin/bash` y sus binarios
precompilados enlazan contra rutas estándar de Linux (`/lib`, `/usr/lib`,
`/lib64/ld-linux-…`). En NixOS esas rutas no existen fuera de un entorno FHS.
El shell FHS (basado en `buildFHSEnv`) monta `/bin/bash`, `/usr/bin/env`,
`/lib`, `/usr/lib` y el linker estándar, además de todas las dependencias de
runtime del editor (SDL2, Vulkan, X11/Wayland, audio, fuentes, ICU, CEF/GTK…).

> ⚠️ Ejecuta `./Setup.sh`, `./GenerateProjectFiles.sh` y `make` **siempre
> dentro de `nix develop`**. Fuera fallan con
> `bad interpreter: /bin/bash: no such file or directory`.

### Comando puntual dentro del FHS

```bash
nix run .# -- -c './Setup.sh'
```

## Compilar sin `-j`

**No uses `make -j`**. El Makefile de UE lanza un target por job y cada uno
invoca UnrealBuildTool (UBT), que solo admite **una instancia** (mutex global);
con `-j` chocan y fallan con `Result: Failed (ConflictingInstance)`. El
paralelismo lo gestiona UBT/UBA internamente, así que basta con `make`.

Para compilar un proyecto concreto (en vez de todo el editor):

```bash
./Engine/Build/BatchFiles/Linux/Build.sh MiProyecto Linux Development
```

## Lanzar el editor

```bash
cd ~/Projects/UnrealGames
nix develop
cd UnrealEngine

# Prueba sin GPU (headless)
Engine/Binaries/Linux/UnrealEditor -nullrhi -unattended -nosplash -log

# Con interfaz gráfica
Engine/Binaries/Linux/UnrealEditor
```

## IDE / editor de código

- **clangd** viene incluido. Para autocompletado, genera la *compile database*:
  ```bash
  ./Engine/Build/BatchFiles/Linux/Build.sh MiProyecto Linux Development \
    -Mode=GenerateClangDatabase
  ```
  Esto genera `compile_commands.json` en la raíz del proyecto.
- Con **VS Code**: instala la extensión `clangd` y apunta al
  `compile_commands.json` generado.
- **direnv** (opcional): el `.envrc` incluido apunta al shell **ligero**
  (`.#editor`) para que direnv sea rápido. El FHS se usa con `nix develop`, no
  con direnv (el FHS monta un *namespace* bwrap que no se puede exportar como
  variables de entorno).

## Notas técnicas

- **Toolchain**: UE 5.x descarga su propio clang (20.x) en `Setup.sh`, así que
  el clang 19 del shell es solo para trabajo C++ general.
- **`.NET`**: UnrealBuildTool usa .NET 8; el flake lo incluye y fija
  `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` para evitar el fallo de ICU.
- **Nixpkgs**: fijado a `nixos-26.05`. Para la última versión, cambia la URL del
  input `nixpkgs` a `nixos-unstable` y ejecuta `nix flake update`.
- **Ruta de Unreal**: descomenta y ajusta `UE_ROOT` en el `profile` del
  `flake.nix` si quieres esa variable de entorno disponible.

## Estructura del repo

```
.
├── flake.nix     # definición del entorno (FHS + editor)
├── flake.lock    # dependencias fijadas (reproducibilidad)
├── .envrc        # direnv -> shell editor (opcional)
├── .gitignore    # excluye UnrealEngine/ (se clona aparte)
└── README.md
```
