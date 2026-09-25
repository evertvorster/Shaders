// ridged-clouds.inc.glsl — a raymarched filamentary nebula.
//
// The density field is a RIDGED FILAMENT network: successive rotated sine waves, rectified
// so the field peaks along thin strands instead of forming smooth blobs. That is what a
// supernova remnant or an HII region actually looks like, and it is a different family from
// the gyroid fbm in Space/Nebula/gyroid-clouds.
//
// INSPIRATION, NO CODE TAKEN. The idea of stacking rotated, rectified sine waves for
// filamentary structure comes from the "spiral noise" used on Shadertoy (otaviogood), and
// the superstructure march that popularised it is Duke's / sebastien durand's "Type 2
// Supernova". Those shaders are CC BY-NC-SA, which is incompatible with this repo's GPL-3.0
// (NonCommercial forbids what the GPL grants; ShareAlike conflicts with it). So this is an
// independent implementation of the *technique*: our own rotation construction, our own
// marching, our own lighting and colour, and this repo's layer contract.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef RIDGED_CLOUDS_GLSLINC
#define RIDGED_CLOUDS_GLSLINC

#include "lib/hash.glsl"
#include "lib/noise.glsl"
#include "lib/raymarch.glsl"

#define FILAMENT_OCTAVES 6    // ridge octaves (cost driver)
#define FIL_MAX_STEPS   192   // hard cap on the march loop

// Extinction colour: what the gas absorbs. Dust-ish, slightly blue.
const vec3 FIL_ABSORB = vec3(0.55, 0.75, 1.00);

// A rotation that mixes all three axes, used to reorient the ridge family each octave.
mat3 filRotate(float a, float b) {
	float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
	return mat3(vec3(ca, sa, 0.0), vec3(-sa, ca, 0.0), vec3(0.0, 0.0, 1.0))
	     * mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cb, sb), vec3(0.0, -sb, cb));
}

// Ridged filament field in [0,1].
//
// Each octave measures a wave along two axes. Rectifying with 1 - |...| keeps only the
// ridges and throws the bulk away, so what survives is a network of thin bright strands.
// Rotating the sample between octaves crosses those families, and squaring sharpens them.
float filamentField(vec3 p) {
	mat3 rot = filRotate(1.13, 0.71);
	float acc = 0.0, weight = 0.0, amp = 1.0;
	for (int i = 0; i < FILAMENT_OCTAVES; i++) {
		float r = 1.0 - clamp(abs(sin(p.y) + 0.85 * cos(p.x)), 0.0, 1.0);
		acc += amp * r * r;             // square: sharpen the strand
		weight += amp;
		p = (rot * p) * uFilFreq;       // rise in frequency AND reorient
		amp *= 0.62;
	}
	return clamp(acc / weight * 1.6, 0.0, 1.0);
}

// Hue/val colour, our own (standard) conversion.
vec3 filHSV(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// The strand colour. The hue is held INSIDE A PALETTE: every variation is scaled into
// uFilHueRange around uFilHue, so the strands are a family of related hues rather than a
// trip around the whole wheel. uFilHueRange 1.0 restores the old cycle-everything look.
//
// Note the depth term is normalised by uFilView: it used to be 0.05 * dist, which over a
// 25-unit march rotated the hue more than twice on its own, so depth alone buried the
// chosen palette under every other colour.
vec3 filamentColour(float f, float dist, float lightDist) {
	float depth = clamp(dist / max(uFilView, 1.0), 0.0, 1.0);
	float lit   = clamp(lightDist / 4.3, 0.0, 1.0);
	float v     = 0.55 * f + 0.10 * depth + 0.35 * lit;   // 0..1, our palette coordinate
	float hue   = fract(uFilHue + uFilHueRange * (v - 0.5));
	return filHSV(vec3(hue, uFilSat, 1.0));
}

// Domain warp: bend the sample point with a low-frequency noise field so the strands kink
// and curl instead of staying straight sine sheets. This is the standard trick for making
// a regular analytic pattern look like it grew rather than was drawn -- without it the
// wave families stay visibly straight. Three vnoise calls per sample; branched out when the
// knob is 0, so it costs nothing to leave off.
vec3 filWarp(vec3 p) {
	float s = uFilWarpScale;
	return (vec3(vnoise(p * s),
	             vnoise(p * s + vec3(17.3, 5.1, 9.7)),
	             vnoise(p * s + vec3(41.7, 23.3, 3.9))) - 0.5) * uFilWarp;
}

// The sample point the ridges see: scaled, and warped if the warp is enabled.
vec3 filWarped(vec3 p) {
	vec3 q = p * uFilScale;
	if (uFilWarp > 0.0) q += filWarp(p);
	return q;
}

vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance) {
	vec3 d = normalize(dir);

	int steps = int(uFilSteps);
	float dt = uFilView / float(steps);
	float dist = dt * dither;          // per-pixel dither of the first step (see gyroid-clouds)

	vec3 col = vec3(0.0);
	vec3 T = vec3(1.0);

	for (int i = 0; i < FIL_MAX_STEPS; i++) {
		if (i >= steps) break;
		vec3 p = camPos + dist * d;

		float f = filamentField(filWarped(p));

		// Voids are the default; strands are where the field is high.
		float dens = smoothstep(uFilVoid, uFilVoid + 0.25, f);
		dens += uFilCore * smoothstep(0.80, 1.00, f);   // extra-bright cores

		if (dens > 0.0) {
			// Repeated light sources on a lattice, so strands glow differently as you fly.
			vec3 lp = mod(p + 2.5, 5.0) - 2.5;
			float ldist = max(length(lp), 1e-3);

			vec3 e = filamentColour(f, dist, ldist) / (1.0 + ldist * ldist * 0.35);
			// Extinction is separate from emission so the gas can GLOW without OCCLUDING.
			// uFilOpacity 1.0 is physically balanced; lower it for a translucent nebula
			// you can see through. (Careful: less extinction means the ray no longer hits
			// the early-out, so a very translucent setting runs every step and costs more.)
			vec3 sigma = FIL_ABSORB * dens * uFilDensity * uFilOpacity;
			vec3 tr = exp(-sigma * dt);

			col += T * e * dens * uFilBright * dt;
			T *= tr;
			if (T.r < 0.003 && T.g < 0.003 && T.b < 0.003) break;
		}
		dist += dt;
	}

	transmittance = T;
	return col;
}

#endif  // RIDGED_CLOUDS_GLSLINC
