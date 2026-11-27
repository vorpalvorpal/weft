"""The setting `chunk_claims`, read by the guest at a failed claim (GN4 of dev/design-8.md).

chunk_claims(source, folder) -> "collect" or "stop". The files are read at each call and nothing is
kept: a kernel's environment can go stale, and the files cannot. Standard library only.

  _weft.yml  the first one found in `folder` or up to 8 parents. The first line that starts at
             column 1 with `chunk_claims`, optional spaces or tabs, then `:`. The value is the rest
             of the line, a `#` comment that follows white space removed, trimmed, and one pair of
             surrounding quotes removed.
  document   when `source` ends .qmd, .md, .ipynb or .py: its front matter, the key `chunk_claims` of its `weft:`
             mapping, in block or flow form. The front matter is every metadata block, as Pandoc and
             weft's R side read them (rule 2.1.6 of dev/PACKAGE-SCOPING.md): a line that is exactly
             `---` at the top (only blank lines above) or after a blank line, a next line that is not
             blank, closed at the next `---` or `...` line, holding a mapping, and not inside a fence
             or an HTML comment. A later block's `weft:` replaces an earlier one's whole, so the value
             is read from the last block with a top-level `weft:` key. The blocks are read with the
             document's includes expanded as Quarto expands them (rule P5; the include rules I1 to I6,
             by the package's own include reader): an included file's blocks sit where its include
             sits. The document's value, when it has one, wins over _weft.yml. A notebook's front
             matter is read from its cells (rule P7): the source of each raw and markdown cell, in
             cell order, each followed by a blank line; a percent script's from its `# %% [markdown]`
             and `# %% [raw]` cells, the leading `#` and one white-space character off each line (or
             the lines inside a cell's triple-quote lines). Code cells hold none, and neither expands
             includes.

The result is "collect" exactly when the value that applies is `collect`; anything else, an absent
key, `Collect`, `true` or an empty value, is "stop".
"""

import json as _json
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


_KNITR_BEGIN = _re.compile(r"^[\t >]*```+\s*\{([a-zA-Z0-9_]+( *[ ,].*)?)\}\s*$")
_KNITR_END = _re.compile(r"^[\t >]*```+\s*$")
_CHUNK_PREFIX = _re.compile(r"^([\t >]*`+)")
_FENCE_LINE = _re.compile(r"^( {0,3})((?:> ?(?: {0,3}(?=>))?)*)( *)(`{3,}|~{3,})(.*)$")
_QUOTE = _re.compile(r"^ {0,3}(?:> ?(?: {0,3}(?=>))?)*")
_ITEM = _re.compile(r"^( *)([-+*]|[0-9]{1,9}[.)])(?:( {1,4})(?=\S)|[ \t]*$)")
_ATTR = (r"\{[ \t]*(?:(?:#[A-Za-z0-9_:.-]+|\.[A-Za-z][A-Za-z0-9_:.-]*"
         r"|[A-Za-z][A-Za-z0-9_:.-]*=(?:\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'|[^ \t}]+)|-)[ \t]*)*\}")
_INFO = _re.compile(r"^(?:\{[ \t]*=[A-Za-z0-9_-]+[ \t]*\}|[^ \t{`]*[ \t]*(?:" + _ATTR + r")?)$")


def _blank(line):
    return not line.strip(" \t\r\n")


def _exact_end(line, p):
    return line.startswith(p) and not line[len(p):].strip()


def _knitr_chunks(lines):
    """The chunks of `lines` as knitr divides a document (R's knitr_chunks()): (open, close) pairs, 0-based."""
    n = len(lines)
    cand, isb = [], []
    for i, line in enumerate(lines):
        if "```" not in line:
            continue
        b = bool(_KNITR_BEGIN.match(line))
        if b or _KNITR_END.match(line):
            cand.append(i)
            isb.append(b)
    out = []

    def reads_on(t, p):
        # is the end line cand[t] (not exact) code, because knitr reads on to a later exact closer?
        i = cand[t]
        e = next((cand[s] for s in range(t + 1, len(cand)) if not isb[s] and _exact_end(lines[cand[s]], p)), None)
        if e is None:
            return False
        return not any(b.startswith(p) and _re.match(r"`*\{", b[len(p):]) for b in lines[i + 1:e])

    cur, p = None, None
    for t, i in enumerate(cand):
        line = lines[i]
        if cur is None:
            if isb[t]:
                cur = i
                p = _CHUNK_PREFIX.match(line).group(1) if i != 0 else None
        elif isb[t]:
            if p is None or line.startswith(p + "{"):
                out.append((cur, i - 1))
                cur = i
        elif not (p is not None and not _exact_end(line, p) and reads_on(t, p)):
            out.append((cur, i))
            cur = None
    if cur is not None:
        out.append((cur, n - 1))
    return out


