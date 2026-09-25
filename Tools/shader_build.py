#!/usr/bin/env python3
"""shader_build.py — the shared build plumbing for every shader source in the repo.

Every builder used to re-implement the same things: inlining `#include`, splitting the
source on its section markers, parsing knob declarations, emitting the SHADERed project,
emitting the Godot host, and verifying the result with glslangValidator. Seven copies of
that, drifting apart. This module owns it once.

A builder is now just: where its sources are, and the one line that calls its layer.

    # Tools/build_<thing>.py
    import shader_build as sb
    OUTDIR = os.path.join(sb.ROOT, "Space", "<Thing>")
    sb.main(OUTDIR, sb.glob_sources(OUTDIR), "nebulaSky",
            glsl_body="col = nebulaSky(uCamPos, dir, pxPerDir, dither, transmittance);")

## The source format

A canonical source is split on four markers, in order:

    // ===== PHYSICS        constants that are not taste (and are NOT knobs)
    // ===== VARIABLES      the knobs, `const float name = value;  // [min, max] note`
    // ===== SHARED MATHS   host-independent code; `#include`s are inlined from the repo root
    // ===== HOST           the glslviewer build; REPLACED entirely by every generated host

The `.frag` itself is the glslviewer build. The generated files are self-contained: the
includes are inlined, because SHADERed and Godot do not resolve include paths.

## Generated files

    <base>.glsl       SHADERed / Shadertoy-style
    <base>.sprj       SHADERed project (carries the knob values)
    <base>.vert       the screen-quad vertex shader the .sprj needs
    <base>.gdshader   Godot 4 spatial shader for a sky sphere

## Traps this module encodes

- `#include` lines must be BARE. The regex matches the whole line, so an include with a
  trailing comment is silently left unresolved and only surfaces as glslangValidator's
  cryptic `missing #endif`.
- glslangValidator does NOT recognise the `.glsl` extension: without `-S <stage>` it
  prints usage and exits non-zero having compiled nothing. The stage is always stated, and
  a nonzero exit is a failure -- grepping for the literal "ERROR" alone reports false OK.
- A host emitter can forget to interpolate `{physics}`/`{shared}` and emit a file with NO
  functions in it, which passes every structural check. `check_host_has_shared()` catches
  that, and is run for every generated shader host.
"""

import glob
import math
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# The whole line, deliberately: a trailing comment must NOT silently disable an include.
INCLUDE_RE = re.compile(r'^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$', re.M)

VAR_RE = re.compile(
    r"^const\s+float\s+(\w+)\s*=\s*([-\d.]+)\s*;\s*(?://\s*)?(?:\[([^\]]+)\]\s*)?(.*)$")

# Colour knobs: `const vec3 NAME = vec3(r, g, b);  // note`. Promoted to a real vec3
# uniform per host (a Godot colour picker via : source_color, a SHADERed float3).
VEC3_RE = re.compile(
    r"^const\s+vec3\s+(\w+)\s*=\s*vec3\(([^)]*)\)\s*;\s*(?://\s*)?(.*)$")


# A layer declares its knobs in its OWN .inc.glsl, inside this block, so anything that
# includes the layer inherits them automatically -- which is the point: a scene no longer has
# to copy them, and cannot silently fall out of step when one changes.
KNOB_BLOCK_RE = re.compile(
    r"^[ \t]*// ===== KNOBS[^\n]*\n(.*?)^[ \t]*// ===== END KNOBS[^\n]*\n", re.M | re.S)


def collect_knob_lines(text):
    """Every knob declaration inside a KNOBS block, in file order."""
    lines = []
    for m in KNOB_BLOCK_RE.finditer(text):
        lines.extend(m.group(1).split("\n"))
    return lines


def strip_knob_blocks(text):
    """Remove KNOBS blocks.

    A host gets the knobs as UNIFORM declarations (so SHADERed can edit them and Godot can
    hint them); leaving the `const` versions in place as well would redeclare every knob.
    """
    return KNOB_BLOCK_RE.sub("", text)


def resolve_includes(text):
    """Inline `#include "path"` lines, paths relative to the repo root."""
    def repl(m):
        path = os.path.join(ROOT, m.group(1))
        if not os.path.isfile(path):
            raise SystemExit("include not found: %s" % path)
        with open(path) as f:
            return resolve_includes(f.read()).rstrip()
    return INCLUDE_RE.sub(repl, text)


