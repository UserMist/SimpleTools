-- This code generator provides functions for creating token readers-writers by writing couple simple short lines of code, describing EBNF.
-- Provides:
-- Token(s)
-- Call(s)
-- Define(s, ...)
-- Optional()
-- Sequence()
-- SeparatedSequence
-- FillerNone()

-- todo: safety check of neighbouring tokens 

local backslash,escapedBackslash,smallQuote,bigQuote = '\\','\\\\','\'','"'
local quotedSmallQuote = smallQuote..backslash..smallQuote..smallQuote
local function rawString(v)
  if #v ~= 1 then return bigQuote..(v:gsub(backslash, escapedBackslash):gsub(bigQuote, backslash..bigQuote))..bigQuote end 
  return (v == smallQuote) and (quotedSmallQuote) or (smallQuote..v..smallQuote)
end

local nilReturnSnip = "self.pos = backup return nil"
local function errorSnip(tokenName)
  return "error(\"Expected \\\""..tokenName.."\\\" at \"..self:getLineInfo()) return nil"
end

local function failureSnip(self, i, isInfallible)
  if i == 1 then return "break" end
  if isInfallible then return errorSnip(self[i].name) end
  return nilReturnSnip
end

--Snippet-------------------------
-- ret13_2_3
local function nextItemIDSnip(info)
  local n = #info.path-1
  info.path[n].lastItem = info.path[n].lastItem + 1
  
  local s = ""
  for i=1,n do
    s = s..info.path[i].lastItem
    if i<n then
      s = s..'_'
    end
  end
  return s
end

--Snippet-------------------------
-- f(a,b,c)
local function callSnip(node)
  local args = "("
  for i=1,#node do
    args = args..(type(node[i]) == "string" and rawString(node[i]) or tostring(node[i]))
    if i < #node then args = args..", " end
  end
  args = args..")"
  return "self:"..node.name..args
end


local function addOptionalScope(self, info)
  local mainRet = nextItemIDSnip(info)
end

