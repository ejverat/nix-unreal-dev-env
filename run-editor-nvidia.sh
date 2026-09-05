#!/usr/bin/env bash
# Launch UnrealEditor on the discrete NVIDIA GPU via PRIME render offload.
# Run this INSIDE the FHS dev shell (`nix develop`).
#
# Addresses, on hybrid-graphics (Optimus) laptops:
#   - Slate/tooltip rendering artifacts
#   - VK_ERROR_DEVICE_LOST crashes (known UE 5.8 Linux Vulkan bug)
# by (a) using the NVIDIA GPU and (b) disabling raytracing (-NoRaytracing).
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

# -NoRaytracing: workaround for the known UE 5.8 Linux Vulkan bug that causes
# VK_ERROR_DEVICE_LOST (device fault during present/swapchain). The GTX 1650
# has no RT cores, so software raytracing is buggy and slow anyway.
# Remove this flag if you prefer raytracing (Lumen) and don't hit the crash.
exec "$EDITOR_BIN" -NoRaytracing "$@"
