#!/usr/bin/env bash
#
# bake-sky.sh — bake a Godot sky shader into a Vega Strike <name>_light.cube.
#
# Runs the Godot baker offscreen (xvfb), splits the 6-face strip into faces,
# compresses each to DXT1, and assembles the cubemap with dds_cubemap.py.
#
# Usage:
#   scripts/bake-sky.sh <name> [--res N] [--shader res://...] [--param k=v ...]
#
# Examples:
#   scripts/bake-sky.sh fiery_galaxy --res 4096 \
#       --param uNebulaAmount=1.1 --param uNebulaColorA=...
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"          # the repo root
LAB="${LAB:-$ROOT/lab}"            # the Godot lab, inside this repo
# Everything here is repo-relative: a clone can bake. Requirements: godot-mono, xvfb-run,
# ImageMagick (magick) and python3.
OUTDIR="${OUTDIR:-$ROOT/candidates}"

name=""
RES=4096
SHADER="res://bake_sky.gdshader"
PARAMS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --res)    RES="$2"; shift 2 ;;
        --shader) SHADER="$2"; shift 2 ;;
        --param)  PARAMS+=(--param "$2"); shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        -*)       echo "unknown option: $1" >&2; exit 2 ;;
        *)        name="$1"; shift ;;
    esac
done

[ -n "$name" ] || { echo "usage: bake-sky.sh <name> [--res N] [--param k=v ...]" >&2; exit 2; }
command -v godot-mono >/dev/null || { echo "godot-mono not found" >&2; exit 1; }
command -v xvfb-run   >/dev/null || { echo "xvfb-run not found" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "baking $name @ ${RES}x${RES} ..."
xvfb-run -a godot-mono --path "$LAB" res://bake.tscn -- \
    --shader "$SHADER" --res "$RES" --out "$work/strip.png" "${PARAMS[@]}" >/dev/null

[ -f "$work/strip.png" ] || { echo "bake produced no strip" >&2; exit 1; }

# Guard: a failed shader compile renders WHITE (not black), so a uniform strip
# means something is wrong rather than a legitimately flat sky. Fail loudly.
sd="$(magick "$work/strip.png" -colorspace Gray -format "%[fx:standard_deviation]" info: 2>/dev/null || echo 1)"
if awk "BEGIN{exit !($sd < 0.004)}"; then
    echo "error: baked strip is uniform (sd=$sd) — shader failed to compile, or the sky is blank" >&2
    exit 1
fi

# split the strip into the six faces, in cubemap order +X,-X,+Y,-Y,+Z,-Z
faces=()
for i in 0 1 2 3 4 5; do
    magick "$work/strip.png" -crop "${RES}x${RES}+$((i * RES))+0" +repage \
        -depth 8 -define dds:compression=dxt1 "$work/f$i.dds"
    faces+=("$work/f$i.dds")
done

mkdir -p "$OUTDIR"
python3 "$HERE/dds_cubemap.py" "$OUTDIR/${name}_light.cube" "${faces[@]}"

file "$OUTDIR/${name}_light.cube"
echo "wrote $OUTDIR/${name}_light.cube ($(du -h "$OUTDIR/${name}_light.cube" | cut -f1))"
