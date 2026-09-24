// lib/raymarch.glsl — helpers for raymarched volumetric layers.
//
// Pure maths with no host assumptions: camera basis, ray/box intersection, phase
// functions, and a texture-free dither. Included (inlined) by Tools/build_*.glsl.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef PI
#define PI 3.141592653589793
#endif

// Slab-method ray/AABB intersection (DomNomNom). Returns (tNear, tFar) in ray units;
// there is no hit when tNear > tFar.
vec2 intersectAABB(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax) {
	vec3 tMin = (bmin - ro) / rd;
	vec3 tMax = (bmax - ro) / rd;
	vec3 t1 = min(tMin, tMax);
	vec3 t2 = max(tMin, tMax);
	return vec2(max(max(t1.x, t1.y), t1.z), min(min(t2.x, t2.y), t2.z));
}

// Henyey-Greenstein phase function. g in (-1, 1): negative scatters back, positive
// forward. mu is the cosine between the view ray and the light direction.
float hgPhase(float g, float cosTheta) {
	return (1.0 / (4.0 * PI)) * ((1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosTheta, 1.5));
}

// Interleaved gradient noise: a cheap per-pixel dither, used to offset the first ray
// step so the marching does not band. No blue-noise texture needed, so it works in
// every host (SHADERed, glslviewer, Godot).
float ign(vec2 fragCoord) {
	return fract(52.9829189 * fract(dot(fragCoord, vec2(0.06711056, 0.00583715))));
}

// Camera basis: columns are right, up, -forward, so a view-space ray (forward is -Z)
// maps into world space. `fwd` is the direction the camera looks.
mat3 lookAt(vec3 fwd, vec3 up) {
	vec3 zaxis = normalize(fwd);
	vec3 xaxis = normalize(cross(zaxis, up));
	vec3 yaxis = cross(xaxis, zaxis);
	return mat3(xaxis, yaxis, -zaxis);
}
