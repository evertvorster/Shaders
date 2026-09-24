#!/usr/bin/env bash
# preview.sh — render one frame of a shader headlessly to a PNG.
#
#   Tools/preview.sh Space/Nebula/gyroid-clouds.frag /tmp/out.png [uHaze=0 uDensity=2]
#
# glslViewer runs headless on the GPU (EGL) and is asked for a screenshot over its
# console channel. The shader's `const float <knob>` values can be overridden per run by
# name, which is how we sweep parameters without editing the source; overrides are
# applied to a temporary copy, so the canonical source stays clean.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$1"; shift
OUT="${1:-/tmp/preview.png}"; [ $# -gt 0 ] && shift
case "$OUT" in /*) : ;; *) OUT="$PWD/$OUT" ;; esac

TMP="$(mktemp --suffix=.frag)"
cp "$SRC" "$TMP"
for kv in "$@"; do
	name="${kv%%=*}"; val="${kv#*=}"
	# const float initialisers must be float literals: turn bare integers into 1.0 etc.
	case "$val" in *.*|*[eE]*) : ;; *) val="$val.0" ;; esac
	sed -i -E "s/^const float ${name}[[:space:]]*=[^;]*;/const float ${name} = ${val};/" "$TMP"
done

FIFO="$(mktemp -u /tmp/glfifo.XXXXXX)"; mkfifo "$FIFO"
rm -f "$OUT"
( sleep "${PREVIEW_DELAY:-4}"; printf 'screenshot,%s\n' "$OUT" > "$FIFO"; sleep "${PREVIEW_SETTLE:-4}" ) &
FEEDER=$!
[ -n "${PREVIEW_SIZE:-}" ] && SZ="-s $PREVIEW_SIZE $PREVIEW_SIZE" || SZ=""
glslViewer "$TMP" -I"$ROOT" --noncurses --headless $SZ < "$FIFO" >/tmp/preview.glslviewer.log 2>&1 &
GL=$!
for _ in $(seq 1 60); do [ -s "$OUT" ] && break; sleep 0.5; done
sleep 0.5
kill "$GL" "$FEEDER" 2>/dev/null
rm -f "$FIFO" "$TMP"
if [ -s "$OUT" ]; then
	echo "wrote $OUT"
else
	echo "FAILED"; tail -5 /tmp/preview.glslviewer.log; exit 1
fi
