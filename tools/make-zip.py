# -*- coding: utf-8 -*-
"""Create a portable ZIP with forward-slash entry names.

PowerShell 5.1's Compress-Archive writes backslashes on Windows, which some
unzip tools on macOS/Linux do not treat as directory separators. Python's
zipfile always writes the names we pass, so this helper normalizes them to "/".
"""

import os
import sys
import zipfile


def main():
    if len(sys.argv) != 3:
        print("usage: make-zip.py <source-dir> <output.zip>", file=sys.stderr)
        return 2

    source = os.path.abspath(sys.argv[1])
    output = os.path.abspath(sys.argv[2])
    parent = os.path.dirname(source)

    if not os.path.isdir(source):
        print("source directory not found: %s" % source, file=sys.stderr)
        return 2

    if os.path.exists(output):
        os.remove(output)

    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, dirs, files in os.walk(source):
            dirs.sort()
            files.sort()
            for name in files:
                full = os.path.join(root, name)
                relative = os.path.relpath(full, parent).replace(os.sep, "/")
                archive.write(full, relative)

            # Preserve empty directories, if any.
            if not dirs and not files:
                relative = os.path.relpath(root, parent).replace(os.sep, "/")
                archive.writestr(relative + "/", b"")

    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
