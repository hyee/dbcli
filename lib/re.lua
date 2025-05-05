--
-- Copyright 2007-2023, Lua.org & PUC-Rio  (see 'lpeg.html' for license)
-- written by Roberto Ierusalimschy
--

-- imported functions and modules
local tonumber, type, print, error,string = tonumber, type, print, error,string
local setmetatable = setmetatable
local m = require"lpeg"

-- 'm' will be used to parse expressions, and 'mm' will be used to
-- create expressions; that is, 're' runs on 'm', creating patterns
-- on 'mm'
local mm = m

-- pattern's metatable
local mt = getmetatable(mm.P(0))


local version = _VERSION

-- No more global accesses after this point
_ENV = nil     -- does no harm in Lua 5.1


local any = m.P(1)


-- Pre-defined names
local Predef = { nl = m.P"\n" }


local mem
local fmem
local gmem


local function updatelocale ()
  mm.locale(Predef)
  Predef.a = Predef.alpha
  Predef.c = Predef.cntrl
  Predef.d = Predef.digit
  Predef.g = Predef.graph
  Predef.l = Predef.lower
  Predef.p = Predef.punct
  Predef.s = Predef.space
  Predef.u = Predef.upper
  Predef.w = Predef.alnum
  Predef.x = Predef.xdigit
  Predef.A = any - Predef.a
  Predef.C = any - Predef.c
  Predef.D = any - Predef.d
  Predef.G = any - Predef.g
  Predef.L = any - Predef.l
  Predef.P = any - Predef.p
  Predef.S = any - Predef.s
  Predef.U = any - Predef.u
  Predef.W = any - Predef.w
  Predef.X = any - Predef.x
  mem = {}    -- restart memoization
  fmem = {}
  gmem = {}
  local mt = {__mode = "v"}
  setmetatable(mem, mt)
  setmetatable(fmem, mt)
  setmetatable(gmem, mt)
end


updatelocale()



local I = m.P(function (s,i) print(i, s:sub(1, i-1)); return i end)


