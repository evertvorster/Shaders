# Starfield — a procedural star base layer

A realistic starfield intended as the **base sky layer** for two projects:

- **SpaceSim** (the Godot game) — runs it live
- **Vega Strike** — bakes it to the engine's `<name>_light.cube` format

Same maths, same look, different plumbing. That is the point of the contract below.

## Files

| file | kind | what it is |
|---|---|---|
| **`starfield.frag`** | **SOURCE** | The maths, written once. Also runs directly in glslviewer. |
| `starfield.glsl` | generated | SHADERed / Shadertoy-style (`iResolution`, `out vec4 outColor`) |
| `starfield.sprj` | generated | SHADERed project — open it and the sliders are there |
| `starfield.vert` | generated | Screen-quad vertex shader the `.sprj` needs |
| `starfield.gdshader` | generated | Godot 4 spatial shader for a sky sphere |

Generated files carry a "do not edit by hand" header. Edit `starfield.frag` and run:

```sh
python3 Tools/build_starfield.py          # generate + verify
python3 Tools/build_starfield.py --check  # verify only
```

## The model

Stars are a **uniformly random field**. Brightness and colour come from bounded
distributions, and **brightness stands in for distance** — on the sky "closer" *is*
"brighter". That isn't a shortcut: a uniform volume distribution with an inverse-square
falloff produces exactly a power-law magnitude distribution, which is what the
magnitude law implements.

## The contract

```glsl
vec3 starfieldSky(vec3 dir, float pxPerDir);
```

`pxPerDir` is the **only** host-specific value: the direction-units-per-*pixel* of the
view being rendered.

| host | pxPerDir |
|---|---|
| Godot sky sphere | `2 * tan(fov_y / 2) / viewport_height` |
| cubemap face (bake) | `2 / faceSize` |
| glslviewer / SHADERed | `1 / (1.4 * resolution.y)` |

Keeping star size in **pixels** is what makes the same shader look identical in the
game, in the editor, and in a baked cubemap.

### Compositing a nebula on top

The function returns **stars only**, so layers stay independent — the nebulae add
their own colour and dim the stars they are in front of:

```glsl
col = starfieldSky(dir, ppd) * dustTransmittance + nebulaColour;
```

## Parameters

**Physics** — constants in the source, identical in every host, deliberately *not*
exposed as sliders, because they describe stars rather than taste:

| constant | meaning |
|---|---|
| `STAR_SIZE` | star radius in pixels at the low-magnitude end |
| `MAGNITUDE` | power-law exponent: higher = more faint stars, rarer bright |
| `GLOW_SCALE` / `GLOW_POW` / `GLOW_GAIN` | glare disc size, selectivity, peak |
| `P2`, `P3` / `W1`, `W2`, `W3` | density multipliers and weights of the three populations |

**Variables** — the knobs, annotated `[min, max]` in the source and promoted to real
uniforms in the generated hosts:

| variable | default | effect |
|---|---|---|
| `uDensity` | 60 | field density. Star count scales with its **square** |
| `uCluster` | 0 | clumping. 0 = perfectly uniform field |
| `uClusterScale` | 4 | clump size; lower = bigger clumps |
| `uBright` | 1 | exposure |
| `uGlow` | 1 | glare on the brightest stars; 0 = none |
| `uCount` | 0.6 | cell occupancy: more stars at the *same* spacing |

## Running it

```sh
glslviewer Space/Starfield/starfield.frag              # source, hot-reloads on save
shadered Space/Starfield/starfield.sprj                # sliders + the debugger
# Godot: attach starfield.gdshader to a sphere; the scene must set uPxPerDir
```

## Things that are easy to get wrong

Learned the hard way; each of these cost real time.

1. **Stars smaller than a pixel vanish.** They fall between samples. So the radius is
   floored near 1 px and magnitude rides on **brightness**, never on shrinking the star.
2. **Cell edges clip stars.** A star near a cell boundary is cut off unless neighbouring
   cells are tested — done cheaply here, only when the pixel is near the shared face.
3. **Channels clipping turns every star white.** Normalise each star's contribution to a
   unit peak instead, so a brilliant blue star stays blue.
4. **Godot: `VERTEX` in `fragment()` is VIEW space.** Transforming it by `MODEL_MATRIX`
   there yields something that never changes as the camera turns — the sky gets painted
   on the screen. Compute the direction in `vertex()` and pass a `varying`.
5. **SHADERed needs `#version` as the literal first line.** glslangValidator tolerates
   comments before it; SHADERed does not.
6. **A glare disc that is too wide reads as blotches**, not as a brilliant star. Keep it
   tight (≈2× the star radius) and steeply falling.

Licence: GPL-3.0 (see `LICENSE` at the repository root).
