# The setting `chunk_claims`, read by the guest at a failed claim (GN4 of dev/design-8.md). The same
# reading as weft/_config.py: the files are read at each call and nothing is kept. Base only.
#
#   _weft.yml  the first one found in the folder or up to 8 parents: the first line that starts at
#              column 1 with `chunk_claims`, optional spaces or tabs, then `:`. The value is the rest
#              of the line, a `#` comment that follows white space removed, trimmed, one pair of
#              surrounding quotes removed.
#   document   when the source ends .qmd, .md, .ipynb or .py: the key `chunk_claims` of the `weft:` mapping of its
#              front matter, in block or flow form. The front matter is every metadata block, as Pandoc
#              and weft's R side read them (rule 2.1.6 of dev/PACKAGE-SCOPING.md): a line that is exactly
#              `---` at the top (only blank lines above) or after a blank line, a next line that is not
#              blank, closed at the next `---` or `...` line, holding a mapping, and not inside a fence
#              or an HTML comment. A later block's `weft:` replaces an earlier one's whole, so the value
#              is read from the last block with a top-level `weft:` key. The blocks are read with the
#              document's includes expanded as Quarto expands them (rule P5, include.jl): an included
#              file's blocks sit where its include sits. The document's value, when it has one, wins.
#              A notebook's or a percent script's front matter is read from its raw and markdown cells
#              (rule P7, notebook.jl).
#
# The result is "collect" exactly when the value that applies is `collect`, else "stop".

const _CC_KEY = r"^chunk_claims[ \t]*:(.*)$"
const _CC_COMMENT = r"(?:^|\s)#"

function _cc_lines(path::AbstractString)
    raw = try
        read(path, String)
    catch
        return nothing
    end
    startswith(raw, Char(0xFEFF)) && (raw = raw[nextind(raw, 1):end])
    split(replace(replace(raw, "\r\n" => "\n"), '\r' => '\n'), '\n')
end

function _cc_strip_comment(s::AbstractString)
    m = match(_CC_COMMENT, s)
    m === nothing ? String(s) : String(s[1:prevind(s, m.offset)])
end

function _cc_clean(rest::AbstractString)
    s = strip(_cc_strip_comment(rest), [' ', '\t'])
    if length(s) >= 2 && first(s) == last(s) && first(s) in ('"', '\'')
        s = s[nextind(s, 1):prevind(s, lastindex(s))]
    end
    String(s)
end

function _cc_yml_value(folder::AbstractString)
    d = abspath(isempty(folder) ? pwd() : folder)
    for _ in 1:9
        f = joinpath(d, "_weft.yml")
        if isfile(f)
            lines = _cc_lines(f)
            lines === nothing && return nothing
            for line in lines
                m = match(_CC_KEY, line)
                m === nothing || return _cc_clean(m.captures[1])
            end
            return nothing
        end
        up = dirname(d)
        up == d && break
        d = up
    end
    nothing
end

# the first colon outside quotes: (key, rest) or nothing
function _cc_partition_colon(item::AbstractString)
    quote_ = nothing
    for (i, ch) in pairs(item)
        if quote_ !== nothing
            ch == quote_ && (quote_ = nothing)
        elseif ch == '"' || ch == '\''
            quote_ = ch
        elseif ch == ':'
            return (item[1:prevind(item, i)], item[nextind(item, i):end])
        end
    end
    nothing
end

# whether the braces of a flow mapping, seen so far, are closed
function _cc_balanced(text::AbstractString)
    depth = 0
    seen = false
    quote_ = nothing
    for ch in text
        if quote_ !== nothing
            ch == quote_ && (quote_ = nothing)
        elseif ch == '"' || ch == '\''
            quote_ = ch
        elseif ch == '{' || ch == '['
            depth += 1
            seen = true
        elseif ch == '}' || ch == ']'
            depth -= 1
        end
    end
    seen && depth <= 0
end

