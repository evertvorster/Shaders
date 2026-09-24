// lib/noise.glsl — value noise and fbm, built on lib/hash.glsl.
//
// Requires hash13() to be included first.
//
// GPL-3.0 (see LICENSE at the repository root).

// low-frequency value noise (once per pixel is plenty at these frequencies)
float vnoise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = 0.0;
	for (int z = 0; z < 2; z++)
	for (int y = 0; y < 2; y++)
	for (int x = 0; x < 2; x++) {
		vec3 o = vec3(float(x), float(y), float(z));
		n += hash13(i + o) * (mix(1.0 - f.x, f.x, o.x)
		                    * mix(1.0 - f.y, f.y, o.y)
		                    * mix(1.0 - f.z, f.z, o.z));
	}
	return n;
}
float fbm3(vec3 p) {
	float a = 0.5, s = 0.0, t = 0.0;
	for (int i = 0; i < 3; i++) { s += a * vnoise(p); t += a; p *= 2.03; a *= 0.5; }
	return s / t;
}
