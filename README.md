# Shaders

Shader work, mainly for space rendering.

Each shader lives in a directory that holds its **canonical source** plus the
**generated outputs for each host** it supports. The maths is written once; a builder
script in `Tools/` generates the per-host variants.

```
Space/
  Starfield/          procedural star base layer (source + generated formats)
  Nebula/             volumetric emission nebulae, one file per variant
  GalacticBand/       the Milky Way band, one file per variant (background content)
  Sky/                the compositor: the ordered stack, folds the layers together
lib/
  hash.glsl           shared hashes (hash13, hash33)
  noise.glsl          shared value noise / fbm
  raymarch.glsl       shared volume/camera helpers (AABB, phase, dither, lookAt)
Tools/
  build_starfield.py  generates every format from Space/Starfield/starfield.frag
  build_nebula.py     generates every format for each Space/Nebula/*.frag
  build_galacticband.py  generates every format for each Space/GalacticBand/*.frag
  build_sky.py        generates every format from Space/Sky/sky.frag
  preview.sh          render one frame headlessly to a PNG (for looking at work)
```

A layer's reusable body (constants + maths + its contract) lives in
`Space/<Layer>/<name>.inc.glsl`, so other shaders — chiefly the compositor — can include
it. The builder inlines those includes; they end in `.glsl` because glslviewer only
resolves includes with a recognised shader extension.

## Why one source, several formats

The same shader has to run in more than one place:

| host | why |
|---|---|
| **glslviewer** | fastest preview, hot-reloads on save |
| **SHADERed** | sliders, pixel inspection, the debugger |
| **Godot** | the game (`SpaceSim`) runs it live |
| **cubemap bake** | Vega Strike still loads a baked `<name>_light.cube` |

Rather than keep four hand-copied variants in sync (which is how they silently
diverge), each shader has one source file and a builder. Generated files are committed
so they can be used without running anything.

## Shared code

GLSL used by more than one shader lives in `lib/`. A canonical source pulls it in with
`#include "lib/foo.glsl"` (repo-root-relative), and the builder **inlines** it, so every
generated output stays self-contained — SHADERed and Godot consumers do not resolve our
include paths. Running a source in glslviewer needs the repo root on the include path
(`-I .`); easiest is simply to run it from the repo root.

## The layer convention

Every sky layer shares one contract — it returns its own emission and reports how much
light from **behind** it survives, **per channel** (gas and dust absorb unevenly and
redden what is behind them):

```glsl
vec3 someLayerSky(vec3 dir, float pxPerDir, out vec3 transmittance);
// a volume layer also takes the ray origin, so it has parallax:
vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance);
```

Layers compose with a single fold, so a compositor never special-cases the base
(the starfield absorbs nothing and simply writes `vec3(1.0)`):

```glsl
float T;
vec3 col = vec3(0.0);
// far to near:  col = layerSky(dir, ppd, T) + T * col;
```

## Building

```sh
python3 Tools/build_starfield.py            # generate + verify
python3 Tools/build_starfield.py --check    # verify only
python3 Tools/build_nebula.py               # generate + verify every nebula variant
```

Render a still to look at (headless, on the GPU):

```sh
Tools/preview.sh Space/Nebula/gyroid-clouds.frag /tmp/out.png [uDensity=4 ...]
```

## SHADERed notes

- **Variables are not automatic sliders.** They live in *right-click the shader pass →
  Variables*; pin the ones you want into the **Pinned** window with `+`.
- **SHADERed's camera only moves SHADERed's camera.** A shader that computes its own camera
  (like the nebulae) ignores the arcball entirely. To let it look around, drive the ray
  from SHADERed's system variables — `View`, `Projection`, `CameraPosition3` — which is
  what `build_nebula.py` emits. (The starfield doesn't need this: it is direction-only.)

GLSL outputs are verified with `glslangValidator`, which checks GLSL without a GPU.
Godot outputs are checked structurally, since Godot's dialect is not valid GLSL.

Licence: GPL-3.0.
