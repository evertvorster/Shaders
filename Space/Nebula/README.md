# Nebula — volumetric gas layers

A **family**: one `*.frag` per variant. `Tools/build_nebula.py` generates the per-host
formats for every variant it finds, so the variant name lives in every filename and a
folder of them is self-describing.

## Variants

| variant | what it is |
|---|---|
| **`gyroid-clouds`** | an **unbounded** world-space volume of gas you fly through. Gyroid-based fbm density, with the voids coming from the noise; sunlight scattered through it (Henyey-Greenstein phase + multi-octave scattering, Beer-Lambert) |
| **`ridged-clouds`** | the same volume idea, different family: the density is a **network of thin ridges** rather than smooth billows — successive rotated sine waves, rectified so only the strands survive. That is what a supernova remnant or an HII region actually looks like. Colours are procedural (hue from the field and from a lattice of light sources), so it shifts palette as you fly |

`gyroid-clouds` is ported from al-ro's *Volumetric nebula rendered in tiles*
(Shadertoy `DtdSz7`, MIT, 2023), reduced to a single pass and adapted to the layer
contract here. The original's multi-buffer camera state and progressive tile rendering
are host work and are dropped.

### Licence note on `ridged-clouds`

The ridged/swirled-sine idea comes from the "spiral noise" used on Shadertoy
(otaviogood), and the superstructure march that popularised it is Duke's / sebastien
durand's *"Type 2 Supernova"* — including the slider UI from Bers' *"IcePrimitives"*.
**All of those are CC BY-NC-SA 3.0**, which is incompatible with this repo's GPL-3.0:
NonCommercial forbids what the GPL grants everyone, and ShareAlike conflicts with it.

**On the palette.** `uFilHueRange` replaces a bug: the hue used to be
`uFilHue + 0.30*f + 0.05*dist + 0.12*lightDist`, and `0.05 * dist` over a 25-unit march
rotated the wheel more than twice *on its own* — so depth alone buried the chosen palette
under every other colour, and the nebula cycled through everything. Depth is now normalised by
`uFilView` and every term is scaled into `uFilHueRange`, so the strands stay a family of
related hues. Measured hue spread over the biased pixels: **7 deg at 0.05, 38 deg at 1.0**.

**On translucency.** `uFilOpacity` multiplies extinction only (emission keeps its own scale),
so the gas can glow without occluding. But be aware of the arithmetic: at the defaults,
`dt = uFilView/uFilSteps = 25/16 = 1.56` and `uFilDensity 3.6` makes the per-step optical
depth greater than 1, so the gas is opaque after ~two samples and NO opacity value in the
useful range makes it see-through. A translucent look needs a lower `uFilDensity` **and**
`uFilOpacity` together — and then the early-out stops saving you, so `uFilSteps` has to rise.
In the standalone nebula this mostly reads as washing out rather than as depth, because there
is nothing behind the gas to see through to.

**The preview camera follows the field scale.** The glslviewer HOST orbits at `3/uFilScale`
instead of a fixed 3. At `uFilScale 0.05` the strands are ~20 units across, so a 3-unit orbit
sat inside a single feature and rendered a flat wash — which looks exactly like a broken
shader, and did mislead us once. Still: this look reads best in motion (the Godot lab), not
from a still.

**On straightness:** the raw field is a stack of sine *sheets*, so without help the strands read
as straight bands. `uFilWarp` domain-warps the sample point through a low-frequency 3D value
noise before the ridges see it, which is the standard fix for a too-regular analytic pattern.
Cost is 3 `vnoise` lookups per sample against the field's 12 trig, and the call is branched out
when the knob is 0, so leaving it off is free.

So `ridged-clouds` is an **independent implementation of the technique**, not a port: our
own rotation construction, our own marching, lighting and colour, our own contract. No
code was taken. If you are tempted to "restore" upstream code here, don't — it would put a
licence landmine under a public GPL repo. The technique itself is fair game; the code is not.

**There is no box.** An earlier version was a ±10 cube with a radial cavity and a cloud
shell — it read as "clouds painted on a small box" and you hit the wall after ten units.
Now the gas is just a 3D noise field, defined everywhere: we march a fixed visible depth
from the camera, so any direction is new gas and you can fly forever.

## Files

| file | kind |
|---|---|
| **`gyroid-clouds.frag`** | **SOURCE** — the maths; also the glslviewer build |
| `gyroid-clouds.glsl` | generated — SHADERed / Shadertoy-style |
| `gyroid-clouds.sprj` | generated — SHADERed project |
| `gyroid-clouds.vert` | generated — screen-quad VS the `.sprj` needs |
| `gyroid-clouds.gdshader` | generated — Godot 4 sky-sphere shader |

```sh
cd ~/Software/Projects/Shaders
python3 Tools/build_all.py            # regenerate + verify everything
```

