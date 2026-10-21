#!/usr/bin/env python3
# Keep the i18n calls in QML/JS in sync with translations.py.
#
# Every user-visible string in the code is written as
#     i18nc("<msgctxt>", "<English text>")      (xi18nc(...) for KUIT markup)
# where msgctxt is the stable key from translations.py (with an optional KUIT
# marker in front) and the English text is the gettext msgid. ki18n treats
# English as the source language and never consults a catalog for it, so the
# msgid itself has to be English.
#
# This script rewrites every call from translations.py so the English in the
# code can never drift from the single source; build.py refuses to build while
# they differ. Idempotent. Also understands the older i18n("<key>") form.
#
# Usage: python3 package/translate/sync_sources.py

import re
import sys
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from translations import STRINGS, SOURCE, msgctxt  # noqa: E402

ROOT = HERE.parent / "contents"
BY_KEY = {e["key"]: e for e in STRINGS}

# [x]i18n[c|p]("ctx", "msg"  or  [x]i18n("msg"  -- only the head of the call;
# any further arguments are left exactly as they are.
CALL_RE = re.compile(
    r'(x?i18n[cp]?)\(\s*(?:"((?:[^"\\]|\\.)*)"\s*,\s*)?"((?:[^"\\]|\\.)*)"'
)


def unesc(s):
    return s.replace(r'\n', '\n').replace(r'\"', '"').replace(r'\\', '\\')


def esc(s):
    return s.replace('\\', '\\\\').replace('"', r'\"').replace('\n', r'\n')


def key_of(ctx, msg):
    """The translations.py key behind a call, or None if it is not ours."""
    if msg in BY_KEY:                      # old form: i18n("key")
        return msg
    if ctx:                                # new form: i18nc("[@marker ]key", "English")
        last = unesc(ctx).split()[-1]
        if last in BY_KEY:
            return last
    return None


def rewrite(text):
    def repl(m):
        fn, ctx, msg = m.group(1), m.group(2), m.group(3)
        key = key_of(ctx, msg)
        if key is None:
            return m.group(0)
        e = BY_KEY[key]
        fn2 = "xi18nc" if fn.startswith("x") else "i18nc"
        return '%s("%s", "%s"' % (fn2, esc(msgctxt(e)), esc(e[SOURCE]))
    return CALL_RE.sub(repl, text)


def source_files():
    return sorted(p for p in ROOT.rglob("*") if p.suffix in (".qml", ".js"))


def check():
    """Files whose i18n calls do not match translations.py (empty = in sync)."""
    return [str(p.relative_to(HERE.parent)) for p in source_files()
            if rewrite(p.read_text(encoding="utf8")) != p.read_text(encoding="utf8")]


def main():
    changed = 0
    for p in source_files():
        src = p.read_text(encoding="utf8")
        dst = rewrite(src)
        if dst != src:
            p.write_text(dst, encoding="utf8")
            changed += 1
            print("rewrote", p.relative_to(HERE.parent))
    print("done; files changed:", changed)


if __name__ == "__main__":
    main()
