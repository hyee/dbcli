local PackageName, Major, Minor, Patch = "RegExpUtils", 1, 0, 0
local PkgMajor, PkgMinor = PackageName, tonumber(string.format("%02d%02d%02d", Major, Minor, Patch))
--local Pkg = Apollo.GetPackage(PkgMajor)
if Pkg and (Pkg.nVersion or 0) >= PkgMinor then
  return -- no upgrade needed
end

-- Set a reference to the actual package or create an empty table
local RegExp = Pkg and Pkg.tPackage or {}

RegExp.cacheSize = 100 -- this is the size of regex cache
local g_sourceCache_re = {}
local g_objectCache_re = {}

function RegExp:new(args)
   local new = { }

   if args then
      for key, val in pairs(args) do
         new[key] = val
      end
   end

   return setmetatable(new, RegExp)
end

local unpack = table.unpack or unpack

-- the base class of all
local __base_class__ = {}
function __base_class__:__init__() end

-- Creates a new class, deriving from a base (optional)
local function class(base)
    base = base or __base_class__

    local cls = {}
    setmetatable(cls, { ["__index"] = base })

    return cls
end

--- Creates a new object of a class
local function new(cls, ...)
    --- cls: the class
    --- ...: arguments for the constructor
    local self = {}
    setmetatable(self, { ["__index"] = cls })
    self:__init__(...)
    return self
end

-- Get object's class
local function classof(object)
    return rawget(getmetatable(object), "__index")
end

-----------------------------------------------------------------------------
-- Nodes of expression tree
--
-- expression's base
--
local Expression = class()

function Expression:SetMatchee(matchee, pos)
    -- Resets the state of the self and set matchee.
    -- setting pos = nil just resets the expression
    --      (or, lets NextMatch(submatches, flags) return false)
    self.matchee = matchee
    self.pos     = pos
    self:OnSetMatchee()
end

function Expression:NextMatch(submatches, flags)
    -- Before first calling this function,
    --   the user should have called self:SetMatchee(matchee, pos).
    --   (otherwise, this function just returns false)
    --
    -- This function enumerates possible matches for the self.
    -- Each time this is called, this returns (isOK, nextPos).
    --   - if isOK == true,
    --         nextPos denotes the position for the next expression.
    --   - if isOK == false,
    --         there was no match left.
    --
    -- Look also at the comment of Expression:OnNextMatch
    local pos = self.pos
    local isOK, nextPos
    if pos then
        isOK, nextPos = self:OnNextMatch(submatches, flags)
        if not isOK then
            self.pos = nil
        end
    end

    if self.name then
        if isOK then
            submatches[self.name] = { pos, nextPos }
        else
            submatches[self.name] = nil
        end
    end

    return isOK, nextPos
end

function Expression:SetName(name)
    -- name: number or string
    self.name = name
end

function Expression:CloneCoreStateTo(clone)
    -- This should be called by Clone() of derived classes.
    -- Clones the core states into 'clone'
    clone.matchee = self.matchee
    clone.pos     = self.pos
    clone.name    = self.name
end

-- Override this if necessary
function Expression:OnSetMatchee() end

-- Define following functions in derived classes
-- function Expression:Clone()
--     Return a clone object of the self.
--     The state of the clone shall be the same as the self.
--     If the self has sub-objects, the sub-objects shall also be cloned.
--
-- function Expression:IsFixedLength()
--     Checks if the expression's length is fixed.
--     This functions returns (isFixed, length)
--
-- function Expression:OnNextMatch(submatches, flags)
--     When this function is called,
--         self.matchee and self.pos refer to the string to be matched.
--
--      - If there are one or more matches for the self, then
--           this function shall return (true, NEXT_POSITION),
--           in the favored order, one by one, each time it is called.
--      - If there are no matches, or if there are no matches left,
--           then this function shall return false.
--
--     It is guaranteed that this function is never called
--     after
--       - this function returns false, or
--       - this function sets self.pos = nil,
--     until the user calls self:SetMatchee again.
--
--     A matched group named 'name' (string or number)
--     can be obtained by
--          pos, nextPos = unpack(submatches[name])
--          str = self.matchee:sub(pos, nextPos-1)

--
-- expression AB
--
local ExpPair = class(Expression)

function ExpPair:__init__(sub1, sub2)
    self.sub1 = sub1
    self.sub2 = sub2
end

function ExpPair:OnSetMatchee()
    self.sub1:SetMatchee(self.matchee, self.pos)
    self.sub2:SetMatchee(nil, nil)
end

function ExpPair:Clone()
    clone = new(classof(self), self.sub1:Clone(), self.sub2:Clone())
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpPair:IsFixedLength()
    local b, len1 = self.sub1:IsFixedLength()
    local len2
    if b then
        b, len2 = self.sub2:IsFixedLength()
        if b then
            return true, len1 + len2
        end
    end

    return false
end

function ExpPair:OnNextMatch(submatches, flags)
    local isOK, nextPos = self.sub2:NextMatch(submatches, flags)
    if isOK then
        return isOK, nextPos
    end

    repeat
        isOK, nextPos = self.sub1:NextMatch(submatches, flags)
        if not isOK then
            return false
        end

        self.sub2:SetMatchee(self.matchee, nextPos)
        isOK, nextPos = self.sub2:NextMatch(submatches, flags)
    until isOK

    return isOK, nextPos
end


--
-- expression A|B
--
local ExpOr = class(Expression)

function ExpOr:__init__(sub1, sub2)
    self.sub1 = sub1
    self.sub2 = sub2
end

