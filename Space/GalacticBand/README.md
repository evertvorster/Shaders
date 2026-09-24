# GalacticBand — the Milky Way

Background content. Unlike the other layers this one is a **world-space volume** (so it
has parallax): we are *inside* the galaxy, and the band is simply what the geometry
produces.

## Variants

| variant | what it is |
|---|---|
| **`volumetric-galaxy`** | a **volumetric flying-saucer** — an exponential disk plus a central bulge, marched along the view ray. Lit from the inside (emission ∝ density, i.e. unresolved starlight) and self-absorbing (dust), with fbm making the gas turbulent |

## Why a volume, not a painted band

Sitting in the disk, off to one side:

- looking **along the plane** → a long path through gas → **the band**
- looking **up or out of the plane** → a short path → dark sky
- looking **toward the core** → the densest, longest path → brightest. The asymmetry is
  the **geometry**, not a mask.
- a long enough path **absorbs** — the dust dims and reddens the far side, and the
  turbulence carves dark lanes.

## The contract

```glsl
vec3 galacticBandSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance);
```

Emission + chromatic transmittance. Composed beneath the local starfield:

```glsl
col += T * galacticBandSky(camPos, dir, pxPerDir, Tl);   // far layer
T *= Tl;
```

## The disk

The galactic centre is the world origin; the disk lies in the plane whose normal is the
`pole` from `uGalPitch` / `uGalYaw`. Constants: radius 30, scale height 1.2, scale length
8, bulge radius 3.

| variable | default | effect |
|---|---|---|
| `uGalPitch` / `uGalYaw` | 0 / 0 | tilt / yaw of the disk (0 = world XZ plane) |
| `uGalEmission` | 0.25 | how brightly the gas glows |
| `uGalDust` | 2.5 | dust extinction — reddens and darkens long paths |
| `uGalTurb` | 0.8 | surface turbulence |
| `uGalNoiseScale` | 0.5 | size of the turbulent structure |
| `uGalSteps` | 64 | march steps: quality vs speed |
| `uGalBright` | 1.0 | exposure |

## Running

```sh
glslviewer Space/GalacticBand/volumetric-galaxy.frag          # from the repo root
shadered Space/GalacticBand/volumetric-galaxy.sprj
# or through the compositor, which is the point:
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://compositor_lab.tscn
```

The compositor lab starts the camera **in the disk** (radius 12, in the plane) looking
tangentially; fly around with WASD + Q/E.

**Status:** first volumetric cut. It reads as a broad glowing band with the core to one
side; the structure is still smooth and needs tuning (and more: spiral arms, star clouds,
darker dust lanes). Defaults are a starting point.

Licence: GPL-3.0 (see `LICENSE`).
