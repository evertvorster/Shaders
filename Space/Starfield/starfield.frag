// starfield.frag — Vega Strike / SpaceSim starfield BASE LAYER (canonical source).
//
// This file is the single source of truth. `Tools/build_starfield.py` generates every
// other format from it:
//
//   starfield.glsl      SHADERed / Shadertoy-style (iResolution, out vec4 outColor)
//   starfield.sprj      a ready-to-open SHADERed project (carries the slider values)
//   starfield.gdshader  Godot 4 spatial shader for a sky sphere
//
// and this file itself runs directly in glslviewer:
//   glslviewer starfield.frag
//
// ---------------------------------------------------------------- THE MODEL
// Stars are a uniformly random field. Each star's brightness and colour come from
// bounded distributions; brightness stands in for distance, because on the sky
// "closer" IS "brighter". That is not a shortcut: a uniform volume distribution with
// an inverse-square falloff yields exactly a power-law magnitude distribution, which
// is what the magnitude law below produces.
//
// ---------------------------------------------------------------- THE CONTRACT
//     vec3 starfieldSky(vec3 dir, float pxPerDir, out vec3 transmittance);
//
// `dir` is any direction (need not be normalised). `pxPerDir` is the only
// host-specific value -- the direction-units-per-*pixel* of the view being rendered:
//
//     Godot sphere : pxPerDir = 2 * tan(fov_y / 2) / viewport_height
//     cubemap face : pxPerDir = 2 / faceSize
//     glslviewer   : pxPerDir = 2 * tan(fov/2) / height   (see HOST below)
//
// Keeping star size in PIXELS this way means the same shader looks identical in the
// game, in the editor, and in a baked cubemap.
//
// The function returns STARS ONLY. Every layer uses the same contract: it returns its
// own emission and writes into `transmittance` the fraction of the light from BEHIND
// it that survives -- per channel, because dust and gas absorb unevenly and redden
// what is behind them. The starfield absorbs nothing, so it writes vec3(1.0) -- that is
// literally true, not a placeholder -- which lets layers compose with a single fold and
// no special case for the base:
//
//     vec3 T;
//     vec3 col = nebulaSky(camPos, dir, ppd, T);   // nearest layer's emission
//     col += starfieldSky(dir, ppd, T);            // ...times what gets through it
//
// Over a list, far to near:  col = layerSky(..., T) + T * col;
//
// ---------------------------------------------------------------- LICENCE
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// Constants: these describe stars, not taste. They are the same in every host, so
// they are NOT exposed as sliders.
const float STAR_SIZE  = 1.10;  // star radius in pixels at the low-magnitude end
const float MAGNITUDE  = 2.60;  // power law: higher = more faint stars, rarer bright
const float GLOW_SCALE = 2.20;  // radius of the glare disc, x the star radius (tight)
const float GLOW_POW   = 10.0;  // how sharply glare concentrates on the brightest
const float GLOW_GAIN  = 1.40;  // glare peak: brilliant, not a dim wide blob
const float P2         = 2.00;  // density multipliers of the 2nd and 3rd populations
const float P3         = 4.30;
const float W1         = 1.00;  // their weights
const float W2         = 0.80;
const float W3         = 0.55;

// ===== VARIABLES ================================================================
// The knobs. Each is annotated `[min, max]` for the generated hosts. In this file
// (the glslviewer build) they are `const` because glslviewer cannot set custom
// uniforms; the builder promotes them to real uniforms for SHADERed and Godot.
const float uDensity      = 60.0;  // [5, 400] field density: star count scales with its SQUARE
const float uCluster      = 0.00;  // [0, 1] clumping; 0 = perfectly uniform field
const float uClusterScale = 4.00;  // [0.5, 20] clump size: lower = bigger clumps
const float uBright       = 1.00;  // [0, 4] exposure
const float uGlow         = 1.00;  // [0, 3] glare around the brightest stars; 0 = none
const float uCount        = 0.60;  // [0.05, 1] cell occupancy: more stars, same spacing

// ===== SHARED MATHS =============================================================
// Everything from here to the HOST marker is host-independent and is copied verbatim
// into every generated output. Shared maths lives in lib/; the builder inlines the
// includes so generated files stay self-contained. This source runs in glslviewer
// with `-I <repo root>`.

#include "lib/hash.glsl"
#include "lib/noise.glsl"

// Star colour by TEMPERATURE, cool -> hot: ~2500 K (deep orange) through sun-like to
// ~30000 K (blue). Real stars are overwhelmingly cool dwarfs, but the ones that stand
// out are hot and blue-white, so the sampled temperature is biased up by magnitude.
vec3 starColour(float t) {
	vec3 c0 = vec3(1.00, 0.58, 0.32);  // 2500 K  deep orange
	vec3 c1 = vec3(1.00, 0.72, 0.53);  // 3500 K
	vec3 c2 = vec3(1.00, 0.83, 0.71);  // 4500 K
	vec3 c3 = vec3(1.00, 0.95, 0.90);  // 5800 K  sun-like
	vec3 c4 = vec3(0.92, 0.94, 1.00);  // 7000 K
	vec3 c5 = vec3(0.80, 0.85, 1.00);  // 11000 K
	vec3 c6 = vec3(0.68, 0.76, 1.00);  // 30000 K blue
	if (t < 0.20) return mix(c0, c1, t / 0.20);
	if (t < 0.40) return mix(c1, c2, (t - 0.20) / 0.20);
	if (t < 0.60) return mix(c2, c3, (t - 0.40) / 0.20);
	if (t < 0.75) return mix(c3, c4, (t - 0.60) / 0.15);
	if (t < 0.90) return mix(c4, c5, (t - 0.75) / 0.15);
	return mix(c5, c6, (t - 0.90) / 0.10);
}