def parse_knobs(lines):
    """Parse knob declarations out of a list of lines."""
    variables = []
    for ln in lines:
        line = ln.strip()
        m = VEC3_RE.match(line)
        if m:
            name, comps, note = m.groups()
            vals = [c.strip() for c in comps.split(",")]
            if len(vals) != 3:
                raise SystemExit("vec3 knob needs 3 components: %s" % line)
            variables.append({"name": name, "type": "vec3", "value": vals,
                              "min": None, "max": None, "note": (note or "").strip()})
            continue
        m = VAR_RE.match(line)
        if m:
            name, value, rng, note = m.groups()
            lo = hi = None
            if rng:
                parts = [p.strip() for p in rng.split(",")]
                if len(parts) == 2:
                    lo, hi = float(parts[0]), float(parts[1])
            variables.append({"name": name, "type": "float", "value": value,
                              "min": lo, "max": hi, "note": (note or "").strip()})
    return variables


def read_source(path):
    """Split a canonical source into (physics, shared, variables).

    Knobs come from two places: the source's own VARIABLES section (scene-level knobs) and
    any KNOBS block in an included layer. Duplicates are an error rather than a silent
    shadowing.
    """
    with open(path) as f:
        resolved = resolve_includes(f.read())
    lines = resolved.split("\n")

    def find(prefix):
        for i, ln in enumerate(lines):
            if ln.startswith(prefix):
                return i
        raise SystemExit("marker not found in %s: %r" % (path, prefix))

    i_phys = find("// ===== PHYSICS")
    i_vars = find("// ===== VARIABLES")
    i_shared = find("// ===== SHARED MATHS")
    i_host = find("// ===== HOST")

    physics = strip_knob_blocks("\n".join(lines[i_phys:i_vars])).rstrip()
    shared = strip_knob_blocks("\n".join(lines[i_shared:i_host])).rstrip()

    variables = parse_knobs(lines[i_vars:i_shared]) + parse_knobs(collect_knob_lines(resolved))
    seen = set()
    for v in variables:
        if v["name"] in seen:
            raise SystemExit("knob %s is declared twice in %s (a scene and a layer both?)"
                             % (v["name"], path))
        seen.add(v["name"])
    if not variables:
        raise SystemExit("no variables parsed in %s -- check the annotations" % path)
    return physics, shared, variables


# ---------------------------------------------------------------- host emission

def decl(v):
    """The uniform declaration for one knob in a GLSL host."""
    return "uniform %s %s;" % ("vec3" if v["type"] == "vec3" else "float", v["name"])


def godot_step(lo, hi):
    span = max(hi - lo, 1e-6)
    return 10.0 ** math.floor(math.log10(span / 100.0))


def godot_uniform(v):
    if v["type"] == "vec3":
        return "uniform vec3 %s : source_color = vec3(%s);  // %s" % (
            v["name"], ", ".join(v["value"]), v["note"])
    if v["min"] is not None:
        return "uniform float %s : hint_range(%.6g, %.6g, %.6g) = %s;  // %s" % (
            v["name"], v["min"], v["max"], godot_step(v["min"], v["max"]), v["value"], v["note"])
    return "uniform float %s = %s;  // %s" % (v["name"], v["value"], v["note"])


def generated_header(builder, source, comment="//"):
    return ("%s GENERATED by Tools/%s via Tools/shader_build.py from %s"
            " -- do not edit by hand." % (comment, builder, source))


def emit_shadered(builder, source, physics, shared, variables, body,
                  dither=True, tonemap=True):
    """The SHADERed / Shadertoy-style host.

    `body` must leave the result in `col`. The camera ray comes from SHADERed's own
    uView/uProj system variables, so its arcball and first-person cameras really do drive
    the view -- its built-in preview camera cannot drive a screen-quad pass that computes
    its own ray.
    """
    uni = "\n".join(decl(v) for v in variables)
    dither_line = ("	// Dither the first step per pixel: without it, flying forward slides the\n"
                   "	// sampling lattice through the volume and the banding flickers.\n"
                   "	float dither = ign(gl_FragCoord.xy);\n") if dither else ""
    finish = ("	col = aces(col);\n	outColor = vec4(pow(col, vec3(0.4545)), 1.0);" if tonemap
              else "	outColor = vec4(col, 1.0);")
    return f"""#version 330
out vec4 outColor;

{generated_header(builder, source)}
// SHADERed build. NOTE: #version must be the literal first line for SHADERed, and its
// GLSL mode is Shadertoy-compatible (iResolution / iMouse / iTime).
uniform vec2  iResolution;
uniform float iTime;
uniform vec2  iMouse;

// SHADERed system variables: driven by SHADERed's own preview camera.
uniform mat4 uView;
uniform mat4 uProj;
uniform vec3 uCamPos;

// The knob values live in the .sprj, not here: GLSL uniforms cannot have initialisers,
// which is why SHADERed shows them as variables you can edit (right-click the pass ->
// Variables, then pin them with +).
{uni}

{physics}

{shared}

vec3 aces(vec3 x) {{
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}}

void main() {{
	vec2 ndc = (gl_FragCoord.xy / iResolution.xy) * 2.0 - 1.0;

	// View-space ray straight from the projection matrix (no fov/aspect guesswork),
	// rotated into the world by the inverse view rotation (a transpose).
	vec3 viewRay = vec3(ndc.x / uProj[0][0], ndc.y / uProj[1][1], -1.0);
	vec3 dir = normalize(transpose(mat3(uView)) * viewRay);
	float pxPerDir = 2.0 / (uProj[1][1] * iResolution.y);

{dither_line}	vec3 transmittance;
	vec3 col = vec3(0.0);
{body}

{finish}
}}
"""


