# Nebula — volumetric gas layers

A **family**: one `*.frag` per variant. `Tools/build_nebula.py` generates the per-host
formats for every variant it finds, so the variant name lives in every filename and a
folder of them is self-describing.

## Variants

| variant | what it is |
|---|---|
| **`gyroid-clouds`** | you are *inside* a world-space cube of gas. Gyroid-based fbm density shaped into a haze shell and a structure shell; sunlight scattered through it (Henyey-Greenstein phase + multi-octave scattering, Beer-Lambert); local stars embedded in the gas light it from within |

`gyroid-clouds` is ported from al-ro's *Volumetric nebula rendered in tiles*
(Shadertoy `DtdSz7`, MIT, 2023), reduced to a single pass and adapted to the layer
contract here. The original's multi-buffer camera state and progressive tile rendering
are host work and are dropped; only the volume, its density and its lighting remain.

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
python3 Tools/build_nebula.py            # generate + verify every variant
python3 Tools/build_nebula.py --check    # verify only
```

## The contract

```glsl
vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance);
```

Unlike the starfield (a direction-only dome), this is a **volume**: it takes the ray
`camPos`, so it has **parallax** — move and the gas shifts against the distant stars.
It returns linear **HDR** emission plus chromatic `transmittance`; tone mapping belongs
to the host. The starfield dome is behind; composing is one fold:

```glsl
vec3 T;
vec3 col = nebulaSky(camPos, dir, ppd, T);
col += starfieldSky(dir, ppd, T);
```

## Knobs

| variable | default | effect |
|---|---|---|
| `uDensity` | 1.5 | overall gas density (optical depth) |
| `uHaze` | 0.4 | soft haze filling the volume |
| `uStructure` | 1.5 | filamentary shell around the cavity |
| `uNoiseScale` | 1.0 | size of the cloud detail; higher = finer |
| `uBright` | 1.0 | exposure |
| `uSunAngle` / `uSunHeight` | 2.0 / 0.5 | where the sun sits |
| `uLocalStars` | 1.0 | stars embedded in the gas, lighting it from within |
| `uSteps` | 16 | march steps: quality vs speed |

## Running it

```sh
# glslviewer — the source, static camera (reproducible stills)
glslviewer Space/Nebula/gyroid-clouds.frag          # run from the repo root

# SHADERed — sliders, and SHADERed's own camera drives the volume
shadered Space/Nebula/gyroid-clouds.sprj

# Godot lab — fly through it (arrow keys / drag look, WASD + Q/E fly)
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://nebula_lab.tscn
```

Headless still, for looking at work without a window:

```sh
Tools/preview.sh Space/Nebula/gyroid-clouds.frag /tmp/out.png [uDensity=8 ...]
```

## What we learned

- **`uSteps` barely changes the look.** The density field is smooth and the medium goes
  optically thick quickly (haze floor + early-out), so the integral converges in a
  handful of steps. Keep it low (10–16) — more steps buy cost, not detail.
- Consequently it reads as **thick clouds**, not fine filaments. For more structure:
  `uNoiseScale` up, `uStructure` up, `uHaze` → 0.
- **Godot is stricter than desktop GLSL**, and the HOST section is replaced per host:
  - `mat3` must be built from three `vec3` columns (no 9-scalar constructor).
  - helpers the host `main` needs (`aces`) must be emitted by the builder — the source
    keeps them in HOST, which the builder discards.
  - use `int` loop counters.
  - SHADERed's camera only drives a shader that reads its `View` / `Projection` /
    `CameraPosition3` system variables — which this build does.

Licence: GPL-3.0 (see `LICENSE`). Upstream technique MIT (c) 2023 al-ro.
