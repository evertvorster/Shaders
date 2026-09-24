# GalacticBand — the Milky Way band

Background content: a direction-only sky layer painted on the celestial sphere (no
parallax). It sits **behind** the local starfield in the compositor.

## Variants

| variant | what it is |
|---|---|
| **`fbm-milkyway`** | the Milky Way seen from the side of one of the arms. We are inside the galaxy, so the band is **asymmetric** — brighter toward the core, thinner and dimmer toward the anticenter, cut by a dust rift just off the midplane. Masks build the shape; value-noise fbm supplies the cloud texture (far cheaper than the scattered-sphere primitives the reference used) |

> Upstream reference: al-ro's sphere-noise Milky Way (Shadertoy), kept verbatim in
> `Shaders/references` in MemPalace. This variant is a lean re-implementation of its
> masks, not a port of its 27-tap sphere primitive.

## Contract

```glsl
vec3 galacticBandSky(vec3 dir, float pxPerDir, out vec3 transmittance);
```

Emission + chromatic transmittance (the dust reddens what is behind it). Composed
beneath the starfield:

```glsl
col += T * galacticBandSky(dir, pxPerDir, Tl);   // far layer
T *= Tl;
```

## Knobs

| variable | default | effect |
|---|---|---|
| `uGalPitch` / `uGalYaw` | 1.0 / 0.5 | orientation of the galactic plane |
| `uGalCoreAngle` | 0 | where the bright core sits along the band |
| `uGalWidth` | 0.14 | band thickness |
| `uGalCoreSize` / `uGalCore` | 0.15 / 0.9 | angular size / brightness of the core bulge |
| `uGalBand` | 0.7 | band brightness |
| `uGalStarClouds` | 0.5 | unresolved star clouds |
| `uGalNoiseScale` | 7 | size of the cloud texture |
| `uGalRiftOffset` / `uGalRiftWidth` | 0.03 / 0.04 | dust rift offset and width |
| `uGalDust` | 1.2 | dust extinction |
| `uGalBright` | 0.8 | exposure |

## Running

```sh
glslviewer Space/GalacticBand/fbm-milkyway.frag          # run from the repo root
shadered Space/GalacticBand/fbm-milkyway.sprj
# or through the compositor, which is the point:
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://compositor_lab.tscn
```

Licence: GPL-3.0 (see `LICENSE`).
