// volumetric-galaxy.inc.glsl — the Milky Way as a VOLUMETRIC disk we are inside.
//
// Instead of painting a band on the sky, this marches a ray through a flattened galaxy
// volume (a "saucer"): an exponential disk plus a central bulge. We sit in the disk, off
// to one side, so:
//
//   * looking along the plane -> a long path through the gas -> the band
//   * looking up/out of the plane -> a short path -> dark sky
//   * looking toward the core -> the path is densest -> the band is brightest. The
//     asymmetry is not a mask, it is the geometry.
//   * a long enough path absorbs (dust), so the far side dims and reddens.
//
// The gas is lit from the inside: emission is proportional to density (unresolved
// starlight), and fbm makes the surface turbulent.
//
// Extracted so the sky compositor can include exactly the same code. The contract takes
// camPos because it is a volume with parallax.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef VOLUMETRIC_GALAXY_INC_GLSL
#define VOLUMETRIC_GALAXY_INC_GLSL

#include "lib/hash.glsl"
#include "lib/noise.glsl"
#include "lib/raymarch.glsl"

// The disk, in world units. The galactic centre is the world origin.
#define MW_RADIUS   30.0   // disk radius
#define MW_HZ        1.2   // disk scale height
#define MW_HR        8.0   // disk scale length
#define MW_CORE      3.0   // bulge radius
#define MW_CORE_HZ   1.6   // bulge scale height

vec3 mwPole() {
	float cp = cos(uGalPitch);
	return normalize(vec3(sin(uGalPitch) * cos(uGalYaw), cp, sin(uGalPitch) * sin(uGalYaw)));
}

// Density of the galaxy at a world point.
float mwDensity(vec3 p, vec3 pole) {
	float z = dot(p, pole);
	float r = length(p - z * pole);
	if (r > MW_RADIUS) return 0.0;
	float disk  = exp(-abs(z) / MW_HZ) * exp(-r / MW_HR);
	float bulge = exp(-(r * r) / (MW_CORE * MW_CORE)) * exp(-abs(z) / MW_CORE_HZ);
	float d = disk + 0.7 * bulge;
	// Make the gas turbulent: clumps and voids rather than a smooth exponential.
	float n = fbm3(p * uGalNoiseScale + 11.0);
	d *= mix(1.0, 0.20 + 1.80 * n, uGalTurb);
	return d;
}

// Exit distance of a ray from a sphere of `radius` centred at the origin (we are inside).
float mwRayExit(vec3 ro, vec3 rd, float radius) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - radius * radius;
	float disc = b * b - c;
	if (disc <= 0.0) return -1.0;
	return -b + sqrt(disc);
}

vec3 galacticBandSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 d = normalize(dir);
	vec3 pole = mwPole();

	float tEnd = mwRayExit(camPos, d, MW_RADIUS);
	if (tEnd <= 0.0) { transmittance = vec3(1.0); return vec3(0.0); }

	int steps = int(uGalSteps);
	float dt = tEnd / float(steps);

	vec3 dustAbs = vec3(0.72, 0.84, 1.0);
	vec3 col = vec3(0.0);
	vec3 T = vec3(1.0);

	for (int i = 0; i < steps; i++) {
		vec3 p = camPos + (float(i) + 0.5) * dt * d;
		float dens = mwDensity(p, pole);
		if (dens > 0.0) {
			float r = length(p - dot(p, pole) * pole);
			float coreness = exp(-r / MW_CORE);
			// warm where the bulge is, cooler out in the disk
			vec3 gasColour = mix(vec3(0.72, 0.82, 1.0), vec3(1.00, 0.90, 0.72), coreness);

			vec3 emission = gasColour * dens * uGalEmission;
			vec3 sigma = dustAbs * uGalDust * dens;
			vec3 tr = exp(-sigma * dt);

			col += T * emission * dt;
			T *= tr;
			if (T.r < 0.003 && T.g < 0.003 && T.b < 0.003) break;
		}
	}

	transmittance = T;
	return col * uGalBright;
}

#endif  // VOLUMETRIC_GALAXY_INC_GLSL
