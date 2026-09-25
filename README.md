# Shaders

Shader work, mainly for space rendering.

Each shader lives in a directory that holds its **canonical source** plus the
**generated outputs for each host** it supports. The maths is written once; a builder
script in `Tools/` generates the per-host variants.

```
Space/
  Starfield/          procedural star base layer (source + generated formats)
  Nebula/             volumetric emission nebulae, one file per variant
  MilkyWay/           the Milky Way as overlapping bands + core (we are inside it)
  Galaxy/             a general distant galaxy, one file per variant (background object)
  Sky/                the compositor: the ordered stack, folds the layers together
lib/
  hash.glsl           shared hashes (hash13, hash33)
  noise.glsl          shared value noise / fbm
  raymarch.glsl       shared volume/camera helpers (AABB, phase, dither, lookAt)
Tools/
  shader_build.py     THE shared plumbing: include inlining, marker parsing, knob
                      collection, the SHADERed project, the Godot host, verification
  build_starfield.py      each of these is now just "where my sources are, and the one
  build_nebula.py         line that calls my layer". They take a --check flag and are
  build_milkyway.py       thin wrappers over shader_build.
  build_galaxy.py
  build_volumetric_starfield.py
  build_scenes.py         composed layers (Space/Scenes/)
  build_sky.py
  preview.sh          render one frame headlessly to a PNG (for looking at work)
```

A layer's **knobs live in its own `.inc.glsl`**, inside a `// ===== KNOBS` block, together
with its constants, maths and contract. Anything that includes the layer inherits the knobs
automatically: the builders collect those blocks and emit them as uniforms per host, so a
scene needs no copy of them and cannot fall out of step when one changes. Add or change a
knob **in the layer**, never in a scene.

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
python3 Tools/build_all.py                  # regenerate + verify EVERYTHING (use this)
python3 Tools/build_all.py --check          # verify only

python3 Tools/build_nebula.py               # one folder, e.g. every nebula variant
python3 Tools/build_scenes.py --check       # one folder, verify only

NOTE: a single builder's `--check` only VERIFIES -- it does not write. It can leave a stale
generated file looking fine. Run build_all.py before committing any shader change.
```

## Running the lab

The repo ships a small **Godot 4 project in `lab/`**: one scene, every generated shader, so you
can look at any layer and tune it.

```sh
godot-mono --path lab res://lab.tscn            # or `godot`, if that is your binary

# start on a particular shader
godot-mono --path lab res://lab.tscn -- --shader res://ridged-clouds.gdshader
```

| control | does |
|---|---|
| drag (any button) | look |
| WASD | fly (speed follows the layer: 8 for a dome, 30 for a volume you fly through) |
| Q / E | down / up |
| arrows | look (redundant fallback) |
| `I` | invert the drag |
| `P` / `L` | save / load the current shader's slider values |
| `R` | **rebuild from source and reload live** |
| `B` | bake a cubemap (name, face size, destination) |
| `Esc` | quit |

- **Pick a shader** from the dropdown. The panel is rebuilt from that shader's own
  `hint_range` annotations and each shader keeps its own settings, so the panel cannot drift
  from the shader.
- **`R`** runs `Tools/build_all.py` and swaps the shader in place, so the loop is: edit a
  `.frag`, press `R`, see it. No relaunch, no re-copy.
- **`B`** is the bake setup screen; it drives `Tools/bake-sky.sh` (below).

Headless, for verification without a display: `--capture <png>`, `--bench N`, and
`--param name=value` (`name=r,g,b` for a colour).

Render a still with glslviewer instead (no Godot needed):

```sh
Tools/preview.sh Space/Nebula/gyroid-clouds.frag /tmp/out.png [uFilVoid=0.65 ...]
```

## Baking a cubemap

Every layer also generates `<name>.bake.gdshader`: a `canvas_item` host that renders the six
cube faces as one strip, using the face-direction mapping in `lib/cubemap.glsl` (the same one
Vega Strike's baker and its orientation self-test use).

```sh
Tools/bake-sky.sh <name> --res 4096 \
    --shader res://ridged-clouds.bake.gdshader \
    --param uFilVoid=0.65 --param uFilBright=0.17
```

It runs the Godot baker offscreen, splits the strip into the six faces in DDS order
(+X, -X, +Y, -Y, +Z, -Z), compresses each to DXT1 and assembles
`<outdir>/<name>_light.cube` — what Vega Strike loads as a background.

Requirements: `godot-mono`, `xvfb-run`, ImageMagick (`magick`) and `python3`.

Two guards worth knowing:
- A failed shader compile renders **white**, not black, so the script fails if the strip is
  uniform (that catches "it compiled to nothing" rather than shipping a blank sky).
- **Check corners, not face centres.** A face centre is the same colour under any rotation or
  mirror, so a centre-only test passes while the cube is visibly wrong. Use
  `python3 Tools/check-cube-seams.py <name>_light.cube`: on a correct cube the pixels along a
  shared edge describe the same direction, so they match. A rotated or mirrored face shows up
  as a jump. (A real bug got through that way once.)

`B` in the lab drives exactly this script, with the current slider values as `--param`s.

## SHADERed notes

- **Variables are not automatic sliders.** They live in *right-click the shader pass →
  Variables*; pin the ones you want into the **Pinned** window with `+`.
- **SHADERed's camera only moves SHADERed's camera.** A shader that computes its own camera
  (like the nebulae) ignores the arcball entirely. To let it look around, drive the ray
  from SHADERed's system variables — `View`, `Projection`, `CameraPosition3` — which is
  what the shared SHADERed host emits. (It was worth doing: the starfield used to ignore
  SHADERed's camera entirely.)

Generated per layer: `<name>.glsl`, `<name>.sprj`, `<name>.vert`, `<name>.gdshader` (the live
Godot host), and `<name>.bake.gdshader` (the cubemap bake host). The lab's copies of the
`.gdshader` files are written by the same build, so they cannot drift from the sources.

GLSL outputs are verified with `glslangValidator`, which checks GLSL without a GPU.
Godot outputs are checked structurally, since Godot's dialect is not valid GLSL.

Licence: GPL-3.0.
