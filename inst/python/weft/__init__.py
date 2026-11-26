"""weft: checks and named values for prose that quotes numbers.

    from weft import claim
    claim(n, "> 10")

Under a weft knit (R's knitr running this Python by reticulate) R loads this
package from its own copy, registers it as `weft`, and attaches the function
forms of rule G19 (fmt_num() and the rest) and the knitr back end. Installed
with pip it is the same code (rule N60).
"""

import collections.abc as _abc
import os as _os
import re as _re
import sys as _sys
import types as _types
import warnings as _warnings

from . import _backend
from . import _record

__weft_package__ = True

_OPERATORS = ("<=", ">=", "==", "!=", "<", ">")

_E50 = "claim() needs at least one check."
_E51 = 'a check is a string, such as "> 10" or "_ % 2 == 0".'
_E54 = 'level is "fail" or "warn".'


class WeftError(Exception):
    """Base of weft's exceptions."""


class ClaimFailed(WeftError, AssertionError):
    """A claim at level "fail" had a failed check."""


class PublishError(WeftError, TypeError):
    """A value that cannot be published by name."""


def _text(x):
    """x as `.val` prints it (rule N8)."""
    r = _record.classify(x)
    t = r["t"]
    if t == "bool":
        return "true" if r["v"] else "false"
    if t == "list":
        return ", ".join(_one(e) for e in r["v"])
    if t == "error":
        s = repr(x)
        return s if len(s) <= 80 else s[:77] + "..."
    return _one(r)


def _one(r):
    if r["t"] == "bool":
        return "true" if r["v"] else "false"
    if r["t"] == "missing":
        return r["why"]
    return str(r["v"])


def _is_bool(r):
    if isinstance(r, bool):
        return True
    np = _sys.modules.get("numpy")
    return np is not None and isinstance(r, np.bool_)


def _type_name(x):
    t = type(x)
    n = t.__module__ + "." + t.__qualname__
    return n[len("builtins."):] if n.startswith("builtins.") else n


def claim(x, *checks, level="fail"):
    """Check the value `x`; return it unchanged when every check passes.

    A check is a string. One that starts with <, <=, >, >=, == or != is read as
    `_ ` followed by it: claim(n, "> 10") checks `_ > 10`. Any other string is a
    Python expression in which `_` is the value: claim(n, "_ % 2 == 0"). It
    sees the caller's globals and locals.

    A failed check at level "fail" is recorded, then raises ClaimFailed. At
    level "warn" it is recorded as a warned check and nothing is raised.
    """
    if not checks:
        raise TypeError(_E50)
    for c in checks:
        if not isinstance(c, str):
            raise TypeError(_E51)
    if not (isinstance(level, str) and level in ("fail", "warn")):
        raise ValueError(_E54)

    frame = _sys._getframe(1)
    ns = dict(frame.f_globals)
    ns.update(frame.f_locals)
    ns["_"] = x
    del frame

    val = None
    failed = []
    for c in checks:
        stripped = c.lstrip(" ")
        shown = c
        src = c
        if stripped.startswith(_OPERATORS):
            src = "_ " + stripped
            shown = src
        why = None
        try:
            r = eval(src, ns)
            ok = _is_bool(r)
        except Exception as e:
            ok = False
            r = None
            why = "%s: %s" % (type(e).__name__, e)
        if ok and r:
            continue
        if val is None:
            val = _text(x)
        if why is not None or not ok:
            if why is None:
                detail = "%s gave a %s, not True or False" % (shown, _type_name(r))
            else:
                detail = "%s was false (value %s); %s" % (shown, val, why)
        else:
            detail = "%s was false (value %s)" % (shown, val)
        if why is None and not ok:
            why_field = "gave a %s, not True or False" % _type_name(r)
        else:
            why_field = why
        failed.append({"text": shown, "why": why_field, "detail": detail})
    if not failed:
        return x

    expr = "claim(" + chr(0x2026) + ", " +", ".join(repr(c) for c in checks) + ")"
    recorded = _backend.report(level, expr, failed, _record.classify(x))
    message = "weft: a claim failed: " + failed[0]["detail"] + "."
    if level == "fail":
        if recorded == "collected":
            return x
        raise ClaimFailed(message)
    if not recorded:
        _warnings.warn(message, UserWarning, stacklevel=2)
    return x


