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
	# Whitespace-tolerant. Requiring exactly one space after 'const vec3' silently matched
	# NOTHING for 'const vec3  uFilBg = vec3(...)' (two spaces), so an override could be quietly
	# ignored and the render would look identical -- which is how the background knob first
	# appeared to do nothing. An override that does not apply must never be silent.
	if [ "${val#*,}" != "$val" ]; then
		# name=r,g,b -> a vec3 colour knob
		sed -i -E "s/^const[[:space:]]+vec3[[:space:]]+${name}[[:space:]]*=[[:space:]]*vec3\([^)]*\);/const vec3 ${name} = vec3(${val});/" "$TMP"
	else
		case "$val" in *.*|*[eE]*) : ;; *) val="$val.0" ;; esac
		sed -i -E "s/^const[[:space:]]+float[[:space:]]+${name}[[:space:]]*=[^;]*;/const float ${name} = ${val};/" "$TMP"
	fi
	if ! grep -qE "^const ${name}[[:space:]]*=" "$TMP" && ! grep -qE "^const[[:space:]]+(float|vec3)[[:space:]]+${name}[[:space:]]*=" "$TMP"; then
		echo "preview.sh: no const knob named '${name}' in ${SRC}" >&2; exit 1
	fi
	if ! grep -qF "${val}" "$TMP"; then
		echo "preview.sh: override '${name}=${val}' did NOT apply" >&2; exit 1
	fi
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
