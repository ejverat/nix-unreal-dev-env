# nix-unreal-dev-env

A **reproducible** [Nix flake](https://nixos.wiki/wiki/Flakes) development
environment for building **Unreal Engine 5.x** (tested with **5.8.2**) from
source on **NixOS / Linux**.

## Prerequisites

- **Nix** with *flakes* enabled (already the case on NixOS). Other distros:
  https://nixos.wiki/wiki/Flakes#Enable_flakes
- **Access to Unreal Engine's source**: link your Epic Games account to GitHub
  (https://www.unrealengine.com/account/connections) and join the `EpicGames`
  organization. The repository is private, so the `git clone` below will fail
  without it.

## Replicate on a new machine (from scratch)

```bash
# 1. Clone this repository
git clone git@github.com:ejverat/nix-unreal-dev-env.git ~/Projects/UnrealGames
cd ~/Projects/UnrealGames

# 2. Enter the FHS shell (slow the first time: it downloads the toolchain and
#    libraries and builds an FHS rootfs with ~600 packages)
nix develop

# 3. Clone and build Unreal (inside the FHS shell)
git clone https://github.com/EpicGames/UnrealEngine.git
cd UnrealEngine
./Setup.sh                 # downloads Epic's dependencies + toolchain (~10-20 GB)
./GenerateProjectFiles.sh  # generates the Makefile
make                       # builds the editor (several hours)
```

> 💡 The build is incremental: if it gets interrupted, re-run `make` and it
> resumes where it left off.

## The two shells

| Command | What it is | Use for |
|---|---|---|
| `nix develop` | **FHS** shell (default) | Cloning and **building** Unreal |
| `nix develop .#editor` | Plain shell (no FHS) | Editor, clangd, C++ work |

### Why the FHS shell is needed

Unreal's scripts use `#!/bin/bash` shebangs, and its prebuilt binaries link
against standard Linux paths (`/lib`, `/usr/lib`, `/lib64/ld-linux-…`). On
NixOS those paths don't exist outside an FHS environment. The FHS shell
(built with `buildFHSEnv`) mounts `/bin/bash`, `/usr/bin/env`, `/lib`,
`/usr/lib` and the standard dynamic linker, plus all of the editor's runtime
dependencies (SDL2, Vulkan, X11/Wayland, audio, fonts, ICU, CEF/GTK, …).

> ⚠️ Run `./Setup.sh`, `./GenerateProjectFiles.sh` and `make` **always inside
> `nix develop`**. Outside it they fail with
> `bad interpreter: /bin/bash: no such file or directory`.

### One-off command inside the FHS

```bash
nix run .# -- -c './Setup.sh'
```

## Build without `-j`

**Do not use `make -j`.** UE's Makefile launches one target per job, and each
one invokes UnrealBuildTool (UBT), which only allows a **single instance**
(global mutex). With `-j` they collide and fail with
`Result: Failed (ConflictingInstance)`. Parallelism is handled internally by
UBT/UBA, so just run `make`.

To build a specific project instead of the whole editor:

```bash
./Engine/Build/BatchFiles/Linux/Build.sh MyProject Linux Development
```

## Launch the editor

```bash
cd ~/Projects/UnrealGames
nix develop
cd UnrealEngine

# Headless smoke test (no GPU)
Engine/Binaries/Linux/UnrealEditor -nullrhi -unattended -nosplash -log

# With the graphical interface
Engine/Binaries/Linux/UnrealEditor
```

### Hybrid graphics (Intel + NVIDIA) — recommended

On laptops with an Intel iGPU + NVIDIA GPU (Optimus), the editor may default
to the weak Intel GPU, causing **tooltip rendering artifacts** and
**`VK_ERROR_DEVICE_LOST`** crashes. Force the NVIDIA GPU:

```bash
cd ~/Projects/UnrealGames
nix develop
./run-editor-nvidia.sh
```

The helper script routes rendering to the NVIDIA GPU via PRIME render
offload. You can also do it manually:

```bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
Engine/Binaries/Linux/UnrealEditor
```

## IDE / code editor

- **clangd** is included. For autocompletion, generate the compile database:
  ```bash
  ./Engine/Build/BatchFiles/Linux/Build.sh MyProject Linux Development \
    -Mode=GenerateClangDatabase
  ```
  This creates `compile_commands.json` at the project root.
- **VS Code**: install the `clangd` extension and point it at the generated
  `compile_commands.json`.
- **direnv** (optional): the included `.envrc` points at the **light**
  (`.#editor`) shell so direnv stays fast. The FHS shell is used via
  `nix develop`, not direnv, because the FHS mounts a bwrap namespace that
  can't be exported as environment variables.

## Technical notes

- **Toolchain**: UE 5.x downloads its own clang (20.x) in `Setup.sh`, so the
  shell's clang 19 is only for general C++ work.
- **`.NET`**: UnrealBuildTool uses .NET 8; the flake includes it and sets
  `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` to avoid the ICU failure.
- **Nixpkgs**: pinned to `nixos-26.05`. For the latest version, change the
  `nixpkgs` input URL to `nixos-unstable` and run `nix flake update`.
- **Unreal path**: uncomment and adjust `UE_ROOT` in the `profile` of
  `flake.nix` if you want that environment variable available.

## Repository layout

```
.
├── flake.nix     # environment definition (FHS + editor shells)
├── flake.lock    # pinned inputs (reproducibility)
├── .envrc        # direnv -> editor shell (optional)
├── .gitignore    # excludes UnrealEngine/ (cloned separately)
└── README.md
```
