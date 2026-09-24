# GalacticBand — the Milky Way

Background content: a **fixed backdrop** at galactic distance (it does not move relative
to the scene in any way that matters).

## Variants

| variant | what it is |
|---|---|
| **`analytic-galaxy`** | a **semi-analytic** band. The column density along the view ray is the closed-form path integral of an exponential disk — no ray marching. Lit from the inside, dust-absorbing, with authored spiral arms and turbulence |

## Why no marching

Earlier this was a raymarched volumetric disk. It worked, but it was fighting us, and the
reason was structural: a thin, flat, extremely anisotropic disk is the worst thing to
march. From outside, most of the ray is empty space, and the samples that do hit the disk
get averaged — which is exactly the smoothness.

For an exponential slab the vertical path integral has a closed form:

```
∫ exp(-|z|/hz) dt  =  2·hz / |dot(dir, pole)|
```

That one term **is** the band: looking along the plane (`|dz| → 0`) is a long path;
looking out of it is a short one. Multiply by the radial falloff at the plane crossing and
you have the core asymmetry. So:

- **emission** ∝ column density — lit from the inside
- **absorption** = `exp(-k · column · dustColour)` — dust over the path, chromatic
- **arms + turbulence** are authored on the column, so **nothing averages away**

A handful of ops instead of a loop, and the structure is whatever we draw. The raymarched
volume lives in git history for the SpaceSim case where you actually want to fly *into* a
nebula.

## The contract

```glsl
vec3 galacticBandSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance);
```

Emission + chromatic transmittance. Composed beneath the local starfield.

## The disk

Galactic centre at the world origin; the plane normal is `pole` from `uGalPitch` /
`uGalYaw`. Constants: scale height 1.2, scale length 8, bulge radius 3.

| variable | default | effect |
|---|---|---|
| `uGalPitch` / `uGalYaw` | 0 / 0 | tilt / yaw of the disk (0 = world XZ plane) |
| `uGalEmission` | 0.25 | how brightly the gas glows |
| `uGalDust` | 2.5 | dust extinction over the path |
| `uGalTurb` | 0.8 | turbulence on the column |
| `uGalNoiseScale` | 0.5 | size of the turbulent structure |
| `uGalArmCount` / `uGalArmTwist` | 2 / 4 | number of spiral arms and how tightly they wind |
| `uGalArmStrength` | 0.6 | arm contrast |
| `uGalSoftness` | 0.08 | bounds the grazing-ray column (finite band brightness) |
| `uGalBright` | 1.0 | exposure |

## Running

```sh
glslviewer Space/GalacticBand/analytic-galaxy.frag          # from the repo root
shadered Space/GalacticBand/analytic-galaxy.sprj
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://compositor_lab.tscn
```

Licence: GPL-3.0 (see `LICENSE`).
