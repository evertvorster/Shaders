# Nebula — volumetric gas layers

A **family**: one `*.frag` per variant. `Tools/build_nebula.py` generates the per-host
formats for every variant it finds, so the variant name lives in every filename and a
folder of them is self-describing.

## Variants

| variant | what it is |
|---|---|
| **`gyroid-clouds`** | an **unbounded** world-space volume of gas you fly through. Gyroid-based fbm density, with the voids coming from the noise; sunlight scattered through it (Henyey-Greenstein phase + multi-octave scattering, Beer-Lambert) |

`gyroid-clouds` is ported from al-ro's *Volumetric nebula rendered in tiles*
(Shadertoy `DtdSz7`, MIT, 2023), reduced to a single pass and adapted to the layer
contract here. The original's multi-buffer camera state and progressive tile rendering
are host work and are dropped.

**There is no box.** An earlier version was a ±10 cube with a radial cavity and a cloud
shell — it read as "clouds painted on a small box" and you hit the wall after ten units.
Now the gas is just a 3D noise field, defined everywhere: we march a fixed visible depth
from the camera, so any direction is new gas and you can fly forever.

## Files

| file | kind |
|---|---|
| **`gyroid-clouds.frag`** | **SOURCE** — the maths; also the glslviewer build |
| `gyroid-clouds.glsl` | generated — SHADERed / Shadertoy-style |
| `gyroid-clouds.sprj` | generated — SHADERed project |
| `gyroid-clouds.vert` | generated — screen-quad VS the `.sprj` needs |
| `gyroid-clouds.gdshader` | generated — Godot 4 sky-sphere shader |

```sh
cd ~/Software/Projects/Shaders
python3 Tools/build_all.py            # regenerate + verify everything
```

## The contract

```glsl
vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance);
```

Unlike the starfield (a direction-only dome), this is a **volume**: it takes the ray
`camPos`, so it has real **parallax** — move and the gas shifts against the distant stars.
It returns linear **HDR** emission plus chromatic `transmittance`; tone mapping belongs
to the host. `dither` (0..1) offsets the first step per pixel and is what stops the
banding from flickering when you fly forward (see below). Composing is one fold:

```glsl
vec3 T;
vec3 col = nebulaSky(camPos, dir, ppd, 0.0, T);
col += starfieldSky(dir, ppd, T);
```

## Knobs

| variable | default | effect |
|---|---|---|
| `uNebDensity` | 0.6 | overall gas thickness |
| `uNebVoid` | 0.12 | **void threshold** — the main shape control: higher = sparser clouds, lower = solid soup. The useful range is low (`[0.02, 0.45]`); the noise lives near 0.1–0.4 |
| `uNebHaze` | 0.4 | soft veil — rides on the cloud mask, not on empty space |
| `uNebStructure` | 1.5 | filamentary detail, also on the mask |
| `uNebNoiseScale` | 0.44 | cloud *size*; higher = finer shreds, lower = big billows |
| `uNebView` | 26 | how far a view ray marches (visible depth) — shorter is cheaper *and* less banded |
| `uNebSteps` | 24 | march steps: quality vs speed. **The main cost lever** |
| `uNebDither` | 1.0 | per-pixel jitter of the first step; 0 = off |
| `uNebBright` | 1.0 | exposure |
| `uNebSunAngle` / `uNebSunHeight` | 2.0 / 0.5 | where the sun sits |

There is deliberately **no in-volume star field**. The gas is lit by the sun only; stars
are the compositor's business (`Space/Starfield`), and a 27-cell star scan per march step
was the single most expensive thing in this shader.

## Running it

```sh
glslviewer Space/Nebula/gyroid-clouds.frag          # source, static camera (run from repo root)
shadered Space/Nebula/gyroid-clouds.sprj            # sliders; SHADERed's camera drives the volume
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://nebula_lab.tscn   # fly through it

Tools/preview.sh Space/Nebula/gyroid-clouds.frag /tmp/out.png [uNebVoid=0.2 ...]

# render-only benchmark (startup excluded), in the lab:
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://nebula_lab.tscn -- --bench 200
```

## Cost — it is the shadow ray

The inner loop is density samples: `uNebSteps` view samples, each firing a short sun ray
of `max(2, uNebSteps*0.15)` more. **Roughly 75% of the work is the shadow ray.** Real
numbers from one round of tuning: Evert saw **25 fps** on an RTX 4090; after the cuts
below it ran at **240 fps**, with the dither artifact effectively gone (fewer steps of
coarser sampling was what made the dither read as grain).

What bought that, in order of effect:

1. **`cloudDensity` was doing two 6-octave gyroid fbm calls per sample** — the second was
   a large-scale "region" term. Removed, and `GYROID_OCTAVES` went 6 → **4**.
2. **`localStars` removed** — a 27-cell scan per march step.
3. **Shadow steps** `max(3, steps*0.25)` → `max(2, steps*0.15)`.

Measured with `--bench 200`: 62 fps / 16.1 ms at 1152×648 headless (the 240 fps figure is
Evert's own resolution).

## Trap: forward motion makes the banding flicker

The samples sit at fixed distances **from the camera** (`0, stepS, 2·stepS, …`). Moving
*sideways* slides you across the field, so the parallax dominates and the clouds keep
their shape. Moving *forward* slides the whole sampling lattice along the ray, so each
sample lands on different gas — coherent banding that flashes. Fix: dither the first step
per pixel with `ign()` (interleaved gradient noise, in `lib/raymarch.glsl`), supplied by
the host (`gl_FragCoord.xy`, or `FRAGCOORD.xy` in Godot) and scaled by `uNebDither`.
Screen-anchored, so the error becomes fixed grain instead of motion.

The better fix, if we ever need it: jitter per *frame* and accumulate temporally.

## Open

- **Occluding game objects.** The field is world-anchored, so the gas genuinely *is* at
  world positions — which means it could occlude objects and be occluded by them, if the
  host knew object depths. That needs the depth buffer: a screen-space pass that
  reconstructs the world position and marches to it (`nebulaFog(camPos, dir, maxDist, out T)`).
  It would stop being a sky layer and become scene fog. Vega Strike cannot do it (a
  cubemap has no depth); SpaceSim can.

## Godot is stricter than desktop GLSL

The HOST section is replaced per host, and:

- `mat3` must be built from three `vec3` columns (no 9-scalar constructor).
- helpers the host `main` needs (`aces`) must be emitted by the builder — the source keeps
  them in HOST, which the builder discards.
- use `int` loop counters.
- fragment built-ins differ: `gl_FragCoord` vs `FRAGCOORD`.
- SHADERed's camera only drives a shader that reads its `View` / `Projection` /
  `CameraPosition3` system variables — which this build does.

Licence: GPL-3.0 (see `LICENSE`). Upstream technique MIT (c) 2023 al-ro.
