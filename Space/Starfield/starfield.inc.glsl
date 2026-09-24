// starfield.inc.glsl — the starfield's constants, shared maths and contract,
// extracted so other shaders (the sky compositor) can include exactly the
// same code. Included by starfield.frag and Space/Sky/sky.frag.
// GPL-3.0 (see LICENSE at the repository root).

#ifndef STARFIELD_GLSLINC
#define STARFIELD_GLSLINC

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
	if (uStarCluster <= 0.0) return 0.0;
	return (fbm3(dir * uStarClusterScale + 3.0) - 0.5) * 2.0;
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
				if (uStarGlow > 0.0) {
					float th   = length(p - P) / (rr * GLOW_SCALE);
					float halo = max(0.0, 1.0 - th);
					b += uStarGlow * GLOW_GAIN * pow(halo, 5.0) * pow(m, GLOW_POW);
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
	float occ = clamp(uStarCount * (1.0 + uStarCluster * cl), 0.05, 1.0);

	vec3 col = vec3(0.0);
	col += starPopulation(d, uStarDensity,      pxPerDir, occ,        0.0) * W1;
	col += starPopulation(d, uStarDensity * P2, pxPerDir, occ * 0.60, 17.0) * W2;
	col += starPopulation(d, uStarDensity * P3, pxPerDir, occ * 0.35, 43.0) * W3;

	transmittance = vec3(1.0);  // the starfield is the base layer: it absorbs nothing
	return col * uStarBright;
}

#endif  // STARFIELD_GLSLINC
