#!/usr/bin/env bash
# Launch UnrealEditor on the discrete NVIDIA GPU via PRIME render offload.
# Run this INSIDE the FHS dev shell (`nix develop`).
#
# Fixes, on hybrid-graphics (Optimus) laptops:
#   - Slate/tooltip rendering artifacts
#   - VK_ERROR_DEVICE_LOST crashes
# by avoiding the underpowered Intel integrated GPU.
set -euo pipefail

# Resolve the Unreal Engine root: $UE_ROOT, or a sibling UnrealEngine/ dir.
UE_ROOT="${UE_ROOT:-$(dirname "$(readlink -f "$0")")/UnrealEngine}"
EDITOR_BIN="$UE_ROOT/Engine/Binaries/Linux/UnrealEditor"

if [ ! -x "$EDITOR_BIN" ]; then
  echo "UnrealEditor not found at: $EDITOR_BIN" >&2
  echo "Set UE_ROOT to your UnrealEngine clone (e.g. export UE_ROOT=/path/to/UnrealEngine)." >&2
  exit 1
fi

# Route rendering to the NVIDIA GPU instead of the integrated Intel GPU.
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# Force the Vulkan loader to use only the NVIDIA ICD (deterministic device
# selection). The path is stable on NixOS; skip it gracefully if absent.
NVIDIA_ICD="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json"
if [ -f "$NVIDIA_ICD" ]; then
  export VK_ICD_FILENAMES="$NVIDIA_ICD"
fi

exec "$EDITOR_BIN" "$@"