local function patt_error (s, i)
  local msg = (#s < i + 20) and s:sub(i)
                             or s:sub(i,i+20) .. "..."
  msg = ("pattern error near '%s'"):format(msg)
  error(msg, 2)
end

local function mult (p, n)
  local np = mm.P(true)
  while n >= 1 do
    if n%2 >= 1 then np = np * p end
    p = p * p
    n = n/2
  end
  return np
end

local function equalcap (s, i, c)
  if type(c) ~= "string" then return nil end
  local e = #c + i
  if s:sub(i, e - 1) == c then return e else return nil end
end


local S = (Predef.space + "--" * (any - Predef.nl)^0)^0

local name = m.R("AZ", "az", "__") * m.R("AZ", "az", "__", "09")^0

local arrow = S * "<-"

local seq_follow = m.P"/" + ")" + "}" + ":}" + "~}" + "|}" + (name * arrow) + -1

name = m.C(name)


-- a defined name only have meaning in a given environment
local Def = name * m.Carg(1)


local function getdef (id, defs)
  local c = defs and defs[id]
  if not c then error("undefined name: " .. id) end
  return c
end

-- match a name and return a group of its corresponding definition
-- and 'f' (to be folded in 'Suffix')
local function defwithfunc (f)
  return m.Cg(Def / getdef * m.Cc(f))
end


local num = m.C(m.R"09"^1) * S / tonumber

local String = "'" * m.C((any - "'")^0) * "'" +
               '"' * m.C((any - '"')^0) * '"'


local defined = "%" * Def / function (c,Defs)
  local cat =  Defs and Defs[c] or Predef[c]
  if not cat then error ("name '" .. c .. "' undefined") end
  return cat
end

local Range = m.Cs(any * (m.P"-"/"") * (any - "]")) / mm.R

local item = (defined + Range + m.C(any)) / m.P

local Class =
    "["
  * (m.C(m.P"^"^-1))    -- optional complement symbol
  * (item * ((item % mt.__add) - "]")^0) /
                          function (c, p) return c == "^" and any - p or p end
  * "]"

local function adddef (t, k, exp)
  if t[k] then
    error("'"..k.."' already defined as a rule")
  else
    t[k] = exp
  end
  return t
end

local function firstdef (n, r) return adddef({n}, n, r) end


local function NT (n, b)
  if not b then
    error("rule '"..n.."' used outside a grammar")
  else return mm.V(n)
  end
end


local exp = m.P{ "Exp",
  Exp = S * ( m.V"Grammar"
            + m.V"Seq" * ("/" * S * m.V"Seq" % mt.__add)^0 );
  Seq = (m.Cc(m.P"") * (m.V"Prefix" % mt.__mul)^0)
        * (#seq_follow + patt_error);
  Prefix = "&" * S * m.V"Prefix" / mt.__len
         + "!" * S * m.V"Prefix" / mt.__unm
         + m.V"Suffix";
  Suffix = m.V"Primary" * S *
          ( ( m.P"+" * m.Cc(1, mt.__pow)
            + m.P"*" * m.Cc(0, mt.__pow)
            + m.P"?" * m.Cc(-1, mt.__pow)
            + "^" * ( m.Cg(num * m.Cc(mult))
                    + m.Cg(m.C(m.S"+-" * m.R"09"^1) * m.Cc(mt.__pow))
                    )
            + "->" * S * ( m.Cg((String + num) * m.Cc(mt.__div))
                         + m.P"{}" * m.Cc(nil, m.Ct)
                         + defwithfunc(mt.__div)
                         )
            + "=>" * S * defwithfunc(mm.Cmt)
            + ">>" * S * defwithfunc(mt.__mod)
            + "~>" * S * defwithfunc(mm.Cf)
            ) % function (a,b,f) return f(a,b) end * S
          )^0;
  Primary = "(" * m.V"Exp" * ")"
            + String / mm.P
            + Class
            + defined
            + "{:" * (name * ":" + m.Cc(nil)) * m.V"Exp" * ":}" /
                     function (n, p) return mm.Cg(p, n) end
            + "=" * name / function (n) return mm.Cmt(mm.Cb(n), equalcap) end
            + m.P"{}" / mm.Cp
            + "{~" * m.V"Exp" * "~}" / mm.Cs
            + "{|" * m.V"Exp" * "|}" / mm.Ct
            + "{" * m.V"Exp" * "}" / mm.C
            + m.P"." * m.Cc(any)
            + (name * -arrow + "<" * name * ">") * m.Cb("G") / NT;
  Definition = name * arrow * m.V"Exp";
  Grammar = m.Cg(m.Cc(true), "G") *
            ((m.V"Definition" / firstdef) * (m.V"Definition" % adddef)^0) / mm.P
}

local pattern = S * m.Cg(m.Cc(false), "G") * exp / mm.P * (-any + patt_error)

local fmt="[%s%s]"
local function case_insensitive_pattern(quote,pattern)
    -- find an optional '%' (group 1) followed by any character (group 2)
    local stack={}
    local is_letter=nil
    local p = pattern:gsub("(%%?)(.)",
        function(percent, letter)
            if percent ~= "" or not letter:match("%a") then
                -- if the '%' matched, or `letter` is not a letter, return "as is"
                if is_letter==false then
                    stack[#stack]=stack[#stack]..percent .. letter
                else
                    stack[#stack+1]=percent .. letter
                    is_letter=false
                end
            else
                if is_letter==false then
                    stack[#stack]=quote..stack[#stack]..quote
                    is_letter=true
                end
                -- else, return a case-insensitive character class of the matched letter
                stack[#stack+1]=fmt:format(letter:lower(), letter:upper())
            end
            return ""
        end)
    if is_letter==false then
        stack[#stack]=quote..stack[#stack]..quote
    end
    if #stack<2 then return stack[1] or (quote..pattern..quote) end
    return '('..table.concat(stack,' ')..')'
end

local function compile (p, defs, case_insensitive)
  if mm.type(p) == "pattern" then return p end   -- already compiled
  if case_insensitive==true then
    p=p:gsub([[(['"'])([^\n]-)(%1)]],case_insensitive_pattern):gsub("%(%s*%((.-)%)%s*%)","(%1)")
  end
  local cp = pattern:match(p, 1, defs)
  if not cp then error("incorrect pattern", 3) end
  return cp
end

local function match (s, p, i,case_insensitive)
  local cp = mem[p]
  if not cp then
    cp = compile(p,nil,case_insensitive)
    mem[p] = cp
  end
  return cp:match(s, i or 1)
end

local function find (s, p, i,case_insensitive)
  local cp = fmem[p]
  if not cp then
    cp = compile(p,nil,case_insensitive) / 0
    cp = mm.P{ mm.Cp() * cp * mm.Cp() + 1 * mm.V(1) }
    fmem[p] = cp
  end
  local i, e = cp:match(s, i or 1)
  if i then return i, e - 1
  else return i
  end
end

local function gsub (s, p, rep,case_insensitive)
  local g = gmem[p] or {}   -- ensure gmem[p] is not collected while here
  gmem[p] = g
  local cp = g[rep]
  if not cp then
    cp = compile(p,nil,case_insensitive)
    cp = mm.Cs((cp / rep + 1)^0)
    g[rep] = cp
  end
  return cp:match(s)
end


-- exported names
local re = {
  compile = compile,
  match = match,
  find = find,
  gsub = gsub,
  updatelocale = updatelocale,
}

if version == "Lua 5.1" then _G.re = re end

return re
