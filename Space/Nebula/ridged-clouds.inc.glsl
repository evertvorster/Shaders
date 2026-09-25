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
// ===== KNOBS ================================================================
// Declared HERE, in the layer, so anything that includes this layer inherits them.
// The builders collect these blocks and emit them as uniforms per host; a scene
// therefore needs no copy of them and cannot fall out of step.
const float uFilScale   = 0.22;  // [0.05, 1.5] field scale: higher = finer strands
const float uFilFreq    = 1.43;  // [1.1, 2.6]  frequency growth per octave
const float uFilVoid    = 0.65;  // [0.05, 0.85] void threshold: higher = sparser strands
const float uFilCore    = 0.00;  // [0, 2]      extra brightness in the cores
const float uFilDensity = 3.60;  // [0.05, 6]   optical depth
const float uFilView    = 25.0;  // [4, 80]     how deep the ray marches
const float uFilSteps   = 16.0;  // [16, 192]   march steps: quality vs speed
const float uFilBright  = 0.167;  // [0, 4]      exposure
const float uFilHue     = 0.695;  // [0, 1]      base hue
const float uFilSat     = 0.39;  // [0, 1]      saturation
const float uFilHueRange = 0.18; // [0, 2]      palette WIDTH: 0 = one hue, 1 = the wheel, >1 = wraps
const float uFilHueScale = 0.90; // [0.1, 6]    how finely the hue follows the clouds
const vec3  uFilBg = vec3(0.000, 0.000, 0.000);  // what shows THROUGH the gas (standalone backdrop)
const float uFilOpacity = 1.00;  // [0, 1]      how much light the gas blocks (lower = translucent)
const float uFilWarp    = 0.78;  // [0, 2]      domain warp: bends the strands (0 = straight)
const float uFilWarpScale = 0.60; // [0.02, 0.6] warp frequency: higher = busier bending
// ===== END KNOBS ============================================================


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
// Where the hue varies from is the important part. It comes from the DENSITY FIELD and from a
// noise sampled in WARPED space (q), so the colour follows the gas. It deliberately does NOT
// use the light lattice: that is a grid, and the creases of a grid are STRAIGHT -- warping
// them by the field's displacement is useless, because that displaces by only ~0.4 world
// units against a 5-unit cell (~8%), which leaves the creases straight. At a tight hue range
// nobody notices; widen the range and you get straight colour bands running through an
// otherwise curly cloud. So colour is driven by warped noise, and the lattice is left to
// modulate brightness only.
vec3 filamentColour(float f, vec3 q, float depth) {
	float v = 0.60 * f + 0.10 * depth + 0.30 * vnoise(q * uFilHueScale);
	float hue = fract(uFilHue + uFilHueRange * (v - 0.5));
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

// The warp displacement, or zero when the warp is off.
vec3 filDisplace(vec3 p) {
	if (uFilWarp > 0.0) return filWarp(p);
	return vec3(0.0);
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

		// The warp is computed ONCE and used for BOTH the density field and the light lattice.
		// Everything the colour reads has to inherit it, or the parts that do not stay straight
		// and show through as straight colour bands. The lattice in particular was evaluated in
		// raw world space -- `mod(p + 2.5, 5.0)` -- and its axis-aligned cell boundaries are
		// literally straight lines: invisible at a tight hue range, plainly visible once the
		// range is widened.
		vec3 wv = filDisplace(p);
		float f = filamentField(p * uFilScale + wv);

		// Voids are the default; strands are where the field is high.
		float dens = smoothstep(uFilVoid, uFilVoid + 0.25, f);
		dens += uFilCore * smoothstep(0.80, 1.00, f);   // extra-bright cores

		if (dens > 0.0) {
			// Brightness still gets the local-light character, but note this is ONLY brightness:
			// the creases of this lattice are straight, which is why the hue no longer reads from it.
			vec3 lp = mod(p + wv + 2.5, 5.0) - 2.5;
			float ldist = max(length(lp), 1e-3);
			float depth = clamp(dist / max(uFilView, 1.0), 0.0, 1.0);

			vec3 e = filamentColour(f, p * uFilScale + wv, depth) / (1.0 + ldist * ldist * 0.35);
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

	// Standalone backdrop: whatever shows through the gas. The layer contract says a layer
	// returns only its OWN emission, and in the compositor that is right -- the star field is
	// composited behind it and this must stay black there, or the background gets counted
	// twice. It exists so the shader is not stuck against pure black when run on its own in
	// glslviewer / SHADERed / the lab. Default black.
	col += uFilBg * T;

	transmittance = T;
	return col;
}

#endif  // RIDGED_CLOUDS_GLSLINC
