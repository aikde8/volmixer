#!/usr/bin/env python3
# Generate one .po file per catalog language from translations.py, then compile
# each into contents/locale/<lang>/LC_MESSAGES/<domain>.mo. Plasma binds that
# directory to the applet's TranslationDomain when the applet loads.
#
# In the catalogs: msgctxt = key (plus KUIT marker), msgid = the English text,
# msgstr = the language's text. English itself needs no catalog: ki18n treats
# it as the source language and returns the msgid, which is why the English
# has to be in the QML. build refuses to run while the QML and translations.py
# disagree (run sync_sources.py first).
#
# Called by the top-level `install` script before kpackagetool6 installs the
# package. Safe to run on its own: it only touches package/translate/*.po and
# package/contents/locale/.

import sys
import shutil
import pathlib
import datetime

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from translations import SOURCE, CATALOGS, STRINGS, ensure_complete, msgctxt  # noqa: E402
import msgfmt  # noqa: E402
import sync_sources  # noqa: E402


PLUGIN_ID = "org.kde.plasma.volmixer"
CATALOG = "plasma_applet_" + PLUGIN_ID
LOCALE_ROOT = HERE.parent / "contents" / "locale"

LANG_META = {
    "ru": ("Russian", "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : "
                     "n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);"),
    "de": ("German", "nplurals=2; plural=(n != 1);"),
    "fr": ("French", "nplurals=2; plural=(n > 1);"),
    "es": ("Spanish", "nplurals=2; plural=(n != 1);"),
}


def po_escape(s):
    return (s.replace("\\", "\\\\")
             .replace('"', '\\"')
             .replace("\n", "\\n"))


def po_lines(keyword, s):
    """`keyword "..."` as a list of lines; multi-line messages use the gettext
    convention of an empty first string followed by one chunk per line."""
    if "\n" in s.rstrip("\n") or s.count("\n") > 1:
        parts = s.split("\n")
        chunks = [p + "\n" for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])
        return [keyword + ' ""'] + ['"' + po_escape(c) + '"' for c in chunks]
    return [keyword + ' "' + po_escape(s) + '"']


def write_po(lang, out_path):
    full_name, plural = LANG_META[lang]
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M%z")
    lines = [
        '# Translation of volmixer in ' + full_name,
        '# This file is distributed under the same license as volmixer.',
        '#',
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: volmixer\\n"',
        '"Report-Msgid-Bugs-To: '
        'https://github.com/aikde8/volmixer/issues\\n"',
        '"PO-Revision-Date: ' + now + '\\n"',
        '"Language-Team: ' + full_name + '\\n"',
        '"Language: ' + lang + '\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        '"Plural-Forms: ' + plural + '\\n"',
        '',
    ]
    for e in STRINGS:
        lines += po_lines("msgctxt", msgctxt(e))
        lines += po_lines("msgid", e[SOURCE])
        lines += po_lines("msgstr", e[lang])
        lines.append('')
    out_path.write_text("\n".join(lines), encoding="utf-8")


def compile_mo(po_path, lang):
    out_dir = LOCALE_ROOT / lang / "LC_MESSAGES"
    out_dir.mkdir(parents=True, exist_ok=True)
    mo_path = out_dir / (CATALOG + ".mo")
    msgfmt.generate(msgfmt.parse_po(str(po_path)), str(mo_path))
    return mo_path


def main():
    ensure_complete()
    stale = sync_sources.check()
    if stale:
        sys.exit("i18n strings in the code differ from translations.py: "
                 + ", ".join(stale)
                 + "\nrun: python3 package/translate/sync_sources.py")
    # The source language needs no catalog; drop leftovers of the old scheme.
    (HERE / (SOURCE + ".po")).unlink(missing_ok=True)
    shutil.rmtree(LOCALE_ROOT / SOURCE, ignore_errors=True)
    for lang in CATALOGS:
        po = HERE / (lang + ".po")
        write_po(lang, po)
        mo = compile_mo(po, lang)
        print("built", lang, "->", mo.relative_to(HERE.parent.parent))


if __name__ == "__main__":
    main()
