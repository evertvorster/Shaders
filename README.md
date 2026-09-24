# Shaders

Shader work, mainly for space rendering.

Each shader lives in a directory that holds its **canonical source** plus the
**generated outputs for each host** it supports. The maths is written once; a builder
script in `Tools/` generates the per-host variants.

```
Space/
  Starfield/          procedural star base layer (source + generated formats)
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

## Building

```sh
python3 Tools/build_starfield.py            # generate + verify
python3 Tools/build_starfield.py --check    # verify only
```

GLSL outputs are verified with `glslangValidator`, which checks GLSL without a GPU.
Godot outputs are checked structurally, since Godot's dialect is not valid GLSL.

Licence: GPL-3.0.