--complete?
--Snippet-------------------------
--  local i1 = 0
--  local ret1
--  while true do
--    self:Filler()
--    
--    if not self:
--
local function addSequenceScope(self, info)
  local j = #info.path+1
  local myInfo = info.path[j-1]
  local parentInfo = info.path[j-2]
  
  local mainRet = nextItemIDSnip(info)
  local indexer = "i"..mainRet
        mainRet = "ret"..mainRet
  
  info:addLine("") 
  info:addLine("local "..indexer.." = 0") 
  info:addLine("local "..mainRet) 
  info:addLine("while true do")
  
  info:indent():tryAddFiller(self[1], true)
  
  if self.separator and not info:tryAddScope(self.separator, nil) then -- REVISIT -------------------------------------------------------------
    local exp = callSnip(self.separator)
    info:addLine("")
  end
  
  myInfo.lastItem = 0
  for i=1,#self do
    info.path[j] = { node = self[i] }
    if not info:tryAddScope(self[i]) then
      local exp = callSnip(self[i])
      
      if self[i].needsSaving then
        local retI = "ret"..nextItemIDSnip(info)
        info:addLine("local "..retI.." = "..exp)
        info:addLine("if not "..retI.." then "..failureSnip(self, i, info.isInfallible).." end")
      else
        info:addLine("if not "..exp.." then "..failureSnip(self, i, info.isInfallible).." end")
      end
      
      if not self[i].addScope then
        info:tryAddFiller(self[i+1])
      end
    end
  end
  info.path[j] = nil
  
  info:addLine("")
  info:addLine("if "..indexer.." == 0 then "..mainRet.." = {} end")
  info:addLine(indexer.." = "..indexer.."+1")
  
  local retList = (#self.items > 1 and "{" or "")
  for i=1,#self.items do
    retList = retList..mainRet..'_'..i
    if i < #self.items then
      retList = retList..", "
    end
  end
  retList = retList..(#self.items > 1 and "}" or "")
  info:addLine(mainRet.."["..indexer.."] = "..retList)
  
  info:outdent()
  info:addLine("end", "")
end

local function addForkScope(self, info)
  info:addLine("local i")
  for i=1,#self do
    info:addLine((i==1 and "local " or "").."retI = "..callSnip(self[i]))
    info:addLine("if retI then retI = { variant = "..rawString(self[i].name)..", retI }")
    info:addLine("else")
    info:indent()
    if i == #self then
      --return or break
    end
  end
  
  for i=1,#self do
    info:outdent()
    info:addLine("end")
  end
end

local Token
local function createTree(name, convertStringsToTokens, ...)
  local tree = { name = name, items = {}, needsSaving = true }
  for i=1, select('#', ...) do
    local f = select(i, ...)
    
    if convertStringsToTokens and type(f) == "string" then
      f = Token(f)
    end
    
    if f.isDefinition then
      f = createTree(f.name, true)
    end
    
    if f.needsSaving then
      tree.items[#tree.items+1] = i
    end
    
    tree[i] = f
  end
  return tree
end


local function addFunctionScope(info, j, child, nextChild)
  if child.name == "[Infallible]" then 
    info.isInfallible = true
    return
  end
  
  info.path[2] = { node = child }
    
  if not info:tryAddScope(child) then
    local exp = callSnip(child)
    
    if child.needsSaving then
      local retI = "ret"..nextItemIDSnip(info)
      info:addLine("local "..retI.." = "..exp)
      info:addLine("if not "..retI.." then "..nilReturnSnip.." end")
    elseif not info.isInfallible or j==1 then
      info:addLine("if not "..exp.." then "..nilReturnSnip.." end")
    else 
      info:addLine("if not "..exp.." then "..errorSnip(child[1]).." end")
    end
  end
  
  if not child.addScope then
    info:tryAddFiller(nextChild)
  end
end

local function addActualFunctionScope(info, definition)
    info.isInfallible = false
    
    info.path[1] = { node = definition, lastItem = 0 }
    info:addLine("function Parser:"..definition.name.."()")
    info:indent():addLine("local backup = self.pos", "")
    
    for j = 1, #definition do
      addFunctionScope(info,j,definition[j],definition[j+1])
    end
    info:addRet()
    info:outdent()
    info:addLine("end")
end

--------------------Info methods---------------------------------
--Snippet-------------------------
-- return { 
--   type = "TokenName", 
--   readd = function(self)
--     
--   end,
--   ret1,
--   ret2_1,
--   ret2_2
-- }
local function addReturnItems(self)
  self:addLine("return {")
  self:indent():addLine("type = "..rawString(self.path[1].node.name)..",")
           self:addLine("readd = function(self)")
           self:indent()
           --self:addLine("local s = ")
           --self:addLine("return s")
  self:outdent()
  self:addLine("end,")
      
  local root = self.path[1].node
  for i=1,#root.items do
    local id = root.items[i]
    self:addLine("ret"..i..(i<#root.items and "," or ""))
  end
      
  self:outdent()
  self:addLine("}")
end

local function indent(self) 
  self.dent = self.dent..self.indentationSymbol
  return self
end

local function outdent(self)
  self.dent = string.sub(self.dent, 1+#self.indentationSymbol)
  return self
end

local function addLine(self, ...)
  for i=1,select('#', ...) do
    self.code = self.code..self.dent..select(i, ...)..'\n'
  end
  return self
end

local function tryAddFiller(self, nextNode, dontPrependNewline)
  if not nextNode or string.sub(nextNode.name, 1, #"Filler") == "Filler" or nextNode.addScope then return end
  
  if dontPrependNewline then
    self:addLine("self:Filler()", "")
  else
    self:addLine("", "self:Filler()", "")
  end
end

local function tryAddScope(self, node)
  if node.addScope then node:addScope(self) return true end
  return false
end

-- Creates token reader-writer code, by creating temporary code generator ("info").
local function DefinitionSet(...)
  local info = {
    code = "", dent = "", indentationSymbol = "  ", path = {},
    indent = indent, outdent = outdent, addLine = addLine,
    tryAddFiller = tryAddFiller, addRet = addReturnItems, tryAddScope = tryAddScope
  }
  
  for i=1, select('#', ...) do
    addActualFunctionScope(info, select(i, ...))
  end
  
  info.path[1] = nil
  return info
end

-------------------/Info methods/--------------------------------

local function Call(name, ...)
  local ret = createTree(name, false, ...)
  return ret
end

local function Define(name, ...)
  local ret = createTree(name, true, ...)
  ret.isDefinition = true
  return ret
end

local function Optional(...) 
  local ret = createTree("[Optional]", true, ...) 
  ret.addScope = addOptionalScope 
  return ret 
end

local function Sequence(...) 
  local ret = createTree("[Sequence]", true, ...) 
  ret.addScope = addSequenceScope
  return ret 
end

local function SeparatedSequence(...) --last arg is a separator
  local ret = createTree("[SeparatedSequence], true, ...")
  --ret.addScope = ?
  return ret
end

local function Fork(...) 
  local ret = createTree("[Fork]", true, ...) 
  ret.addScope = addForkScope
  return ret 
end

local function Infallible()
  local ret = createTree("[Infallible]", true)
  ret.needsSaving = false
  return ret
end

--revisit
local function FillerNone()
  local ret = createTree("FillerNone", true)
  ret.needsSaving = false
  return ret
end

Token = function(symbol)
  local ret = Call(string.match(string.sub(symbol,#symbol,#symbol), "%a") and "Keyword" or "Match", symbol)
  ret.needsSaving = false
  return ret
end


local function WordFromChars(chars) end
local function Conversion(ToName) end
local function AddOptionalToString(info)
  
end

-- merged
-- [ ]   nullable
--  |    enum
-- { }   array


local Name       = Call("Name")
local Exp        = Call("Expression")
local Assignment = Define("Assignment", Name, '=', Exp)
local Table      = Define("Table", '{', Name, Sequence(',', Name, ' = ', Name), '}')

print(DefinitionSet(
  Assignment,
  Table
).code)

--print(DefinitionSet(Define("Assignment", "+", Optional("{", Name), Exp)).code)