def emit_godot(builder, source, physics, shared, variables, body,
               dither=True, tonemap=True):
    """The Godot 4 spatial shader for a sky sphere.

    `body` must leave the result in `col`.

    CRITICAL: the world direction is computed in vertex(). Inside fragment(), VERTEX is in
    VIEW space, so transforming it there gives a value that never changes when the camera
    rotates -- the sky gets painted on the screen. It cost us once.
    """
    uni = "\n".join(godot_uniform(v) for v in variables)
    dither_line = "	float dither = ign(FRAGCOORD.xy);\n" if dither else ""
    tone = """
// ACES filmic tone map (Krzysztof Narkowicz). The canonical source keeps this in its HOST
// section, which the builder replaces, so the generated host carries its own.
vec3 aces(vec3 x) {
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}
""" if tonemap else ""
    finish = ("	col = aces(col);\n	ALBEDO = pow(col, vec3(0.4545));" if tonemap
              else "	ALBEDO = col;")
    return f"""// {generated_header(builder, source)[3:]}
// Godot 4 spatial shader for a sky sphere: an inverted sphere (cull_front) with the
// camera at its centre. Attach to a MeshInstance3D SphereMesh of any large radius, and
// keep it centred on the camera -- the volume is world-anchored, so uCamPos is what gives
// parallax. The host must set uCamPos every frame and uPxPerDir on ready and on resize.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_never, depth_test_disabled;

{uni}

// Host plumbing: set by the scene, not a user knob.
uniform vec3  uCamPos = vec3(0.0, 0.0, 0.0);
uniform float uPxPerDir : hint_range(0.00005, 0.02, 0.00005) = 0.0013;

{physics}

{shared}
{tone}
varying vec3 v_dir;

void vertex() {{
	v_dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}}

void fragment() {{
	vec3 dir = normalize(v_dir);
{dither_line}	vec3 transmittance;
	vec3 col = vec3(0.0);
{body}
{finish}
}}
"""


def sprj_var(v):
    if v["type"] == "vec3":
        rows = "".join("<value>%s</value>" % c for c in v["value"])
        return ('\n\t\t\t\t<variable type="float3" name="%s">\n'
                '\t\t\t\t\t<row>%s</row>\n'
                '\t\t\t\t</variable>' % (v["name"], rows))
    return ('\n\t\t\t\t<variable type="float" name="%s">\n'
            '\t\t\t\t\t<row><value>%s</value></row>\n'
            '\t\t\t\t</variable>' % (v["name"], v["value"]))


def emit_sprj(variables, base):
    var_xml = "".join(sprj_var(v) for v in variables)
    return f"""<?xml version="1.0"?>
<project version="2">
\t<pipeline>
\t\t<pass name="{base}" type="shader" active="true" patchverts="1">
\t\t\t<shader type="vs" path="{base}.vert" entry="main" />
\t\t\t<shader type="ps" path="{base}.glsl" entry="main" />
\t\t\t<inputlayout>
\t\t\t\t<item value="Position" semantic="POSITION" />
\t\t\t\t<item value="Normal" semantic="NORMAL" />
\t\t\t\t<item value="Texcoord" semantic="TEXCOORD0" />
\t\t\t</inputlayout>
\t\t\t<rendertexture />
\t\t\t<items>
\t\t\t\t<item name="FS" type="geometry">
\t\t\t\t\t<type>ScreenQuad</type>
\t\t\t\t\t<width>1</width>
\t\t\t\t\t<height>1</height>
\t\t\t\t\t<depth>1</depth>
\t\t\t\t\t<topology>TriangleList</topology>
\t\t\t\t</item>
\t\t\t</items>
\t\t\t<itemvalues />
\t\t\t<variables>
\t\t\t\t<variable type="float4x4" name="matVP" system="Orthographic" />
\t\t\t\t<variable type="float4x4" name="matGeo" system="GeometryTransform" />
\t\t\t\t<variable type="float2" name="iResolution" system="ViewportSize" />
\t\t\t\t<variable type="float2" name="iMouse" system="MousePosition" />
\t\t\t\t<variable type="float" name="iTime" system="Time" />
\t\t\t\t<variable type="float4x4" name="uView" system="View" />
\t\t\t\t<variable type="float4x4" name="uProj" system="Projection" />
\t\t\t\t<variable type="float3" name="uCamPos" system="CameraPosition3" />{var_xml}
\t\t\t</variables>
\t\t\t<macros />
\t\t</pass>
\t</pipeline>
\t<objects />
\t<cameras />
\t<settings>
\t\t<entry type="property" name="{base}" item="pipe" />
\t\t<entry type="file" name="{base}" shader="vs" />
\t\t<entry type="file" name="{base}" shader="ps" />
\t\t<entry type="camera" fp="false">
\t\t\t<distance>3</distance>
\t\t\t<pitch>20</pitch>
\t\t\t<yaw>45</yaw>
\t\t\t<roll>360</roll>
\t\t</entry>
\t\t<entry type="clearcolor" r="0" g="0" b="0" a="1" />
\t\t<entry type="usealpha" val="false" />
\t</settings>
\t<plugindata />
</project>
"""


