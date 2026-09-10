# -*- coding: utf-8 -*-
# test_removed_apis.py — regression: Midnight removed some Frame APIs without
# backward compat (2.0.0 crash: SetMinResize). lupa stubs return a function for
# ANY method name, so they CANNOT catch this class of bug — grep the source.
# Extend REMOVED when the next removal is found (see AGENTS.md rule 6).

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
ADDON = ROOT / "addons" / "DecorLumberProfit"

# method names removed from the 12.1.0 client (verified via
# tools/find-api.ps1 + wiki-lua/15_widget_api.md + 16_widget_script_handlers.md)
REMOVED = [
    "SetMinResize",
    "SetMaxResize",
]


def run(lua, check, exec_):
    hits = []
    for path in sorted(ADDON.rglob("*.lua")):
        try:
            src = path.read_text(encoding="utf-8")
        except OSError:
            continue
        for name in REMOVED:
            # match `f:SetMinResize(` / `:SetMinResize (` but not `SetResizeBounds`
            # (contains a different stem) and not comments mentioning the removal
            for i, line in enumerate(src.splitlines(), 1):
                stripped = line.split("--", 1)[0]
                if (":" + name + "(") in stripped.replace(" ", ""):
                    hits.append("%s:%d:%s" % (path.name, i, name))
    check("no removed frame APIs used", str(len(hits)), "0")
    if hits:
        print("   hits:", hits)
