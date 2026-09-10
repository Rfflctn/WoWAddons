"""Check the addon version in the TOC, runtime namespace and changelog."""

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "DecorLumberProfit"
TOC = ADDON / "DecorLumberProfit.toc"
INIT = ADDON / "Init.lua"
CHANGELOG = ADDON / "CHANGELOG.md"


def find_one(pattern, text, label):
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise ValueError("cannot find %s" % label)
    return match.group(1)


def main():
    toc_version = find_one(r"^##\s+Version:\s*(\S+)", TOC.read_text(encoding="utf-8"), "TOC version")
    init_version = find_one(
        r"^\s*Addon\.VERSION\s*=\s*[\"']([^\"']+)",
        INIT.read_text(encoding="utf-8"),
        "Init.VERSION",
    )
    changelog = CHANGELOG.read_text(encoding="utf-8")
    releases = re.findall(r"^##\s+\[?(\d+\.\d+\.\d+)\]?\s*(?:-|$)", changelog, re.MULTILINE)
    if not releases:
        raise ValueError("cannot find a release heading in CHANGELOG.md")
    changelog_version = releases[0]

    errors = []
    if toc_version != init_version:
        errors.append(".toc=%s, Init.lua=%s" % (toc_version, init_version))
    if toc_version != changelog_version:
        errors.append(".toc=%s, latest CHANGELOG release=%s" % (toc_version, changelog_version))
    if errors:
        for error in errors:
            print("VERSION CHECK FAILED: " + error)
        return 1

    print("VERSION CHECK PASSED: %s" % toc_version)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print("VERSION CHECK FAILED: %s" % error)
        sys.exit(1)