_E41 = ("`%s` is not a name weft can publish: ASCII letters, digits, _ and ., starting with a "
        "letter or _ (rule 1.12.1).")
_E42 = "`%s` is a list of %d elements; weft publishes at most 10000 (rule 2.13.1)."
_E59 = "auto() works in a Jupyter kernel or a weft knit."
_E60 = 'auto() cannot read the document %s; give it: auto("doc.qmd").'


def put(*maps, **named):
    """Publish values by name: put(depth=3.2) or put({"depth": 3.2}).

    Each keyword, and each key of a mapping given positionally, is published
    under that name. Nothing is published when one of them is not a NAME or is a
    list of more than 10000 elements (PublishError). Returns None.
    """
    pairs = []
    for m in maps:
        if not isinstance(m, _abc.Mapping):
            raise PublishError("put() takes keywords or mappings: put(n=3) or put({'n': 3}).")
        pairs.extend(m.items())
    pairs.extend(named.items())
    values = {}
    for k, v in pairs:
        if not _backend.is_name(k):
            raise PublishError(_E41 % (k,))
        rec, n = _backend.record_of(v)
        if rec is None:
            raise PublishError(_E42 % (k, n))
        values[k] = rec
    _backend.publish(values)
    return None


# ---- auto() (N45, N71) ------------------------------------------------------------------------

_auto = {"callback": None, "names": [], "last": {}}

