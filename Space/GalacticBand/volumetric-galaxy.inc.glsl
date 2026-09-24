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
#define MW_H         5.0   // half-height of the bounding cylinder

vec3 mwPole() {
	float cp = cos(uGalPitch);
	return normalize(vec3(sin(uGalPitch) * cos(uGalYaw), cp, sin(uGalPitch) * sin(uGalYaw)));
}

// Density of the galaxy at a world point. `ax`,`ay` are the in-plane basis vectors.
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

float mwDensity(vec3 p, vec3 pole, vec3 ax, vec3 ay) {
	float z = dot(p, pole);
	vec3 planar = p - z * pole;
	float r = length(planar);
	if (r > MW_RADIUS) return 0.0;

	float disk  = exp(-abs(z) / MW_HZ) * exp(-r / MW_HR);
	float bulge = exp(-(r * r) / (MW_CORE * MW_CORE)) * exp(-abs(z) / MW_CORE_HZ);
	float d = disk + 0.7 * bulge;

	// Spiral arms: a logarithmic spiral density pattern in the plane. This is the
	// large-scale structure -- "we are on the side of one of the arms".
	float phi = atan(dot(planar, ay), dot(planar, ax));
	float twist = log(max(r, 1.0)) * uGalArmTwist;
	float arms = 0.5 + 0.5 * cos(uGalArmCount * (phi - twist));
	arms = pow(arms, 3.0);
	d *= mix(1.0, 0.10 + 1.90 * arms, uGalArmStrength);

	// Turbulence: a CONTRAST-STRETCHED fbm. A smooth field just averages out over the
	// ~100 samples of the ray; pushing it through a smoothstep makes clumps and voids.
	float n = mwFbm(p * uGalNoiseScale + 11.0, 5);
	n = smoothstep(0.30, 0.80, n);
	d *= mix(1.0, n, uGalTurb);

	return d;
}

// Span of t for which the ray is inside a finite cylinder (radius `R`, half-height `H`)
// centred at the origin with axis `pole`. Works whether the camera is inside it (looking
// out through the band) or outside it (looking at the galaxy as a distant object).
// No overlap if t0 > t1.
vec2 mwRaySpan(vec3 ro, vec3 rd, vec3 pole, float R, float H) {
	vec3 op = ro - dot(ro, pole) * pole;
	vec3 dp = rd - dot(rd, pole) * pole;
	float t0 = -1e20, t1 = 1e20;

	// the cylinder wall
	float a = dot(dp, dp);
	float b = 2.0 * dot(op, dp);
	float c = dot(op, op) - R * R;
	if (a > 1e-9) {
		float disc = b * b - 4.0 * a * c;
		if (disc <= 0.0) return vec2(1.0, 0.0);
		float sq = sqrt(disc);
		t0 = max(t0, (-b - sq) / (2.0 * a));
		t1 = min(t1, (-b + sq) / (2.0 * a));
	} else if (c > 0.0) {
		return vec2(1.0, 0.0);
	}

	// the slab in z
	float z0 = dot(ro, pole);
	float dz = dot(rd, pole);
	if (abs(dz) > 1e-9) {
		float ta = (-H - z0) / dz;
		float tb = ( H - z0) / dz;
		t0 = max(t0, min(ta, tb));
		t1 = min(t1, max(ta, tb));
	} else if (abs(z0) > H) {
		return vec2(1.0, 0.0);
	}
	return vec2(t0, t1);
}

vec3 galacticBandSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 d = normalize(dir);
	vec3 pole = mwPole();

	vec2 span = mwRaySpan(camPos, d, pole, MW_RADIUS, MW_H);
	float tStart = max(0.0, span.x);
	float tEnd = span.y;
	if (tEnd <= tStart) { transmittance = vec3(1.0); return vec3(0.0); }

	// in-plane basis, for the spiral arms
	vec3 up = abs(pole.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 ax = normalize(cross(pole, up));
	vec3 ay = cross(pole, ax);

	int steps = int(uGalSteps);
	float dt = (tEnd - tStart) / float(steps);

	vec3 dustAbs = vec3(0.72, 0.84, 1.0);
	vec3 col = vec3(0.0);
	vec3 T = vec3(1.0);

	for (int i = 0; i < steps; i++) {
		vec3 p = camPos + (tStart + (float(i) + 0.5) * dt) * d;
		float dens = mwDensity(p, pole, ax, ay);
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
