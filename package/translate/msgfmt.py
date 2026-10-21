#!/usr/bin/env python3
# Minimal self-contained .po -> .mo compiler. Bundled so the install step
# doesn't need the gettext package (the Debian/Ubuntu `gettext-base` package
# only ships gettext/ngettext/envsubst, not msgfmt).
#
# Supports:
#   - msgid / msgstr (multi-line, concatenated string literals)
#   - msgctxt (encoded as "<ctx>\x04<msgid>" in the catalog)
#   - comments (#, #., #:, #,) are ignored
#
# The .mo binary layout follows the GNU gettext spec (little-endian, no
# hash table). See https://www.gnu.org/software/gettext/manual/html_node/MO-Files.html
#
# Usage: python3 msgfmt.py <input.po> <output.mo>

import re
import struct
import sys


STR_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*$')


def unquote(line):
    m = STR_RE.match(line.strip())
    if not m:
        raise ValueError("not a quoted string: %r" % line)
    # Only interpret the escapes gettext itself defines.
    raw = m.group(1)
    out = []
    i = 0
    while i < len(raw):
        c = raw[i]
        if c == "\\" and i + 1 < len(raw):
            nxt = raw[i + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r",
                        "\\": "\\", '"': '"'}.get(nxt, nxt))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def parse_po(path):
    """Yield (msgctxt_or_None, msgid, msgstr) tuples."""
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i].rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue

        ctx = None
        if stripped.startswith("msgctxt "):
            ctx = unquote(stripped[len("msgctxt "):])
            i += 1
            while i < n and lines[i].strip().startswith('"'):
                ctx += unquote(lines[i])
                i += 1
            stripped = lines[i].strip() if i < n else ""

        if not stripped.startswith("msgid "):
            # malformed: skip to next line
            i += 1
            continue
        msgid = unquote(stripped[len("msgid "):])
        i += 1
        while i < n and lines[i].strip().startswith('"'):
            msgid += unquote(lines[i])
            i += 1

        if i >= n or not lines[i].strip().startswith("msgstr "):
            # entry has no msgstr yet — skip
            continue
        msgstr = unquote(lines[i].strip()[len("msgstr "):])
        i += 1
        while i < n and lines[i].strip().startswith('"'):
            msgstr += unquote(lines[i])
            i += 1

        yield (ctx, msgid, msgstr)


def generate(entries, out_path):
    """Write a .mo file from an iterable of (ctx, msgid, msgstr) tuples."""
    # Drop entries with an empty translation (except the header one, msgid "").
    msgs = {}
    for ctx, mid, mstr in entries:
        if mid != "" and not mstr:
            continue
        key = (ctx + "\x04" + mid) if ctx else mid
        msgs[key] = mstr

    keys = sorted(msgs.keys())
    offsets = []
    ids_blob = b""
    strs_blob = b""

    for k in keys:
        k_b = k.encode("utf-8")
        v_b = msgs[k].encode("utf-8")
        offsets.append((len(k_b), len(ids_blob), len(v_b), len(strs_blob)))
        ids_blob += k_b + b"\x00"
        strs_blob += v_b + b"\x00"

    n_strings = len(keys)
    # Header: magic, version, nstrings, offset of key table, offset of val table,
    # hash size, hash offset. Each table entry is (length, offset).
    key_tab_off = 7 * 4
    val_tab_off = key_tab_off + n_strings * 8
    data_off = val_tab_off + n_strings * 8

    header = struct.pack(
        "Iiiiiii",
        0x950412DE,     # magic
        0,              # version
        n_strings,
        key_tab_off,
        val_tab_off,
        0,              # hash size (none)
        0,              # hash offset
    )

    key_tab = b""
    val_tab = b""
    for k_len, k_off, v_len, v_off in offsets:
        key_tab += struct.pack("ii", k_len, data_off + k_off)
        val_tab += struct.pack(
            "ii", v_len, data_off + len(ids_blob) + v_off
        )

    with open(out_path, "wb") as fh:
        fh.write(header)
        fh.write(key_tab)
        fh.write(val_tab)
        fh.write(ids_blob)
        fh.write(strs_blob)


def main(argv):
    if len(argv) != 3:
        print("usage: msgfmt.py <input.po> <output.mo>", file=sys.stderr)
        return 2
    generate(parse_po(argv[1]), argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