VERT = """#version 330
uniform mat4 matVP;
uniform mat4 matGeo;

layout (location = 0) in vec3 pos;
layout (location = 1) in vec3 normal;

void main() {
	gl_Position = matVP * matGeo * vec4(pos, 1);
}
"""


# ---------------------------------------------------------------- verification

def verify(path, stage):
    """Compile check with glslangValidator. `stage` None means a non-GLSL artifact."""
    if not stage:
        return "structural"
    if not shutil.which("glslangValidator"):
        return "skipped (no glslangValidator)"
    r = subprocess.run(["glslangValidator", "-S", stage, path],
                       capture_output=True, text=True)
    errs = [l for l in (r.stdout + r.stderr).split("\n") if "ERROR" in l]
    if errs or r.returncode != 0:
        detail = errs[:5] or ["exited %d" % r.returncode]
        return "FAILED:\n    " + "\n    ".join(detail)
    return "OK"


def check_host_has_shared(path, shared):
    """Catch a host emitter that forgot to emit {shared}.

    A .gdshader whose shared maths was missing ENTIRELY passed every structural check: the
    emitter simply never interpolated {shared}, so the file had no functions in it and
    Godot failed with "No matching function found for: 'ign'". "Structurally fine" is not
    "has the code in it". Every function the shared section defines must appear in the host.
    """
    names = set(re.findall(r"^\s*(?:float|vec3|vec2|mat3|void|int)\s+(\w+)\s*\(", shared, re.M))
    text = open(path).read()
    missing = sorted(n for n in names if not re.search(r"\b%s\s*\(" % re.escape(n), text))
    if missing:
        return "FAILED: shared functions missing from this host: %s" % ", ".join(missing)
    return "OK"


# ---------------------------------------------------------------- the runner

def glob_sources(outdir):
    sources = sorted(glob.glob(os.path.join(outdir, "*.frag")))
    if not sources:
        raise SystemExit("no sources found in %s" % outdir)
    return sources


def build(outdir, base, source, builder, glsl_body, godot_body,
          check_only=False, dither=True, tonemap=True):
    physics, shared, variables = read_source(source)
    outputs = [
        ("%s.glsl" % base, emit_shadered(builder, source, physics, shared, variables,
                                        glsl_body, dither, tonemap), "frag"),
        ("%s.sprj" % base, emit_sprj(variables, base), None),
        ("%s.vert" % base, VERT, "vert"),
        ("%s.gdshader" % base, emit_godot(builder, source, physics, shared, variables,
                                          godot_body, dither, tonemap), None),
    ]
    print("\nsource : %s" % base)
    if not check_only:
        for name, text, _ in outputs:
            with open(os.path.join(outdir, name), "w") as f:
                f.write(text)
        print("wrote  : %s" % ", ".join(n for n, _, _ in outputs))
    bad = 0
    for name, _, stage in outputs:
        path = os.path.join(outdir, name)
        res = verify(path, stage)
        # Only real shader hosts -- the .sprj is XML and would always "fail".
        if not res.startswith("FAILED") and name.endswith(".gdshader"):
            res = check_host_has_shared(path, shared)
        if res.startswith("FAILED"):
            bad += 1
        print("    %-28s %s" % (name, res))
    return bad


def main(outdir, sources, builder, glsl_body, godot_body, argv=None,
         dither=True, tonemap=True):
    argv = sys.argv if argv is None else argv
    check_only = "--check" in argv
    bad = 0
    for source in sources:
        bad += build(outdir, os.path.basename(source)[:-len(".frag")], source, builder,
                     glsl_body, godot_body, check_only, dither, tonemap)
    sys.exit(1 if bad else 0)
