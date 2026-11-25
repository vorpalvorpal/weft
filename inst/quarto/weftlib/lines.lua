-- weftlib/lines.lua: the line of a construct, by text search in the source (dev/design-6.md N89, D21).
--
--   local lines = dofile("weftlib/lines.lua")
--   local L = lines.new(path)          -- nil when the file cannot be read
--   file, line = L:find(needle, ok)    -- the next occurrence after the previous one of the same
--                                      -- needle; ok(text, start) may reject a match; nil if none
--
-- The searchable text is the source with each `{{< include F >}}` line replaced by F's searchable
-- text (relative to the including file, recursively, at most 8 deep), with fenced code blocks
-- blanked except their lines that start `#|` (and the body of a {=latex} or {=tex} fence), and HTML comments blanked, line structure kept.
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

local function join(dir, rel)
  if rel:sub(1, 1) == "/" or rel:match("^%a:[/\\]") then return rel end
  local p = dir .. "/" .. rel
  p = p:gsub("/%./", "/"):gsub("^%./", "")
  return p
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

local function expand(path, depth, parts, files, seen_files)
  local text = read_file(path)
  if not text then return false end
  local idx = #files + 1
  files[idx] = path
  local masked = masked_lines(text)
  for i = 1, #masked do
    local line = masked[i]
    local inc = line:match("^[ \t\r\n]*{{<[ \t\r\n]*include[ \t\r\n]+([^ \t\r\n]+)[ \t\r\n]*>}}[ \t\r\n]*$")
    local done = false
    if inc and depth < 8 then
      local target = join(dir_of(path), inc)
      done = expand(target, depth + 1, parts, files, seen_files)
    end
    if not done then parts[#parts + 1] = { idx, i, line } end
  end
  return true
end

function M.new(path)
  if not path then return nil end
  local parts, files = {}, {}
  if not expand(path, 0, parts, files) then return nil end
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
