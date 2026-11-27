# Jupyter notebooks and percent scripts, for the reader of a document's front matter (rule P7 of 2.1.6 in
# dev/PACKAGE-SCOPING.md): the twin of R's R/notebook.R and of weft/_config.py. Base only, so the notebook's
# JSON is read by the small reader below.
#
#   .ipynb  the source of each raw and markdown cell, in cell order, each followed by a blank line
#   .py     a percent script (one with a `# %% [markdown]` or `# %% [raw]` cell): each markdown and raw
#           cell, its empty lines at either end dropped, the leading `#` and one white-space character off
#           each line (or the lines inside its triple-quote lines), then a blank line; a raw cell that
#           names a format is raw output, fenced; code cells and the text above the first `# %%` line are
#           left out
#
# Code cells hold no front matter, and neither kind expands includes.

# ---- a JSON reader ----------------------------------------------------------------------------------

# Objects as Dict{String,Any}, arrays as Vector{Any}, strings, numbers as Float64, true, false and nothing
# (for null). Malformed text throws.
mutable struct _NbJson
    s::String
    i::Int
end

_nbj_peek(p::_NbJson) = p.i <= ncodeunits(p.s) ? p.s[p.i] : '\0'

function _nbj_skip!(p::_NbJson)
    while p.i <= ncodeunits(p.s) && p.s[p.i] in (' ', '\t', '\n', '\r')
        p.i += 1
    end
end

function _nbj_string!(p::_NbJson)
    s = p.s
    p.i += 1
    io = IOBuffer()
    while true
        p.i > ncodeunits(s) && error("JSON: a string is not closed")
        c = s[p.i]
        if c == '"'
            p.i += 1
            return String(take!(io))
        elseif c == '\\'
            e = s[p.i + 1]
            p.i += 2
            if e == 'u'
                u = parse(UInt32, s[p.i:p.i + 3]; base = 16)
                p.i += 4
                if 0xd800 <= u <= 0xdbff && p.i + 5 <= ncodeunits(s) && s[p.i] == '\\' && s[p.i + 1] == 'u'
                    lo = parse(UInt32, s[p.i + 2:p.i + 5]; base = 16)
                    if 0xdc00 <= lo <= 0xdfff
                        u = 0x10000 + ((u - 0xd800) << 10) + (lo - 0xdc00)
                        p.i += 6
                    end
                end
                print(io, isvalid(Char, u) ? Char(u) : '\ufffd')
            else
                print(io, e == 'n' ? '\n' : e == 't' ? '\t' : e == 'r' ? '\r' : e == 'b' ? '\b' :
                          e == 'f' ? '\f' : e)
            end
        else
            print(io, c)
            p.i = nextind(s, p.i)
        end
    end
end

function _nbj_value!(p::_NbJson)
    _nbj_skip!(p)
    c = _nbj_peek(p)
    if c == '{'
        p.i += 1
        d = Dict{String, Any}()
        _nbj_skip!(p)
        if _nbj_peek(p) == '}'
            p.i += 1
            return d
        end
        while true
            _nbj_skip!(p)
            _nbj_peek(p) == '"' || error("JSON: a key is not a string")
            k = _nbj_string!(p)
            _nbj_skip!(p)
            _nbj_peek(p) == ':' || error("JSON: no colon after a key")
            p.i += 1
            d[k] = _nbj_value!(p)
            _nbj_skip!(p)
            c = _nbj_peek(p)
            p.i += 1
            c == '}' && return d
            c == ',' || error("JSON: no comma between members")
        end
    elseif c == '['
        p.i += 1
        v = Any[]
        _nbj_skip!(p)
        if _nbj_peek(p) == ']'
            p.i += 1
            return v
        end
        while true
            push!(v, _nbj_value!(p))
            _nbj_skip!(p)
            c = _nbj_peek(p)
            p.i += 1
            c == ']' && return v
            c == ',' || error("JSON: no comma between elements")
        end
    elseif c == '"'
        return _nbj_string!(p)
    end
    j = p.i
    while p.i <= ncodeunits(p.s) && !(p.s[p.i] in (',', ']', '}', ' ', '\t', '\n', '\r'))
        p.i += 1
    end
    t = p.s[j:p.i - 1]
    t == "true" && return true
    t == "false" && return false
    t == "null" && return nothing
    x = tryparse(Float64, t)
    x === nothing && error("JSON: an unknown value")
    x
end

_nb_json(text::AbstractString) = _nbj_value!(_NbJson(String(text), 1))

# ---- the lines front matter is read from --------------------------------------------------------------

# The lines of a notebook's JSON `text` its front matter is read from (nothing read: no lines).
function _nb_lines(text::AbstractString)
    nb = try
        _nb_json(text)
    catch
        return String[]
    end
    out = String[]
    (nb isa Dict && get(nb, "cells", nothing) isa Vector) || return out
    for cell in nb["cells"]
        (cell isa Dict && get(cell, "cell_type", "") in ("markdown", "raw")) || continue
        src = get(cell, "source", "")
        s = src isa AbstractString ? String(src) :
            src isa Vector ? join([x for x in src if x isa AbstractString]) : ""
        if !isempty(s)
            endswith(s, "\n") && (s = s[1:prevind(s, lastindex(s))])
            append!(out, String.(split(s, '\n')))
        end
        push!(out, "")
    end
    out
end

const _PC_SCRIPT = r"^\s*#\s*%%+\s+\[(markdown|raw)\]"m
const _PC_HEADER = r"^\s*#\s*%%+\s*(?:\[(markdown|raw)\])?\s*(.*)?$"
const _PC_TRIPLE = r"^\"{3,}\s*$"

# The lines of a percent script's `text` its front matter is read from (no markdown or raw cell: none).
function _pc_lines(text::AbstractString)
    text = strip(text)
    occursin(_PC_SCRIPT, text) || return String[]
    cells = Tuple{String, String, Vector{String}}[]
    for line in split(text, '\n')
        m = match(_PC_HEADER, line)
        if m !== nothing
            push!(cells, (m.captures[1] === nothing ? "code" : String(m.captures[1]),
                          m.captures[2] === nothing ? "" : String(m.captures[2]), String[]))
        elseif !isempty(cells)
            push!(cells[end][3], String(line))
        end
    end
    out = String[]
    for (kind, attrs, body) in cells
        kind == "code" && continue
        a = findfirst(l -> !isempty(strip(l)), body)
        b = findlast(l -> !isempty(strip(l)), body)
        body = a === nothing ? String[] : body[a:b]
        if length(body) > 2 && occursin(_PC_TRIPLE, body[1]) && occursin(_PC_TRIPLE, body[end])
            body = body[2:end - 1]
        else
            body = [replace(l, r"^#\s?" => "") for l in body]
        end
        if kind == "raw" && occursin(r"(^|\s)(format|raw_mimetype)=", attrs)
            body = vcat(["```{=raw}"], body, ["```"])
        end
        append!(out, body)
        push!(out, "")
    end
    out
end
