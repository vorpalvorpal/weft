-- weftlib/lines.lua: the line of a construct, by text search in the source (dev/design-6.md N89, D21).
--
--   local lines = dofile("weftlib/lines.lua")
--   local L = lines.new(path, main_dir, root)  -- nil when the file cannot be read; main_dir is the
--                                      -- document's folder (absolute), root the Quarto project root
--   file, line = L:find(needle, ok)    -- the next occurrence after the previous one of the same
--                                      -- needle; ok(text, start) may reject a match; nil if none
--   lines.include_targets(lines, main_dir, root, in_included)  -- line -> path of each include
--   lines.expanded_lines(path, text, main_dir, root)  -- the source's lines, its includes expanded
--
-- The searchable text is the source with each `{{< include F >}}` line replaced by F's searchable
-- text, as Quarto expands it (the include rules I1 to I6, below), with fenced code blocks
-- blanked except their lines that start `#|` (and the body of a {=latex} or {=tex} fence), and HTML comments blanked, line structure kept.
-- A file included inside a fence or a comment is blanked whole: Quarto puts its text there.
-- No side effect on load.

local M = {}
M.__index = M

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function dir_of(path)
  local d = path:gsub("[/\\]+[^/\\]*$", "")
  if d == path then return "." end
  return d
end

-- the lines of a text with fenced code and comments blanked
local function masked_lines(text)
  text = text:gsub("<!%-%-.-%-%->", function(m) return (m:gsub("[^\n]", "")) end)
  local out, n = {}, 0
  local fence_char, fence_len, fence_raw
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    local keep = line
    local marks = line:match("^[ \t\r\n>]*(`+)") or line:match("^[ \t\r\n>]*(~+)")
    if fence_char then
      local close = line:match("^[ \t\r\n>]*(" .. fence_char .. "+)[ \t\r\n]*$")
      if close and #close >= fence_len then fence_char = nil
      elseif not (fence_raw or line:match("^[ \t\r\n]*#|")) then keep = "" end
      if fence_char == nil then keep = "" end
    elseif marks and #marks >= 3 then
      fence_char = marks:sub(1, 1)
      if fence_char == "`" then fence_char = "`" else fence_char = "~" end
      fence_len = #marks
      -- the body of a raw TeX fence is searched: a named value in it has a line (design 9, D82)
      local info = line:match("^[ \t\r\n>]*[`~]+[ \t]*{=(%a+)}[ \t\r\n]*$")
      fence_raw = info == "latex" or info == "tex"
      keep = ""
    end
    out[n] = keep
  end
  -- a trailing empty line is an artefact of the final newline
  if n > 0 and out[n] == "" and text:sub(-1) == "\n" then out[n] = nil end
  return out
end

