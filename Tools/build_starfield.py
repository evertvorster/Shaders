#!/usr/bin/env python3
"""build_starfield.py — generate every host format of the starfield (the dome layer).

    python3 Tools/build_starfield.py            # generate + verify
    python3 Tools/build_starfield.py --check    # verify only

All the plumbing lives in Tools/shader_build.py; this file only says where the source is
and what its host calls.

NOTE: the starfield is the one layer that does NOT tone-map. Its star brightnesses are
already display-referred, so aces() is skipped in both hosts (tonemap=False). Everything
else tone-maps. That inconsistency is deliberate and historical -- resolve it on purpose,
not by accident.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_build as sb

OUTDIR = os.path.join(sb.ROOT, "Space", "Starfield")

sb.main(OUTDIR,
        [os.path.join(OUTDIR, "starfield.frag")],
        "build_starfield.py",
        glsl_body="\tcol = starfieldSky(dir, pxPerDir, transmittance);",
        godot_body="\tcol = starfieldSky(dir, uPxPerDir, transmittance);",
        dither=False, tonemap=False)
