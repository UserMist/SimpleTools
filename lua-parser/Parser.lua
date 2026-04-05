-- This library implements a top-down parsing, which is very versatile, even though it's not the fastest approach nor it is great at determining multiple syntax errors in multiple places at the same time, all because it skips tokenization step and builds trees directly.

-- Parser is an object, that is meant to go through source string, and which provides various methods for reading tokens in it.
-- Each time token reader function starts, it sets up a checkpoint, and each time it exits, it removes it. If it was successful, a previous checkpoint is set to the current reading position.
-- This is done so that we can have nested token readers, which are easy to implement for reading practically any AST (aka nested tokens) we desire.
-- (Note: checkpoints can be omitted, if token reader will only end up calling a single other token reader)

-- Token readers return token they've parsed, otherwise nil. All token reader names start with capital letter.
-- Writing tokens back to a string is done by having "w" function inside tokens.
-- Each token can be written to a string, and then again be read by same token reader resulting in same token.
-- But token readers are surjective functions, since they often cause loss of unimportant details, such as exact formatting.
-- Some token readers have a stage of reading, after which they aren't allowed to fail (such as reading a body of a function), and when they do - it's because of syntax errors.
-- In those cases error callback on parser is called.

do
  getmetatable('').__index = function(str,i) return string.sub(str,i,i) end -- adds "str[i]" syntax
  getmetatable('').__newindex = function(str,i,v) end
  function back(t) return t[#t] end
  function class(base, init)
    local ret = {}
    if not init and type(base) == 'function' then
      init = base
      base = nil
    elseif type(base) == 'table' then
      for i,v in pairs(base) do
        ret[i] = v
      end
      ret._base = base
    end
    ret.__index = ret

    local mt = {}
    mt.__call = function(class_tbl, ...)
      local obj = {}
      setmetatable(obj,ret)
      if init then
        init(obj,...)
      else 
        if base and base.init then
          base.init(obj, ...)
        end
      end
      return obj
    end
    ret.init = init
    ret.is = function(self, klass)
      local m = getmetatable(self)
      while m do 
        if m == klass then return true end
        m = m._base
      end
      return false
    end
    setmetatable(ret, mt)
    return ret
  end
end

-------------------------
Parser = class(
  function(self, src) 
    self.src = src
    self.pos = 1
    self.path = {}
    self.short = {}
    self.outs = nil
    
    self.getLineInfo = function(self)
      local line = 1
      local char
      for i = self.pos-1,1,-1 do
        if self.src[i] == '\n' then
          line = line+1
          char = char or self.pos-i
        end
      end
      return '(line: '..(line)..'; char: '..(char or self.pos)..')'
    end
  end
)
----------------------------
-- Sets checkpoint. All token functions with it.
function Parser:try()
  table.insert(self.path, self.pos) 
  return true
end

-- Sets position to checkpoint.
function Parser:retry()
  self.pos = self.path[#self.path]
end

-- Moves current(!) checkpoint to position.
function Parser:overwriteTry()
  self.path[#self.path] = self.pos
end

-- Usecase in token reader: "return self:endTry(ret)".
-- When given an argument, moves. Otherwise reverts it. 
-- Returns argument it was given.
function Parser:endTry(item)
  if not item then
    self.pos = self.path[#self.path]
  end
  table.remove(self.path)
  return item
end

-- Returns previous memorized position.
function Parser:prevPos()
  return self.path[#self.path]
end

 -- Use ONLY when function HAS to succeed.
function Parser:addError(errors, msg)
  table.insert(errors, { position = self.pos , message = msg })
  return nil
end

-- Start output tuple
function Parser:out()
  self.outs = {}
  table.insert(self.short, self.outs)
end

-- End output tuple
function Parser:endOut()
  table.remove(self.short)
  self.outs = back(self)
end

--
function Parser:store(val)
  table.insert(back(self.short), val)
  return val
end

-- Used in shortcircuit evaluation pattern to skip over tokens, presence of which doesn't matter.
function Parser:skip(item)
  return true
end

-- Moves parser by specified symbol count
function Parser:jumpBy(delta)
  self.pos = self.pos + delta
end

-- Returns all characters read since last checkpoint.
function Parser:substr(offsetA,offsetB)
  return string.sub(self.src, self:prevPos()+(offsetA or 0), self.pos-1-(offsetB or 0))
end

-- Moves token reader to the next substring encounter.
function Parser:marchUntilInclusive(sub)
  while not self:Match(sub) do 
    if not self:Char() then return false end 
  end
  return true
end

-- Runs token reader without actually changing parser position.
function Parser:stepless(f, ...)
  self:try()
  local ret = f(self, ...)
  self:endTry()
  return ret
end

------------------------- Commonly used token readers ---------------------

-- Reads a single string element.
function Parser:Char()
  if self.pos > #self.src then return nil end
  self.pos = self.pos+1
  return self.src[self.pos-1]
end

-- Reads a single string element, but only if it's present in argument.
function Parser:CharFrom(chars)
  if self.pos > #self.src then return nil end
  
  for i=1,#chars do
    if chars[i] == self.src[self.pos] then
      self:jumpBy(1)
      return chars[i]
    end
  end
  return nil
end

-- Reads same substring (no quotes). 
function Parser:Match(sub)
  local start,len,src = self.pos, #sub-1, self.src
  if start+len <= #src and string.sub(src,start,start+len) == sub then
    --print('=========="'..sub..'"')
    self.pos=start+(len+1)
    return sub
  end
  --print('"'..sub..'"')
end

-- Reads one of few specified substrings (no quotes).
function Parser:MatchMulti(...)
  for i=1,select('#',...) do
    local ret = self:Match(select(i,...))
    if ret then
      return ret
    end
  end
end

-- "Match" but a bit faster, since it works only on a single character.
function Parser:MatchChar(ch)
  if self.pos <= #self.src and self.src[self.pos] == ch then 
    self:jumpBy(1)
    return ch
  end
  return nil
end

function Parser:Letter() 
  return self:CharFrom("_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") 
end

function Parser:Letters()
  while self:Digit() do end
  if self:prevPos() == self.pos then return nil end
  return self:substr()
end

function Parser:Digit()
  return self:CharFrom("0123456789") 
end

function Parser:UnsignedNumber()
  self:try()
  do
    local won = false
    while self:Digit() do won = true end
    if not won then return self:endTry(nil) end
  end
  
  if self:Match('.') then
    local won = false
    while self:Digit() do won = true end
    if not won then self:jumpBy(-1) end
  end
  
  return self:endTry(tonumber(self:substr()))
end

function Parser:Number()
  self:try()
  
  local m = 1
  if self:Match('-') then m = -m end
  if self:UnsignedNumber() then return self:endTry(tonumber(self:substr())) end
  
  self:endTry()
end

-- Skips tabs, spaces and newlines. If any were encountered, returns true.
function Parser:Trim()
  local won
  while self:CharFrom(" \t\n") do won = '\n' end
  return won
end

-- Skips only tabs and spaces. If any were encountered, returns true.
function Parser:SkipSpacing()
  local won
  while self:CharFrom(" \t") do won = ' ' end
  return won
end

-- "Match", but one that ensures there's no other letters (/digits) right after substring.
function Parser:Keyword(s)
  self:try()
  if self:Match(s) and not (self:Letter() or self:Digit()) then return self:endTry(self:substr()) end
  self:endTry()
end

function StringFromAST(d,pre,v)
  local pre = d..pre
  if type(v) == 'string' or type(v) == 'number' then return pre..'"'..v..'"\n' end
  
  if type(v) == 'table' then
    local s = v.t and pre..'{'..v.t..'}\n' or pre..'{}\n'
    local d = d..'  '
    for k,_v in pairs(v) do
      local _s
      if k=='w' or k=='t' or k=='precedence' or k=='isPrefix' or k=='isPostfix' then
        _s = ''
      else
        _s = StringFromAST(d, (type(k)=='number' and k%1==0) and '' or ''..tostring(k)..' = ',_v)
      end
      if #_s>0 then s = s.._s end
    end
    return s
  end
  
  return pre..tostring(v)..'\n'
end

return Parser