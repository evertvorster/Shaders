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

## The drift guard (important)

The builders read knob declarations out of the `.frag`'s VARIABLES section, so a scene has to
**repeat** every knob its layers declare — and that is a drift trap: add or rename a knob in a
layer and the scene silently stops exposing it, while the `.sprj` and the Godot hints keep the
stale name and the value goes nowhere.

So `build_scenes.py` fails the build if the scene is missing a knob that a layer it includes
declares:

```
FAILED: scene does not declare every layer knob:
    missing uFilWarp (from ridged-clouds.frag)
```

The right long-term fix is to move knob declarations into the layer `.inc` files and teach the
builders to collect them from inlined includes; until then this guard makes the duplication
loud instead of silent. The Godot lab takes the same approach from the other end: it derives
its sliders from the shader's own `hint_range` annotations rather than a hand-written list.