# the top-level `key: value` items of a flow mapping, as (key, rest) pairs
function _cc_split_flow(text::AbstractString)
    items = String[]
    depth = 0
    quote_ = nothing
    cur = IOBuffer()
    for ch in text
        if quote_ !== nothing
            write(cur, ch)
            ch == quote_ && (quote_ = nothing)
        elseif ch == '"' || ch == '\''
            quote_ = ch
            write(cur, ch)
        elseif ch == '{' || ch == '['
            depth += 1
            depth > 1 && write(cur, ch)
        elseif ch == '}' || ch == ']'
            depth -= 1
            depth >= 1 && write(cur, ch)
            depth <= 0 && break
        elseif ch == ',' && depth == 1
            push!(items, String(take!(cur)))
        else
            write(cur, ch)
        end
    end
    push!(items, String(take!(cur)))
    out = Tuple{String, String}[]
    for it in items
        kv = _cc_partition_colon(it)
        kv === nothing || push!(out, (String(kv[1]), String(kv[2])))
    end
    out
end

const _CC_FENCE = r"^[ \t>]*(`{3,}|~{3,})"
const _CC_OPEN = r"^---[ \t]*$"
const _CC_CLOSE = r"^(---|\.\.\.)[ \t]*$"
const _CC_COMMENT_OPEN = r"^ {0,3}<!--"
const _CC_MAP_KEY = r"^[A-Za-z_\"'][^:]*:([ \t]|$)"
const _CC_WEFT_KEY = r"^weft[ \t]*:"

_cc_blank(s::AbstractString) = isempty(strip(s))

# Whether the lines of a candidate block read as a YAML mapping: its first line that is not blank and not
# a comment is `key:` or opens a flow mapping (no YAML parser here; plain text or a list is what it has to
# tell apart).
function _cc_is_mapping(inner)
    for line in inner
        t = strip(line, [' ', '\t'])
        (isempty(t) || startswith(t, "#")) && continue
        return occursin(_CC_MAP_KEY, line) || startswith(t, "{")
    end
    false
end

# ---- the one fence finder (A18), the twin of R/fences.R -------------------------------------------------
# The metadata blocks are found as R's doc_fences() finds them (the A18 ruling and its amendments of 27 Nov):
# first the executable chunks over the whole text, as knitr finds them (_cc_knitr_chunks()); then, in the text
# outside them, the plain fences as Pandoc's markdown reader reads them, the HTML comments that hide them, and
# the metadata blocks (_cc_blocks()).

const _CC_KNITR_BEGIN = r"^[\t >]*```+\s*\{([a-zA-Z0-9_]+( *[ ,].*)?)\}\s*$"
const _CC_KNITR_END = r"^[\t >]*```+\s*$"
const _CC_CHUNK_PREFIX = r"^([\t >]*`+)"
const _CC_FENCE_LINE = r"^( {0,3})((?:> ?(?: {0,3}(?=>))?)*)( *)(`{3,}|~{3,})(.*)$"
const _CC_QUOTE = r"^ {0,3}(?:> ?(?: {0,3}(?=>))?)*"
const _CC_ITEM = r"^( *)([-+*]|[0-9]{1,9}[.)])(?:( {1,4})(?=\S)|[ \t]*$)"
const _CC_ATTR = "\\{[ \\t]*(?:(?:#[A-Za-z0-9_:.-]+|\\.[A-Za-z][A-Za-z0-9_:.-]*" *
                 "|[A-Za-z][A-Za-z0-9_:.-]*=(?:\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|[^ \\t}]+)|-)[ \\t]*)*\\}"
const _CC_INFO = Regex("^(?:\\{[ \\t]*=[A-Za-z0-9_-]+[ \\t]*\\}|[^ \\t{`]*[ \\t]*(?:" * _CC_ATTR * ")?)\$")

_cc_exact_end(l, p) = startswith(l, p) && isempty(strip(l[nextind(l, lastindex(p)):end]))

# The chunks of `lines` as knitr divides a document (R's knitr_chunks()): (open, close) pairs.
function _cc_knitr_chunks(lines)
    n = length(lines)
    cand = Int[]
    isb = Bool[]
    for (i, l) in enumerate(lines)
        occursin("```", l) || continue
        b = occursin(_CC_KNITR_BEGIN, l)
        if b || occursin(_CC_KNITR_END, l)
            push!(cand, i)
            push!(isb, b)
        end
    end
    out = Tuple{Int, Int}[]
    # is the end line cand[t] (not exact) code, because knitr reads on to a later exact closer?
    function reads_on(t, p)
        i = cand[t]
        e = 0
        for s in t + 1:length(cand)
            if !isb[s] && _cc_exact_end(lines[cand[s]], p)
                e = cand[s]
                break
            end
        end
        e == 0 && return false
        for q in i + 1:e - 1
            b = lines[q]
            startswith(b, p) && occursin(r"^`*\{", b[nextind(b, lastindex(p)):end]) && return false
        end
        true
    end
    cur = 0
    p = nothing
    for (t, i) in enumerate(cand)
        l = lines[i]
        if cur == 0
            if isb[t]
                cur = i
                p = i == 1 ? nothing : match(_CC_CHUNK_PREFIX, l).captures[1]
            end
        elseif isb[t]
            if p === nothing || startswith(l, p * "{")
                push!(out, (cur, i - 1))
                cur = i
            end
        elseif !(p !== nothing && !_cc_exact_end(l, p) && reads_on(t, p))
            push!(out, (cur, i))
            cur = 0
        end
    end
    cur == 0 || push!(out, (cur, n))
    out
