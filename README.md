# Shaders

Shader work, mainly for space rendering.

Each shader lives in a directory that holds its **canonical source** plus the
**generated outputs for each host** it supports. The maths is written once; a builder
script in `Tools/` generates the per-host variants.

```
Space/
  Starfield/          procedural star base layer (source + generated formats)
lib/
  hash.glsl           shared hashes (hash13, hash33)
  noise.glsl          shared value noise / fbm
Tools/
  build_starfield.py  generates every format from Space/Starfield/starfield.frag
```

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
light from **behind** it survives:

```glsl
vec3 someLayerSky(vec3 dir, float pxPerDir, out float transmittance);
```

Layers compose with a single fold, so a compositor never special-cases the base
(the starfield absorbs nothing and simply writes `1.0`):

```glsl
float T;
vec3 col = vec3(0.0);
// far to near:  col = layerSky(dir, ppd, T) + T * col;
```

## Building

```sh
python3 Tools/build_starfield.py            # generate + verify
python3 Tools/build_starfield.py --check    # verify only
```

GLSL outputs are verified with `glslangValidator`, which checks GLSL without a GPU.
Godot outputs are checked structurally, since Godot's dialect is not valid GLSL.

Licence: GPL-3.0.