def _expand_tabs(line):
    """`line` with the tabs of its leading white space and `>` markers expanded to the next stop of 4."""
    if not _re.match(r"^[ >]*\t", line):
        return line
    lead = _re.match(r"^[ \t>]*", line).group(0)
    out = ""
    for ch in lead:
        out += " " * (4 - len(out) % 4) if ch == "\t" else ch
    return out + line[len(lead):]


def _parse_fence(line):
    """A fence line as R's parse_fence_lines() reads it: (depth, indent, char, length, info), or None."""
    m = _FENCE_LINE.match(_expand_tabs(line))
    if not m:
        return None
    depth = m.group(2).count(">")
    indent = len(m.group(3)) if depth else len(m.group(1)) + len(m.group(3))
    return depth, indent, m.group(4)[0], len(m.group(4)), m.group(5)


def _quote_depth(line):
    return _QUOTE.match(line).group(0).count(">")


def _lead_width(line):
    return len(_expand_tabs(line)) - len(_expand_tabs(line).lstrip(" "))


def _list_item_col(lines, k, ind):
    """The content column of the list item the line k, indented ind (4 or more), sits in, or None."""
    j = k - 1
    while j >= 0:
        if _blank(lines[j]):
            j -= 1
            continue
        line = _expand_tabs(lines[j])
        m = _ITEM.match(line)
        if m:
            c0 = len(m.group(0)) if m.group(3) else len(m.group(1)) + len(m.group(2)) + 1
            if c0 <= ind <= c0 + 3:
                return c0
            if not m.group(1):
                return None
        elif _lead_width(line) == 0 and (j == 0 or _blank(lines[j - 1])):
            return None
        j -= 1
    return None


def _blocks(lines):
    """The inner lines of each metadata block of a document, in order (see the module's note), as R's
    plain_blocks() reads them outside the chunks: a fence opens with an info string Pandoc's markdown reader
    takes (none, one word, an attribute block); one that does not close in its container is no fence; in a
    list item a fence at indent 4 or more needs a blank line above."""
    n = len(lines)
    inchunk = [False] * n
    for a, b in _knitr_chunks(lines):
        for q in range(a, b + 1):
            inchunk[q] = True
    pf = {}
    fi = []
    for j, line in enumerate(lines):
        if not inchunk[j] and _FENCE.match(line):
            pf[j] = _parse_fence(line)
            fi.append(j)
    at = {j: s for s, j in enumerate(fi)}

    def closes(j, r, d, c0):
        q = pf.get(j)
        return bool(q) and q[2] == r[2] and q[3] >= r[3] and q[0] == d and not q[4].strip(" \t\r") \
            and c0 <= q[1] <= c0 + 3

    def fence_close(k, r, c0):
        if r[0] == 0 and c0 == 0:
            return next((j for j in fi[at[k] + 1:] if closes(j, r, 0, 0)), None)
        for j in range(k + 1, n):
            if inchunk[j]:
                continue
            line = lines[j]
            if r[0] > 0 and _quote_depth(line) < r[0]:
                return None
            if c0 > 0 and not _blank(line) and _lead_width(line) < c0:
                return None
            if j in pf and closes(j, r, r[0], c0):
                return j
        return None

    out = []
    closers = set()
    k = 0
    while k < n:
        line = lines[k]
        nxt = k + 1
        if inchunk[k]:
            pass
        elif k in pf:
            r = pf[k]
            if r and _INFO.match(r[4].strip(" \t\r\n")):
                c0 = 0
                if r[1] > 3:
                    if r[0] > 0:
                        c0 = None
                    elif k > 0 and not _blank(lines[k - 1]) and not inchunk[k - 1] and (k - 1) not in closers:
                        # no blank line (or a block's end) above: the line goes on the paragraph above
                        c0 = None
                    else:
                        c0 = _list_item_col(lines, k, r[1])
                c = fence_close(k, r, c0) if c0 is not None else None
                if c is not None:
                    closers.add(c)
                    nxt = c + 1
        elif _COMMENT_OPEN.match(line):
            # the comment ends at the first `-->` after its `<!--`; one that never ends hides nothing
            if "-->" in line.split("<!--", 1)[1]:
                nxt = k + 1
            else:
                end = next((j for j in range(k + 1, n) if not inchunk[j] and "-->" in lines[j]), None)
                if end is not None:
                    nxt = end + 1
        elif _OPEN.match(line) and (k == 0 or _blank(lines[k - 1])) and k + 1 < n and not _blank(lines[k + 1]):
            j = k + 1
            while j < n and not _CLOSE.match(lines[j]):
                j += 1
            if j < n and _is_mapping(lines[k + 1:j]):
                out.append(lines[k + 1:j])
                nxt = j + 1
        k = nxt
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