## The contract

```glsl
vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance);
```

Unlike the starfield (a direction-only dome), this is a **volume**: it takes the ray
`camPos`, so it has real **parallax** — move and the gas shifts against the distant stars.
It returns linear **HDR** emission plus chromatic `transmittance`; tone mapping belongs
to the host. `dither` (0..1) offsets the first step per pixel and is what stops the
banding from flickering when you fly forward (see below). Composing is one fold:

```glsl
vec3 T;
vec3 col = nebulaSky(camPos, dir, ppd, 0.0, T);
col += starfieldSky(dir, ppd, T);
```

## Knobs

| variable | default | effect |
|---|---|---|
| `uNebDensity` | 0.6 | overall gas thickness |
| `uNebVoid` | 0.12 | **void threshold** — the main shape control: higher = sparser clouds, lower = solid soup. The useful range is low (`[0.02, 0.45]`); the noise lives near 0.1–0.4 |
| `uNebHaze` | 0.4 | soft veil — rides on the cloud mask, not on empty space |
| `uNebStructure` | 1.5 | filamentary detail, also on the mask |
| `uNebNoiseScale` | 0.44 | cloud *size*; higher = finer shreds, lower = big billows |
| `uNebView` | 26 | how far a view ray marches (visible depth) — shorter is cheaper *and* less banded |
| `uNebSteps` | 24 | march steps: quality vs speed. **The main cost lever** |
| `uNebDither` | 1.0 | per-pixel jitter of the first step; 0 = off |
| `uNebBright` | 1.0 | exposure |
| `uNebRayleigh` | (0.175, 0.44, 1.0) | **the palette.** The Rayleigh scattering colour — the gas's own glow, any hue |
| `uNebAbsorbColour` | (0.232, 0.606, 1.0) | the extinction colour — what the gas absorbs (higher = absorbed harder) |
| `uNebSunColour` | (1,1,1) | the sun's colour |
| `uNebSunAngle` / `uNebSunHeight` | 2.0 / 0.5 | where the sun sits |

The three colour knobs are `vec3`, so each host gets a real colour control: Godot shows a
colour picker (`: source_color`), SHADERed a float3, and `Tools/preview.sh` takes
`uNebRayleigh=0.20,1.00,0.40`. They ARE the colour (normalised to the max channel) while the
**magnitude** stays in physics (`SCATTER_GAIN` / `EXTINCT_GAIN`, derived from the original
atmosphere coefficients) — so the defaults reproduce the physical look exactly and any hue is
reachable.

They used to be *multipliers* on the physical blue, which was a real limitation: scaling can
only suppress channels, and blue was always the maximum, so **a green nebula was impossible**.
Remember when recolouring that emission AND extinction both matter — the default extinction
eats blue hard, which is why a blue-only Rayleigh renders very dim.

```sh
# green / magenta, straight to a still
Tools/preview.sh Space/Nebula/gyroid-clouds.frag /tmp/g.png \
  uNebRayleigh=0.20,1.00,0.40 uNebAbsorbColour=1.00,0.25,1.00
```

There is deliberately **no in-volume star field**. The gas is lit by the sun only; stars
are the compositor's business (`Space/Starfield`), and a 27-cell star scan per march step
was the single most expensive thing in this shader.

### `ridged-clouds` knobs

Evert's tuned look, baked as the defaults. Worth reading as a worked example of how these
trade off against each other:

| variable | default | effect |
|---|---|---|
| `uFilVoid` | **0.65** | void threshold — higher = sparser, thinner strands |
| `uFilScale` | 0.22 | field scale; higher = finer strands |
| `uFilFreq` | 1.43 | frequency growth per octave (1.1–2.6) |
| `uFilCore` | 0.00 | extra brightness in the ridge cores |
| `uFilDensity` | 3.60 | optical depth |
| `uFilView` | 25 | how deep the ray marches |
| `uFilSteps` | **16** | march steps: quality vs speed |
| `uFilBright` | 0.167 | exposure |
| `uFilHue` / `uFilSat` | 0.695 / 0.39 | palette: base hue and saturation |
| `uFilHueRange` | 0.18 | palette **width**: 0 = one hue, 1 = the whole wheel |
| `uFilOpacity` | 1.00 | how much light the gas blocks (lower = translucent) |
| `uFilWarp` | 0.78 | **domain warp**: bends the strands. 0 = raw straight sheets |
| `uFilWarpScale` | 0.60 | warp frequency — higher = busier bending |

