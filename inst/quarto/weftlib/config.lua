-- weftlib/config.lua: the filter's configuration (dev/design-6.md N84, D18, E33).
--
--   local config = dofile("weftlib/config.lua")
--   cfg, problems = config.load(source_path, source_text)
--
-- Reads `_weft.yml` (found upward from the source's folder, at most 8 levels) and the `weft:`
-- mapping of the source's own front matter, as text, with a flat reader and never through
-- Pandoc's metadata (which mangles " " and "--", measured 10). The document's value wins.
-- The front matter is every metadata block, as Pandoc and weft's R side read them (rule 2.1.6 of
-- dev/PACKAGE-SCOPING.md): a line that is exactly `---` at the top (only blank lines above) or after a
-- blank line, a next line that is not blank, closed at the next `---` or `...` line, holding a mapping,
-- and not inside a fence or an HTML comment. A later block's `weft:` replaces an earlier one's whole, so
-- the `weft:` mapping is read from the last block with a top-level `weft:` key. The blocks are read with
-- the source's includes expanded (rule P5): an included file's blocks sit where its include sits, read
-- by weftlib/lines.lua's expanded_lines() from beside this file. A notebook's (`.ipynb`) and a percent
-- script's (`.py`) are read from its raw and markdown cells (rule P7, jupyter_lines()).
-- A mapping may be written in block style or in flow style (`weft: {digits: 3}`, `formatters:
-- {.f: {digits: 2}}`), on one line or several; both give the same settings. A `weft:` or `formatters:`
-- value that is neither is a problem (E33), never ignored.
--   cfg       the settings (defaults filled in), plus cfg.formatters, a set of the class names (no
--             dot) under a non-empty `formatters:` mapping.
--   problems  an array of {file = <display path>, key = <key>, value = <text>, what = <kind>}:
--             a value of the wrong kind for its key (E33); the default is used for it.
-- No side effect on load.

local M = {}

-- the folder of this file, for its sibling weftlib/lines.lua (loaded when a source has an include)
local HERE = (debug.getinfo(1, "S").source or ""):match("^@(.*)[/\\][^/\\]*$") or "."
local lines_lib

M.DEFAULTS = {
  digits = 1, decimal_mark = ".", big_mark = ",", thousands_from = 1000, minus = "\u{2212}",
  governor_class = "num", pct_proportion = true, serial_comma = false, count_threshold = 10,
  word_limit = 100, date_format = "%-d %B %Y", draft = false, ledger = true,
  p_label = "p", output_refs = "fail", output_missing = "warn", output_markup = "fail", chunk_claims = "stop",
}

local KINDS = {
  digits = "int", thousands_from = "int", count_threshold = "int", word_limit = "int",
  pct_proportion = "bool", serial_comma = "bool", draft = "bool", ledger = "bool",
  decimal_mark = "str", big_mark = "str", minus = "str", governor_class = "str", date_format = "str",
  p_label = "str", p_digits = "pdig",
  output_refs = "sev", output_missing = "sev", output_markup = "sev",
  chunk_claims = "claims",
}
local WHAT = { int = "whole number", bool = "true or false", str = "string",
               pdig = "whole number from 1 to 6, or null", sev = "fail, warn or off",
               claims = "stop or collect" }