// clusterField: the star-specific wrapper on the shared fbm3 (lib/noise.glsl).
float clusterField(vec3 dir) {
	if (uCluster <= 0.0) return 0.0;
	return (fbm3(dir * uClusterScale + 3.0) - 0.5) * 2.0;
}

// One population of stars.
//   cells : lattice density      pxDir : direction units per PIXEL
//   count : cell occupancy       seed  : decorrelates the populations
vec3 starPopulation(vec3 dir, float cells, float pxDir, float count, float seed) {
	vec3 p    = dir * cells;
	vec3 base = floor(p);
	vec3 fr   = p - base;
	vec3 acc  = vec3(0.0);

	// A neighbouring cell matters only when this pixel is within a star radius of the
	// shared face -- rare, since the radius is ~1 px and a cell is tens of px wide.
	// That is what avoids clipped stars without paying for 27 cells every pixel.
	float rrMax = STAR_SIZE * 1.45 * pxDir * cells;

	for (int ox = -1; ox <= 1; ox++) {
		if (float(ox) == -1.0 && fr.x >= rrMax) continue;
		if (float(ox) ==  1.0 && 1.0 - fr.x >= rrMax) continue;
		for (int oy = -1; oy <= 1; oy++) {
			if (float(oy) == -1.0 && fr.y >= rrMax) continue;
			if (float(oy) ==  1.0 && 1.0 - fr.y >= rrMax) continue;
			for (int oz = -1; oz <= 1; oz++) {
				if (float(oz) == -1.0 && fr.z >= rrMax) continue;
				if (float(oz) ==  1.0 && 1.0 - fr.z >= rrMax) continue;

				vec3 c = base + vec3(float(ox), float(oy), float(oz));
				if (hash13(c + seed) > count) continue;      // no star in this cell

				vec3 P = c + 0.15 + 0.70 * hash33(c + seed * 1.7);

				float m   = pow(hash13(c + seed * 3.1), MAGNITUDE);
				float rpx = STAR_SIZE * (0.95 + 0.45 * m);
				float rr  = max(rpx * pxDir * cells, 1e-9);

				float t    = length(p - P) / rr;
				float core = max(0.0, 1.0 - t);
				float b    = core * core * (0.80 + 7.20 * m);

				// GLARE. A bright point spreads into a disc by scattering in the eye and
				// atmosphere -- real optics, not an effect. Weighted by a steep power of
				// the magnitude so only the few brightest stars get it.
				if (uGlow > 0.0) {
					float th   = length(p - P) / (rr * GLOW_SCALE);
					float halo = max(0.0, 1.0 - th);
					b += uGlow * GLOW_GAIN * pow(halo, 5.0) * pow(m, GLOW_POW);
				}

				// temperature, biased hotter for the brighter stars
				float tp  = clamp(pow(hash13(c + seed * 5.3), 1.4) + 0.40 * m, 0.0, 1.0);
				vec3 tint = starColour(tp);

				// Hue-preserving normalisation: letting the channels CLIP turns every
				// bright star white, so normalise to a unit peak instead.
				vec3 contrib = tint * b;
				float pk = max(max(contrib.r, contrib.g), contrib.b);
				if (pk > 1.0) contrib /= pk;

				acc += contrib;
			}
		}
	}
	return acc;
}

// ===== THE CONTRACT =============================================================
vec3 starfieldSky(vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 d = normalize(dir);

	float cl  = clusterField(d);
	float occ = clamp(uCount * (1.0 + uCluster * cl), 0.05, 1.0);

	vec3 col = vec3(0.0);
	col += starPopulation(d, uDensity,      pxPerDir, occ,        0.0) * W1;
	col += starPopulation(d, uDensity * P2, pxPerDir, occ * 0.60, 17.0) * W2;
	col += starPopulation(d, uDensity * P3, pxPerDir, occ * 0.35, 43.0) * W3;

	transmittance = vec3(1.0);  // the starfield is the base layer: it absorbs nothing
	return col * uBright;
}

// ===== HOST (glslviewer) ========================================================
// Everything from this marker down is host plumbing and is REPLACED by the builder.
// The marker line itself (`// ===== HOST`) is what the builder splits on.

void main() {
	// perspective view: screen -> direction
	vec2 uv  = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
	vec3 dir = normalize(vec3(uv, 1.4));

	// direction units per pixel for this view (2*tan(fov/2)/height, fov ~71 degrees)
	float pxPerDir = 1.0 / (1.4 * u_resolution.y);

	vec3 transmittance;  // unused here, but every layer shares one contract
	gl_FragColor = vec4(starfieldSky(dir, pxPerDir, transmittance), 1.0);
}
