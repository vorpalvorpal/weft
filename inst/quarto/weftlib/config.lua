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

-- ---- the one fence finder (A18), the twin of R/fences.R -----------------------------------------------
-- The metadata blocks are found as R's doc_fences() finds them (the A18 ruling and its amendments of 27
-- Nov): first the executable chunks over the whole text, as knitr finds them (knitr_chunks()); then, in the
-- text outside them, the plain fences as Pandoc's markdown reader reads them, the HTML comments that hide
-- them, and the metadata blocks (plain_pass()).

-- A knitr chunk header (knitr 1.51 `chunk.begin`: ^[\t >]*```+\s*\{([a-zA-Z0-9_]+( *[ ,].*)?)\}\s*$).
local function knitr_begin(l)
  local inner = l:match("^[\t >]*```+%s*{(.*)}%s*$")
  if not inner then return false end
  return inner:match("^[A-Za-z0-9_]+$") ~= nil or inner:match("^[A-Za-z0-9_]+ *[ ,]") ~= nil
end

-- the opener's prefix an exact closer repeats, and whether `l` is that closer
local function chunk_prefix(l) return l:match("^([\t >]*`+)") end
local function exact_end(l, p) return l:sub(1, #p) == p and l:sub(#p + 1):match("^%s*$") ~= nil end

-- The chunks of `lines` as knitr divides a document (R's knitr_chunks()): an array of {open, close}.
local function knitr_chunks(lines)
  local n = #lines
  local cand, isb = {}, {}
  for i = 1, n do
    local l = lines[i]
    if l:find("```", 1, true) then
      local b = knitr_begin(l)
      if b or l:match("^[\t >]*```+%s*$") then
        cand[#cand + 1] = i
        isb[#cand] = b
      end
    end
  end
  local out = {}
  -- is the end line cand[t] (not exact) code, because knitr reads on to a later exact closer?
  local function reads_on(t, p)
    local i, e = cand[t], nil
    for s = t + 1, #cand do
      if not isb[s] and exact_end(lines[cand[s]], p) then e = cand[s]; break end
    end
    if not e then return false end
    for q = i + 1, e - 1 do
      local b = lines[q]
      if b:sub(1, #p) == p and b:sub(#p + 1):match("^`*{") then return false end
    end
    return true
  end
  local cur, p
  for t = 1, #cand do
    local i = cand[t]
    local l = lines[i]
    if not cur then
      if isb[t] then
        cur = i
        p = (i ~= 1) and chunk_prefix(l) or nil
      end
    elseif isb[t] then
      if p == nil or l:sub(1, #p + 1) == p .. "{" then
        out[#out + 1] = { cur, i - 1 }
        cur = i
      end
    elseif not (p ~= nil and not exact_end(l, p) and reads_on(t, p)) then
      out[#out + 1] = { cur, i }
      cur = nil
    end
  end
  if cur then out[#out + 1] = { cur, n } end
  return out
end

-- `l` with the tabs of its leading white space and `>` markers expanded to the next stop of 4
local function expand_tabs(l)
  if not l:match("^[ >]*\t") then return l end
  local lead = l:match("^[ \t>]*")
  local out, col = {}, 0
  for c in lead:gmatch(".") do
    if c == "\t" then
      local w = 4 - col % 4
      out[#out + 1] = string.rep(" ", w)
      col = col + w
    else
      out[#out + 1] = c
      col = col + 1
    end
  end
  return table.concat(out) .. l:sub(#lead + 1)
end

-- the block-quote markers at `i` of `l` (` {0,3}` before, then `> ?`, then up to 3 spaces before another
-- `>`): their number and the position after them
local function quote_markers(l, i)
  local depth = 0
  while l:sub(i, i) == ">" do
    depth = depth + 1
    i = i + 1
    if l:sub(i, i) == " " then i = i + 1 end
    local j, c = i, 0
    while c < 3 and l:sub(j, j) == " " do j = j + 1; c = c + 1 end
    if l:sub(j, j) == ">" then i = j end
  end
  return depth, i
end

local function lead_spaces(l, max)
  local s = #l:match("^ *")
  return (max and s > max) and max or s
end

-- A fence line read as R's parse_fence_lines() reads it: depth, indent, fence character, run length and info;
-- nil when it is no fence line.
local function parse_fence(l)
  l = expand_tabs(l)
  local n1 = lead_spaces(l, 3)
  local depth, i = quote_markers(l, n1 + 1)
  local s3 = #l:match("^ *", i)
  i = i + s3
  local run = l:match("^```+", i) or l:match("^~~~+", i)
  if not run then return nil end
  return { depth = depth, indent = (depth > 0) and s3 or (n1 + s3), fch = run:sub(1, 1), flen = #run,
           info = l:sub(i + #run) }
end

local function quote_depth(l)
  local d = quote_markers(l, lead_spaces(l, 3) + 1)
  return d
end
local function lead_width(l) return #expand_tabs(l):match("^ *") end

-- a quoted string at `i` of `s` (quote `q`, backslash escapes): the position after it, or nil
local function quoted_end(s, i, q)
  if s:sub(i, i) ~= q then return nil end
  i = i + 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then i = i + 2
    elseif c == q then return i + 1
    else i = i + 1 end
  end
  return nil
end

-- a Pandoc attribute block at `i` of `s` (`{#id .class key=value -}`): the position after it, or nil
local function attr_end(s, i)
  if s:sub(i, i) ~= "{" then return nil end
  i = i + 1 + #s:match("^[ \t]*", i + 1)
  while true do
    if s:sub(i, i) == "}" then return i + 1 end
    local e
    local m = s:match("^#[A-Za-z0-9_:.%-]+", i) or s:match("^%.[A-Za-z][A-Za-z0-9_:.%-]*", i)
      or (s:sub(i, i) == "-" and "-" or nil)
    if m then
      e = i + #m
    else
      local k = s:match("^[A-Za-z][A-Za-z0-9_:.%-]*=", i)
      if not k then return nil end
      local v = i + #k
      e = quoted_end(s, v, "\"") or quoted_end(s, v, "'")
      if not e then
        local u = s:match("^[^ \t}]+", v)
        if not u then return nil end
        e = v + #u
      end
    end
    i = e + #s:match("^[ \t]*", e)
  end
end

-- Does an info string (trimmed) open a fence for Pandoc's markdown reader (R's pandoc_fence_info()): none,
-- one word, an attribute block or both, or a raw attribute; with `any_brace`, any braced text too.
local function fence_info_ok(x, any_brace)
  if any_brace and x:match("^{.*}$") then return true end
  if x:match("^{[ \t]*=[A-Za-z0-9_%-]+[ \t]*}$") then return true end
  local i = 1 + #x:match("^[^ \t{`]*")
  i = i + #x:match("^[ \t]*", i)
  if i > #x then return true end
  local e = attr_end(x, i)
  return e ~= nil and e > #x
end

-- the content column of a list item line, and the item's own indent; nil when the line is no item
local function item_col(l)
  local sp, mk = l:match("^( *)([%-+*])")
  if not sp then
    sp, mk = l:match("^( *)(%d+[.)])")
    if mk and #mk > 10 then mk = nil end
  end
  if not mk then return nil end
  local rest = l:sub(#sp + #mk + 1)
  local gap = rest:match("^( +)%S")
  if gap and #gap <= 4 then return #sp + #mk + #gap, #sp end
  if rest:match("^[ \t]*$") then return #sp + #mk + 1, #sp end
  return nil
end

-- the content column of the list item a line `k` indented `ind` (4 or more) sits in, or nil (R's
-- list_item_col())
local function list_item_col(lines, k, ind)
  local j = k - 1
  while j >= 1 do
    if not blank(lines[j]) then
      local l = expand_tabs(lines[j])
      local c0, own = item_col(l)
      if c0 then
        if ind >= c0 and ind <= c0 + 3 then return c0 end
        if own == 0 then return nil end
      elseif #l:match("^ *") == 0 and (j == 1 or blank(lines[j - 1])) then
        return nil
      end
    end
    j = j - 1
  end
  return nil
end

-- The plain fences and the metadata blocks of `lines` outside the chunks (`inchunk`, a set of line numbers),
-- as R's plain_blocks() reads them: `fences`, an array of {open, close}; `blocks`, the inner lines of each
-- metadata block, its field `open` the line of its opening `---`.
local function plain_pass(lines, inchunk, any_brace)
  local n = #lines
  local pf, fi, at = {}, {}, {}
  for j = 1, n do
    local l = lines[j]
    if not inchunk[j] and (l:match("^[ \t>]*```") or l:match("^[ \t>]*~~~")) then
      fi[#fi + 1] = j
      at[j] = #fi
      pf[j] = parse_fence(l) or false
    end
  end
  local function closes(j, r, d, c0)
    local q = pf[j]
    return q and q.fch == r.fch and q.flen >= r.flen and q.depth == d and q.info:match("^[ \t\r]*$") ~= nil
      and q.indent >= c0 and q.indent <= c0 + 3
  end
  -- the closer of the fence opened on `k`, or nil: a fence that does not close in its container is no fence
  local function fence_close(k, r, c0)
    if r.depth == 0 and c0 == 0 then
      for s = at[k] + 1, #fi do
        if closes(fi[s], r, 0, 0) then return fi[s] end
      end
      return nil
    end
    for j = k + 1, n do
      if not inchunk[j] then
        local l = lines[j]
        if r.depth > 0 and quote_depth(l) < r.depth then return nil end
        if c0 > 0 and not blank(l) and lead_width(l) < c0 then return nil end
        if pf[j] and closes(j, r, r.depth, c0) then return j end
      end
    end
    return nil
  end
  local fences, blocks, closers = {}, {}, {}
  local k = 1
  while k <= n do
    local l = lines[k]
    local nextk = k + 1
    if inchunk[k] then
      -- a chunk's line
    elseif pf[k] ~= nil then
      local r = pf[k]
      if r and fence_info_ok(trim(r.info), any_brace) then
        local c0 = 0
        if r.indent > 3 then
          if r.depth > 0 then c0 = nil
          -- no blank line (or a block's end) above: the line goes on the paragraph above
          elseif k > 1 and not blank(lines[k - 1]) and not inchunk[k - 1] and not closers[k - 1] then c0 = nil
          else c0 = list_item_col(lines, k, r.indent) end
        end
        local c = c0 and fence_close(k, r, c0)
        if c then
          fences[#fences + 1] = { k, c }
          closers[c] = true
          nextk = c + 1
        end
      end
    elseif #(l:match("^( *)<!%-%-") or "    ") <= 3 then
      -- the comment ends at the first `-->` after its `<!--`; one that never ends hides nothing
      local at4 = l:find("<!--", 1, true)
      local stop
      if l:find("-->", at4 + 4, true) then stop = k
      else
        for j = k + 1, n do
          if not inchunk[j] and lines[j]:find("-->", 1, true) then stop = j; break end
        end
      end
      if stop then nextk = stop + 1 end
    elseif l:match("^%-%-%-[ \t\r]*$") and (k == 1 or blank(lines[k - 1])) and k < n and not blank(lines[k + 1]) then
      local j = k + 1
      while j <= n and not (lines[j]:match("^%-%-%-[ \t\r]*$") or lines[j]:match("^%.%.%.[ \t\r]*$")) do
        j = j + 1
      end
      if j <= n then
        local inner = { open = k }
        for q = k + 1, j - 1 do inner[#inner + 1] = lines[q] end
        if is_mapping(inner) then
          blocks[#blocks + 1] = inner
          nextk = j + 1
        end
      end
    end
    k = nextk
  end
  return { fences = fences, blocks = blocks }
end

-- The inner lines of each metadata block of a document, in order (the rule in the note at the top); each
-- array's field `open` is the line number of its opening `---`.
local function metadata_blocks(lines)
  local inchunk = {}
  for _, c in ipairs(knitr_chunks(lines)) do
    for q = c[1], c[2] do inchunk[q] = true end
  end
  return plain_pass(lines, inchunk, false).blocks
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

-- ---- the engine Quarto runs a document on (the twin of R's quarto_engine_choice()) --------------------------
-- Quarto 1.11.9's markdownExecutionEngine(): a project's `engines:` list first, then julia, knitr, jupyter,
-- markdown. The front block's keys come first: the first engine of that order that a truthy top-level key of
-- its name claims, or that `engine:` or `execute: engine:` names. Only then the chunk languages.
local QUARTO_ENGINES = { "julia", "knitr", "jupyter", "markdown" }
local HANDLER_LANGS = { mermaid = true, dot = true, ojs = true }

-- the language of a chunk header as Quarto reads it for the engine (languagesWithClasses()), lower-cased
local function quarto_lang(l)
  local inner = l:match("^[\t >]*```+%s*{([^}]*)}%s*$")
  local lang = inner and inner:match("^([A-Za-z][A-Za-z0-9_.]*)")
  return lang and lang:lower()
end

-- the backticks of a cell start (breakQuartoMd()), or nil
local function quarto_cell_ticks(l)
  local ticks, inner = l:match("^%s*(```+)%s*{(.*)}%s*$")
  if not ticks then return nil end
  if inner:match("^[=A-Za-z][=A-Za-z0-9._]*$") or inner:match("^[=A-Za-z][=A-Za-z0-9._]* *[ ,]") then
    return #ticks
  end
  return nil
end

-- the header line of the cell breakQuartoMd() leaves open at the end, or nil (R's quarto_unclosed_cell())
local function quarto_unclosed_cell(lines)
  local n = #lines
  local in_yaml, in_cell, in_code = false, nil, 0
  for i = 1, n do
    local l = lines[i]
    local hr = l:match("^%-%-%-%s*$") ~= nil
    if hr or l:match("^%s*```") then
      local cell = quarto_cell_ticks(l)
      local endt = l:match("^%s*(```+)%s*$")
      if hr and not in_cell and in_code == 0
         and (in_yaml or not (i > 1 and blank(lines[i - 1]) and (i < n and blank(lines[i + 1])))) then
        in_yaml = not in_yaml
      elseif not in_yaml and not in_cell and in_code == 0 and cell then
        in_cell, in_code = i, cell
      elseif in_code > 0 and endt and #endt == in_code then
        in_cell, in_code = nil, 0
      elseif in_code == 0 and l:sub(1, 3) == "```" then
        local word = l:match("^[^ ]*")
        local _, c = word:gsub("`", "")
        in_code = c
      end
    end
  end
  return in_cell
end

-- the lines inside a plain fence read over the whole text, chunk headers taken as fences (R's fenced_lines())
local function fenced_lines(lines)
  local out = {}
  for _, f in ipairs(plain_pass(lines, {}, true).fences) do
    for q = f[1] + 1, f[2] do out[q] = true end
  end
  return out
end

-- the chunk headers Quarto reads the languages from: an array of {line, lang} (R's quarto_chunk_headers())
local function quarto_chunk_headers(lines)
  local out = {}
  local fenced, open
  for i, l in ipairs(lines) do
    local lang = l:find("```", 1, true) and quarto_lang(l)
    if lang then
      if not fenced then
        fenced = fenced_lines(lines)
        open = quarto_unclosed_cell(lines)
      end
      if not fenced[i] and i ~= open then out[#out + 1] = { line = i, lang = lang } end
    end
  end
  return out
end

-- a one-line YAML scalar's text: no trailing comment, no quotes
local function scalar_text(v)
  v = trim((v:gsub("^#.*$", ""):gsub("[ \t]#.*$", "")))
  return (v:gsub("^[\"']", ""):gsub("[\"']$", ""))
end

-- the engine the front block's lines `fm` claim, in the order `order`, or nil (R's front_engine_claim())
local function front_engine_claim(fm, order)
  local top = {}
  for i, l in ipairs(fm) do
    local k = l:match("^([A-Za-z_][A-Za-z0-9_.%-]*)[ \t]*:")
    if k then top[#top + 1] = { i = i, key = k, rest = l:sub(#l:match("^[^:]*:") + 1) } end
  end
  local function under(t)
    local to = top[t + 1] and top[t + 1].i - 1 or #fm
    local b = {}
    for q = top[t].i + 1, to do
      if not blank(fm[q]) and not fm[q]:match("^[ \t]*#") then b[#b + 1] = fm[q] end
    end
    return b
  end
  local falsy = { ["false"] = true, False = true, FALSE = true, null = true, Null = true, NULL = true,
                  ["~"] = true, ["0"] = true, ['""'] = true, ["''"] = true }
  local function truthy(t)
    local raw = trim((top[t].rest:gsub("^#.*$", ""):gsub("[ \t]#.*$", "")))
    if raw == "" then return #under(t) > 0 end
    return not falsy[raw]
  end
  local exec
  for t, e in ipairs(top) do
    if e.key == "engine" then
      local v = scalar_text(e.rest)
      if v == "" then
        local b = under(t)
        v = b[1] and (b[1]:match("^[ \t]*([A-Za-z]+)") or "") or ""
      end
      exec = v:lower()
    elseif e.key == "execute" then
      local b = under(t)
      if b[1] then
        local ind = #b[1]:match("^[ \t]*")
        for _, l in ipairs(b) do
          if #l:match("^[ \t]*") == ind and l:match("^[ \t]*engine[ \t]*:") then
            exec = scalar_text(l:gsub("^[^:]*:", "", 1)):lower()
            break
          end
        end
      end
    end
  end
  for _, name in ipairs(order) do
    local last
    for t, e in ipairs(top) do
      if e.key == name then last = t end
    end
    if last and truthy(last) then return name end
    if exec == name then return name end
  end
  return nil
end

-- the engine names of a project's `engines:` list (its `_quarto.yml`), in order
local function project_engines(path)
  local d = dir_of(path)
  if d == path then d = "." end
  local q = M.find_upward(d, "_quarto.yml") or M.find_upward(d, "_quarto.yaml")
  local text = q and read_file(q)
  local out = {}
  if not text then return out end
  local ls = lines_of(text)
  for i, l in ipairs(ls) do
    local rest = l:match("^engines[ \t]*:(.*)$")
    if rest then
      rest = trim((rest:gsub("[ \t]#.*$", "")))
      if rest:sub(1, 1) == "[" then
        for item in rest:gsub("^%[", ""):gsub("%].*$", ""):gmatch("[^,]+") do
          local v = scalar_text(item)
          if v:match("^[A-Za-z_][A-Za-z0-9_%-]*$") then out[#out + 1] = v end
        end
      elseif rest == "" then
        for j = i + 1, #ls do
          local item = ls[j]:match("^[ \t]*%-[ \t]+(.*)$")
          if item then
            local v = scalar_text(item)
            if v:match("^[A-Za-z_][A-Za-z0-9_%-]*$") then out[#out + 1] = v end
          elseif not (blank(ls[j]) or ls[j]:match("^[ \t]")) then
            break
          end
        end
      end
      break
    end
  end
  return out
end

-- the engine and how it was chosen ("key" or "chunks"), from the front block `fm` (or nil) and the lines
local function engine_choice(fm, lines, project)
  local order, seen = {}, {}
  for _, list in ipairs({ project, QUARTO_ENGINES }) do
    for _, e in ipairs(list) do
      if not seen[e] then order[#order + 1] = e; seen[e] = true end
    end
  end
  local e = fm and front_engine_claim(fm, order)
  if e then return e, "key", {} end
  local hdrs = quarto_chunk_headers(lines)
  local has, other = {}, false
  for _, h in ipairs(hdrs) do
    has[h.lang] = true
    if h.lang ~= "r" and h.lang ~= "julia" and not HANDLER_LANGS[h.lang] then other = true end
  end
  if has.r then return "knitr", "chunks", hdrs end
  if has.julia then
    for _, o in ipairs(order) do
      if o == "julia" or o == "jupyter" then return o, "chunks", hdrs end
    end
  end
  if other then return "jupyter", "chunks", hdrs end
  return "markdown", "chunks", hdrs
end

-- Is the source a document the knitr hooks resolve (N14, N92)? The rule of R/scan-contexts.R:
-- filter_resolves(): an .Rmd is knitr's, and the intermediate `.knit.md` of rmarkdown; a .qmd that Quarto
-- runs on knitr (engine_choice()), unless the engine came from its chunks and every R chunk among them is
-- `eval = FALSE` (`#| eval: false`). The keys are read from the front block alone, as Quarto reads them
-- (rule 2.1.6): the first metadata block, when only blank lines stand above it, in the include-expanded
-- text, so an include on line 1 can supply it (P4); the chunks are read from that text too.
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
  local engine, by, hdrs = engine_choice(fm, flines, project_engines(path))
  if engine ~= "knitr" then return false end
  if by == "key" then return true end
  for _, h in ipairs(hdrs) do
    if h.lang == "r" then
      local l = flines[h.line]
      local off = l:match("[ ,{]eval[ \t]*=[ \t]*FALSE[ \t]*[,}]") or l:match("[ ,{]eval[ \t]*=[ \t]*F[ \t]*[,}]")
      local j = h.line + 1
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
