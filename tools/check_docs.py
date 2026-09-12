# -*- coding: utf-8 -*-
"""check_docs.py — валидатор дрейфа документации (AGENTS.md / PROJECT-INDEX.md).

Только чтение, без сети. Проверяет:
1. число tools/tests/test_*.py == каждому числу "N сьютов" в PROJECT-INDEX.md;
2. каждый stem test_<name> упомянут в PROJECT-INDEX.md или AGENTS.md;
3. каждая конкретная ссылка wiki-lua/<...>, tools/<...>, addons/<...>
   и bare-имя файла (*.md/*.lua/*.py/*.ps1/*.toc/*.json) из обоих доков существует.
   Токены с '*', '<', '>' — шаблоны/плейсхолдеры, пропускаются.

Выход: 0 = DOCS CHECK PASSED, 1 = список расхождений.
Использование: python tools/check_docs.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = [ROOT / "AGENTS.md", ROOT / "PROJECT-INDEX.md"]
TESTS_DIR = ROOT / "tools" / "tests"

# Куда резолвятся bare-имена файлов (без префикса wiki-lua//tools//addons/).
BARE_DIRS = ["wiki-lua", "addons/DecorLumberProfit", "", "tools", "tools/tests"]

REF_EXT = r"[A-Za-z0-9_][A-Za-z0-9_.\-]*\.(?:md|lua|py|ps1|toc|json)$"


def is_template(token):
    return any(c in token for c in ("*", "<", ">"))


def check_path_exists(ref):
    return (ROOT / ref).exists()


def resolve_bare(name):
    for d in BARE_DIRS:
        cand = ROOT / d / name if d else ROOT / name
        if cand.exists():
            return True
    return False


def main():
    errors = []
    texts = {}
    for doc in DOCS:
        try:
            texts[doc.name] = doc.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append("%s: cannot read (%s)" % (doc.name, exc))

    # ---- 1-2. сьюты ----
    suites = []
    try:
        suites = sorted(p.stem for p in TESTS_DIR.glob("test_*.py"))
    except OSError as exc:
        errors.append("cannot list tools/tests: %s" % exc)
    if suites:
        for name, text in texts.items():
            for match in re.finditer(r"(\d+)\s*сьют", text):
                if int(match.group(1)) != len(suites):
                    errors.append(
                        "%s: says %s suites, found %d (%s)"
                        % (name, match.group(1), len(suites), ", ".join(suites))
                    )
        for stem in suites:
            if not any(stem in text for text in texts.values()):
                errors.append("%s.py not mentioned in AGENTS.md/PROJECT-INDEX.md" % stem)

    # ---- 3. ссылки на файлы ----
    for name, text in texts.items():
        seen = set()
        for match in re.finditer(r"`([^`\n]+)`", text):
            token = match.group(1).strip().strip("'\"")
            if not token or token in seen:
                continue
            seen.add(token)
            if not is_template(token):
                whole = token.strip().strip("'\"").rstrip(".,:;")
                if not whole:
                    continue
                if whole.split()[0].startswith(("wiki-lua/", "tools/", "addons/")):
                    if not check_path_exists(whole):
                        errors.append("%s: missing `%s`" % (name, whole))
                    continue
            # иначе: ищем конкретные имена файлов среди частей токена
            if " " in token:
                parts = [p for p in token.split() if p.startswith(("wiki-lua/", "tools/", "addons/"))]
            else:
                parts = [token]
            for part in parts:
                part = part.strip().strip("'\"").rstrip(".,:;")
                if not part or is_template(part):
                    continue
                if not re.search(REF_EXT, part):
                    continue
                if part.startswith(("wiki-lua/", "tools/", "addons/")):
                    ok = check_path_exists(part)
                else:
                    ok = resolve_bare(part)
                if not ok:
                    errors.append("%s: missing `%s`" % (name, part))

    if errors:
        print("DOCS CHECK FAILED:")
        for error in errors:
            print("  " + error)
        return 1
    print("DOCS CHECK PASSED (suites=%d)" % len(suites))
    return 0


if __name__ == "__main__":
    sys.exit(main())