function ExpOr:OnSetMatchee()
    self.sub1:SetMatchee(self.matchee, self.pos)
    self.sub2:SetMatchee(self.matchee, self.pos)
end

function ExpOr:Clone()
    clone = new(classof(self), self.sub1:Clone(), self.sub2:Clone())
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpOr:IsFixedLength()
    local b, len1 = self.sub1:IsFixedLength()
    local len2
    if b then
        b, len2 = self.sub2:IsFixedLength()
        if b and len1 == len2 then
            return true, len1
        end
    end

    return false
end

function ExpOr:OnNextMatch(submatches, flags)
    local isOK, nextPos = self.sub1:NextMatch(submatches, flags)
    if isOK then
        return isOK, nextPos
    end

    return self.sub2:NextMatch(submatches, flags)
end


--
-- expression A{a,b}, which includes:
--     A* = A{,}
--     A+ = A{1,}
--     A? = A{,1}
--     A{n} = A{n,n}
-- a,b when omitted are assumed to be 0 and infinity, respectively
--
local ExpRepeat = class(Expression)

function ExpRepeat:__init__(sub, min, max)
    self.sub   = sub
    self.min   = min or 0
    self.max   = max
end

function ExpRepeat:OnSetMatchee()
    local clone = self.sub:Clone()
    clone:SetMatchee(self.matchee, self.pos)
    self.stack = { {clone, self.pos} }
end

