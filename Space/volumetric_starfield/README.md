# volumetric_starfield — a starfield you can fly through

`Space/Starfield` is a **dome**: every star sits on the celestial sphere, so it never moves
relative to you. That is right for distant stars, but it gives no sense of travel.

This layer is a **volume**: stars sit on a world-anchored lattice around the viewer, so flying
past them produces real parallax.

    vec3 volumetricStarfieldSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance);

Stars absorb nothing, so `transmittance` is always `1.0` — the same as the dome, and it means
this layer is free to sit *behind* anything in the fold.

## Local by design, and why that is not just an optimisation

The march is capped at `uStvView`; everything beyond is the dome's job. The reason is
geometric. A star is a point source, so its **angular** size is constant — which means the
cylinder a single pixel sweeps out has radius `(angular size x distance)` and **grows without
limit**. Past some range that cylinder is wider than a cell, and any one-cell-per-step test
starts missing stars that are near the ray but sitting in a neighbouring cell. Bounded, that
cannot happen — and distant stars are the dome's business anyway, where parallax is genuinely
negligible.

So the split is: **volume = local parallax, dome = the far field.** Compose them as

    col = volumetricStarfieldSky(...) + Ts * domeSky(...)     // Ts == 1, so it is just a sum

## How a star is found

March at **half a cell** (so the ray cannot stride over a cell) and evaluate a cell only when
the ray **enters** it, tracked with `lastCell`. That dedup is what stops a star being counted
once per step. A 3D DDA would be exact; this is the cheap version, and at half-cell steps the
only cells it can miss are ones clipped at a corner.

Stars are placed in the **inner 70%** of their cell, which keeps their disc out of a
neighbouring cell's ray segment — that is what makes the one-cell test safe.

Sub-pixel stars **fade** rather than being lost or fattened, so the field stays
resolution-independent, the same rule as the dome.

## Knobs

| variable | default | effect |
|---|---|---|
| `uStvCell` | 2.0 | cell size in world units — **the main density control** (smaller = many more stars per ray) |
| `uStvDensity` | 0.50 | fraction of cells that hold a star |
| `uStvView` | 100 | how far the local volume reaches |
| `uStvAng` | 0.0016 | star angular radius (direction units) — constant, because a star is a point source |
| `uStvBright` | 2.0 | exposure |
| `uStvFalloff` | 0.0020 | inverse-square scale: bigger = stars dim faster with distance |
| `uStvSeed` | 0.0 | lattice seed |

Note that `uStvCell` is the density control, not `uStvDensity`: halving the cell puts far more
cells along every ray. In a 512px frame the defaults give ~6800 star pixels; `uStvCell 8` with
everything else equal gives **1**.

## Composition

The fold that puts this behind a nebula, with the dust occluding the stars:

    vec3 Tn; vec3 neb   = nebulaSky(camPos, dir, pxPerDir, dither, Tn);
    vec3 Ts; vec3 stars = volumetricStarfieldSky(camPos, dir, pxPerDir, dither, Ts);
    vec3 col = neb + Tn * stars;          // Tn is the nebula's transmittance

**Verified:** with a thin nebula the star contribution covers 7504 pixels; with dense gas it is
**0** — the dust occludes them completely.

## Toolchain

```sh
python3 Tools/build_volumetric_starfield.py            # generate + verify
python3 Tools/build_volumetric_starfield.py --check    # verify only
Tools/preview.sh Space/volumetric_starfield/volumetric_starfield.frag /tmp/stars.png
```

`build_volumetric_starfield.py` reuses `build_nebula.py`'s plumbing (marker parsing, include inlining,
the SHADERed project, verification); the only real difference is the contract function.