**Why this set works, and why it is cheap.** `uFilVoid 0.65` throws away most of the field and
keeps only the strongest ridges, so sparse filaments stand against real voids (Godot measures
sd 53.6 here, the highest contrast any setting has produced). `uFilDensity 3.60` then makes
those filaments optically thick within about two samples — `dt = uFilView/uFilSteps = 1.56`, so
per-step optical depth exceeds 1 — and the march hits its early-out almost immediately. That is
how 16 steps can carry this much structure: the gas saturates, so the ray never runs long.
`uFilScale 0.22` with `uFilFreq 1.43` keeps the octave frequencies rising modestly, and the
warp supplies the kinking that stops the strands reading as straight bands.

## Running it

```sh
glslviewer Space/Nebula/gyroid-clouds.frag          # source, static camera (run from repo root)
shadered Space/Nebula/gyroid-clouds.sprj            # sliders; SHADERed's camera drives the volume
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://nebula_lab.tscn   # fly through it

Tools/preview.sh Space/Nebula/gyroid-clouds.frag /tmp/out.png [uNebVoid=0.2 ...]

# render-only benchmark (startup excluded), in the lab:
godot-mono --path ~/Software/Projects/vs05-godot-shader-lab res://nebula_lab.tscn -- --bench 200
```

## Cost — it is the shadow ray

The inner loop is density samples: `uNebSteps` view samples, each firing a short sun ray
of `max(2, uNebSteps*0.15)` more. **Roughly 75% of the work is the shadow ray.** Real
numbers from one round of tuning: Evert saw **25 fps** on an RTX 4090; after the cuts
below it ran at **240 fps**, with the dither artifact effectively gone (fewer steps of
coarser sampling was what made the dither read as grain).

What bought that, in order of effect:

1. **`cloudDensity` was doing two 6-octave gyroid fbm calls per sample** — the second was
   a large-scale "region" term. Removed, and `GYROID_OCTAVES` went 6 → **4**.
2. **`localStars` removed** — a 27-cell scan per march step.
3. **Shadow steps** `max(3, steps*0.25)` → `max(2, steps*0.15)`.
4. **The shadow samples a cheaper field** (`SHADOW_OCTAVES 2` vs `GYROID_OCTAVES 4`): a
   shadow only needs the cloud *shape*, not the filigree. Measured with the bench below,
   0.98 → **0.71 ms/frame** at 24 steps (~28%).

**`--bench N` draws WITHOUT swapping buffers** (`RenderingServer.force_draw(false)`).
Presenting costs ~15 ms/frame under `xvfb-run` (Mesa: "No DRI3 support … required for
presentation") and swamped the shader completely — an earlier version of this bench
reported ~60 fps no matter what the shader did, which cost a round of wrong conclusions.

Drawing without a swap measures the render, so it responds to load:
`uNebSteps` 8 / 24 / 48 → 3175 / 1539 / 587 fps at 1152×648. But it is **not
GPU-synchronised**, so treat it as a **relative** instrument — good for "is this change
faster", not for absolute fps. The in-game FPS counter is the absolute truth (Evert: 240
fps at his resolution, where this bench was reporting 60).

`--param name=value` (and `name=r,g,b` for colour knobs) makes headless sweeps possible:

```sh
godot-mono --path . res://nebula_lab.tscn -- --bench 300 --param uNebSteps=24
```

## Trap: forward motion makes the banding flicker

The samples sit at fixed distances **from the camera** (`0, stepS, 2·stepS, …`). Moving
*sideways* slides you across the field, so the parallax dominates and the clouds keep
their shape. Moving *forward* slides the whole sampling lattice along the ray, so each
sample lands on different gas — coherent banding that flashes. Fix: dither the first step
per pixel with `ign()` (interleaved gradient noise, in `lib/raymarch.glsl`), supplied by
the host (`gl_FragCoord.xy`, or `FRAGCOORD.xy` in Godot) and scaled by `uNebDither`.
Screen-anchored, so the error becomes fixed grain instead of motion.

The better fix, if we ever need it: jitter per *frame* and accumulate temporally.

## Open

- **Occluding game objects.** The field is world-anchored, so the gas genuinely *is* at
  world positions — which means it could occlude objects and be occluded by them, if the
  host knew object depths. That needs the depth buffer: a screen-space pass that
  reconstructs the world position and marches to it (`nebulaFog(camPos, dir, maxDist, out T)`).
  It would stop being a sky layer and become scene fog. Vega Strike cannot do it (a
  cubemap has no depth); SpaceSim can.

## Godot is stricter than desktop GLSL

The HOST section is replaced per host, and:

- `mat3` must be built from three `vec3` columns (no 9-scalar constructor).
- helpers the host `main` needs (`aces`) must be emitted by the builder — the source keeps
  them in HOST, which the builder discards.
- use `int` loop counters.
- fragment built-ins differ: `gl_FragCoord` vs `FRAGCOORD`.
- SHADERed's camera only drives a shader that reads its `View` / `Projection` /
  `CameraPosition3` system variables — which this build does.

Licence: GPL-3.0 (see `LICENSE`). Upstream technique MIT (c) 2023 al-ro.
