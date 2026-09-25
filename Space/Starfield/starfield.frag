// starfield.frag — Vega Strike / SpaceSim starfield BASE LAYER (canonical source).
//
// This file is the single source of truth. `Tools/build_starfield.py` generates every
// other format from it:
//
//   starfield.glsl      SHADERed / Shadertoy-style (iResolution, out vec4 outColor)
//   starfield.sprj      a ready-to-open SHADERed project (carries the slider values)
//   starfield.gdshader  Godot 4 spatial shader for a sky sphere
//
// and this file itself runs directly in glslviewer:
//   glslviewer starfield.frag
//
// ---------------------------------------------------------------- THE MODEL
// Stars are a uniformly random field. Each star's brightness and colour come from
// bounded distributions; brightness stands in for distance, because on the sky
// "closer" IS "brighter". That is not a shortcut: a uniform volume distribution with
// an inverse-square falloff yields exactly a power-law magnitude distribution, which
// is what the magnitude law below produces.
//
// ---------------------------------------------------------------- THE CONTRACT
//     vec3 starfieldSky(vec3 dir, float pxPerDir, out vec3 transmittance);
//
// `dir` is any direction (need not be normalised). `pxPerDir` is the only
// host-specific value -- the direction-units-per-*pixel* of the view being rendered:
//
//     Godot sphere : pxPerDir = 2 * tan(fov_y / 2) / viewport_height
//     cubemap face : pxPerDir = 2 / faceSize
//     glslviewer   : pxPerDir = 2 * tan(fov/2) / height   (see HOST below)
//
// Keeping star size in PIXELS this way means the same shader looks identical in the
// game, in the editor, and in a baked cubemap.
//
// The function returns STARS ONLY. Every layer uses the same contract: it returns its
// own emission and writes into `transmittance` the fraction of the light from BEHIND
// it that survives -- per channel, because dust and gas absorb unevenly and redden
// what is behind them. The starfield absorbs nothing, so it writes vec3(1.0) -- that is
// literally true, not a placeholder -- which lets layers compose with a single fold and
// no special case for the base:
//
//     vec3 T;
//     vec3 col = nebulaSky(camPos, dir, ppd, T);   // nearest layer's emission
//     col += starfieldSky(dir, ppd, T);            // ...times what gets through it
//
// Over a list, far to near:  col = layerSky(..., T) + T * col;
//
// ---------------------------------------------------------------- LICENCE
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// The starfield's constants, shared maths and contract live in starfield.glslinc
// (below), so the sky compositor can include the identical code. Nothing to see here.

// ===== VARIABLES ================================================================
// The knobs live in the layer's .inc.glsl (see its KNOBS block) so that scenes
// inherit them instead of copying them. Add or change them THERE.

// ===== VARIABLES ================================================================
// The knobs. Each is annotated `[min, max]` for the generated hosts. In this file
// (the glslviewer build) they are `const` because glslviewer cannot set custom
// uniforms; the builder promotes them to real uniforms for SHADERed and Godot.


// ===== SHARED MATHS ===========================================================
#include "Space/Starfield/starfield.inc.glsl"

// ===== HOST (glslviewer) ========================================================
// Everything from this marker down is host plumbing and is REPLACED by the builder.
// The marker line itself (`// ===== HOST`) is what the builder splits on.

void main() {
	// perspective view: screen -> direction
	vec2 uv  = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
	vec3 dir = normalize(vec3(uv, 1.4));

	// direction units per pixel for this view (2*tan(fov/2)/height, fov ~71 degrees)
	float pxPerDir = 1.0 / (1.4 * u_resolution.y);

	vec3 transmittance;  // unused here, but every layer shares one contract
	gl_FragColor = vec4(starfieldSky(dir, pxPerDir, transmittance), 1.0);
}
