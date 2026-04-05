--When creating a parser, we're creating a oriented graph with one entry point and no exits.
--During it's work, parser is meant to memorize the path it took into the network, guided by the tokens it managed or didn't manage to read.

--Span1, SpanFinite, SpanInfinite

--Span0 tokens don't need to be stored
--Span1 tokens are represented as bools
--Other spans - numbers
--Lack of span means it can only be a table/string

--Spans:
--branch/token = 0
--optional branch/token = 1
--(optional) fork = n
--sequence = nil_inf

local function Call(text)
  return {t == "Call", asText = text}
end

local backslash,escapedBackslash,smallQuote,bigQuote = '\\','\\\\','\'','"'
local quotedSmallQuote = smallQuote..backslash..smallQuote..smallQuote
local function rawString(v)
  if #v ~= 1 then return bigQuote..(v:gsub(backslash, escapedBackslash):gsub(bigQuote, backslash..bigQuote))..bigQuote end 
  return (v == smallQuote) and (quotedSmallQuote) or (smallQuote..v..smallQuote)
end

local function Token(text)
  local argStr = '('..rawString(text)..')'
  return {
    t = "Call", 
    asText = string.match(string.sub(text,#text,#text), "%a") and "self:Keyword"..argStr or "self:Match"..argStr,
    span = 1 --only 2 possible states
  }
end

local function Unsaved(node)
  node.omitSaving = true
  return node
end

local function Infallible()
  return {t = "Infallible"}
end

-- Helps interpret args as node tree
local function populate(node, ...)
  local n = select('#', ...)
  local j = 1
  for i=1, n do
    local child = select(i, ...)
    
    if child.t == "Infallible" then
      node.infallibleAt = math.min(j, node.infallibleAt or 1/0)
    else
      if child.t == "Branch" then 
        child = {t = "Call", name = child.name, asText = "self:"..child.name.."()" }
      end
      node[j] = child
      j = j+1
    end
  end
  return node
end

local function Def(name, ...)
  return populate({t = "Branch", name = name, isExternal = select('#', ...) == 0}, ...)
end

local function Optional(...)
  local t = populate({t = "OptionalBranch", isOptional = true}, ...)
  if #t <= 1 then
    t = t[1]
    t.isOptional = true
  end
  return t
end

--Fork of:
--forks       = fork
--unit tokens = enum or an "or"-chain
--
local function Fork(...)
  for i=1,select('#', ...) do
    local child = select(i, ...)
    if child.isOptional then 
      return error("Invalid syntax! Fork can't have optional members") 
    end
  end
  
  return populate({t = "Fork"}, ...)
end

local function indent(self) 
  self.dent = self.dent..self.indentationSymbol
  self.depth = self.depth+1
  return self
end

local function outdent(self)
  self.dent = string.sub(self.dent, 1+#self.indentationSymbol)
  self.depth = self.depth-1
  return self
end

local function addLine(self, line, dontNewline)
  if dontNewline then
    self.code = self.code..self.dent..line
  else
    self.code = self.code..self.dent..line..'\n'
  end
  return self
end

local function addInline(self, text)
  self.code = self.code..text
  return self
end

local function addFiller(self)
  self:addLine(self.fillerName)
  return self
end

local function countItems(gen, node)
  if node.t == "Call" then
    node.itemCount = 1
    return
  end
  
  node.itemCount = 0
  for i=1,#node do
    local child = node[i]
    if not child.omitSaving then
      if not child.itemCount then
        countItems(gen, child)
      end
      if child.itemCount > 0 then
        node.itemCount = node.itemCount + 1
      end
    end
  end
end


local function nextItemID(gen)
  local p = gen.itemPath
  local id = p[#p]+1
  p[#p] = id
  
  local s = p[1]
  for i= 2, #p do
    s = '_'..s
  end
  return id
end

local function failureSnippet(isFirst, inLoop, isInfallible, tokenName)
  if inLoop then
    if isFirst then
      return "break"
    elseif isInfallible then
      return "return error(\"Expected \\\""..tokenName.."\\\" at \"..self:getLineInfo())"
    else
      return "self.pos = backup break"
    end
  end
  
  if isFirst then
    return "return nil"
  elseif isInfallible then
    return "return error(\"Expected \\\""..tokenName.."\\\" at \"..self:getLineInfo())"
  else
    return "self.pos = backup return nil"
  end
end

local function getChildID(parent, child)
  if not parent then return nil end
  for i=1,#parent do
    if child == parent[i] then return i end
  end
  return nil
end

--When we add a snippet, we look at our path and sometimes at our neighbours. But never children.
local function addSnippet(gen, node)
  local depth = gen.depth
  local parent = gen.path[#gen.path]
  table.insert(gen.path, node)
  
  if depth == 0 then
    if node.t ~= "Branch" then return error("ExposeDefs accepts only Defs as arguments!") end
    table.insert(gen.itemPath, 0)
    
    gen:addLine("function Parser:"..node.name.."()")
    gen:indent()
    if node.itemCount > 1 then
      gen:addLine("local backup = self.pos")
    end
    
    for i=1,#node do gen:addSnippet(node[i]) end
    if node.itemCount == 0 then 
      gen:addLine("return true")
    end
    
    gen:outdent()
    gen:addLine("end")
  else
    if node.t == "Call" then
      local id = getChildID(parent, node)
      local isFirst = id == 1
      local isInfallible = parent.infallibleAt and id >= parent.infallibleAt
      local isInLoop = depth > 1
      
      if not isFirst then
        gen:addFiller()
      end
      
      if node.omitSaving and node.isOptional then
        gen:addLine(node.asText)
      elseif node.isOptional then
        gen:addLine("local ret"..nextItemID(gen).." = "..node.asText)
      elseif node.omitSaving then
        gen:addLine("if not"..node.asText.." then "..failureSnippet(isFirst, isInLoop, isInfallible, node.name).." end")
      else
        local retI = "ret"..nextItemID(gen)
        gen:addLine("local "..retI.." = "..node.asText)
        gen:addLine("if not "..retI.." then "..failureSnippet(isFirst, isInLoop, isInfallible, node.name).." end")
      end
    elseif node.t == "Fork" then
      local chainStart = 1
      for i=1,#node do
        local child = node[i]
        if child.t ~= "Call" then
          
          
          for j = chainStart,i-1 do
            gen:addInline(child.asText)
            if(j < i-1) then gen:AddInline(" or ") end
          end
        else
          
        end
      end
      
      local orChain = true
      for i=1,#node do
        if node[i].t ~= "Call" then orChain = false break end
      end
      
      if orChain then
        gen:addLine("return "..node[1].asText, true)
        for i=2,#node do gen:addInline(" or "..node[i].asText) end
        gen:addLine("")
      else
        return error("Fork does not support non-definition members")
      end
    else
      return error("Unsupported node type = "..node.t)
    end
  end
  
  table.remove(gen.path)
end

local function ExposeDefs(...)
  local root = table.pack(...)
  local gen = { root = root, path = {}, itemPath = {}, depth = 0, code = "", dent = "", indentationSymbol = "  ", indent = indent, outdent = outdent, addLine = addLine, addInline = addInline, addFiller = addFiller, fillerName = "self:Filler()", addSnippet = addSnippet }
  for i=1,#root do countItems(gen, root[i]) end
  for i=1,#root do gen:addSnippet(root[i]) end
  return gen
end


local digitDef  = Def("Digit", Fork(Token('0'), Token('1')))
local numDef    = Def("Num", Fork(digitDef, Def("Num")))
local tablePart = Def("TablePart", Token(','), Def("TablePart"))
local tableDef  = Def("Table", Token('{'), Optional(numDef, tablePart), Token('}'))
local funcDef   = Def("Func", Token("function"), Token('('), tableDef)

local simpleDef2 = Def("Ext")
local simpleDef  = Def("Hey", Optional(simpleDef2, Infallible(), simpleDef2))

local code = ExposeDefs(simpleDef)
print(code)

return {Call = Call, Token = Token, Unsaved = Unsaved, Infallible = Infallible, Def = Def, Optional = Optional, Fork = Fork, ExposeDefs = ExposeDefs}

