// analytic-galaxy.inc.glsl — the Milky Way as a semi-analytic band.
//
// No ray marching. For an exponential disk the vertical path integral has a closed form:
//
//     ∫ exp(-|z|/hz) dt  =  2·hz / |dot(dir, pole)|
//
// so the column density along a line of sight is one divide, not a hundred samples. That
// single term is the band: looking along the plane (dot(dir,pole) -> 0) is a long path;
// looking out of it is a short one. Multiply by the radial falloff at the plane crossing
// for the core asymmetry, then light it from the inside and let the dust absorb over the
// same column.
//
// Because the structure is AUTHORED rather than integrated, nothing averages away -- and
// it costs a handful of ops instead of a loop. The raymarched volume (git history) remains
// the option for flying *into* a nebula; a fixed backdrop does not need it.
//
// Extracted so the sky compositor can include exactly the same code.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef ANALYTIC_GALAXY_INC_GLSL
#define ANALYTIC_GALAXY_INC_GLSL

#include "lib/hash.glsl"
#include "lib/noise.glsl"
// lookAt lives in raymarch; the standalone host uses it.
#include "lib/raymarch.glsl"
// ===== KNOBS ================================================================
// Declared HERE, in the layer, so anything that includes this layer inherits them.
// The builders collect these blocks and emit them as uniforms per host; a scene
// therefore needs no copy of them and cannot fall out of step.
const float uGalPitch       = 0.00;  // [0, 3.14]   tilt of the galactic plane (0 = world XZ)
const float uGalYaw         = 0.00;  // [0, 6.28]   yaw of the plane
const float uGalEmission    = 0.25;  // [0, 4]      how brightly the gas glows
const float uGalDust        = 2.50;  // [0, 6]      dust extinction over the path
const float uGalTurb        = 0.80;  // [0, 1]      turbulence on the column
const float uGalNoiseScale  = 0.50;  // [0.05, 2]   size of the turbulent structure
const float uGalArmCount    = 2.00;  // [1, 6]      number of spiral arms
const float uGalArmTwist    = 4.00;  // [1, 10]     how tightly the arms wind
const float uGalArmStrength = 0.60;  // [0, 1]      arm contrast
const float uGalSoftness    = 0.08;  // [0.01, 0.5] bounds the grazing-ray column
const float uGalBright      = 1.00;  // [0, 4]      exposure
// ===== END KNOBS ============================================================


// The disk, in world units. The galactic centre is the world origin.
#define MW_HZ        1.2   // disk scale height
#define MW_HR        8.0   // disk scale length
#define MW_CORE      3.0   // bulge radius
#define MW_CORE_HZ   1.6   // bulge scale height

vec3 mwPole() {
	float cp = cos(uGalPitch);
	return normalize(vec3(sin(uGalPitch) * cos(uGalYaw), cp, sin(uGalPitch) * sin(uGalYaw)));
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

vec3 galaxySky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 d = normalize(dir);
	vec3 pole = mwPole();

	vec3 up = abs(pole.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 ax = normalize(cross(pole, up));
	vec3 ay = cross(pole, ax);

	float z0 = dot(camPos, pole);
	float dz = dot(d, pole);
	vec3 q0 = camPos - z0 * pole;     // planar origin
	vec3 qd = d - dz * pole;          // planar direction

	// The representative point: the plane crossing if the ray crosses, otherwise the
	// in-plane closest approach (grazing rays, which is what makes the band).
	float t = (abs(dz) > 1e-4) ? (-z0 / dz) : (-dot(q0, qd) / max(dot(qd, qd), 1e-6));
	vec3 q = q0 + t * qd;
	float r = length(q);

	// Slab column (bounded by uGalSoftness so a grazing ray is bright, not infinite),
	// times the radial falloff at the crossing; plus a rounder bulge term.
	float vertical = 2.0 * MW_HZ / (abs(dz) + uGalSoftness);
	float column = vertical * exp(-r / MW_HR)
	             + 0.7 * (MW_CORE_HZ / (abs(dz) + uGalSoftness))
	                   * exp(-(r * r) / (MW_CORE * MW_CORE));

	// Spiral arms and turbulence, authored ON the column: coherent, nothing to average.
	float phi = atan(dot(q, ay), dot(q, ax));
	float twist = log(max(r, 1.0)) * uGalArmTwist;
	float arms = pow(0.5 + 0.5 * cos(uGalArmCount * (phi - twist)), 3.0);
	column *= mix(1.0, 0.10 + 1.90 * arms, uGalArmStrength);

	float n = smoothstep(0.30, 0.80, mwFbm(q * uGalNoiseScale + 11.0, 5));
	column *= mix(1.0, n, uGalTurb);

	// Lit from the inside: emission follows the column. Dust absorbs over the same path,
	// so the source saturates where the path is long and the band is opaque.
	vec3 dustAbs = vec3(0.72, 0.84, 1.0);
	vec3 T = exp(-dustAbs * uGalDust * column);

	float coreness = exp(-r / MW_CORE);
	vec3 emitColour = mix(vec3(0.72, 0.82, 1.0), vec3(1.00, 0.90, 0.72), coreness);

	vec3 col = emitColour * uGalEmission * (1.0 - T);
	transmittance = T;
	return col * uGalBright;
}

#endif  // ANALYTIC_GALAXY_INC_GLSL