-- ---- Quarto's {{< include >}} (the include rules I1 to I6, Quarto 1.11.9) ---------------------------
-- The Lua twin of R's include_targets() (R/include.R): a line is an include only when the whole line
-- is the shortcode, one space inside each bracket (I1); `include` is lowercase in the main document,
-- any case in an included file (I2); the path is the first positional parameter (I3); every path, at
-- any depth, resolves against the MAIN document's folder, a leading / against the Quarto project root
-- (I4); fences, cells and comments do not hide an include, a cell of the main document holding
-- ```{shortcodes=false} does (I5); no depth limit, and a file is not expanded inside itself (I6).

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function normpath(p)
  p = p:gsub("\\", "/")
  local lead = p:match("^%a:/") or (p:sub(1, 1) == "/" and "/" or "")
  local out = {}
  for seg in p:sub(#lead + 1):gmatch("[^/]+") do
    if seg == "." then
      -- nothing
    elseif seg == ".." then
      if #out > 0 and out[#out] ~= ".." then out[#out] = nil elseif lead == "" then out[#out + 1] = seg end
    else
      out[#out + 1] = seg
    end
  end
  local r = lead .. table.concat(out, "/")
  if r == "" then return "." end
  return r
end

-- the name and positional parameters of a line that is a block shortcode (I1), or nil
local function block_shortcode(line)
  local rest = line:match("^%s*{{< (.*)$")
  if not rest then return nil end
  rest = rest:gsub("%s+$", "")
  if #rest < 5 or rest:sub(-4) ~= " >}}" then return nil end
  local cap = rest:sub(1, -5)
  if cap:sub(1, 2) == "/*" or cap:sub(-2) == "*/" then return nil end
  local name = cap:match("^/?[%w_]+")
  if not name then return nil end
  local params = {}
  local r = trim(cap:sub(#name + 1))
  while #r > 0 do
    local hit = r:match('^[%w_%-]+="[^"]*"') or r:match("^[%w_%-]+='[^']*'") or r:match("^[%w_%-]+=[^\"'%s]+")
    if not hit then
      hit = r:match("^[^\"'%s]+")
      if hit then
        params[#params + 1] = hit
      else
        hit = r:match('^"[^"]*"') or r:match("^'[^']*'")
        if not hit then return nil end
        params[#params + 1] = hit:sub(2, -2)
      end
    end
    r = trim(r:sub(#hit + 1))
  end
  return name, params
end

-- an executable cell's opening fence, as breakQuartoMd reads it: its backticks, or nil
local function cell_start(line)
  local ticks, inner = line:match("^%s*(```+)%s*{(.*)}%s*$")
  if not ticks then return nil end
  local lang = inner:match("^[=%a][=%w%._]*")
  if not lang then return nil end
  local more = inner:sub(#lang + 1)
  if more ~= "" and not more:match("^ *[ ,]") then return nil end
  return ticks
end

-- which lines of the main document sit in a cell Quarto does not expand includes in (I5): the cells
-- are breakQuartoMd's, and a cell whose text holds ```{shortcodes=false} is skipped
local function skipped_lines(lines)
  local n, skip = #lines, {}
  local any = false
  for i = 1, n do if lines[i]:find("shortcodes", 1, true) then any = true end end
  if not any then return skip end
  local buf = {}
  local function flush(force)
    if #buf > 0 or force then
      local parts = {}
      for j, k in ipairs(buf) do parts[j] = lines[k] end
      if table.concat(parts, "\n"):find("```%s*{%s*shortcodes%s*=%s*false%s*}") then
        for _, k in ipairs(buf) do skip[k] = true end
      end
    end
    buf = {}
  end
  local function blank(k) return k >= 1 and k <= n and lines[k]:match("^%s*$") ~= nil end
  local function yaml_delim(k, skip_hr)
    if not lines[k]:match("^%-%-%-%s*$") then return false end
    return not (skip_hr and k > 1 and blank(k - 1) and k < n and blank(k + 1))
  end
  local in_yaml, in_cell, in_code = false, false, 0
  for k = 1, n do
    local line = lines[k]
    local plain = not in_cell and in_code == 0 and not in_yaml
    local close = line:match("^%s*(```+)%s*$")
    if in_code == 0 and not in_cell and yaml_delim(k, not in_yaml) then
      if in_yaml then
        buf[#buf + 1] = k; flush(); in_yaml = false
      else
        flush(); buf[#buf + 1] = k; in_yaml = true
      end
    elseif plain and block_shortcode(line) then
      flush(); buf[#buf + 1] = k; flush()
    elseif plain and cell_start(line) then
      flush(); in_cell = true; in_code = #cell_start(line); buf[#buf + 1] = k
    elseif in_code > 0 and close and #close == in_code then
      buf[#buf + 1] = k
      if in_cell then in_cell = false; flush(true) end
      in_code = 0
    elseif in_code == 0 and line:sub(1, 3) == "```" then
      local first = line:match("^[^ ]*")
      in_code = select(2, first:gsub("`", ""))
      buf[#buf + 1] = k
    else
      buf[#buf + 1] = k
    end
  end
  flush()
  return skip
end

-- The includes of one file's lines (I1 to I5): a table from line number to the path the include
-- resolves to (normalised; the file may not exist). main_dir is the MAIN document's folder, root the
-- Quarto project root, in_included whether these lines are an included file's.
function M.include_targets(lines, main_dir, root, in_included)
  local out = {}
  local skip = in_included and {} or skipped_lines(lines)
  for k, line in ipairs(lines) do
    if not skip[k] and line:find("{{< ", 1, true) then
      local name, params = block_shortcode(line)
      if name and #params > 0 then
        if in_included then name = name:lower() end
        if name == "include" then
          local p = params[1]:gsub("\\", "/")
          if p:sub(1, 1) == "/" then
            p = root:gsub("/+$", "") .. p
          elseif not p:match("^%a:/") then
            p = main_dir .. "/" .. p
          end
          out[k] = normpath(p)
        end
      end
    end
  end
  return out
end

-- the lines of a text, as masked_lines() splits them
local function raw_lines(text)
  local out, n = {}, 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do n = n + 1; out[n] = line end
  if n > 0 and out[n] == "" and text:sub(-1) == "\n" then out[n] = nil end
  return out
end

local function expand(path, key, ctx, stack, blank, in_included, parts, files)
  local text = read_file(path)
  if not text then return false end
  local idx = #files + 1
  files[idx] = path
  local masked = masked_lines(text)
  local raw = raw_lines(text)
  local incs = M.include_targets(raw, ctx.main_dir, ctx.root, in_included)
  stack[key] = true
  for i = 1, #masked do
    local line = masked[i]
    local target = incs[i]
    local done = false
    if target and not stack[target] then
      done = expand(target, target, ctx, stack, blank or line ~= raw[i], true, parts, files)
    end
    if not done then parts[#parts + 1] = { idx, i, blank and "" or line } end
  end
  stack[key] = nil
  return true
end

-- The lines of a source with every include expanded as Quarto splices them, for the readers of its front
-- matter (rules P4 and P5 of 2.1.6; the twin of R's include_expand()): each include line is replaced by
-- the included file's expanded lines and one blank line (two for an include inside an included file). A
-- file is not expanded inside itself (I6); an include whose file cannot be read stays the line it is.
-- text is the main document's text (nil: it is read from path); main_dir its folder, root the Quarto
-- project root. Nil when there is no path or no text.
function M.expanded_lines(path, text, main_dir, root)
  if not path then return nil end
  text = text or read_file(path)
  if not text then return nil end
  main_dir = normpath(main_dir or dir_of(path))
  root = normpath(root or main_dir)
  local out = {}
  local function go(lines, key, stack, in_included)
    local incs = M.include_targets(lines, main_dir, root, in_included)
    stack[key] = true
    for i, line in ipairs(lines) do
      local target = incs[i]
      local sub = target and not stack[target] and read_file(target) or nil
      if sub then
        go(raw_lines(sub), target, stack, true)
        out[#out + 1] = ""
        if in_included then out[#out + 1] = "" end
      else
        out[#out + 1] = line
      end
    end
    stack[key] = nil
  end
  local key = path:sub(1, 1) == "/" and normpath(path) or (main_dir .. "/" .. (path:match("([^/\\]*)$")))
  go(raw_lines(text), normpath(key), {}, false)
  return out
end

function M.new(path, main_dir, root)
  if not path then return nil end
  main_dir = main_dir or dir_of(path)
  local ctx = { main_dir = normpath(main_dir), root = normpath(root or main_dir) }
  local key = path:sub(1, 1) == "/" and normpath(path) or (ctx.main_dir .. "/" .. (path:match("([^/\\]*)$")))
  local parts, files = {}, {}
  if not expand(path, normpath(key), ctx, {}, false, false, parts, files) then return nil end
  local buf, starts, pos = {}, {}, 1
  for i, p in ipairs(parts) do
    starts[i] = pos
    buf[i] = p[3]
    pos = pos + #p[3] + 1
  end
  return setmetatable({
    text = table.concat(buf, "\n"), starts = starts, parts = parts, files = files, cursor = {},
  }, M)
end

function M:locate(pos)
  local lo, hi = 1, #self.starts
  if hi == 0 then return nil end
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if self.starts[mid] <= pos then lo = mid else hi = mid - 1 end
  end
  local p = self.parts[lo]
  return p[1], p[2]
end

-- the next match of one needle: its start and end, or nil; nothing is committed
function M:next_match(needle, ok)
  local from = self.cursor[needle] or 1
  while true do
    local s, e = self.text:find(needle, from, true)
    if not s then return nil end
    if not ok or ok(self.text, s) then return s, e end
    from = s + 1
  end
end

-- the file index (into self.files) and line of the next occurrence of needle. A needle holding `|` is
-- also searched in its escaped form `\|`, which a pipe table needs (the tree holds the unescaped
-- text): the earlier of the two matches wins.
function M:find(needle, ok)
  local s, e = self:next_match(needle, ok)
  local used = needle
  if needle:find("|", 1, true) then
    local esc = needle:gsub("|", "\\|")
    local s2, e2 = self:next_match(esc, ok)
    if s2 and (not s or s2 < s) then s, e, used = s2, e2, esc end
  end
  if not s then return nil end
  self.cursor[used] = e + 1
  return self:locate(s)
end

-- Whether a code point (the start of a UTF-8 character) is a letter or digit, as far as the backslash rule
-- needs it: Pandoc keeps a `\` before a Unicode letter or digit. The non-ASCII punctuation, symbol and
-- space blocks are listed; every other non-ASCII character counts as a letter.
local function alnum_cp(cp)
  if cp < 0x80 then return false end
  if cp == 0xAA or cp == 0xB5 or cp == 0xBA or cp == 0xB2 or cp == 0xB3 or cp == 0xB9
     or (cp >= 0xBC and cp <= 0xBE) then return true end
  if cp <= 0xBF or cp == 0xD7 or cp == 0xF7 then return false end
  if cp >= 0x2000 and cp <= 0x206F then return false end
  if cp >= 0x2190 and cp <= 0x2BFF then return false end
  if cp >= 0x3000 and cp <= 0x303F then return false end
  if cp >= 0xFE00 and cp <= 0xFE0F then return false end
  if cp >= 0xFF00 and cp <= 0xFF0F then return false end
  return true
end

-- The value written after `=` at `pos`, as Pandoc reads it (not weft's subset, so that a document weft would
-- refuse still gets its lines, rule 2.13.6): quoted in `"` or `'`, or bare up to white space or `}`; a `\`
-- before a character that is not a letter or digit (Unicode ones included) is that character (a whole UTF-8
-- character), a `\` before a letter or digit stays, and so does a `\` before a line break; a line break in a
-- quoted value is a space, and `strip` spaces of the next line are dropped (a list item's content indent).
-- Character references are not decoded. Returns the value and the position after it, or nil.
local function read_value(text, pos, strip)
  strip = strip or 0
  local q = text:sub(pos, pos)
  local out, i = {}, pos
  local quoted = q == '"' or q == "'"
  if quoted then i = i + 1 end
  local function brk(n)
    out[#out + 1] = " "
    i = i + n
    local k = 0
    while k < strip and text:sub(i, i) == " " do i = i + 1; k = k + 1 end
  end
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" and i < #text then
      local nx = text:sub(i + 1, i + 1)
      if nx == "\n" or nx == "\r" then
        out[#out + 1] = c
        i = i + 1
      elseif nx:match("[A-Za-z0-9]") then
        out[#out + 1] = c .. nx
        i = i + 2
      else
        local ch = text:match("^[\0-\x7F\xC2-\xFD][\x80-\xBF]*", i + 1) or nx
        local cp = utf8.codepoint(ch, 1, 1, true)
        if #ch > 1 and cp and alnum_cp(cp) then
          out[#out + 1] = c .. ch
        else
          out[#out + 1] = ch
        end
        i = i + 1 + #ch
      end
    elseif quoted and c == q then
      return table.concat(out), i + 1
    elseif quoted and c == "\r" and text:sub(i + 1, i + 1) == "\n" then
      brk(2)
    elseif quoted and c == "\n" then
      brk(1)
    elseif not quoted and c:match("[ \t\r\n}]") then
      break
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  if quoted then return nil end
  if #out == 0 then return nil end
  return table.concat(out), i
end

-- How the line holding `pos` starts: "bq" (after indentation, `>`), "li" and the content indent of a list
-- item, or "" (R2).
local function line_context(text, pos)
  local k = pos
  while k > 1 and text:sub(k - 1, k - 1) ~= "\n" do k = k - 1 end
  local pre = text:sub(k, pos - 1)
  if pre:match("^[ \t]*>") then return "bq", 0 end
  local m = pre:match("^ *[-+*] +") or pre:match("^ *%d+[.)] +")
  if m then return "li", #m end
  return "", 0
end

-- The file index and line of the next occurrence of `KEY=` that follows `{`, a space, a tab or a line break
-- and whose value, read as Pandoc reads it, equals `value` (rule 2.13.6). The cursor is kept per key and value,
-- so an occurrence found nowhere moves nothing on for the others.
function M:find_attr(key, value)
  local id = key .. "\0" .. value
  local from = self.cursor[id] or 1
  local needle = key .. "="
  while true do
    local s, e = self.text:find(needle, from, true)
    if not s then return nil end
    local prev = s > 1 and self.text:sub(s - 1, s - 1) or ""
    if prev == "{" or prev == " " or prev == "\t" or prev == "\n" or prev == "\r" then
      local kind, indent = line_context(self.text, s)
      local v, after
      v, after = read_value(self.text, e + 1, kind == "li" and indent or 0)
      -- a quoted value that crosses a line break in a block quote is a construct error: no line
      if v ~= nil and kind == "bq" and self.text:sub(e + 1, after - 1):find("\n", 1, true) then v = nil end
      if v ~= nil and v == value then
        self.cursor[id] = after
        return self:locate(s)
      end
    end
    from = s + 1
  end
end

return M
