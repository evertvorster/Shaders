// gyroid-clouds.inc.glsl — this variant's constants, shared maths and contract,
// extracted so other shaders (the sky compositor) can include exactly the
// same code. Included by gyroid-clouds.frag and Space/Sky/sky.frag.
// GPL-3.0 (see LICENSE at the repository root).

#ifndef GYROID_CLOUDS_GLSLINC
#define GYROID_CLOUDS_GLSLINC

// ===== PHYSICS ==================================================================
// The gas, the sun and the box. Constants, not sliders.
const vec3  BETA_RAYLEIGH = 100.0 * vec3(0.05802, 0.14558, 0.331);  // Earth-ish air, tweaked
const vec3  BETA_OZONE    = vec3(0.650, 1.881, 0.085);
const vec3  SIGMA_S = 2.0 * BETA_RAYLEIGH;              // scattering
const vec3  SIGMA_A = 4.0 * (BETA_RAYLEIGH + 3.0 * BETA_OZONE);  // absorption
const vec3  SIGMA_E = SIGMA_A;                          // extinction
const float VOLUME_EXTENT = 10.0;                       // half-size of the cube
const float SUN_POWER     = 200.0;

#define GYROID_OCTAVES 6    // fbm octaves in the density field (cost driver)

// ===== SHARED MATHS =============================================================
// Everything from here to the HOST marker is host-independent and is copied verbatim
// into every generated output. Shared maths lives in lib/; the builder inlines the
// includes so generated files stay self-contained. This source runs in glslviewer
// with `-I <repo root>`.

#include "lib/hash.glsl"
#include "lib/raymarch.glsl"

//-------------------------------- Shape --------------------------------

// A gyroid is a triply-periodic minimal surface; |...| turns it into a shell, and the
// fbm below stacks rotated copies at falling amplitude to make cloud structure.
float gyroid(vec3 p, float thickness, float bias, float frequency) {
	return clamp(abs(dot(sin(p * 0.5), cos(p.zxy * 1.23) * frequency) - bias) - thickness,
	             0.0, 3.0) / 3.0;
}

float gyroidFbm(vec3 p) {
	const int   octaves = GYROID_OCTAVES;
	const float fbmScale = 1.95;
	float a = PI / float(octaves);
	mat3 m3 = fbmScale * mat3(vec3(cos(a), sin(a), 0.0),
	                          vec3(-sin(a), cos(a), 0.0),
	                          vec3(0.0, 0.0, 1.0));
	float weight = 0.0;
	float amplitude = 1.0;
	float frequency = 1.0;
	float res = 0.0;
	for (int i = 0; i < octaves; i++) {
		res += amplitude * gyroid(p, 0.1, 0.0, frequency);
		p *= m3;
		weight += amplitude;
		amplitude *= (i < 4) ? 0.9 : 0.7;
		frequency *= (i < 3) ? 0.65 : 0.78;
	}
	return clamp(res / weight, 0.0, 1.0);
}

// Density of the gas at a world point. Zero outside the box. Away from the centre the
// noise becomes a haze shell and, sharper, a structure shell -- so we sit in a cavity
// looking out at clouds rather than inside a uniform fog.
float cloudDensity(vec3 p) {
	if (p.x < -VOLUME_EXTENT || p.x > VOLUME_EXTENT ||
	    p.y < -VOLUME_EXTENT || p.y > VOLUME_EXTENT ||
	    p.z < -VOLUME_EXTENT || p.z > VOLUME_EXTENT) {
		return 0.0;
	}
	float n = gyroidFbm(uNebNoiseScale * p);
	float r = length(p);
	float structure = smoothstep(3.0, 5.0, r) * smoothstep(0.05, 0.10, n) * uNebStructure;
	float haze      = smoothstep(2.0, 10.0, r) * smoothstep(0.02, 0.50, n) * uNebHaze;
	return uNebDensity * (3e-4 + 0.5 * haze + 0.75 * structure);
}

//-------------------------------- Local stars --------------------------------

// Star colour by temperature, as a cosine palette (Inigo Quilez).
vec3 starTint(float t) {
	vec3 a = vec3(0.65);
	vec3 b = 1.0 - a;
	vec3 c = vec3(1.0);
	vec3 d = vec3(0.15, 0.5, 0.75);
	return pow(a + b * cos(2.0 * PI * (c * t + d)), vec3(2.2));
}

// One star per cell near p, with a tight glow. These are LOCAL stars -- inside the gas
// volume, not on the distant dome -- so the gas can occlude them and they can light it.
vec3 localStars(vec3 p) {
	p *= 0.2;
	vec3 bestRand = vec3(0.0);
	vec3 bestCell = vec3(0.0);
	float best = 1e10;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 c = floor(p) + vec3(float(x), float(y), float(z));
		vec3 h = 2.0 * hash33(c) - 1.0;          // in [-1, 1]
		vec3 f = c + 0.5 + 0.5 * h;
		float dd = length(p - f);
		if (dd < best) { best = dd; bestRand = h; bestCell = c; }
	}
	vec3 r1 = clamp(0.5 + 0.5 * bestRand, 0.0, 1.0);
	vec3 r2 = clamp(0.5 + 0.5 * (2.0 * hash33(bestCell + vec3(3.12, 104.9, -9.5)) - 1.0),
	                0.0, 1.0);
	float glow = max(0.0, pow(0.25 / max(best, 1e-5), 2.0));
	return vec3(0.05) * r1.z * step(0.45, r2.z)
	     * mix(vec3(1.0), starTint(r1.y), 0.3)
	     * smoothstep(0.5, 0.0, best) * glow;
}

