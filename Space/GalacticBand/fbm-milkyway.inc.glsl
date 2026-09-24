// fbm-milkyway.inc.glsl — the Milky Way band as a direction-only background layer.
//
// We are INSIDE the galaxy, so the band is not symmetric: it is brighter toward the
// galactic core, thinner and dimmer toward the anticenter, and cut by a dust rift just
// off the midplane. The masks below build that; the texture is value-noise fbm, which is
// far cheaper than the scattered-sphere primitives the reference used.
//
// Extracted so the sky compositor can include exactly the same code. Included by
// fbm-milkyway.frag and Space/Sky/sky.frag.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef FBM_MILKYWAY_INC_GLSL
#define FBM_MILKYWAY_INC_GLSL

#include "lib/hash.glsl"
#include "lib/noise.glsl"
#include "lib/raymarch.glsl"

// value-noise fbm with a variable octave count (for the band's cloud texture)
float mwFbm(vec3 p, float octaves) {
	float a = 0.5, s = 0.0, t = 0.0;
	for (int i = 0; i < 5; i++) {
		if (float(i) >= octaves) break;
		s += a * vnoise(p);
		t += a;
		p *= 2.03;
		a *= 0.5;
	}
	return s / max(t, 1e-5);
}

// The galactic frame from the knobs: `pole` is the band normal (the plane is where
// dot(dir, pole) == 0), and `coreDir` is where the bright core sits in that plane.
vec3 mwGalacticFrame(out vec3 coreDir) {
	float cp = cos(uGalPitch);
	vec3 pole = normalize(vec3(sin(uGalPitch) * cos(uGalYaw), cp, sin(uGalPitch) * sin(uGalYaw)));
	vec3 up = abs(pole.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 x = normalize(cross(pole, up));
	vec3 y = cross(pole, x);
	coreDir = normalize(cos(uGalCoreAngle) * x + sin(uGalCoreAngle) * y);
	return pole;
}

vec3 galacticBandSky(vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 d = normalize(dir);

	vec3 coreDir;
	vec3 pole = mwGalacticFrame(coreDir);

	float b = dot(d, pole);        // height above the galactic plane
	float l = dot(d, coreDir);     // longitude: +1 toward the core, -1 anticenter

	// Brighter toward the core, dimmer toward the anticenter: we are off to one side.
	float asym = 0.35 + 0.65 * smoothstep(-1.0, 1.0, l);

	// The band: thin, and thinner away from the core.
	float width = uGalWidth * (0.5 + 0.75 * smoothstep(-1.0, 1.0, l));
	float band = exp(-(b * b) / (width * width));

	// Cloudy texture inside the band, then a finer granular layer for star clouds.
	float clouds = mwFbm(d * uGalNoiseScale, 4.0);
	float nebulosity = band * mix(0.45, 1.0, clouds) * asym;
	float grain = smoothstep(0.55, 0.95, mwFbm(d * uGalNoiseScale * 4.0, 3.0));
	float starClouds = band * grain * asym;

	// The core bulge.
	float cosang = clamp(dot(d, coreDir), -1.0, 1.0);
	float ang = acos(cosang);
	float core = exp(-(ang * ang) / (uGalCoreSize * uGalCoreSize));

	// Dust: a rift just off the midplane, deepest toward the core.
	float rift = exp(-pow((b - uGalRiftOffset) / uGalRiftWidth, 2.0)) * (0.3 + 0.7 * smoothstep(-1.0, 1.0, l));
	vec3 dustAbs = vec3(0.72, 0.84, 1.0);
	vec3 T = exp(-dustAbs * uGalDust * rift);

	vec3 col = vec3(0.0);
	col += core * vec3(1.00, 0.93, 0.80) * uGalCore;
	col += nebulosity * vec3(0.70, 0.80, 1.00) * uGalBand;
	col += starClouds * vec3(0.85, 0.90, 1.00) * uGalStarClouds;
	col *= T;   // dust carves dark lanes through the band itself

	transmittance = T;
	return col * uGalBright;
}

#endif  // FBM_MILKYWAY_INC_GLSL
