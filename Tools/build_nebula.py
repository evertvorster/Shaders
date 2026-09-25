#!/usr/bin/env python3
"""build_nebula.py — generate every host format of every nebula variant.

Every `*.frag` in Space/Nebula/ is a variant; the variant name is the file stem, so it
appears in every generated filename.

    python3 Tools/build_nebula.py            # generate + verify all variants
    python3 Tools/build_nebula.py --check    # verify only

All the plumbing lives in Tools/shader_build.py; this file only says where the sources are
and what their host calls.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_build as sb

OUTDIR = os.path.join(sb.ROOT, "Space", "Nebula")

sb.main(OUTDIR, sb.glob_sources(OUTDIR), "build_nebula.py",
        glsl_body="\tcol = nebulaSky(uCamPos, dir, pxPerDir, dither, transmittance);",
        godot_body="\tcol = nebulaSky(uCamPos, dir, uPxPerDir, dither, transmittance);")
