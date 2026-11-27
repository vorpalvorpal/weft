"""The setting `chunk_claims`, read by the guest at a failed claim (GN4 of dev/design-8.md).

chunk_claims(source, folder) -> "collect" or "stop". The files are read at each call and nothing is
kept: a kernel's environment can go stale, and the files cannot. Standard library only.

  _weft.yml  the first one found in `folder` or up to 8 parents. The first line that starts at
             column 1 with `chunk_claims`, optional spaces or tabs, then `:`. The value is the rest
             of the line, a `#` comment that follows white space removed, trimmed, and one pair of
             surrounding quotes removed.
  document   when `source` ends .qmd or .md: its front matter, the key `chunk_claims` of its `weft:`
             mapping, in block or flow form. The front matter is every metadata block, as Pandoc and
             weft's R side read them (rule 2.1.6 of dev/PACKAGE-SCOPING.md): a line that is exactly
             `---` at the top (only blank lines above) or after a blank line, a next line that is not
             blank, closed at the next `---` or `...` line, holding a mapping, and not inside a fence
             or an HTML comment. A later block's `weft:` replaces an earlier one's whole, so the value
             is read from the last block with a top-level `weft:` key. The blocks are read with the
             document's includes expanded as Quarto expands them (rule P5; the include rules I1 to I6,
             by the package's own include reader): an included file's blocks sit where its include
             sits. The document's value, when it has one, wins over _weft.yml.

The result is "collect" exactly when the value that applies is `collect`; anything else, an absent
key, `Collect`, `true` or an empty value, is "stop".
"""

import os as _os
import re as _re

_KEY = _re.compile(r"^chunk_claims[ \t]*:(.*)$")
_BLOCK_KEY = _re.compile(r"^chunk_claims[ \t]*:(.*)$")
_COMMENT = _re.compile(r"(?:^|\s)#")


