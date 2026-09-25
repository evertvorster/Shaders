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
// Scattering and extinction are now functions of the colour knobs, so the palette is
// art rather than physics. The knobs scale the coefficients, so (1,1,1) reproduces the
// original look exactly; suppress a channel to shift the whole nebula's colour.
vec3 sigmaS() { return 2.0 * BETA_RAYLEIGH * uNebGlowColour; }
vec3 sigmaE() { return 4.0 * (BETA_RAYLEIGH + 3.0 * BETA_OZONE) * uNebAbsorbColour; }
const float LIGHT_DIST    = 18.0;   // how far the sun ray is marched (no box any more)
const float SUN_POWER     = 200.0;

#define GYROID_OCTAVES 4    // fbm octaves in the density field (cost driver: 6 -> 4)
#define SHADOW_OCTAVES 2    // octaves for the sun ray: shapes only, no filigree

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

float gyroidFbmLod(vec3 p, int octaves) {
	const float fbmScale = 1.95;
	float a = PI / float(GYROID_OCTAVES);
	mat3 m3 = fbmScale * mat3(vec3(cos(a), sin(a), 0.0),
	                          vec3(-sin(a), cos(a), 0.0),
	                          vec3(0.0, 0.0, 1.0));
	float weight = 0.0;
	float amplitude = 1.0;
	float frequency = 1.0;
	float res = 0.0;
	for (int i = 0; i < GYROID_OCTAVES; i++) {
		if (i >= octaves) break;
		res += amplitude * gyroid(p, 0.1, 0.0, frequency);
		p *= m3;
		weight += amplitude;
		amplitude *= (i < 4) ? 0.9 : 0.7;
		frequency *= (i < 3) ? 0.65 : 0.78;
	}
	return clamp(res / weight, 0.0, 1.0);
}

float gyroidFbm(vec3 p) { return gyroidFbmLod(p, GYROID_OCTAVES); }

// Density of the gas at a world point. UNBOUNDED: there is no box.
//
// The field is a 3D noise function, defined everywhere, so we never meet a wall -- fly in
// any direction and there is always new gas ahead. There is also NO radial shaping: the
// voids come from the noise rather than from a cavity, which is what makes it read as a
// nebula you are inside rather than a shell painted on a box.
//
// The octave count is a parameter so the SHADOW ray can sample a cheaper version of the
// same field: shadows only need the cloud shapes, not the fine structure, and the shadow
// ray is ~75% of the cost of this shader.
float cloudDensityLod(vec3 p, int octaves) {
	float n = gyroidFbmLod(uNebNoiseScale * p, octaves);
	// Voids are the default; a cloud is where the noise is high. Both the haze and the
	// structure ride on that mask -- otherwise a term like smoothstep(0.02,0.5,n) is ~1
	// everywhere and the whole volume glows uniformly.
	float cloud = smoothstep(uNebVoid, uNebVoid + 0.22, n);
	float density = cloud * (0.5 * uNebHaze + 0.75 * uNebStructure);
	return uNebDensity * (1e-4 + density);
}

float cloudDensity(vec3 p) { return cloudDensityLod(p, GYROID_OCTAVES); }
float cloudDensityShadow(vec3 p) { return cloudDensityLod(p, SHADOW_OCTAVES); }

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
		luminance += b * phase * exp(-stepL * extinction * sigmaE() * a);
		a *= 0.3;
		b *= 0.5;
		c *= 0.5;
	}
	return luminance;
}

// Light reaching p from the sun, by marching a short ray toward it and applying
// Beers-Law, blended with the powder effect for backlighting.
vec3 lightRay(vec3 p, float mu, vec3 sunDirection) {
	// No bounds: the sun ray just marches a fixed distance -- far enough for the gas to
	// occlude it, which is all the shadowing needs.
	float lightRayDistance = LIGHT_DIST;
	// Fewer shadow steps than before: each one is a full density sample, and this is the
	// inner loop of the whole shader.
	int lsteps = max(2, int(uNebSteps * 0.15));
	float stepL = lightRayDistance / float(lsteps);
	float lightRayDensity = 0.0;
	for (int j = 0; j < lsteps; j++) {
		lightRayDensity += cloudDensityShadow(p + sunDirection * float(j) * stepL);
	}
	vec3 beersLaw = multipleOctaves(lightRayDensity, mu, stepL);
	return mix(beersLaw * 2.0 * (1.0 - exp(-stepL * lightRayDensity * 2.0 * sigmaE())),
	           beersLaw, 0.5 + 0.5 * mu);
}

//-------------------------------- Raymarching --------------------------------

// Colour along one view ray, and the transmittance of everything in front of what is
// behind the volume (so distant stars can be composed in).
vec3 mainRay(vec3 org, vec3 dir, vec3 sunDirection, out vec3 totalTransmittance,
             float offset) {
	totalTransmittance = vec3(1.0);
	vec3 colour = vec3(0.0);

	// UNBOUNDED -- no box and no intersection to find. The gas is a 3D noise field defined
	// everywhere, so we always start at the camera and march a fixed visible depth: every
	// step is new gas wherever we are. Fly forever, fresh clouds ahead.
	int steps = int(uNebSteps);
	float stepS = uNebView / float(steps);
	float dist  = stepS * offset;
	vec3 p = org + dist * dir;

	float mu = dot(dir, sunDirection);
	float phaseFunction = mix(hgPhase(-0.3, mu), hgPhase(0.3, mu), 0.7);
	vec3 sunLight = vec3(SUN_POWER) * uNebSunColour;

	for (int i = 0; i < steps; i++) {
		float density = cloudDensity(p);
		if (density > 0.0) {
			vec3 sampleSigmaS = sigmaS() * density;
			vec3 sampleSigmaE = sigmaE() * density;

			// Lit only by the sun. There is deliberately NO in-volume star field here: the
			// stars are the compositor's business (Space/Starfield), and a 27-cell star
			// scan per march step was the most expensive thing in this shader.
			vec3 luminance = sunLight * phaseFunction * lightRay(p, mu, sunDirection);
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
// `dither` offsets the first step per pixel (0..1). Without it the samples sit at fixed
// distances from the CAMERA, so flying forward slides the whole sampling lattice through the
// gas and the banding flickers. Dithering turns that into fixed grain instead.
vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance) {
	vec3 d = normalize(dir);
	vec3 sunDirection = normalize(vec3(cos(uNebSunAngle), uNebSunHeight, sin(uNebSunAngle)));
	vec3 colour = mainRay(camPos, d, sunDirection, transmittance, dither * uNebDither);
	return colour * uNebBright;
}

#endif  // GYROID_CLOUDS_GLSLINC
