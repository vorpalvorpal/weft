# Quarto's `{{< include >}}`, read the way Quarto 1.11.9 expands it (the include rules I1 to I6 of 2.7.4 in
# dev/PACKAGE-SCOPING.md), for the reader of a document's front matter (rule P5 of 2.1.6). The twin of R's
# R/include.R and of `weft._include_lines` in Python. Base only.
#
#   I1  a line is an include only when the whole line is the shortcode: optional white space, `{{< `,
#       the name, the parameters, ` >}}`, optional white space; the escaped `{{</* include x */>}}` is
#       not one
#   I2  the name is `include`, lowercase, in the main document; any case in an included file
#   I3  the path is the first positional parameter: "...", '...' or a run with no white space or quote
#   I4  every path, at any depth, is resolved against the MAIN document's folder; a leading `/` against
#       the Quarto project root (the folder of `_quarto.yml`), else the main document's folder
#   I5  fences, executable cells and HTML comments do not hide an include; in the main document a cell
#       whose text holds ```` ```{shortcodes=false} ```` does (Quarto checks no cell in an included file)
#   I6  no depth limit; a file is not expanded inside itself, so a cycle ends

const _INC_LINE = r"^\s*\{\{< (?!/\*)(.+?)(?<!\*/) >\}\}\s*$"
const _INC_NAME = r"^/?[A-Za-z0-9_]+"
const _INC_NAMED = (r"^[A-Za-z0-9_-]+=\"[^\"]*\"", r"^[A-Za-z0-9_-]+='[^']*'", r"^[A-Za-z0-9_-]+=[^\"'\s]+")
const _INC_BARE = r"^[^\"'\s]+"
const _INC_QUOTED = r"^\"[^\"]*\"|^'[^']*'"
const _INC_CELL = r"^\s*(```+)\s*\{([=A-Za-z][=A-Za-z0-9._]*)( *[ ,].*)?\}\s*$"
const _INC_CODE_END = r"^\s*(```+)\s*$"
const _INC_YAML = r"^---\s*$"
const _INC_NO_SHORTCODES = r"\s*```\s*\{\s*shortcodes\s*=\s*false\s*\}"

# The name and positional parameters of a line that is a block shortcode (I1), else nothing.
function _inc_block_shortcode(line::AbstractString)
    m = match(_INC_LINE, line)
    m === nothing && return nothing
    cap = m.captures[1]
    nm = match(_INC_NAME, cap)
    nm === nothing && return nothing
    rest = strip(cap[nextind(cap, 0, length(nm.match) + 1):end])
    params = String[]
    while !isempty(rest)
        hit = nothing
        for rx in _INC_NAMED
            hit = match(rx, rest)
            hit === nothing || break
        end
        if hit !== nothing
            rest = strip(rest[nextind(rest, 0, length(hit.match) + 1):end])
            continue
        end
        hit = match(_INC_BARE, rest)
        if hit !== nothing
            push!(params, String(hit.match))
        else
            hit = match(_INC_QUOTED, rest)
            hit === nothing && return nothing
            q = hit.match
            push!(params, String(q[nextind(q, 1):prevind(q, lastindex(q))]))
        end
        rest = strip(rest[nextind(rest, 0, length(hit.match) + 1):end])
    end
    (String(nm.match), params)
end

# Which lines of the main document sit in a cell Quarto does not expand includes in (I5): the cells are
# breakQuartoMd's (front matter, a block shortcode line, an executable cell, and the markdown between).
function _inc_skipped(lines)
    n = length(lines)
    skip = falses(n)
    any(l -> occursin("shortcodes", l), lines) || return skip
    buf = Int[]
    function flush!()
        if !isempty(buf) && occursin(_INC_NO_SHORTCODES, join(lines[buf], "\n"))
            skip[buf] .= true
        end
        empty!(buf)
    end
    blank(k) = 1 <= k <= n && isempty(strip(lines[k]))
    function yaml_delim(k, skip_hr)
        occursin(_INC_YAML, lines[k]) || return false
        !(skip_hr && k > 1 && blank(k - 1) && k < n && blank(k + 1))
    end
    in_yaml = false
    in_cell = false
    in_code = 0
    for k in 1:n
        line = lines[k]
        plain = !in_cell && in_code == 0 && !in_yaml
        fin = match(_INC_CODE_END, line)
        if in_code == 0 && !in_cell && yaml_delim(k, !in_yaml)
            if in_yaml
                push!(buf, k)
                flush!()
                in_yaml = false
            else
                flush!()
                push!(buf, k)
                in_yaml = true
            end
        elseif plain && _inc_block_shortcode(line) !== nothing
            flush!()
            push!(buf, k)
            flush!()
        elseif plain && occursin(_INC_CELL, line)
            flush!()
            in_cell = true
            in_code = length(match(_INC_CELL, line).captures[1])
            push!(buf, k)
        elseif in_code > 0 && fin !== nothing && length(fin.captures[1]) == in_code
            push!(buf, k)
            if in_cell
                in_cell = false
                flush!()
            end
            in_code = 0
        elseif in_code == 0 && startswith(line, "```")
            in_code = count(==('`'), split(line, ' ')[1])
            push!(buf, k)
        else
            push!(buf, k)
        end
    end
    flush!()
    skip
end

# The folder of _quarto.yml above the main document's folder, else that folder (I4).
function _inc_quarto_root(main_dir::AbstractString)
    d = main_dir
    while true
        any(m -> isfile(joinpath(d, m)), ("_quarto.yml", "_quarto.yaml")) && return d
        up = dirname(d)
        up == d && return main_dir
        d = up
    end
end

_inc_real(p::AbstractString) = ispath(p) ? realpath(p) : normpath(p)

# (line, path it resolves to) of each include of one file's lines (I1 to I5); the file may not exist.
function _inc_lines(lines, main_dir::AbstractString, root::AbstractString, in_included::Bool)
    skip = in_included ? falses(length(lines)) : _inc_skipped(lines)
    out = Tuple{Int, String}[]
    for (k, line) in enumerate(lines)
        (occursin("{{< ", line) && !skip[k]) || continue
        sc = _inc_block_shortcode(line)
        (sc === nothing || isempty(sc[2])) && continue
        name = in_included ? lowercase(sc[1]) : sc[1]
        name == "include" || continue
        p = sc[2][1]
        p = startswith(p, "/") ? rstrip(root, '/') * p : joinpath(main_dir, p)
        push!(out, (k, _inc_real(normpath(p))))
    end
    out
end

# The lines of the document `source` (its own `lines`, as `read` gives them) with every include expanded as
# Quarto splices them: each include line replaced by the included file's expanded lines and one blank line
# (two for an include inside an included file). A file is not expanded inside itself (I6); an include
# whose file cannot be read (`read` gives nothing) stays the line it is.
function _inc_expanded(source::AbstractString, lines, read)
    any(l -> occursin("{{< ", l), lines) || return lines
    main = _inc_real(abspath(source))
    main_dir = dirname(main)
    root = _inc_quarto_root(main_dir)
    out = String[]
    function go(ls, key, stack, in_included)
        targets = Dict(_inc_lines(ls, main_dir, root, in_included))
        stack = union(stack, Set([key]))
        for (k, line) in enumerate(ls)
            p = get(targets, k, nothing)
            sub = (p !== nothing && !(p in stack) && isfile(p)) ? read(p) : nothing
            if sub === nothing
                push!(out, String(line))
                continue
            end
            go(sub, p, stack, true)
            append!(out, fill("", in_included ? 2 : 1))
        end
    end
    go(lines, main, Set{String}(), false)
    out
end