def _lines(path):
    """The lines of a file, CR LF read as LF; None when it cannot be read."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        return None
    text = raw.decode("utf-8", "replace")
    if text.startswith(chr(0xFEFF)):
        text = text[1:]
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


def _clean(rest):
    """A value as the rest of its line: comment out, trimmed, one pair of quotes off."""
    m = _COMMENT.search(rest)
    if m:
        rest = rest[:m.start()]
    rest = rest.strip(" \t")
    if len(rest) >= 2 and rest[0] == rest[-1] and rest[0] in "\"'":
        rest = rest[1:-1]
    return rest


def _yml_value(folder):
    d = _os.path.abspath(folder) if folder else _os.getcwd()
    for _ in range(9):
        f = _os.path.join(d, "_weft.yml")
        if _os.path.isfile(f):
            lines = _lines(f)
            if lines is None:
                return None
            for line in lines:
                m = _KEY.match(line)
                if m:
                    return _clean(m.group(1))
            return None
        up = _os.path.dirname(d)
        if up == d:
            break
        d = up
    return None


def _split_flow(text):
    """The top-level `key: value` items of a flow mapping `{...}` as (key, rest) pairs."""
    items = []
    depth = 0
    quote = None
    cur = []
    for ch in text:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in "{[":
            depth += 1
            if depth > 1:
                cur.append(ch)
        elif ch in "}]":
            depth -= 1
            if depth >= 1:
                cur.append(ch)
            if depth <= 0:
                break
        elif ch == "," and depth == 1:
            items.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    items.append("".join(cur))
    out = []
    for it in items:
        k, sep, v = _partition_colon(it)
        if sep:
            out.append((k, v))
    return out


def _partition_colon(item):
    """Split at the first colon that is outside quotes: (key, ':', rest)."""
    quote = None
    for i, ch in enumerate(item):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == ":":
            return item[:i], ":", item[i + 1:]
    return item, "", ""


def _balanced(text):
    depth = 0
    quote = None
    seen = False
    for ch in text:
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch in "{[":
            depth += 1
            seen = True
        elif ch in "}]":
            depth -= 1
    return seen and depth <= 0


def _strip_comment(s):
    m = _COMMENT.search(s)
    return s[:m.start()] if m else s


_FENCE = _re.compile(r"^[ \t>]*(`{3,}|~{3,})")
_OPEN = _re.compile(r"^---[ \t]*$")
_CLOSE = _re.compile(r"^(---|\.\.\.)[ \t]*$")
_COMMENT_OPEN = _re.compile(r"^ {0,3}<!--")
_MAP_KEY = _re.compile(r"^[A-Za-z_\"'][^:]*:([ \t]|$)")
_WEFT_KEY = _re.compile(r"^weft[ \t]*:")


def _is_mapping(inner):
    """Whether the lines of a candidate block read as a YAML mapping: its first line that is not blank and
    not a comment is `key:` or opens a flow mapping. (The R side parses the YAML; this module has no
    parser, and a block of plain text or a list is what it has to tell apart.)"""
    for line in inner:
        t = line.strip(" \t")
        if not t or t.startswith("#"):
            continue
        return bool(_MAP_KEY.match(line)) or t.startswith("{")
    return False


def _blocks(lines):
    """The inner lines of each metadata block of a document, in order (see the module's note)."""
    out = []
    n = len(lines)
    k = 0
    while k < n:
        line = lines[k]
        m = _FENCE.match(line)
        if m:
            close = _re.compile(r"^[ \t>]*" + _re.escape(m.group(1)[0]) + "{" + str(len(m.group(1))) +
                                r",}[ \t]*$")
            j = k + 1
            while j < n and not close.match(lines[j]):
                j += 1
            k = j + 1
            continue
        if _COMMENT_OPEN.match(line):
            # the comment ends at the first `-->` after its `<!--`; one that never ends hides nothing
            end = k if "-->" in line.split("<!--", 1)[1] else next(
                (j for j in range(k + 1, n) if "-->" in lines[j]), None)
            k = k + 1 if end is None else end + 1
            continue
        if _OPEN.match(line) and (k == 0 or not lines[k - 1].strip()) and k + 1 < n and lines[k + 1].strip():
            j = k + 1
            while j < n and not _CLOSE.match(lines[j]):
                j += 1
            if j < n and _is_mapping(lines[k + 1:j]):
                out.append(lines[k + 1:j])
                k = j + 1
                continue
        k += 1
    return out


def _expanded(source, lines):
    """The lines of the document `source` with every include expanded as Quarto splices them: each include
    line replaced by the included file's expanded lines and one blank line (two for an include inside an
    included file). A file is not expanded inside itself (I6); an include whose file cannot be read stays
    the line it is. The twin of R's include_expand()."""
    if not any("{{< " in line for line in lines):
        return lines
    from . import _include_lines, _quarto_root
    main = _os.path.realpath(_os.path.abspath(source))
    main_dir = _os.path.dirname(main)
    root = _quarto_root(main_dir)
    out = []

    def go(ls, key, stack, in_included):
        targets = dict(_include_lines(ls, main_dir, root, in_included))
        stack = stack | {key}
        for k, line in enumerate(ls):
            p = targets.get(k)
            sub = _lines(p) if p is not None and p not in stack and _os.path.isfile(p) else None
            if sub is None:
                out.append(line)
                continue
            go(sub, p, stack, True)
            out.extend([""] * (2 if in_included else 1))

    go(lines, main, frozenset(), False)
    return out


def _front_value(source):
    lines = _lines(source)
    if not lines:
        return None
    lines = _expanded(source, lines)
    weft = [b for b in _blocks(lines) if any(_WEFT_KEY.match(line) for line in b)]
    if not weft:
        return None
    return _weft_value(weft[-1])


def _weft_value(front):
    """`chunk_claims` of the `weft:` mapping in the lines `front` of one block, or None."""
    for i, line in enumerate(front):
        m = _re.match(r"^weft[ \t]*:(.*)$", line)
        if not m:
            continue
        rest = _strip_comment(m.group(1)).strip(" \t")
        if rest.startswith("{"):
            text = rest
            j = i + 1
            while not _balanced(text) and j < len(front):
                text += " " + _strip_comment(front[j]).strip(" \t")
                j += 1
            for k, v in _split_flow(text):
                if _clean(k) == "chunk_claims":
                    return _clean(v)
            return None
        indent = None
        for line2 in front[i + 1:]:
            if not line2.strip(" \t"):
                continue
            ind = len(line2) - len(line2.lstrip(" \t"))
            if ind == 0:
                break
            if indent is None:
                indent = ind
            if ind == indent:
                m2 = _BLOCK_KEY.match(line2[ind:])
                if m2:
                    return _clean(m2.group(1))
        return None
    return None


def chunk_claims(source, folder):
    """"collect" when `chunk_claims` is collect for the document `source` in `folder`, else "stop"."""
    try:
        v = None
        if source and str(source).lower().endswith((".qmd", ".md")):
            v = _front_value(str(source))
        if v is None:
            v = _yml_value(folder)
        return "collect" if v == "collect" else "stop"
    except Exception:
        return "stop"
