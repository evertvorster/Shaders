// milkyway.inc.glsl — the Milky Way as overlapping, sky-spanning components.
//
// This is NOT a distant galaxy (see Space/Galaxy for that) and NOT a volume: we are
// inside it, and it stretches across the sky. It is built from three overlapping things,
// composed front to back:
//
//   1. a dark, turbulent band IN FRONT   — dust, silhouetted against what is behind it
//   2. a bright, turbulent band BEHIND   — the unresolved starlight of the disk
//   3. a galactic core                   — glow with its own dust, at the band's centre
//
// The band is a FINITE ARC, not a great circle: it is thickest at its centre (where the
// core sits) and both thins and fades toward either end, so it spans roughly half the sky
// instead of wrapping all the way around.
//
// Band coordinates:
//   b     = dot(dir, pole)          distance from the galactic plane (0 = midplane)
//   angle = atan2(dot(dir,side), dot(dir,core))   along the band, 0 at the centre
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef MILKYWAY_INC_GLSL
#define MILKYWAY_INC_GLSL

#include "lib/hash.glsl"
#include "lib/noise.glsl"
#include "lib/raymarch.glsl"

vec3 mwPole() {
	float cp = cos(uMwPitch);
	return normalize(vec3(sin(uMwPitch) * cos(uMwYaw), cp, sin(uMwPitch) * sin(uMwYaw)));
}

float mwFbm(vec3 p, int octaves) {
	float a = 0.5, s = 0.0, t = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) break;
		s += a * vnoise(p);
		t += a;
		p *= 2.03;
		a *= 0.5;
	}
	return s / max(t, 1e-5);
}

vec3 milkywaySky(vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 d = normalize(dir);
	vec3 pole = mwPole();

	vec3 up = abs(pole.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 ax = normalize(cross(pole, up));
	vec3 ay = cross(pole, ax);
	vec3 coreDir = normalize(cos(uMwCoreAngle) * ax + sin(uMwCoreAngle) * ay);  // band centre
	vec3 sideDir = cross(pole, coreDir);                                        // 90 deg along

	float b = dot(d, pole);                 // across the band
	float c = dot(d, coreDir);
	float s = dot(d, sideDir);
	float a = atan(s, c) * (2.0 / PI);      // along it: 0 at the centre, +/-1 at the ends

	float aa = abs(a);
	float present = smoothstep(uMwSpan, uMwSpan * 0.45, aa);  // the arc: how far it stretches
	float thick   = smoothstep(1.0, 0.35, aa);                // thick in the middle, thin at the sides

	// Turbulence in BAND coordinates (a, b), so the structure stretches along the band.
	vec3 q = vec3(a, b, 0.0) * uMwNoiseScale;
	float n = smoothstep(0.32, 0.78, mwFbm(q + 3.0, 5));

	// ---- 2. the bright turbulent band ----
	float wBright = uMwWidth * mix(1.0 - uMwTaper, 1.0, thick);
	float band = exp(-(b * b) / (wBright * wBright)) * present;
	float bright = band * (0.20 + 1.60 * n);
	float grain = smoothstep(0.60, 0.95, mwFbm(q * 3.0 + 9.0, 3));
	bright += band * grain * 1.5;           // brighter star-cloud knots

	// ---- 3. the galactic core, at the band centre ----
	float ang = acos(clamp(c, -1.0, 1.0));
	float core = exp(-(ang * ang) / (uMwCoreSize * uMwCoreSize));
	core *= mix(0.35, 1.0, n);              // the core has dust across it

	// ---- 1. the dark turbulent band, IN FRONT ----
	float wDark = uMwDustWidth * mix(1.0 - uMwTaper, 1.0, thick);
	float dark = exp(-pow((b - uMwDustOffset) / wDark, 2.0)) * present;
	dark *= 0.35 + 1.20 * smoothstep(0.25, 0.70, mwFbm(q * 1.4 + 21.0, 4));

	vec3 dustAbs = vec3(0.70, 0.82, 1.0);
	vec3 T = exp(-dustAbs * uMwDust * dark);

	// ---- compose: emission is behind the dark band ----
	vec3 brightColour = vec3(0.72, 0.82, 1.00);
	vec3 coreColour   = vec3(1.00, 0.95, 0.85);

	vec3 col = brightColour * bright * uMwBright + coreColour * core * uMwCore;
	col *= T;

	transmittance = T;
	return col;
}

#endif  // MILKYWAY_INC_GLSL