end

# `l` with the tabs of its leading white space and `>` markers expanded to the next stop of 4.
function _cc_expand_tabs(l::AbstractString)
    occursin(r"^[ >]*\t", l) || return String(l)
    lead = match(r"^[ \t>]*", l).match
    out = IOBuffer()
    col = 0
    for ch in lead
        if ch == '\t'
            w = 4 - col % 4
            write(out, " "^w)
            col += w
        else
            write(out, ch)
            col += 1
        end
    end
    String(take!(out)) * l[nextind(l, lastindex(lead)):end]
end

# A fence line as R's parse_fence_lines() reads it: (depth, indent, char, length, info), or nothing.
function _cc_parse_fence(l)
    m = match(_CC_FENCE_LINE, _cc_expand_tabs(l))
    m === nothing && return nothing
    depth = count(==('>'), m.captures[2])
    indent = depth > 0 ? length(m.captures[3]) : length(m.captures[1]) + length(m.captures[3])
    (depth, indent, first(m.captures[4]), length(m.captures[4]), String(m.captures[5]))
end

_cc_quote_depth(l) = count(==('>'), match(_CC_QUOTE, l).match)
_cc_lead_width(l) = length(match(r"^ *", _cc_expand_tabs(l)).match)

# The content column of the list item the line `k`, indented `ind` (4 or more), sits in, or nothing.
function _cc_list_item_col(lines, k, ind)
    j = k - 1
    while j >= 1
        if _cc_blank(lines[j])
            j -= 1
            continue
        end
        l = _cc_expand_tabs(lines[j])
        m = match(_CC_ITEM, l)
        if m !== nothing
            c0 = m.captures[3] === nothing ? length(m.captures[1]) + length(m.captures[2]) + 1 : length(m.match)
            c0 <= ind <= c0 + 3 && return c0
            isempty(m.captures[1]) && return nothing
        elseif _cc_lead_width(l) == 0 && (j == 1 || _cc_blank(lines[j - 1]))
            return nothing
        end
        j -= 1
    end
    nothing
end

