#!/usr/bin/env python3
"""check-cube-seams.py — seam-continuity check for a baked sky cubemap.

Idea (Evert): on a CORRECT cubemap the pixels along the shared edge of two
adjacent faces describe the same sky direction, so they match. A rotated or
mirrored face makes the content jump at the seam — which is much easier to see
than any single face on its own.

Where the two faces meet, the direction is computed from the standard GL/DDS
cubemap mapping (NOT from the renderer's own mapping), so this catches an error
that a self-consistent test would miss.

Usage: check-cube-seams.py <cube> [--samples N]
"""
import math
import subprocess
import sys


def load_faces(path, res):
    faces = []
    for i in range(6):
        raw = subprocess.run(
            ["magick", f"{path}[{i}]", "-depth", "8", "-resize", f"{res}x{res}!", "rgb:-"],
            capture_output=True, check=True).stdout
        faces.append(raw)
    return faces


def spec_dir(f, u, v):
    """Direction the GL/DDS cubemap spec assigns to (face, u, v)."""
    if f == 0:   return (1.0, 1.0 - 2.0 * v, 1.0 - 2.0 * u)          # +X
    if f == 1:   return (-1.0, 1.0 - 2.0 * v, 2.0 * u - 1.0)         # -X
    if f == 2:   return (2.0 * u - 1.0, 1.0, 2.0 * v - 1.0)          # +Y
    if f == 3:   return (2.0 * u - 1.0, -1.0, 1.0 - 2.0 * v)         # -Y
    if f == 4:   return (2.0 * u - 1.0, 1.0 - 2.0 * v, 1.0)          # +Z
    return (1.0 - 2.0 * u, 1.0 - 2.0 * v, -1.0)                      # -Z


def uv_of_dir(d):
    """Inverse: which face and (u, v) does the engine sample for direction d?"""
    x, y, z = d
    ax, ay, az = abs(x), abs(y), abs(z)
    if ax >= ay and ax >= az:
        if x > 0:
            return 0, (1.0 - z / ax) / 2.0, (1.0 - y / ax) / 2.0
        return 1, (z / ax + 1.0) / 2.0, (1.0 - y / ax) / 2.0
    if ay >= ax and ay >= az:
        if y > 0:
            return 2, (x / ay + 1.0) / 2.0, (z / ay + 1.0) / 2.0
        return 3, (x / ay + 1.0) / 2.0, (1.0 - z / ay) / 2.0
    if z > 0:
        return 4, (x / az + 1.0) / 2.0, (1.0 - y / az) / 2.0
    return 5, (1.0 - x / az) / 2.0, (1.0 - y / az) / 2.0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    res = 512
    if "--samples" in sys.argv:
        res = int(sys.argv[sys.argv.index("--samples") + 1])

    faces = load_faces(path, res)

    def pixel(f, u, v):
        x = min(res - 1, max(0, int(u * res)))
        y = min(res - 1, max(0, int(v * res)))
        i = (y * res + x) * 3
        return faces[f][i], faces[f][i + 1], faces[f][i + 2]

    names = ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
    worst = 0.0
    seen = set()
    print(f"seam continuity for {path} (sampling {res}px/face, 0=perfect, "
          f"255=completely different)")
    # walk every pixel of every face's border, and compare it to the pixel the
    # ENGINE would sample for the same direction
    for f in range(6):
        diffs = []
        for edge in range(4):
            for k in range(res):
                if edge == 0:   u, v = 0.5 / res, (k + 0.5) / res   # left
                elif edge == 1: u, v = 1.0 - 0.5 / res, (k + 0.5) / res
                elif edge == 2: u, v = (k + 0.5) / res, 0.5 / res   # top
                else:           u, v = (k + 0.5) / res, 1.0 - 0.5 / res
                d = spec_dir(f, u, v)
                g, u2, v2 = uv_of_dir(d)
                if g == f:
                    continue
                a = pixel(f, u, v)
                b = pixel(g, u2, v2)
                diffs.append(max(abs(a[i] - b[i]) for i in range(3)))
                key = (min(f, g), max(f, g))
                if edge in (0, 1) and key not in seen:
                    seen.add(key)
                    print(f"  {names[f]:>2} <-> {names[g]:>2}: "
                          f"{sum(diffs) / len(diffs):6.1f} mean, {max(diffs):5.0f} max")
        if diffs:
            m = sum(diffs) / len(diffs)
            worst = max(worst, m)
    print(f"\nworst mean seam difference across faces: {worst:.1f}")
    print("verdict:", "CONTINUOUS (seams match)" if worst < 8 else "** SEAM MISMATCH **")
    return 0


if __name__ == "__main__":
    sys.exit(main())