def _text(path):
    """The text of a file, as _lines() reads it; None when it cannot be read."""
    lines = _lines(path)
    return None if lines is None else "\n".join(lines)


def _notebook_lines(text):
    """The lines a notebook's JSON `text` gives its front matter (rule P7; the twin of R's notebook_view()):
    the source of each raw and markdown cell, in cell order, each followed by a blank line."""
    try:
        nb = _json.loads(text)
    except ValueError:
        return []
    cells = nb.get("cells") if isinstance(nb, dict) else None
    out = []
    for cell in cells if isinstance(cells, list) else []:
        if not isinstance(cell, dict) or cell.get("cell_type") not in ("markdown", "raw"):
            continue
        src = cell.get("source", "")
        if isinstance(src, list):
            src = "".join(p for p in src if isinstance(p, str))
        s = src if isinstance(src, str) else ""
        if s:
            out.extend((s[:-1] if s.endswith("\n") else s).split("\n"))
        out.append("")
    return out


_PERCENT_SCRIPT = _re.compile(r"^\s*#\s*%%+\s+\[(markdown|raw)\]", _re.M)
_PERCENT_HEADER = _re.compile(r"^\s*#\s*%%+\s*(?:\[(markdown|raw)\])?\s*(.*)?$")
_TRIPLE_QUOTE = _re.compile(r'^"{3,}\s*$')


def _percent_lines(text):
    """The lines a percent script's `text` gives its front matter (rule P7; the twin of R's percent_view()):
    each markdown and raw cell, its empty lines at either end dropped, the leading `#` and one white-space
    character off each line (or the lines inside its triple-quote lines), then a blank line. A raw cell that names a
    format is raw output, fenced; code cells and the text above the first `# %%` line are left out. A script
    with no markdown or raw cell is no Quarto document: no lines."""
    text = text.strip()
    if not _PERCENT_SCRIPT.search(text):
        return []
    cells = []
    for line in text.split("\n"):
        m = _PERCENT_HEADER.match(line)
        if m:
            cells.append((m.group(1) or "code", m.group(2) or "", []))
        elif cells:
            cells[-1][2].append(line)
    out = []
    for kind, attrs, body in cells:
        if kind == "code":
            continue
        while body and not body[0].strip():
            body = body[1:]
        while body and not body[-1].strip():
            body = body[:-1]
        if len(body) > 2 and _TRIPLE_QUOTE.match(body[0]) and _TRIPLE_QUOTE.match(body[-1]):
            body = body[1:-1]
        else:
            body = [_re.sub(r"^#\s?", "", line) for line in body]
        if kind == "raw" and _re.search(r"(^|\s)(format|raw_mimetype)=", attrs):
            body = ["```{=raw}"] + body + ["```"]
        out.extend(body + [""])
    return out


def _front_value(source):
    low = source.lower()
    if low.endswith((".ipynb", ".py")):
        text = _text(source)
        if text is None:
            return None
        lines = _notebook_lines(text) if low.endswith(".ipynb") else _percent_lines(text)
    else:
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
        if source and str(source).lower().endswith((".qmd", ".md", ".ipynb", ".py")):
            v = _front_value(str(source))
        if v is None:
            v = _yml_value(folder)
        return "collect" if v == "collect" else "stop"
    except Exception:
        return "stop"