# The inner lines of each metadata block of a document, in order (see the note at the top), as R's
# plain_blocks() reads them outside the chunks: a fence opens with an info string Pandoc's markdown reader
# takes (none, one word, an attribute block); one that does not close in its container is no fence; in a list
# item a fence at indent 4 or more needs a blank line above.
function _cc_blocks(lines)
    out = Vector{Vector{String}}()
    n = length(lines)
    inchunk = falses(n)
    for (a, b) in _cc_knitr_chunks(lines)
        inchunk[a:b] .= true
    end
    pf = Dict{Int, Any}()
    fi = Int[]
    for (j, l) in enumerate(lines)
        if !inchunk[j] && occursin(_CC_FENCE, l)
            pf[j] = _cc_parse_fence(l)
            push!(fi, j)
        end
    end
    at = Dict(j => s for (s, j) in enumerate(fi))
    function closes(j, r, d, c0)
        q = get(pf, j, nothing)
        q === nothing && return false
        q[3] == r[3] && q[4] >= r[4] && q[1] == d && isempty(strip(q[5], [' ', '\t', '\r'])) && c0 <= q[2] <= c0 + 3
    end
    function fence_close(k, r, c0)
        if r[1] == 0 && c0 == 0
            for s in at[k] + 1:length(fi)
                closes(fi[s], r, 0, 0) && return fi[s]
            end
            return nothing
        end
        for j in k + 1:n
            inchunk[j] && continue
            l = lines[j]
            r[1] > 0 && _cc_quote_depth(l) < r[1] && return nothing
            c0 > 0 && !_cc_blank(l) && _cc_lead_width(l) < c0 && return nothing
            haskey(pf, j) && closes(j, r, r[1], c0) && return j
        end
        nothing
    end
    closers = Set{Int}()
    k = 1
    while k <= n
        line = lines[k]
        nxt = k + 1
        if inchunk[k]
            # a chunk's line
        elseif haskey(pf, k)
            r = pf[k]
            if r !== nothing && occursin(_CC_INFO, strip(r[5], [' ', '\t', '\r', '\n']))
                c0 = 0
                if r[2] > 3
                    if r[1] > 0
                        c0 = nothing
                    elseif k > 1 && !_cc_blank(lines[k - 1]) && !inchunk[k - 1] && !((k - 1) in closers)
                        # no blank line (or a block's end) above: the line goes on the paragraph above
                        c0 = nothing
                    else
                        c0 = _cc_list_item_col(lines, k, r[2])
                    end
                end
                c = c0 === nothing ? nothing : fence_close(k, r, c0)
                if c !== nothing
                    push!(closers, c)
                    nxt = c + 1
                end
            end
        elseif occursin(_CC_COMMENT_OPEN, line)
            # the comment ends at the first `-->` after its `<!--`; one that never ends hides nothing
            after = split(line, "<!--"; limit = 2)[2]
            if !occursin("-->", after)
                stop = findnext(j -> !inchunk[j] && occursin("-->", lines[j]), 1:n, k + 1)
                stop === nothing || (nxt = stop + 1)
            end
        elseif occursin(_CC_OPEN, line) && (k == 1 || _cc_blank(lines[k - 1])) && k < n && !_cc_blank(lines[k + 1])
            j = k + 1
            while j <= n && !occursin(_CC_CLOSE, lines[j])
                j += 1
            end
            if j <= n && _cc_is_mapping(lines[k + 1:j - 1])
                push!(out, String.(lines[k + 1:j - 1]))
                nxt = j + 1
            end
        end
        k = nxt
    end
    out
end

function _cc_front_value(source::AbstractString)
    lines = _cc_lines(source)
    (lines === nothing || isempty(lines)) && return nothing
    low = lowercase(source)
    lines = endswith(low, ".ipynb") ? _nb_lines(join(lines, "\n")) :
            endswith(low, ".py") ? _pc_lines(join(lines, "\n")) : _inc_expanded(source, lines, _cc_lines)
    weft = filter(b -> any(l -> occursin(_CC_WEFT_KEY, l), b), _cc_blocks(lines))
    isempty(weft) && return nothing
    _cc_weft_value(last(weft))
end

# `chunk_claims` of the `weft:` mapping in the lines `front` of one block, or nothing.
function _cc_weft_value(front)
    for (i, line) in enumerate(front)
        m = match(r"^weft[ \t]*:(.*)$", line)
        m === nothing && continue
        rest = strip(_cc_strip_comment(m.captures[1]), [' ', '\t'])
        if startswith(rest, "{")
            text = String(rest)
            j = i + 1
            while !_cc_balanced(text) && j <= length(front)
                text *= " " * strip(_cc_strip_comment(front[j]), [' ', '\t'])
                j += 1
            end
            for (k, v) in _cc_split_flow(text)
                _cc_clean(k) == "chunk_claims" && return _cc_clean(v)
            end
            return nothing
        end
        indent = nothing
        for line2 in front[i + 1:end]
            isempty(strip(line2, [' ', '\t'])) && continue
            ind = length(line2) - length(lstrip(line2, [' ', '\t']))
            ind == 0 && break
            indent === nothing && (indent = ind)
            if ind == indent
                m2 = match(_CC_KEY, line2[ind + 1:end])
                m2 === nothing || return _cc_clean(m2.captures[1])
            end
        end
        return nothing
    end
    nothing
end

"""
    chunk_claims_setting(source, folder) -> "collect" | "stop"

The setting `chunk_claims` for the document `source` (a path, or "") in `folder`: `collect` exactly when the
value that applies, the document's front matter first, then the nearest `_weft.yml`, is `collect`.
"""
function chunk_claims_setting(source::AbstractString, folder::AbstractString)::String
    try
        v = nothing
        if any(e -> endswith(lowercase(source), e), (".qmd", ".md", ".ipynb", ".py"))
            v = _cc_front_value(source)
        end
        v === nothing && (v = _cc_yml_value(folder))
        v == "collect" ? "collect" : "stop"
    catch
        "stop"
    end
end