local function trim(s) return (s:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")) end

-- one VALUE: returns kind ("str", "bool", "int", "bare", "empty", "bad") and the value
local function scalar(text)
  text = trim(text)
  if text == "" or text:sub(1, 1) == "#" then return "empty" end
  local q = text:sub(1, 1)
  if q == '"' then
    local i = 2
    while i <= #text do
      local c = text:sub(i, i)
      if c == "\\" then i = i + 2
      elseif c == '"' then break
      else i = i + 1 end
    end
    if i > #text then return "bad", text end
    local ok, v = pcall(pandoc.json.decode, text:sub(1, i), false)
    if ok and type(v) == "string" then return "str", v end
    return "bad", text
  elseif q == "'" then
    local out, i = {}, 2
    while i <= #text do
      local c = text:sub(i, i)
      if c == "'" then
        if text:sub(i + 1, i + 1) == "'" then out[#out + 1] = "'"; i = i + 2
        else return "str", table.concat(out) end
      else out[#out + 1] = c; i = i + 1 end
    end
    return "bad", text
  end
  -- a bare value: a trailing `# comment` (a # after white space) is removed
  local body = text:gsub("[ \t\r\n]+#.*$", "")
  body = trim(body)
  -- booleans as the YAML reader of R reads them: true, True, TRUE (and false likewise)
  if body == "true" or body == "True" or body == "TRUE" then return "bool", true end
  if body == "false" or body == "False" or body == "FALSE" then return "bool", false end
  -- a whole number, written 2 or +2, or as a decimal that is whole (2.0, 3.): R's whole() takes both
  local digits = body:match("^%+?([0-9]+)$")
  if not digits then
    local ip, fp = body:match("^%+?([0-9]+)%.([0-9]*)$")
    if ip and not fp:find("[1-9]") then digits = ip end
  end
  if digits then return "int", math.tointeger(tonumber(digits)) or tonumber(digits), digits end
  return "bare", body
end

-- ---- flow mappings ({k: v, k2: v2}) ----------------------------------------------------------------

-- the index just past a quoted scalar that starts at i, or nil when it never closes
local function skip_quoted(text, i)
  local q = text:sub(i, i)
  local j = i + 1
  while j <= #text do
    local c = text:sub(j, j)
    if q == '"' and c == "\\" then j = j + 2
    elseif c == q then
      if q == "'" and text:sub(j + 1, j + 1) == "'" then j = j + 2 else return j + 1 end
    else j = j + 1 end
  end
  return nil
end

-- true when the braces of a text that starts a flow mapping are all closed (quotes respected)
local function flow_closed(text)
  local depth, i = 0, 1
  while i <= #text do
    local c = text:sub(i, i)
    if (c == '"' or c == "'") and (i == 1 or text:sub(i - 1, i - 1):find("^[ \t\r\n{%[,:]")) then
      i = skip_quoted(text, i)
      if not i then return false end
    else
      if c == "{" or c == "[" then depth = depth + 1
      elseif c == "}" or c == "]" then
        depth = depth - 1
        if depth == 0 then return true end
      end
      i = i + 1
    end
  end
  return false
end

-- A flow mapping `{k: v, ...}` (a trailing `# comment` after the closing brace is allowed) as an array of
-- {key = <text>, value = <raw text of the value>}, or nil when it is not one this reader reads.
local function parse_flow(text)
  text = trim(text)
  if text:sub(1, 1) ~= "{" then return nil end
  local n, i = #text, 2
  local found = {}
  local function skip_ws() while i <= n and text:sub(i, i):find("^[ \t\r\n]") do i = i + 1 end end
  skip_ws()
  if text:sub(i, i) ~= "}" then
    while true do
      skip_ws()
      local key
      local c = text:sub(i, i)
      if c == '"' or c == "'" then
        local j = skip_quoted(text, i)
        if not j then return nil end
        local kind, v = scalar(text:sub(i, j - 1))
        if kind ~= "str" then return nil end
        key, i = v, j
        skip_ws()
        if text:sub(i, i) ~= ":" then return nil end
        i = i + 1
      else
        local j = text:find(":", i, true)
        if not j then return nil end
        key = trim(text:sub(i, j - 1))
        if key == "" or key:find("[,{}%[%]]") then return nil end
        i = j + 1
      end
      -- the value: up to a comma or the closing brace outside any nesting and quotes
      skip_ws()
      local start, depth = i, 0
      local c0 = text:sub(i, i)
      if c0 == '"' or c0 == "'" then
        local j = skip_quoted(text, i)
        if not j then return nil end
        i = j
      end
      while i <= n do
        local ch = text:sub(i, i)
        if (ch == '"' or ch == "'") and depth > 0 and text:sub(i - 1, i - 1):find("^[ \t\r\n{%[,:]") then
          local j = skip_quoted(text, i)
          if not j then return nil end
          i = j
        elseif ch == "{" or ch == "[" then depth = depth + 1; i = i + 1
        elseif ch == "}" or ch == "]" then
          if depth == 0 then break end
          depth = depth - 1; i = i + 1
        elseif ch == "," and depth == 0 then break
        else i = i + 1 end
      end
      if i > n then return nil end
      found[#found + 1] = { key = key, value = trim(text:sub(start, i - 1)) }
      if text:sub(i, i) == "," then
        i = i + 1
        skip_ws()
        if text:sub(i, i) == "}" then break end   -- a trailing comma
      else
        break
      end
    end
  end
  if text:sub(i, i) ~= "}" then return nil end
  local after = text:sub(i + 1)
  if not (after:find("^[ \t\r\n]*$") or after:find("^[ \t\r\n]+#")) then return nil end
  return found
end

-- the flow mapping that starts at line `from` (its first text being `first`), read over as many lines as
-- it takes to close it: its text and the index of its last line
local function gather_flow(lines, from, first)
  local text, last = trim(first), from
  while not flow_closed(text) and last < #lines do
    last = last + 1
    text = text .. "\n" .. lines[last]
  end
  return text, last
end

local function one_line(text) return trim((text:gsub("[ \t\r\n]+", " "))) end

-- the names (no dot) of a `formatters:` mapping written in flow style, into `formatters`; a problem when
-- the value is not a mapping
local function formatters_flow(value, formatters, problems, file)
  local items = parse_flow(value)
  if not items then
    problems[#problems + 1] = { file = file, key = "formatters", value = one_line(value), what = "mapping" }
    return
  end
  for _, it in ipairs(items) do formatters[(it.key:gsub("^%.", ""))] = true end
end

local function is_null_text(rest)
  local body = trim((rest:gsub("[ \t\r\n]+#.*$", "")))
  return body == "" or body == "~" or body == "null" or body == "Null" or body == "NULL" or body:sub(1, 1) == "#"
end

local function apply(cfg, problems, file, key, rest)
  if key == "formatters" then
    -- the block form is read by read_formatters(); a value on the key's own line is flow, or nothing
    if not is_null_text(rest) then formatters_flow(rest, cfg.formatters, problems, file) end
    return
  end
  local want = KINDS[key]
  if not want then return end
  local kind, v = scalar(rest)
  local ok = false
  if want == "pdig" then
    -- p_digits: a whole number from 1 to 6, or null (the default, so nil)
    if kind == "bare" and (v == "null" or v == "Null" or v == "NULL" or v == "~") then
      cfg[key] = nil
      return
    end
    ok = kind == "int" and v >= 1 and v <= 6
  elseif want == "sev" then
    ok = kind == "bare" and (v == "fail" or v == "warn" or v == "off")
  elseif want == "claims" then
    ok = (kind == "bare" or kind == "str") and (v == "stop" or v == "collect")
  elseif want == "int" then ok = kind == "int"
  elseif want == "bool" then ok = kind == "bool"
  else ok = kind == "str" or kind == "bare" or kind == "int" or kind == "bool" end
  if ok and want == "str" and (kind == "int" or kind == "bool") then
    v = trim((rest:gsub("[ \t\r\n]+#.*$", "")))
  end
  if not ok then
    problems[#problems + 1] = { file = file, key = key, value = trim((rest:gsub("[ \t\r\n]+#.*$", ""))), what = WHAT[want] }
    -- a wrong value in a later source gives the default, not an earlier source's value (E33)
    if want == "pdig" or want == "sev" or want == "claims" then cfg[key] = M.DEFAULTS[key] end
  else
    cfg[key] = v
  end
end

-- the lines of a block at exactly `indent`: calls set(key, rest_of_line) for each `KEY: VALUE`
-- line; deeper lines (the nested keys of other settings) are skipped. A value that opens a flow mapping
-- is read over its following lines until it closes.
local function read_block(lines, indent, set)
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local ind, key, rest = line:match("^([ \t\r\n]*)([%w_%.%-]+):(.*)$")
    if ind and #ind == indent then
      if trim(rest):sub(1, 1) == "{" then
        local text, last = gather_flow(lines, i, rest)
        set(key, text)
        i = last
      else
        set(key, rest)
      end
    end
    i = i + 1
  end
end

-- the `weft:` mapping of the front matter: nil when there is none, else
--   { kind = "block", lines = {...}, indent = n }   its lines, and the indent they are read at
--   { kind = "flow", text = "{...}" }               a flow mapping
--   { kind = "bad", text = <value> }                a value that is not a mapping
local function blank(l) return l:match("^[ \t\r\n]*$") ~= nil end

-- Do the lines of a candidate block read as a YAML mapping: the first line that is not blank and not a
-- comment is `key:` or opens a flow mapping (no YAML parser here; plain text or a list is what it has to
-- tell apart).
local function is_mapping(inner)
  for _, l in ipairs(inner) do
    local t = trim(l)
    if t ~= "" and t:sub(1, 1) ~= "#" then
      return l:match("^[A-Za-z_\"'][^:]*:[ \t\r]") ~= nil or l:match("^[A-Za-z_\"'][^:]*:$") ~= nil
        or t:sub(1, 1) == "{"
    end
  end
  return false
end

-- The inner lines of each metadata block of a document, in order (the rule in the note at the top); each
-- array's field `open` is the line number of its opening `---`.
local function metadata_blocks(lines)
  local out, n, k = {}, #lines, 1
  while k <= n do
    local l = lines[k]
    local mark = l:match("^[ \t>]*(```+)") or l:match("^[ \t>]*(~~~+)")
    local lead = l:match("^( *)<!%-%-")
    if mark then
      local c, j = mark:sub(1, 1), k + 1
      while j <= n do
        local m = lines[j]:match("^[ \t>]*(" .. c .. "+)[ \t\r]*$")
        if m and #m >= #mark then break end
        j = j + 1
      end
      k = j + 1
    elseif lead and #lead <= 3 then
      -- the comment ends at the first `-->` after its `<!--`; one that never ends hides nothing
      local at = l:find("<!--", 1, true)
      local stop
      if l:find("-->", at + 4, true) then stop = k
      else
        for j = k + 1, n do
          if lines[j]:find("-->", 1, true) then stop = j; break end
        end
      end
      k = (stop or k) + 1
    else
      local opened = false
      if l:match("^%-%-%-[ \t\r]*$") and (k == 1 or blank(lines[k - 1])) and k < n and not blank(lines[k + 1]) then
        local j = k + 1
        while j <= n and not (lines[j]:match("^%-%-%-[ \t\r]*$") or lines[j]:match("^%.%.%.[ \t\r]*$")) do
          j = j + 1
        end
        if j <= n then
          local inner = { open = k }
          for q = k + 1, j - 1 do inner[#inner + 1] = lines[q] end
          if is_mapping(inner) then
            out[#out + 1] = inner
            k = j + 1
            opened = true
          end
        end
      end
      if not opened then k = k + 1 end
    end
  end
  return out
end

local function front_matter_weft(lines)
  local fm
  for _, b in ipairs(metadata_blocks(lines)) do
    for _, l in ipairs(b) do
      if l:match("^weft[ \t]*:") then fm = b; break end
    end
  end
  if not fm then return nil end
  local out, inside = {}, false
  local i = 1
  while i <= #fm do
    local l = fm[i]
    local rest = (not inside) and l:match("^weft[ \t]*:(.*)$") or nil
    if rest ~= nil then
      local body = trim(rest)
      if body == "" or body:sub(1, 1) == "#" then
        inside = true
      elseif body:sub(1, 1) == "{" then
        local t = gather_flow(fm, i, rest)
        return { kind = "flow", text = t }
      elseif is_null_text(rest) then
        return { kind = "block", lines = {}, indent = 0 }
      else
        return { kind = "bad", text = trim((rest:gsub("[ \t\r\n]+#.*$", ""))) }
      end
    elseif inside then
      if l:match("^[ \t\r\n]*$") or l:match("^[ \t\r\n]*#") then
        -- skip
      elseif l:match("^[ \t\r\n]") then out[#out + 1] = l
      else inside = false end
    end
    i = i + 1
  end
  if #out == 0 then return { kind = "block", lines = {}, indent = 0 } end
  -- the first indent level found is the one read
  local ind = #out[1]:match("^([ \t\r\n]*)")
  for _, l in ipairs(out) do
    local n = #l:match("^([ \t\r\n]*)")
    if n < ind then ind = n end
  end
  return { kind = "block", lines = out, indent = ind }
end

local function lines_of(text)
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = l end
  return lines
end

-- the block form of `formatters:` (a key with nothing on its own line, and the keys under it)
local function read_formatters(lines, indent, formatters)
  local on = false
  local first
  for _, l in ipairs(lines) do
    local ind, key = l:match("^([ \t\r\n]*)([^ \t\r\n:#][^:]*):")
    if l:match("^[ \t\r\n]*$") or l:match("^[ \t\r\n]*#") then
      -- skip
    elseif #(l:match("^([ \t\r\n]*)")) == indent and l:match("^[ \t\r\n]*formatters:") then
      on = is_null_text((l:match("^[ \t\r\n]*formatters:(.*)$")))
      first = nil
    elseif on then
      local n = #(l:match("^([ \t\r\n]*)"))
      if n <= indent then on = false
      elseif ind and (first == nil or n == first) then
        first = n
        formatters[(key:gsub("^%.", ""))] = true
      end
    end
  end
end

function M.read_text(text, indent, file, cfg, problems)
  local lines = lines_of(text)
  read_block(lines, indent, function(key, rest) apply(cfg, problems, file, key, rest) end)
  read_formatters(lines, indent, cfg.formatters)
end

-- a `weft:` mapping in flow style: each pair as the block form reads it
local function read_flow_weft(text, file, cfg, problems)
  local items = parse_flow(text)
  if not items then
    problems[#problems + 1] = { file = file, key = "weft", value = one_line(text), what = "mapping" }
    return
  end
  for _, it in ipairs(items) do apply(cfg, problems, file, it.key, it.value) end
end

local function dir_of(path)
  return (path:gsub("[/\\]+[^/\\]*$", ""))
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end
M.read_file = read_file

-- find a file by name in a folder or a parent of it (the folder and 8 parents)
function M.find_upward(start_dir, rel)
  local cur = start_dir
  for _ = 1, 9 do
    local p = cur .. "/" .. rel
    local f = io.open(p, "r")
    if f then f:close(); return p end
    local parent = dir_of(cur)
    if parent == cur or parent == "" then break end
    cur = parent
  end
  return nil
end

-- The lines of a source its front matter is read from (rules P4 and P5 of 2.1.6): with every include
-- expanded, when it has one and its folder is known; else its own lines. A failed expansion gives its own.
local function front_lines(path, text, own)
  if not path or not text:find("{{< ", 1, true) then return own end
  local main_dir = dir_of(path)
  if main_dir == path then main_dir = "." end
  local q = M.find_upward(main_dir, "_quarto.yml") or M.find_upward(main_dir, "_quarto.yaml")
  local root = q and dir_of(q) or main_dir
  local ok, out = pcall(function()
    lines_lib = lines_lib or dofile(HERE .. "/lines.lua")
    return lines_lib.expanded_lines(path, text, main_dir, root)
  end)
  return ok and out or own
end

-- The lines of a notebook's JSON text its front matter is read from (rule P7 of 2.1.6; the twin of R's
-- notebook_view() in R/notebook.R): the source of each raw and markdown cell, in cell order, each followed
-- by a blank line. Code cells hold none. Nothing when the JSON cannot be read (pandoc.json decodes it).
local function notebook_lines(text)
  if not (pandoc and pandoc.json and pandoc.json.decode) then return {} end
  local ok, nb = pcall(pandoc.json.decode, text, false)
  if not ok or type(nb) ~= "table" or type(nb.cells) ~= "table" then return {} end
  local out = {}
  for _, cell in ipairs(nb.cells) do
    if type(cell) == "table" and (cell.cell_type == "markdown" or cell.cell_type == "raw") then
      local src = cell.source
      local s = ""
      if type(src) == "string" then
        s = src
      elseif type(src) == "table" then
        local parts = {}
        for _, p in ipairs(src) do
          if type(p) == "string" then parts[#parts + 1] = p end
        end
        s = table.concat(parts)
      end
      if s ~= "" then
        if s:sub(-1) == "\n" then s = s:sub(1, -2) end
        for l in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = l end
      end
      out[#out + 1] = ""
    end
  end
  return out
end

-- A percent script's `# %%` cell header: its kind ("markdown", "raw" or "code") and the rest of the line,
-- as Quarto's percentCellHeader() reads it; nil for a line that is none. `strict` asks for the form that
-- makes a `.py` a percent script: white space, then `[markdown]` or `[raw]`.
local function percent_header(l, strict)
  local rest = l:match("^%s*#%s*%%%%+(.*)$")
  if not rest then return nil end
  local kind, attrs = rest:match("^%s*%[(%a+)%](.*)$")
  if strict then
    local k = rest:match("^%s+%[(%a+)%]")
    return (k == "markdown" or k == "raw") and k or nil
  end
  if kind == "markdown" or kind == "raw" then return kind, attrs end
  return "code", rest
end

-- The lines of a percent script's text its front matter is read from (rule P7; the twin of R's
-- percent_view()): each markdown and raw cell, its empty lines at either end dropped, its lines with the
-- leading `#` and one white-space character off (or the lines inside its `"""` lines), then a blank line.
-- A raw cell that names a format is raw output, fenced; code cells, and the text above the first `# %%`
-- line, are left out. A script with no markdown or raw cell is no Quarto document: nothing.
local function percent_lines(text)
  local all = lines_of((text:gsub("^%s+", ""):gsub("%s+$", "")))
  local script = false
  for _, l in ipairs(all) do
    if percent_header(l, true) then script = true; break end
  end
  if not script then return {} end
  local cells = {}
  for _, l in ipairs(all) do
    local kind, attrs = percent_header(l)
    if kind then cells[#cells + 1] = { kind = kind, attrs = attrs or "", lines = {} }
    elseif #cells > 0 then table.insert(cells[#cells].lines, l) end
  end
  local out = {}
  for _, c in ipairs(cells) do
    if c.kind ~= "code" then
      local a, b = 1, #c.lines
      while a <= b and blank(c.lines[a]) do a = a + 1 end
      while b >= a and blank(c.lines[b]) do b = b - 1 end
      local body = {}
      local tq = "^\"\"\"+%s*$"
      if b - a + 1 > 2 and c.lines[a]:match(tq) and c.lines[b]:match(tq) then
        for q = a + 1, b - 1 do body[#body + 1] = c.lines[q] end
      else
        for q = a, b do body[#body + 1] = (c.lines[q]:gsub("^#%s?", "")) end
      end
      local fenced = c.kind == "raw" and (c.attrs:match("format=") or c.attrs:match("raw_mimetype="))
      if fenced then out[#out + 1] = "```{=raw}" end
      for _, l in ipairs(body) do out[#out + 1] = l end
      if fenced then out[#out + 1] = "```" end
      out[#out + 1] = ""
    end
  end
  return out
end

-- The lines of a source its `weft:` front matter is read from: a notebook's or a percent script's cells
-- (rule P7), else its lines with its includes expanded (front_lines()).
local function jupyter_lines(path, text)
  local low = path and path:lower() or ""
  if low:match("%.ipynb$") then return notebook_lines(text) end
  if low:match("%.py$") then return percent_lines(text) end
  return nil
end

-- Is the source a document the knitr hooks resolve (N14, N92)? The rule of R/scan-contexts.R:
-- filter_resolves(): an .Rmd is knitr's; a .qmd with `engine: knitr`, or with an executed {r} chunk and no
-- `engine:` or `jupyter:` key; and the intermediate `.knit.md` of rmarkdown. `engine:` and `jupyter:` are
-- read from the front block alone, as Quarto reads them (rule 2.1.6): the first metadata block, when only
-- blank lines stand above it, in the include-expanded text, so an include on line 1 can supply it (P4); the
-- chunks are read from that text too.
function M.source_is_knitr(path, text)
  if not path then return false end
  local low = path:lower()
  if low:match("%.rmd$") or low:match("%.rmarkdown$") or low:match("%.knit%.md$") then return true end
  if not low:match("%.qmd$") or not text then return false end
  local lines = lines_of(text)
  local flines = front_lines(path, text, lines)
  local fm = metadata_blocks(flines)[1]
  if fm then
    for q = 1, fm.open - 1 do
      if not blank(flines[q]) then fm = nil; break end
    end
  end
  if fm then
    for _, l in ipairs(fm) do
      local v = l:match("^engine[ \t\r\n]*:(.*)$")
      if v then
        v = v:gsub("[ \t\r\n]+#.*$", ""):gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")
        v = v:gsub("^[\"']", ""):gsub("[\"']$", "")
        return v:lower() == "knitr"
      end
    end
    for _, l in ipairs(fm) do
      if l:match("^jupyter[ \t\r\n]*:") then return false end
    end
  end
  for i, l in ipairs(flines) do
    if l:match("^[ \t>]*```+[ \t]*{[ \t]*[rR][ \t,}]") then
      local off = l:match("[ ,{]eval[ \t]*=[ \t]*FALSE[ \t]*[,}]") or l:match("[ ,{]eval[ \t]*=[ \t]*F[ \t]*[,}]")
      local j = i + 1
      while not off and flines[j] and flines[j]:match("^[ \t>]*#|") do
        local v = flines[j]:match("^[ \t>]*#|[ ]?eval[ \t]*:[ \t]*(%a+)[ \t]*$")
                  or flines[j]:match("^[ \t>]*#|[ ]?eval[ \t]*:[ \t]*(%a+)[ \t]*#.*$")
        if v == "false" or v == "no" or v == "FALSE" then off = true end
        j = j + 1
      end
      if not off then return true end
    end
  end
  return false
end

-- source_path: the document's path, or nil; source_text: its text, or nil; cwd: the working folder
function M.load(source_path, source_text, cwd)
  local cfg = {}
  for k, v in pairs(M.DEFAULTS) do cfg[k] = v end
  cfg.formatters = {}
  local problems = {}
  local function display(p)
    if cwd and p:sub(1, #cwd + 1) == cwd .. "/" then return p:sub(#cwd + 2) end
    return (p:gsub("^%./", ""))
  end
  local start = cwd or "."
  if source_path then
    local d = dir_of(source_path)
    if d == source_path then d = "." end
    if d:sub(1, 1) == "/" or d:match("^%a:[/\\]") or not cwd then start = d
    else start = (cwd .. "/" .. d):gsub("/%./", "/"):gsub("/%.$", "") end
  end
  local yml = M.find_upward(start, "_weft.yml")
  if yml then
    local text = read_file(yml)
    if text then M.read_text(text, 0, display(yml), cfg, problems) end
  end
  if source_text then
    local fm = front_matter_weft(jupyter_lines(source_path, source_text)
                                 or front_lines(source_path, source_text, lines_of(source_text)))
    local file = source_path and display(source_path) or "the document"
    if fm then
      if fm.kind == "flow" then
        read_flow_weft(fm.text, file, cfg, problems)
      elseif fm.kind == "bad" then
        problems[#problems + 1] = { file = file, key = "weft", value = fm.text, what = "mapping" }
      elseif #fm.lines > 0 then
        M.read_text(table.concat(fm.lines, "\n"), fm.indent, file, cfg, problems)
      end
    end
  end
  return cfg, problems
end

return M
