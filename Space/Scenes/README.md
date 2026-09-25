# Scenes — composed layers

Each source here is a **scene**: several layers of the sky stack folded together. A scene
owns no maths of its own; it just includes layer `.inc.glsl` files and composes them in the
right order.

| scene | what |
|---|---|
| **`nebula-and-stars`** | the filamentary nebula (`Space/Nebula/ridged-clouds`) **in front of** the fly-through star volume (`Space/volumetric_starfield`) |

## The fold

```glsl
vec3 Tn; vec3 neb   = nebulaSky(camPos, dir, pxPerDir, dither, Tn);
vec3 Ts; vec3 stars = volumetricStarfieldSky(camPos, dir, pxPerDir, dither, Ts);
vec3 col = neb + Tn * uStars * stars;        // Tn is the dust
```

Stars first (they are behind), then the nebula in front dimming them by its transmittance.
The layers do **not** interact: the stars do not light the gas and the gas does not scatter
starlight. The only coupling is occlusion — fly into dense dust and the stars behind it
disappear. Verified by measurement: with a thin nebula the star contribution covers 7504
pixels, with dense gas it is **0**.

Back-to-front is the whole reason the contract hands each layer's transmittance outward.

## Build

```sh
python3 Tools/build_scenes.py          # or python3 Tools/build_all.py for everything
Tools/preview.sh Space/Scenes/nebula-and-stars.frag /tmp/scene.png
```

## Knobs are inherited, never copied

A scene declares only what is **genuinely its own** (here, `uStars`). Every layer knob comes
from that layer's `.inc.glsl` KNOBS block, which the builders collect from the inlined
includes — so adding a knob to a layer makes it appear in every scene automatically, and there
is nothing to keep in step.

This replaced a drift guard that failed the build when a scene was missing a layer knob. The
guard worked, but the duplication it was guarding was the actual problem. (A scene and a layer
declaring the SAME knob name is now a hard error instead: that would be silent shadowing.)

The Godot lab takes the same approach from the other end: it derives its sliders from the
shader's own `hint_range` annotations rather than a hand-written list.
