# Sky — the compositor

The **ordered stack** the whole sky slots into. It invents no content of its own: it
declares the order and the fold, and every layer keeps its own contract
(emission + transmittance).

## Files

| file | kind |
|---|---|
| **`sky.frag`** | **SOURCE** — the fold; also the glslviewer build |
| `sky.glsl` | generated — SHADERed |
| `sky.sprj` | generated — SHADERed project |
| `sky.vert` | generated — screen-quad VS |
| `sky.gdshader` | generated — Godot 4 sky-sphere shader |

```sh
python3 Tools/build_sky.py            # generate + verify
python3 Tools/build_sky.py --check    # verify only
```

## The fold

Front-to-back, **nearest layer first**:

```glsl
vec3 col = vec3(0.0);
vec3 T   = vec3(1.0);
// per layer:  col += T * emission;  T *= transmittance;
if (T.r < 0.01 && T.g < 0.01 && T.b < 0.01) return col;   // opaque -> drop the rest
```

A layer's transmittance therefore reaches everything behind it, and when a foreground
layer goes opaque the layers behind it are not merely invisible — they are **never
evaluated**, which is where the cost saving lives.

## The order

```
near  ->  local nebula (a volume; parallax)          Space/Nebula/*
      ->  local starfield (a dome)                   Space/Starfield/*
      ->  background content                         <-- next: Milky Way, galaxies...
far
```

Each layer has a **fade** knob. A faded-out layer contributes neither emission nor
absorption (its `T` is pulled to `1`), so it truly disappears instead of leaving a veil.

## Adding a layer

1. Put the layer's reusable body — constants, shared maths and its contract function —
   in `Space/<Layer>/<name>.inc.glsl`, wrapped in an include guard.
2. Include it in the `// ===== SHARED MATHS` section here, after the variables it reads.
3. Add its knobs to `// ===== VARIABLES` (namespaced per layer — a GLSL translation unit
   is flat, so `uStarDensity` / `uNebDensity`, never two bare `uDensity`s).
4. Fold it into `skyColour()` at the right depth, with a fade.

The nearest layers are listed first; background content goes after the starfield.

## Running it

```sh
glslviewer Space/Sky/sky.frag                 # run from the repo root
shadered Space/Sky/sky.sprj
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://compositor_lab.tscn
Tools/preview.sh Space/Sky/sky.frag /tmp/sky.png [uFadeNebula=0 ...]
```

Licence: GPL-3.0 (see `LICENSE`).