_GOV_RE = _re.compile(
    r'(?<![A-Za-z0-9_.-])(?i:n|if|sign|list)='
    r'(?:"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'|((?:[^\s}"\'\\]|\\\|)+))', _re.S)
_UNESC_RE = _re.compile(r'\\(["\'| ])')
_LITERAL_RE = _re.compile(r"'[^']*'|\"[^\"]*\"")
_TOKEN_RE = _re.compile(r"(?<![A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*")
_CODE_RE = _re.compile(r"`([A-Za-z_][A-Za-z0-9_.]{0,63})`\{")


# ---- Quarto's {{< include >}} (the include rules I1 to I6, Quarto 1.11.9) ----------------------------
# The Python twin of R's include_targets() and include_walk() (R/include.R): a line is an include only
# when the whole line is the shortcode, one space inside each bracket (I1); `include` is lowercase in the
# main document, any case in an included file (I2); the path is the first positional parameter (I3);
# every path, at any depth, resolves against the MAIN document's folder, a leading / against the Quarto
# project root (I4); fences, cells and comments do not hide an include, a cell of the main document
# holding ```{shortcodes=false} does (I5); no depth limit, and a file already reached is not read again
# (I6).

_SHORTCODE_LINE_RE = _re.compile(r"^\s*\{\{< (?!/\*)(.+?)(?<!\*/) >\}\}\s*$")
_SC_NAME_RE = _re.compile(r"^/?[a-zA-Z0-9_]+")
_SC_NAMED_RES = (_re.compile(r'^[a-zA-Z0-9_-]+="[^"]*"'), _re.compile(r"^[a-zA-Z0-9_-]+='[^']*'"),
                 _re.compile(r"^[a-zA-Z0-9_-]+=[^\"'\s]+"))
_SC_BARE_RE = _re.compile(r"^[^\"'\s]+")
_SC_QUOTED_RE = _re.compile(r'^"[^"]*"|^\'[^\']*\'')
_CELL_START_RE = _re.compile(r"^\s*(```+)\s*\{([=A-Za-z][=A-Za-z0-9._]*)( *[ ,].*)?\}\s*$")
_CODE_END_RE = _re.compile(r"^\s*(```+)\s*$")
_YAML_RE = _re.compile(r"^---\s*$")
_NO_SHORTCODES_RE = _re.compile(r"\s*```\s*\{\s*shortcodes\s*=\s*false\s*\}")


def _block_shortcode(line):
    """The name and positional parameters of a line that is a block shortcode (I1), else None."""
    m = _SHORTCODE_LINE_RE.match(line)
    if not m:
        return None
    cap = m.group(1)
    nm = _SC_NAME_RE.match(cap)
    if not nm:
        return None
    rest = cap[nm.end():].strip()
    params = []
    while rest:
        hit = None
        for rx in _SC_NAMED_RES:
            hit = rx.match(rest)
            if hit:
                break
        if hit:
            rest = rest[hit.end():].strip()
            continue
        hit = _SC_BARE_RE.match(rest)
        if hit:
            params.append(hit.group(0))
        else:
            hit = _SC_QUOTED_RE.match(rest)
            if not hit:
                return None
            params.append(hit.group(0)[1:-1])
        rest = rest[hit.end():].strip()
    return nm.group(0), params


def _include_skipped(lines):
    """Which lines of the main document sit in a cell Quarto does not expand includes in (I5)."""
    n = len(lines)
    skip = [False] * n
    if not any("shortcodes" in x for x in lines):
        return skip
    buf = []

    def flush(force=False):
        if buf or force:
            if _NO_SHORTCODES_RE.search("\n".join(lines[k] for k in buf)):
                for k in buf:
                    skip[k] = True
        del buf[:]

    def blank(k):
        return 0 <= k < n and lines[k].strip() == ""

    def yaml_delim(k, skip_hr):
        if not _YAML_RE.match(lines[k]):
            return False
        return not (skip_hr and k > 0 and blank(k - 1) and k < n - 1 and blank(k + 1))

    in_yaml = in_cell = False
    in_code = 0
    for k, line in enumerate(lines):
        plain = not in_cell and not in_code and not in_yaml
        end = _CODE_END_RE.match(line)
        if not in_code and not in_cell and yaml_delim(k, not in_yaml):
            if in_yaml:
                buf.append(k)
                flush()
                in_yaml = False
            else:
                flush()
                buf.append(k)
                in_yaml = True
        elif plain and _block_shortcode(line) is not None:
            flush()
            buf.append(k)
            flush()
        elif plain and _CELL_START_RE.match(line):
            flush()
            in_cell = True
            in_code = len(_CELL_START_RE.match(line).group(1))
            buf.append(k)
        elif in_code and end and len(end.group(1)) == in_code:
            buf.append(k)
            if in_cell:
                in_cell = False
                flush(True)
            in_code = 0
        elif not in_code and line.startswith("```"):
            in_code = line.split(" ")[0].count("`")
            buf.append(k)
        else:
            buf.append(k)
    flush()
    return skip


def _quarto_root(main_dir):
    """The folder of _quarto.yml above the main document's folder, else that folder (I4)."""
    d = main_dir
    while True:
        if any(_os.path.isfile(_os.path.join(d, m)) for m in ("_quarto.yml", "_quarto.yaml")):
            return d
        up = _os.path.dirname(d)
        if up == d:
            return main_dir
        d = up


def _include_targets(lines, main_dir, root, in_included):
    """The paths the includes of one file's lines resolve to (absolute; the file may not exist)."""
    skip = None if in_included else _include_skipped(lines)
    out = []
    for k, line in enumerate(lines):
        if "{{< " not in line or (skip is not None and skip[k]):
            continue
        sc = _block_shortcode(line)
        if sc is None or not sc[1]:
            continue
        name = sc[0].lower() if in_included else sc[0]
        if name != "include":
            continue
        p = sc[1][0]
        p = root.rstrip("/") + p if p.startswith("/") else _os.path.join(main_dir, p)
        out.append(_os.path.realpath(_os.path.normpath(p)))
    return out


def _include_walk(path, read):
    """The lines of the main document and of every file it includes, each read once (I6)."""
    main = _os.path.realpath(_os.path.abspath(path))
    main_dir = _os.path.dirname(main)
    root = _quarto_root(main_dir)
    seen = {main}
    out = []

    def walk(lines, in_included):
        for p in _include_targets(lines, main_dir, root, in_included):
            if p in seen or not _os.path.isfile(p):
                continue
            seen.add(p)
            il = read(p)
            out.append(il or [])
            if il:
                walk(il, True)

    if not _os.path.isfile(main):
        return out
    lines = read(main)
    out.append(lines or [])
    if lines:
        walk(lines, False)
    return out


def _read_lines(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read().split("\n")
    except OSError:
        return None


def _source_names(path):
    """The names a source names (N45): its code spans and governors, and those of the files it includes."""
    found = []
    found_code = []
    for lines in _include_walk(path, _read_lines):
        txt = "\n".join(lines)
        found_code.extend(_CODE_RE.findall(txt))
        found.extend(_CODE_RE.findall(txt))
        for m in _GOV_RE.finditer(txt):
            g = _UNESC_RE.sub(r"\1", "".join(x for x in m.groups() if x is not None))
            found.extend(_TOKEN_RE.findall(_LITERAL_RE.sub(" ", g)))
    # a document with no named value (a code span with a name) publishes nothing by itself (N43)
    if not any(_backend.is_name(n) for n in found_code):
        return []
    out = []
    for n in found:
        if _backend.is_name(n) and n not in out:
            out.append(n)
    return out


def _is_code(v):
    return isinstance(v, (_types.ModuleType, _types.FunctionType, _types.BuiltinFunctionType,
                          _types.MethodType, type))


def _changes(names):
    """{name: wire record} for each of `names` bound in __main__ whose record changed since the last call.

    A name that is a module, function or class, or starts with an underscore, is left. A list of more than
    10000 elements raises PublishError (E42), as put() does, and nothing is recorded as published."""
    main = _sys.modules["__main__"].__dict__
    changed = {}
    texts = {}
    for n in names:
        if n.startswith("_") or n not in main:
            continue
        v = main[n]
        if _is_code(v):
            continue
        rec, k = _backend.record_of(v)
        if rec is None:
            raise PublishError(_E42 % (n, k))
        text = _backend.dumps(rec)
        if _auto["last"].get(n) != text:
            texts[n] = text
            changed[n] = rec
    _auto["last"].update(texts)
    return changed


def _publish_changes(*_args):
    """The post_run_cell callback of auto(): publish the changed names in one block.

    A PublishError (E42) is raised out of the callback, which IPython reports as the cell's error output."""
    try:
        changed = _changes(_auto["names"])
    except PublishError:
        raise
    except Exception as e:  # never break a cell from a callback
        _sys.stderr.write("weft: auto() could not publish: %s: %s\n" % (type(e).__name__, e))
        return
    if changed:
        try:
            _backend.publish(changed)
        except Exception as e:
            _sys.stderr.write("weft: auto() could not publish: %s: %s\n" % (type(e).__name__, e))


def _knitr_changes(names):
    """Under knitr, R asks (at each block of prose) which of `names` changed in __main__ since last asked:
    a dict {name: the record's JSON text}. Empty unless auto() was called in the knit (N71)."""
    if not _backend.auto_main:
        return {}
    names = [n for n in names if _backend.is_name(n)]
    return {n: _backend.dumps(r) for n, r in _changes(names).items()}


def auto(path=None):
    """Publish, after each cell, the names the document uses.

    In a Jupyter kernel: registers one post_run_cell callback (a second call
    replaces it) that publishes, in one block, each top-level name of __main__
    that the source names, that is not a module, function or class, and whose
    value changed. `path` is the source; by default QUARTO_DOCUMENT_PATH joined
    to QUARTO_DOCUMENT_FILE. Returns the path used.
    """
    k = _backend.kind()
    if k == "none":
        raise WeftError(_E59)
    if path is None:
        d = _os.environ.get("QUARTO_DOCUMENT_PATH", "")
        f = _os.environ.get("QUARTO_DOCUMENT_FILE", "")
        path = _os.path.join(d, f) if (d and f) else None
    else:
        path = _os.fspath(path)
    if k == "knitr":
        _backend.auto_main = True
        return path
    if path is None:
        raise WeftError(_E60 % "(QUARTO_DOCUMENT_PATH and QUARTO_DOCUMENT_FILE are not set)")
    try:
        with open(path, "rb") as fh:
            fh.read(1)
    except OSError:
        raise WeftError(_E60 % path)
    ip = _backend._ipython()
    old = _auto["callback"]
    if old is not None:
        try:
            ip.events.unregister("post_run_cell", old)
        except Exception:
            pass
    _auto["names"] = _source_names(path)
    _auto["last"] = {}
    _auto["callback"] = _publish_changes
    ip.events.register("post_run_cell", _publish_changes)
    return path
