#!/usr/bin/env python3
"""build_scenes.py — generate every host format of every SCENE source.

A scene folds several layers together (Space/Scenes/README.md). Its host body is the fold,
which is the only thing that differs from a single-layer build.

    python3 Tools/build_scenes.py            # generate + verify all scenes
    python3 Tools/build_scenes.py --check    # verify only
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_build as sb

OUTDIR = os.path.join(sb.ROOT, "Space", "Scenes")

# The fold: stars first (they are behind), then the nebula in front dimming them by its
# transmittance. No light interaction between the layers -- only occlusion.
FOLD = """\tvec3 Tn; vec3 neb   = nebulaSky(uCamPos, dir, {ppd}, dither, Tn);
\tvec3 Ts; vec3 stars = volumetricStarfieldSky(uCamPos, dir, {ppd}, dither, Ts);
\tcol = neb + Tn * uStars * stars;"""

sb.main(OUTDIR, sb.glob_sources(OUTDIR), "build_scenes.py",
        glsl_body=FOLD.format(ppd="pxPerDir"),
        godot_body=FOLD.format(ppd="uPxPerDir"))