function ExpRepeat:Clone()
    clone = new(classof(self), self.sub:Clone(), self.min, self.max)
    self:CloneCoreStateTo(clone)

    if self.stack then
        local cloneStack = {}
        for i,v in ipairs(self.stack) do
            local sub, pos = unpack(v)
            cloneStack[#cloneStack + 1] = {sub:Clone(), pos}
        end
        clone.stack = cloneStack
    end

    return clone
end

function ExpRepeat:IsFixedLength()
    if self.min == self.max then
        local b, len = self.sub:IsFixedLength()
        if b then
            return len * self.min
        end
    end

    return false
end

function ExpRepeat:OnNextMatch(submatches, flags)
    local stack = self.stack
    local max = self.max
    local isOK, nextPos

    while self.pos do
        local sub, pos

        while true do
            sub, pos = unpack(stack[#stack])
            isOK, nextPos = sub:NextMatch(submatches, flags)
            if isOK then
                if not max or #stack < max then
                    local clone = self.sub:Clone()
                    clone:SetMatchee(self.matchee, nextPos)
                    stack[#stack+1] = {clone, nextPos}
                else
                    break
                end
            else
                stack[#stack] = nil
                nextPos = pos
                break
            end
        end

        local iteration = #stack
        if iteration == 0 then
            self.pos = nil
        end

        if (self.min <= iteration)
        and (not self.max or iteration <= self.max)
        then
            return true, nextPos
        end
    end

    return false
end


--
-- expression A{a,b}?, which includes:
--     A*? = A{,}?
--     A+? = A{1,}?
--     A?? = A{,1}?
-- a,b when omitted are assumed to be 0 and infinity, respectively
--
local ExpVigorless = class(Expression)

function ExpVigorless:__init__(sub, min, max)
    self.sub = sub
    self.min = min or 0
    self.max = max
end

function ExpVigorless:OnSetMatchee()
    self.sub:SetMatchee(self.matchee, self.pos)
    self.queue    = nil
    self.curExp   = nil
    self.curDepth = 0
end

function ExpVigorless:Clone()
    clone = new(classof(self), self.sub:Clone(), self.min, self.max)
    self:CloneCoreStateTo(clone)

    if self.queue then
        local cloneQ = {}
        for i,v in ipairs(self.queue) do
            cloneQ[#cloneQ + 1] = v
        end
        clone.queue = cloneQ
    end

    clone.curExp   = self.curExp
    clone.curDepth = self.curDepth

    return clone
end

function ExpVigorless:IsFixedLength()
    if self.min == self.max then
        local b, len = self.sub:IsFixedLength()
        if b then
            return len * self.min
        end
    end

    return false
end

function ExpVigorless:OnNextMatch(submatches, flags)
    local min   = self.min
    local max   = self.max

    if not self.queue then
        self.queue = { {self.pos, 1} }
        if (min <= 0)
        and (not max or 0 <= max)
        then
            return true, self.pos
        end
    end

    local queue = self.queue

    while true do
        if self.curExp then
            isOK, nextPos = self.curExp:NextMatch(submatches, flags)
            if isOK then
                if not max or self.curDepth < max then
                    queue[#queue+1] = { nextPos, self.curDepth + 1 }
                end
                if (min <= self.curDepth)
                and (not max or self.curDepth <= max)
                then
                    return isOK, nextPos
                end
            else
                self.curExp = nil
            end
        elseif #queue > 0 then
            nextPos, self.curDepth = unpack(table.remove(queue, 1))
            local clone = self.sub:Clone()
            clone:SetMatchee(self.matchee, nextPos)
            self.curExp = clone
        else
            return false
        end
    end
end


--
-- expression (?=A), (?!A)
--
local ExpLookAhead = class(Expression)

function ExpLookAhead:__init__(sub, affirmative)
    self.sub = sub
    self.aff = affirmative
end

function ExpLookAhead:OnSetMatchee()
    self.sub:SetMatchee(self.matchee, self.pos)
end

function ExpLookAhead:Clone()
    clone = new(classof(self), self.sub:Clone())
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpLookAhead:IsFixedLength()
    return true, 0
end

function ExpLookAhead:OnNextMatch(submatches, flags)
    local isOK, nextPos = self.sub:NextMatch(submatches, flags)
    if (not self.aff) == (not isOK) then
        nextPos = self.pos
        self.pos = nil
        return true, nextPos
    end

    return false
end


--
-- expression (?<=A), (?<!A)
--
local ExpLookBack = class(Expression)

function ExpLookBack:__init__(sub, affirmative)
    local isFixed, len = sub:IsFixedLength()
    assert(isFixed)

    self.sub = sub
    self.len = len
    self.aff = affirmative
end

function ExpLookBack:OnSetMatchee()
    if self.len < self.pos then
        self.sub:SetMatchee(self.matchee, self.pos - self.len)
    else
        self.sub:SetMatchee(nil, nil)
    end
end

function ExpLookBack:Clone()
    clone = new(classof(self), self.sub:Clone())
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpLookBack:IsFixedLength()
    return true, 0
end

function ExpLookBack:OnNextMatch(submatches, flags)
    local isOK, nextPos = self.sub:NextMatch(submatches, flags)
    if (not self.aff) == (not isOK) then
        nextPos = self.pos
        self.pos = nil
        return true, nextPos
    end

    return false
end


--
-- expression (?(NAME)A|B)
--    "|B" can be omitted
--

local ExpConditional = class(Expression)

function ExpConditional:__init__(refname, sub1, sub2)
    self.refname = refname
    self.sub1 = sub1
    self.sub2 = sub2
end

function ExpConditional:OnSetMatchee()
    self.sub1:SetMatchee(self.matchee, self.pos)
    if self.sub2 then
        self.sub2:SetMatchee(self.matchee, self.pos)
    end
end

function ExpConditional:Clone()
    local cloneSub1 = self.sub1:Clone()
    local cloneSub2
    if self.sub2 then
        cloneSub2 = self.sub2:Clone()
    end

    clone = new(classof(self), self.refname, cloneSub1, cloneSub2)
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpConditional:IsFixedLength()
    local b, len1 = self.sub1:IsFixedLength()
    if b then
        if self.sub2 then
            local len2
            b, len2 = self.sub2:IsFixedLength()
            if b and len1 == len2 then
                return true, len1
            end
        elseif len1 == 0 then
            return true, 0
        end
    end

    return false
end

function ExpConditional:OnNextMatch(submatches, flags)
    if submatches[self.refname] then
        return self.sub1:NextMatch(submatches, flags)
    elseif self.sub2 then
        return self.sub2:NextMatch(submatches, flags)
    else
        local pos = self.pos
        self.pos = nil
        return true, pos
    end
end


--
-- expression (?P=NAME)
--

local ExpReference = class(Expression)

function ExpReference:__init__(refname)
    self.refname = refname
end

function ExpReference:Clone()
    clone = new(classof(self), self.refname)
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpReference:IsFixedLength()
    return false
end

function ExpReference:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    local refRange = submatches[self.refname]
    if refRange then
        local refBeg, refEnd = unpack(refRange)
        local len = refEnd - refBeg
        if self.matchee:sub(pos, pos + len - 1) == self.matchee:sub(refBeg, refEnd-1) then
            return true, pos + len
        else
            return false
        end
    else
        return true, pos
    end
end


--
-- expression that matches just one char
--
local ExpOneChar = class(Expression)

function ExpOneChar:__init__(fnIsMatch)
    -- fnIsMatch(char:byte()) -> bool
    self.fnIsMatch = fnIsMatch
end

function ExpOneChar:Clone()
    clone = new(classof(self), self.fnIsMatch)
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpOneChar:IsFixedLength()
    return true, 1
end

function ExpOneChar:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    if pos > #self.matchee then return false end

    if self.fnIsMatch(self.matchee:byte(pos)) then
        return true, pos + 1
    else
        return false
    end
end


--
-- expression ^
--
local ExpLineBegin = class(Expression)

function ExpLineBegin:Clone()
    clone = new(classof(self))
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpLineBegin:IsFixedLength()
    return true, 0
end

function ExpLineBegin:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    -- ^ matches even a null string
    if pos == 1 then
        return true, pos
    end

    if self.matchee:sub(pos-1, pos-1) == '\n' then
        return true, pos
    end

    return false
end


--
-- expression $
--
local ExpLineEnd = class(Expression)

function ExpLineEnd:Clone()
    clone = new(classof(self))
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpLineEnd:IsFixedLength()
    return true, 0
end

function ExpLineEnd:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    -- $ matches even a null string
    if pos == #self.matchee + 1 then
        return true, pos
    end

    if self.matchee:sub(pos, pos) == '\n' then
        return true, pos
    end

    return false
end


--
-- expression \A
--
local ExpBegin = class(Expression)

function ExpBegin:Clone()
    clone = new(classof(self))
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpBegin:IsFixedLength()
    return true, 0
end

function ExpBegin:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    -- ^ matches even a null string
    if pos == 1 then
        return true, pos
    end

    return false
end


--
-- expression \Z
--
local ExpEnd = class(Expression)

function ExpEnd:Clone()
    clone = new(classof(self))
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpEnd:IsFixedLength()
    return true, 0
end

function ExpEnd:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    -- $ matches even a null string
    if pos == #self.matchee + 1 then
        return true, pos
    end

    return false
end


--
-- expression \b
--
local ExpBorder = class(Expression)

function ExpBorder:Clone()
    clone = new(classof(self))
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpBorder:IsFixedLength()
    return true, 0
end

function ExpBorder:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    if self:IsWordAt(pos-1) ~= self:IsWordAt(pos) then
        return true, pos
    end

    return false
end

function ExpBorder:IsWordAt(pos)
    if pos <= 0 then return false end
    local value = self.matchee:byte(pos)
    if not value then return false end

    local zero, nine, A, Z, a, z, ubar = ("09AZaz_"):byte(1,7)
    return (zero <= value and value <= nine)
        or (A <= value and value <= Z)
        or (a <= value and value <= z)
        or value == ubar
end


--
-- expression \B
--
local ExpNegBorder = class(ExpBorder)

function ExpNegBorder:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    if self:IsWordAt(pos-1) == self:IsWordAt(pos) then
        return true, pos
    end

    return false
end


--
-- expression that matches a terminal string
--
local ExpTerminals = class(Expression)

function ExpTerminals:__init__(str)
    self.str     = str
end

function ExpTerminals:Clone()
    clone = new(classof(self), self.str)
    self:CloneCoreStateTo(clone)
    return clone
end

function ExpTerminals:IsFixedLength()
    return true, #self.str
end

function ExpTerminals:OnNextMatch(submatches, flags)
    local pos = self.pos
    self.pos = nil

    local len = #self.str

    if self.matchee:sub(pos, pos + len - 1) == self.str then
        return true, pos + len
    else
        return false
    end
end


-----------------------------------------------------------------------------
-- Parser to compile regex-string to expression-tree

local Parser = class()

function Parser:__init__(regex, flags)
    self.regex = regex
    self.flags  = flags
    self.nextCapture = 1

    local expOr, nextPos = self:GetExpOr(1)

    if not expOr then
        return
    end

    if nextPos ~= #regex + 1 then
        if not self.errMsg then
            self.errMsg = "cannot compile"
            self.errPos = nextPos
        end
        return
    end

    self.errMsg = nil
    self.errPos = nil
    self.exp    = expOr
end

function Parser:Error()
    return self.errMsg, self.errPos
end

function Parser:Expression()
    return self.exp
end

function Parser:GetExpOr(pos)
    local expOr, nextPos = self:GetExpPair(pos)
    if not expOr then return nil end

    local expPair
    while self.regex:sub(nextPos,nextPos) == '|' do
        expPair, nextPos = self:GetExpPair(nextPos + 1)
        if not expPair then return nil end

        expOr = new(ExpOr, expOr, expPair)
    end

    return expOr, nextPos
end

function Parser:GetExpPair(pos)
    local expPair, nextPos = self:GetExpRepeat(pos)
    if not expPair then
        return new(ExpTerminals, ""), pos
    end

    pos = nextPos
    local expRepeat
    while true do
        expRepeat, nextPos = self:GetExpRepeat(pos)
        if not expRepeat then
            return expPair, pos
        end

        expPair = new(ExpPair, expPair, expRepeat)
        pos     = nextPos
    end
end

function Parser:GetExpRepeat(pos)
    local expRepeat, nextPos = self:GetExpPrimary(pos)
    if not expRepeat then return nil end

    pos = nextPos
    local repeater
    while true do
        repeater, nextPos = self:GetRepeater(pos)
        if not repeater then
            return expRepeat, pos
        end

        local clsExp
        if self.regex:sub(nextPos, nextPos) == '?' then
            clsExp = ExpVigorless
            nextPos = nextPos + 1
        else
            clsExp = ExpRepeat
        end

        local min    = repeater.min
        local max    = repeater.max

        expRepeat = new(clsExp, expRepeat, min, max)
        pos       = nextPos
    end
end

function Parser:GetExpPrimary(pos)
    local regex = self.regex

    if regex:sub(pos,pos) == '(' then
        pos = pos+1

        local subExp, nextPos

        if regex:sub(pos,pos) == '?' then
            pos = pos+1

            if regex:sub(pos,pos) == ':' then
                subExp, nextPos = self:GetUnnamedGroup(pos+1)
            elseif regex:sub(pos,pos+1) == 'P<' then
                subExp, nextPos = self:GetUserNamedGroup(pos+2)
            elseif regex:sub(pos,pos+1) == 'P=' then
                subExp, nextPos = self:GetUserNamedRef(pos+2)
            elseif regex:sub(pos,pos) == '=' then
                subExp, nextPos = self:GetLookAhead(pos+1)
            elseif regex:sub(pos,pos) == '!' then
                subExp, nextPos = self:GetNegLookAhead(pos+1)
            elseif regex:sub(pos,pos+1) == '<=' then
                subExp, nextPos = self:GetLookBack(pos+2)
            elseif regex:sub(pos,pos+1) == '<!' then
                subExp, nextPos = self:GetNegLookBack(pos+2)
            elseif regex:sub(pos,pos) == '(' then
                subExp, nextPos = self:GetConditional(pos+1)
            else
                self.errMsg = "invalid char"
                self.errPos = pos
                return nil
            end
        else
            subExp, nextPos = self:GetNamedGroup(pos)
        end

        if not subExp then return nil end

        if self.regex:sub(nextPos,nextPos) == ')' then
            return subExp, nextPos+1
        else
            self.errMsg = ") expected"
            self.errPos = nextPos
            return nil
        end
    end

    local subExp, nextPos = self:GetCharClass(pos)
    if subExp then
        return subExp, nextPos
    end

    subExp, nextPos = self:GetNonTerminal(pos)
    if subExp then
        return subExp, nextPos
    end

    subExp, nextPos = self:GetTerminalStr(pos)
    if subExp then
        return subExp, nextPos
    end

    return nil
end

function Parser:GetUnnamedGroup(pos)
    return self:GetExpOr(pos)
end

function Parser:GetUserNamedGroup(pos)
    local name, nextPos = self:GetIdentifier(pos)
    if not name then return nil end

    if self.regex:sub(nextPos,nextPos) ~= '>' then
        self.errMsg = "> expected"
        self.errPos = nextPos
        return nil
    end

    local expOr
    expOr, nextPos = self:GetExpOr(nextPos + 1)
    if expOr then
        expOr:SetName(name)
    end

    return expOr, nextPos
end

function Parser:GetUserNamedRef(pos)
    local name, nextPos = self:GetName(pos)
    if not name then return nil end

    return new(ExpReference, name), nextPos
end

function Parser:GetLookAhead(pos)
    local expOr, nextPos = self:GetExpOr(pos)
    if expOr then
        expOr = new(ExpLookAhead, expOr, true)
    end

    return expOr, nextPos
end

function Parser:GetNegLookAhead(pos)
    local expOr, nextPos = self:GetExpOr(pos)
    if expOr then
        expOr = new(ExpLookAhead, expOr, false)
    end

    return expOr, nextPos
end

function Parser:GetLookBack(pos)
    local expOr, nextPos = self:GetExpOr(pos)
    if not expOr then return nil end

    if not expOr:IsFixedLength() then
        self.errMsg = "length must be fixed"
        self.errPos = pos+1
        return nil
    end

    return new(ExpLookBack, expOr, true), nextPos
end

function Parser:GetNegLookBack(pos)
    local expOr, nextPos = self:GetExpOr(pos)
    if not expOr then return nil end

    if not expOr:IsFixedLength() then
        self.errMsg = "length must be fixed"
        self.errPos = pos+1
        return nil
    end

    return new(ExpLookBack, expOr, false), nextPos
end

function Parser:GetConditional(pos)
    local name, nextPos = self:GetName(pos)
    if not name then return nil end

    if self.regex:sub(nextPos,nextPos) ~= ')' then
        self.errMsg = ") expected"
        self.errPos = nextPos
        return nil
    end

    local exp1
    exp1, nextPos = self:GetExpPair(nextPos + 1)
    if not exp1 then return nil end

    local exp2
    if self.regex:sub(nextPos,nextPos) == '|' then
        exp2, nextPos = self:GetExpPair(nextPos + 1)
        if not exp2 then return nil end
    end

    return new(ExpConditional, name, exp1, exp2), nextPos
end

function Parser:GetNamedGroup(pos)
    local id = self.nextCapture
    self.nextCapture = self.nextCapture + 1

    local expOr, nextPos = self:GetExpOr(pos)
    if expOr then
        expOr:SetName(id)
    else
        -- restore 'nextCapture'
        self.nextCapture = id
    end

    return expOr, nextPos
end

function Parser:GetRepeater(pos)
    local regex = self.regex

    if pos > #regex then return nil end
    local c = regex:sub(pos, pos)

    if c == '*' then
        return {}, pos+1
    end
    if c == '+' then
        return {["min"] = 1}, pos+1
    end
    if c == '?' then
        return {["max"] = 1}, pos+1
    end
    if c ~= '{' then
        return nil
    end

    pos = pos + 1
    local min, max, nextPos

    min, nextPos = self:GetNumber(pos)
    if min then
        pos = nextPos
    end

    c = regex:sub(pos, pos)
    if c == '' or (c ~= ',' and c ~= '}') then
        self.errMsg = ", or } expected"
        self.errPos = pos
        return nil
    end

    if not min and c == '}' then
        self.errMsg = "iteration number expected"
        self.errPos = pos
        return nil
    end

    pos = pos + 1

    if c == ',' then
        max, nextPos = self:GetNumber(pos)
        if max then
            pos = nextPos
        end

        c = regex:sub(pos, pos)
        if c == '' or c ~= '}' then
            self.errMsg = "} expected"
            self.errPos = pos
            return nil
        end

        pos = pos + 1
    else
        max = min
    end

    return {["min"] = min, ["max"] = max}, pos
end

function Parser:GetCharClass(pos)
    local regex = self.regex
    if regex:sub(pos,pos) ~= '[' then
        return nil
    end

    pos = pos+1

    local affirmative
    if regex:sub(pos,pos) == '^' then
        affirmative = false
        pos = pos+1
    else
        affirmative = true
    end

    local fnIsMatch, nextPos = self:GetUserCharClass(pos)
    if not fnIsMatch then return nil end

    if regex:sub(nextPos,nextPos) ~= ']' then
        self.errMsg = "] expected"
        self.errPos = nextPos
        return nil
    end

    local fn
    if affirmative then
        fn = fnIsMatch
    else
        fn = function(c) return not fnIsMatch(c) end
    end

    return new(ExpOneChar, fn), nextPos+1
end

function Parser:GetUserCharClass(pos)
    local fnIsMatch, nextPos = self:GetUserCharRange(pos)
    if not fnIsMatch then
        self.errMsg = "empty class not allowed"
        self.errPos = pos
        return nil
    end

    local aFn = { fnIsMatch }

    pos = nextPos
    while true do
        -- the following 'local' is mandatory
        local fnIsMatch, nextPos = self:GetUserCharRange(pos)
        if not fnIsMatch then
            local fn = function(c)
                for i,v in ipairs(aFn) do
                    if v(c) then return true end
                end
                return false
            end
            return fn, pos
        end

        aFn[#aFn+1] = fnIsMatch
        pos         = nextPos
    end
end

function Parser:GetUserCharRange(pos)
    local char1, nextPos = self:GetUserChar(pos)
    if not char1 then return nil end

    if self.regex:sub(nextPos,nextPos) ~= '-' then
        return function(c) return c == char1 end, nextPos
    end

    pos = nextPos + 1

    local char2, nextPos = self:GetUserChar(pos)
    if char2 then
        return function(c) return char1 <= c and c <= char2 end, nextPos
    else
        char2 = ('-'):byte()
        return function(c) return char1 == c or c == char2 end, pos
    end
end

function Parser:GetUserChar(pos)
    local value, nextPos = self:GetClassEscSeq(pos)
    if value then
        return value, nextPos
    end

    local c = self.regex:sub(pos, pos)
    if c ~= '' and c ~= '\\' and c ~= ']' then
        return c:byte(), pos + 1
    else
        return nil
    end
end

function Parser:GetClassEscSeq(pos)
    local value, nextPos = self:GetTermEscSeq(pos)
    if value then
        return value, nextPos
    end

    if self.regex:sub(pos,pos+1) == "\\b" then
        return 0x08, pos+2
    else
        return nil
    end
end

function Parser:GetNonTerminal(pos)
    local regex = self.regex
    local c = regex:sub(pos,pos)
    if c == '^' then
        return new(ExpLineBegin), pos+1
    end
    if c == '$' then
        return new(ExpLineEnd), pos+1
    end
    if c == '.' then
        local nl = ('\n'):byte()
        return new(ExpOneChar, function(c) return c ~= nl end), pos+1
    end
    if c ~= '\\' then
        return nil
    end

    local zero, nine, A, Z, a, z, ubar = ("09AZaz_"):byte(1,7)
    local ff, nl, cr, ht, vt, ws = ("\f\n\r\t\v "):byte(1,6)

    c = regex:sub(pos+1, pos+1)
    if c == 'd' then
        local fn = function(c) return zero <= c and c <= nine end
        return new(ExpOneChar, fn), pos+2
    end
    if c == 'D' then
        local fn = function(c) return not(zero <= c and c <= nine) end
        return new(ExpOneChar, fn), pos+2
    end
    if c == 's' then
        local fn = function(c)
            -- check it in the order of likeliness
            return c == ws or c == nl or c == ht
                or c == cr or c == vt or c == ff
        end
        return new(ExpOneChar, fn), pos+2
    end
    if c == 'S' then
        local fn = function(c)
            -- check it in the order of likeliness
            return not(c == ws or c == nl or c == ht
                or c == cr or c == vt or c == ff
            )
        end
        return new(ExpOneChar, fn), pos+2
    end
    if c == 'w' then
        local fn = function(c)
            return (a <= c and c <= z)
                or (A <= c and c <= Z)
                or (zero <= c and c <= nine)
                or c == ubar
        end
        return new(ExpOneChar, fn), pos+2
    end
    if c == 'W' then
        local fn = function(c)
            return not(
                (a <= c and c <= z)
                or (A <= c and c <= Z)
                or (zero <= c and c <= nine)
                or c == ubar
            )
        end
        return new(ExpOneChar, fn), pos+2
    end
    if c == 'A' then
        return new(ExpBegin), pos+2
    end
    if c == 'b' then
        return new(ExpBorder), pos+2
    end
    if c == 'B' then
        return new(ExpNegBorder), pos+2
    end
    if c == 'Z' then
        return new(ExpEnd), pos+2
    end

    local value, nextPos = self:GetNumber(pos+1)
    if value then
        return new(ExpReference, value), nextPos
    end

    self.errMsg = "invalid escape sequence"
    self.errPos = pos
    return nil
end

function Parser:GetTerminalStr(pos)
    local value, nextPos = self:GetTerminal(pos)
    if not value then return nil end

    local list = { value }
    pos = nextPos

    while true do
        value, nextPos = self:GetTerminal(pos)
        if not value then
            local exp = new(ExpTerminals,
                self.regex.char(unpack(list))
            )
            return exp, pos
        end

        list[#list+1] = value
        pos = nextPos
    end
end

local g_nonTerminal_Parser_GetTerminal = {
    [('^'):byte()] = true,
    [('$'):byte()] = true,
    [('\\'):byte()] = true,
    [('|'):byte()] = true,
    [('['):byte()] = true,
    [(']'):byte()] = true,
    [('{'):byte()] = true,
    [('}'):byte()] = true,
    [('('):byte()] = true,
    [(')'):byte()] = true,
    [('*'):byte()] = true,
    [('+'):byte()] = true,
    [('?'):byte()] = true,
}
function Parser:GetTerminal(pos)
    local value, nextPos = self:GetTermEscSeq(pos)
    if value then
        return value, nextPos
    end

    value = self.regex:byte(pos,pos)
    if not value then return nil end

    local nonTerminal = g_nonTerminal_Parser_GetTerminal
    if nonTerminal[value] then return nil end

    return value, pos+1
end

local g_entity_Parser_GetTermEscSeq = {
    [('a'):byte()] = 0x07,
    [('f'):byte()] = 0x0c,
    [('n'):byte()] = 0x0a,
    [('r'):byte()] = 0x0d,
    [('t'):byte()] = 0x09,
    [('v'):byte()] = 0x0b,
    [('!'):byte()] = ('!'):byte(),
    [('"'):byte()] = ('"'):byte(),
    [('#'):byte()] = ('#'):byte(),
    [('$'):byte()] = ('$'):byte(),
    [('%'):byte()] = ('%'):byte(),
    [('&'):byte()] = ('&'):byte(),
    [("'"):byte()] = ("'"):byte(),
    [('('):byte()] = ('('):byte(),
    [(')'):byte()] = (')'):byte(),
    [('*'):byte()] = ('*'):byte(),
    [('+'):byte()] = ('+'):byte(),
    [(','):byte()] = (','):byte(),
    [('-'):byte()] = ('-'):byte(),
    [('.'):byte()] = ('.'):byte(),
    [('/'):byte()] = ('/'):byte(),
    [(':'):byte()] = (':'):byte(),
    [(';'):byte()] = (';'):byte(),
    [('<'):byte()] = ('<'):byte(),
    [('='):byte()] = ('='):byte(),
    [('>'):byte()] = ('>'):byte(),
    [('?'):byte()] = ('?'):byte(),
    [('@'):byte()] = ('@'):byte(),
    [('['):byte()] = ('['):byte(),
    [('\\'):byte()] =('\\'):byte(),
    [(']'):byte()] = (']'):byte(),
    [('^'):byte()] = ('^'):byte(),
    [('_'):byte()] = ('_'):byte(),
    [('`'):byte()] = ('`'):byte(),
    [('{'):byte()] = ('{'):byte(),
    [('|'):byte()] = ('|'):byte(),
    [('}'):byte()] = ('}'):byte(),
    [('~'):byte()] = ('~'):byte(),
}
function Parser:GetTermEscSeq(pos)
    local regex = self.regex
    if regex:sub(pos,pos) ~= '\\' then return nil end

    local entity = g_entity_Parser_GetTermEscSeq
    local c = regex:byte(pos+1)
    local value = entity[c]
    if value then
        return value, pos+2
    end

    if c == ('x'):byte() then
        value, nextPos = self:GetHexNumber(pos+2, 2)
        if not value then
            self.errMsg = "hexadecimal number expected"
            self.errPos = pos+2
            return nil
        end
        return value, nextPos
    end

    self.errMsg = "invalid escape sequence"
    self.errPos = pos

    return nil
end

function Parser:GetName(pos)
    local name, nextPos = self:GetIdentifier(pos)
    if name then
        return name, nextPos
    end

    name, nextPos = self:GetNumber(pos)
    if name then
        return name, nextPos
    end

    return nil
end

function Parser:GetIdentifier(pos)
    local regex = self.regex
    local zero, nine, A, Z, a, z, bar = ('09AZaz_'):byte(1,7)

    local value
    local c = regex:byte(pos)
    if not c then return nil end

    if (A <= c and c <= Z)
        or (a <= c and c <= z)
        or c == bar
    then
        value = { c }
    else
        return nil
    end

    local nextPos = pos + 1
    while true do
        c = regex:byte(nextPos)
        if not c then
            break
        end
        if (A <= c and c <= Z)
            or (a <= c and c <= z)
            or (zero <= c and c <= nine)
            or c == bar
        then
            value[#value + 1] = c
            nextPos = nextPos + 1
        else
            break
        end
    end

    return regex.char(unpack(value)), nextPos
end

function Parser:GetNumber(pos)
    local regex = self.regex
    local zero, nine = ('09'):byte(1,2)

    local nextPos = pos
    local value  = 0
    while true do
        local digit = regex:byte(nextPos)
        if not digit then
            break
        end
        if not (zero <= digit and digit <= nine) then
            break
        end
        value = 10*value + (digit - zero)
        nextPos = nextPos + 1
    end

    if pos == nextPos then return nil end

    return value, nextPos
end

function Parser:GetHexNumber(pos, maxDigits)
    local regex = self.regex
    local zero, nine, A, F, a, f = ('09AFaf'):byte(1,6)

    local nextPos = pos
    local value  = 0
    local i = 0
    while not maxDigits or i < maxDigits do
        local digit = regex:byte(nextPos)
        if not digit then
            break
        end
        if zero <= digit and digit <= nine then
            value = 16*value + (digit - zero)
        elseif A <= digit and digit <= F then
            value = 16*value + (digit - A + 10)
        elseif a <= digit and digit <= f then
            value = 16*value + (digit - a + 10)
        else
            break
        end

        nextPos = nextPos + 1
        i = i + 1
    end

    if pos == nextPos then return nil end

    return value, nextPos
end


--------------------------------------------------------------------------
-- Match class (represents submatches)

local Match = class()

function Match:__init__(matchee, submatches)
    self.matchee    = matchee
    self.submatches = submatches
end

-- function Match:expand(format) end
--  This is defined later (to use Regex)

function Match:group(...)
    -- /(a)(b)(c)/ matching "abc", then
    --  group(0,1,2,3) returns "abc", "a", "b", "c"
    -- group() is equivalent to group(0)

    local args = {...}
    if #args == 0 then args = { 0 } end

    local matchee    = self.matchee
    local submatches = self.submatches
    local groups = {}

    for i = 1, #args do
        local name = args[i]
        local span = submatches[name]
        if span then
            local b,e = unpack(span)
            groups[i] = matchee:sub(b,e-1)
        end
    end

    return unpack(groups)
end

function Match:span(groupId)
    -- Returns index pair (begin, end) of group 'groupId'.
    -- Note 'end' is one past the end.

    groupId = groupId or 0

    local span = self.submatches[groupId]
    if span then
        return unpack(span)
    else
        return nil
    end
end


--------------------------------------------------------------------------
-- Regex class
--
local Regex = class()
Regex.__regex__ = true -- type marker

function Regex:__init__(regex, flags)
    local parser = new(Parser, regex, flags)
    local exp = parser:Expression()
    if exp == nil then
        msg, pos = parser:Error()
        error(("regex at %d: %s"):format(pos, msg))
    end

    self.exp   = exp
    self.flags = flags
end

function Regex:match(str, pos)
    if not pos then
        pos = 1
    elseif pos < 0 then
        pos = #str - (pos + 1)
    end

    if pos < 0 then
        pos = 1
    end

    local submatches = {}

    self.exp:SetMatchee(str, pos)
    isOK, nextPos = self.exp:NextMatch(submatches, self.flags)

    if not isOK then return nil end

    submatches[0] = {pos, nextPos}
    return new(Match, str, submatches)
end

function Regex:search(str, pos)
    if not pos then
        pos = 1
    elseif pos < 0 then
        pos = #str - (pos + 1)
    end

    if pos < 0 then
        pos = 1
    end

    for p = pos, #str do
        local match = self:match(str, p)
        if match then return match end
    end

    return nil
end

function Regex:sub(repl, str, count)
    if count and count <= 0 then return str, 0 end

    local isFunc
    if type(repl) == "function" then
        isFunc = true
    else
        local meta = getmetatable(repl)
        if meta and meta.__call then
            isFunc = true
        end
    end

    local list = {}
    local nRepl = 0
    local prevPos = 1
    for match in self:finditer(str) do
        local curBeg, curEnd = match:span()
        list[#list+1] = str:sub(prevPos,curBeg-1)

        local r
        if isFunc then
            r = repl(match)
            if r then
                r = tostring(r)
            else
                r = ""
            end
        else
            r = match:expand(repl)
        end

        list[#list+1] = r
        prevPos = curEnd

        nRepl = nRepl + 1
        if count and count <= nRepl then break end
    end

    list[#list+1] = str:sub(prevPos,-1)

    return table.concat(list), nRepl
end

function Regex:findall(str, pos)
    local list = {}
    for match in self:finditer(str, pos) do
        list[#list+1] = match
    end

    return list
end

function Regex:finditer(str, pos)
    pos = pos or 1

    local match = {
        ["matchee"] = str,
        ["span"] = function() return nil, pos end
    }
    return self.__finditer, self, match
end

function Regex:__finditer(match)
    local prevBeg, prevEnd = match:span(0)
    if prevBeg == prevEnd then
        prevEnd = prevEnd + 1
    end
    return self:search(match.matchee, prevEnd)
end


-- additional method of Match
local g_regex_Match_expand =
    new(Regex, [[\\(?:(\d+)|g<(?:(\d+)|([A-Za-z_][A-Za-z0-9_]*))>|[xX]([0-9a-fA-F]{1,2})|([abfnrtv\\]))]])
function Match:expand(format)
    -- Replaces \number, \g<number>, \g<name>
    --   to the corresponding groups
    -- Also \a, \b, \f, \n, \r, \t, \v, \x## are recognized

    local regex   = g_regex_Match_expand

    local function replace(match)
        local group = match:group(1) or match:group(2)
        if group then
            local id = tonumber(group, 10)
            return self:group(id)
        end

        group = match:group(3)
        if group then
            return self:group(group)
        end

        group = match:group(4)
        if group then
            return match.matchee.char(tonumber("0x" .. group))
        end

        group = match:group(5)
        if     group == 'a' then return '\a'
        elseif group == 'b' then return '\b'
        elseif group == 'f' then return '\f'
        elseif group == 'n' then return '\n'
        elseif group == 'r' then return '\r'
        elseif group == 't' then return '\t'
        elseif group == 'v' then return '\v'
        elseif group == '\\' then return '\\'
        end
    end

    return (regex:sub(replace, format))
end

-- Main RegExp class
function RegExp.compile(regex, flags)
    return new(Regex, regex, flags)
end

function RegExp.match(regex, str, pos, flags)
    return self.__getRegex(regex, flags):match(str, pos)
end

function RegExp.search(regex, str, pos, flags)
    return self.__getRegex(regex, flags):search(str, pos)
end

function RegExp.sub(regex, repl, str, count, flags)
    return self.__getRegex(regex, flags):sub(repl, str, count)
end

function RegExp.findall(regex, str, pos, flags)
    return self.__getRegex(regex, flags):findall(str, pos)
end

function RegExp.finditer(regex, str, pos, flags)
    return self.__getRegex(regex, flags):finditer(str, pos)
end

function RegExp.__getRegex(regex, flags)
    if regex.__regex__ then
        return regex
    else
        return self.__compile(regex, flags)
    end
end

function RegExp.__compile(regex, flags)
    local sourceCache = g_sourceCache_re
    local objectCache = g_objectCache_re

    local obj = objectCache[regex]
    if obj then
        -- flags must be considered:
        -- anyway, flags does not work for now

        local theI = 0
        for i,v in ipairs(sourceCache) do
            if v == regex then
                theI = i
                break
            end
        end
        if theI > 1 then
            for i = theI, 2, -1  do
                sourceCache[i] = sourceCache[i-1]
            end
            sourceCache[1] = regex
        end
        return obj
    end

    obj = self.compile(regex, flags)
    local cacheSize = self.cacheSize

    local size = #sourceCache
    while cacheSize <= size do
        local name = sourceCache[size]
        sourceCache[size] = nil
        objectCache[name] = nil
        size = size - 1
    end

    table.insert(sourceCache, 1, regex)
    objectCache[regex] = obj

    return obj
end
return RegExp
--Apollo.RegisterPackage(RegExp, PkgMajor, PkgMinor, {})