//-------------------------------- Lighting --------------------------------

// Multi-octave scattering (the Frostbite/Hillaire formulation): a few cheaper, broader
// scattering events stand in for the many real ones.
vec3 multipleOctaves(float extinction, float mu, float stepL) {
	vec3 luminance = vec3(0.0);
	const int octaves = 6;   // int, not float: safer across GLSL/Godot loop forms
	float a = 1.0;  // attenuation
	float b = 1.0;  // contribution
	float c = 1.0;  // phase attenuation
	for (int i = 0; i < octaves; i++) {
		float phase = mix(hgPhase(-0.1 * c, mu), hgPhase(0.3 * c, mu), 0.7);
		luminance += b * phase * exp(-stepL * extinction * SIGMA_E * a);
		a *= 0.3;
		b *= 0.5;
		c *= 0.5;
	}
	return luminance;
}

// Light reaching p from the sun, by marching a short ray toward it and applying
// Beers-Law, blended with the powder effect for backlighting.
vec3 lightRay(vec3 p, float mu, vec3 sunDirection) {
	vec2 hit = intersectAABB(p, sunDirection, vec3(-VOLUME_EXTENT), vec3(VOLUME_EXTENT));
	float lightRayDistance = VOLUME_EXTENT * 0.25;
	if (hit.x < hit.y && hit.y > 0.0) {
		lightRayDistance = hit.y - max(hit.x, 0.0);
	}
	int lsteps = max(3, int(uNebSteps * 0.25));
	float stepL = lightRayDistance / float(lsteps);
	float lightRayDensity = 0.0;
	for (int j = 0; j < lsteps; j++) {
		lightRayDensity += cloudDensity(p + sunDirection * float(j) * stepL);
	}
	vec3 beersLaw = multipleOctaves(lightRayDensity, mu, stepL);
	return mix(beersLaw * 2.0 * (1.0 - exp(-stepL * lightRayDensity * 2.0 * SIGMA_E)),
	           beersLaw, 0.5 + 0.5 * mu);
}

//-------------------------------- Raymarching --------------------------------

// Colour along one view ray, and the transmittance of everything in front of what is
// behind the volume (so distant stars can be composed in).
vec3 mainRay(vec3 org, vec3 dir, vec3 sunDirection, out vec3 totalTransmittance,
             float offset) {
	totalTransmittance = vec3(1.0);
	vec3 colour = vec3(0.0);

	vec2 hit = intersectAABB(org, dir, vec3(-VOLUME_EXTENT), vec3(VOLUME_EXTENT));

	// Start at the camera when it is inside the box, otherwise at the near face.
	bool inside = org.x > -VOLUME_EXTENT && org.x < VOLUME_EXTENT &&
	              org.y > -VOLUME_EXTENT && org.y < VOLUME_EXTENT &&
	              org.z > -VOLUME_EXTENT && org.z < VOLUME_EXTENT;
	float distToStart = inside ? 0.0 : hit.x;
	float distToEnd   = hit.y;
	if (!(distToEnd > distToStart) || distToEnd <= 0.0) return colour;

	int steps = int(uNebSteps);
	float stepS = (distToEnd - distToStart) / float(steps);
	distToStart += stepS * offset;

	float dist = distToStart;
	vec3 p = org + dist * dir;
	float mu = dot(dir, sunDirection);
	float phaseFunction = mix(hgPhase(-0.3, mu), hgPhase(0.3, mu), 0.7);
	vec3 sunLight = vec3(SUN_POWER);

	for (int i = 0; i < steps; i++) {
		float density = cloudDensity(p);
		if (density > 0.0) {
			vec3 sampleSigmaS = SIGMA_S * density;
			vec3 sampleSigmaE = SIGMA_E * density;

			// Local starlight, scaled by how much gas is here (so stars brighten the
			// clouds they sit in, not empty space).
			vec3 ambient = vec3(0.0);
			if (uNebLocalStars > 0.0) {
				ambient = uNebLocalStars * localStars(p);
				ambient *= smoothstep(1e-3, 2e-3, density);
			}

			vec3 luminance = ambient + sunLight * phaseFunction * lightRay(p, mu, sunDirection);
			luminance *= sampleSigmaS;

			vec3 transmittance = exp(-sampleSigmaE * stepS);

			// Energy-conserving in-scattering integration (Frostbite 5.6).
			colour += totalTransmittance * (luminance - luminance * transmittance) / sampleSigmaE;
			totalTransmittance *= transmittance;

			if (totalTransmittance.r + totalTransmittance.g + totalTransmittance.b <= 0.003) {
				totalTransmittance = vec3(0.0);
				return colour;
			}
		}
		dist += stepS;
		p = org + dir * dist;
	}
	return colour;
}

// ===== THE CONTRACT =============================================================
vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 d = normalize(dir);
	vec3 sunDirection = normalize(vec3(cos(uNebSunAngle), uNebSunHeight, sin(uNebSunAngle)));
	vec3 colour = mainRay(camPos, d, sunDirection, transmittance, 0.0);
	return colour * uNebBright;
}

#endif  // GYROID_CLOUDS_GLSLINC
