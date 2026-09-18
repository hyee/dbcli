--[[--
  flamegraph.lua    flame stack grapher (dbcli Lua port of flamegraph.pl).

  This takes stack samples and renders a call graph, allowing hot functions
  and codepaths to be quickly identified.

  USAGE: flamegraph.lua [options] infile > graph.svg   (or via env.flamegraph.BuildGraph)

  Then open the resulting .svg in a web browser, for interactivity: mouse-over
  frames for info, click to zoom, and ctrl-F to search (ctrl-I toggles
  case-insensitive search). The zoom/search state is stored in the URL query
  (?x= &y= &s=) so a graph can be shared in a zoomed/filtered state.

  The input is stack frames and sample counts formatted as single lines.  Each
  frame in the stack is semicolon separated, with a space and count at the end
  of the line. Example input:

   swapper;start_kernel;rest_init;cpu_idle;default_idle;native_safe_halt 1

  An optional extra column of counts can be provided to generate a differential
  flame graph of the counts, colored red for more, and blue for less.

  The input functions can optionally have annotations at the end of each
  function name (Linux perf's precedent):
      _[k] for kernel
      _[i] for inlined
      _[j] for jit
      _[w] for waker
  They are used merely for colors by some palettes, eg, --colors=java.

  Palettes (--colors): hot (default), mem, io, wakeup, chain, java, js, perl,
  red, green, blue, aqua, yellow, purple, orange, teal, pink, lime, brown,
  steel, gold, grey, oracle.

  The "oracle" palette classifies Oracle server kernel layers by their C
  function prefix and gives each layer its own hue (ks=services/waits red,
  kc=cache orange, kd/ka=data gold, kt=transaction purple, q*/SQL=blue,
  kk/kx/ev/compile=teal, op/kp=program-interface green, PL/SQL p*/rp=pink,
  kg=generic lime, kj=RAC brown, skg/net=steel, non-Oracle=grey), so a flame
  graph instantly shows which Oracle kernel layer is burning the samples.
  Other palettes color randomly but DETERMINISTICALLY per function name (the
  same name keeps the same color across every flame graph, like the modern
  flamegraph.pl default); use --hash for the classic positional namehash and
  --random for truly random colors.

  HISTORY

  Lua port for dbcli (oradebug profile). Upstream sync point:
  https://github.com/brendangregg/FlameGraph commit 41fee1f (2024-10-21).

  Ported upstream fixes/features: deterministic per-name coloring
  (random_namehash), --random, namehash short-name crash, minwidth as a
  percentage of time, case-insensitive search (Ctrl-I / "ic" button), zoom &
  search state persisted in URL parameters, re-apply search after zoom/unzoom,
  faster update_text, --countname=samples low-count warning, --flamechart,
  multi-line --nameattr files, CRLF tolerant input, alphabetical frame
  ordering.

  Copyright 2016 Netflix, Inc.
  Copyright 2011 Joyent, Inc.  All rights reserved.
  Copyright 2011 Brendan Gregg.  All rights reserved.

  CDDL HEADER START

  The contents of this file are subject to the terms of the
  Common Development and Distribution License (the "License").
  You may not use this file except in compliance with the License.

  You can obtain a copy of the license at docs/cddl1.txt or
  http://opensource.org/licenses/CDDL-1.0.
  See the License for the specific language governing permissions
  and limitations under the License.

  When distributing Covered Code, include this CDDL HEADER in each
  file and include the License file at docs/cddl1.txt.
  If applicable, add the following below this CDDL HEADER, with the
  fields enclosed by brackets "[]" replaced with your own identifying
  information: Portions Copyright [yyyy] [name of copyright owner]

  CDDL HEADER END
]]--

local tonumber, type, print, table, string, error, math = tonumber, type, print, table, string, error, math
local unpack = table.unpack or unpack

local options = {
    encoding = nil,
    fonttype = "Verdana",
    imagewidth = 1200,          -- max width, pixels
    frameheight = 16,           -- max height is dynamic
    fontsize = 12,              -- base text size
    fontwidth = 0.59,           -- avg width relative to fontsize
    minwidth = 0.1,             -- min function width, pixels (or "x%" of time)
    nametype = "Function:",     -- what are the names in the data?
    countname = "samples",      -- what are the counts in the data?
    colors = "hot",             -- color theme
    bgcolors = "",              -- background color theme
    nameattrfile = nil,         -- file holding function attributes
    timemax = nil,              -- (override the) sum of the counts
    factor = 1,                 -- factor to scale counts by
    hash = 0,                   -- color by function name hash
    random = 0,                 -- color randomly
    palette = 0,                -- if we use consistent palettes (default off)
    pal_file = "palette.map",   -- palette map file name
    stackreverse = 0,           -- reverse stack order, switching merge end
    inverted = 0,               -- icicle graph
    flamechart = 0,             -- produce a flame chart (sort by time, do not merge stacks)
    negate = 0,                 -- switch differential hues
    titletext = "",             -- centered heading
    titledefault = "Flame Graph",   -- overwritten by --title
    titleinverted = "Icicle Graph", --   "    "
    searchcolor = "rgb(230,0,230)", -- color for search highlighting
    notestext = "",             -- embedded notes in SVG
    subtitletext = "",          -- second level title (optional)
    help = 0
}
local FlameGraph = {}

-- CLI options that take a value; everything else is a boolean flag.
local VALUE_OPTS = {
    encoding=1, fonttype=1, imagewidth=1, frameheight=1, fontsize=1, fontwidth=1,
    minwidth=1, nametype=1, countname=1, colors=1, bgcolors=1, nameattrfile=1,
    timemax=1, factor=1, pal_file=1, titletext=1, titledefault=1, titleinverted=1,
    searchcolor=1, notestext=1, subtitletext=1
}
-- long option -> options table key
local ALIAS = {
    title='titletext', subtitle='subtitletext', width='imagewidth', height='frameheight',
    total='timemax', notes='notestext', nameattr='nameattrfile', reverse='stackreverse',
    cp='palette', color='colors'
}
local NUMERIC_INT = { imagewidth=1, frameheight=1 }
local NUMERIC_NUM = { fontsize=1, fontwidth=1, factor=1 }

function FlameGraph.usage()
    return [[
    Usage  : flamegraph.lua [options] infile > <outfile>.svg
    Options:
        --title TEXT     # change title text
        --subtitle TEXT  # second level title (optional)
        --width NUM      # width of image (default 1200)
        --height NUM     # height of each frame (default 16)
        --minwidth NUM   # omit smaller functions. In pixels or use "%" for
                         # percentage of time (default 0.1 pixels)
        --fonttype FONT  # font type (default "Verdana")
        --fontsize NUM   # font size (default 12)
        --countname TEXT # count type label (default "samples")
        --nametype TEXT  # name type label (default "Function:")
        --colors PALETTE # hot (default), mem, io, wakeup, chain, java, js, perl,
                         # red, green, blue, aqua, yellow, purple, orange, teal,
                         # pink, lime, brown, steel, gold, grey, oracle
        --bgcolors COLOR # background colors. gradient choices are yellow
                         # (default), blue, green, grey; flat colors use "#rrggbb"
        --hash           # colors are keyed by function name hash
        --random         # colors are randomly generated (default: deterministic
                         # per function name, stable across graphs)
        --cp             # use consistent palette (palette.map)
        --reverse        # generate stack-reversed flame graph
        --inverted       # icicle graph
        --flamechart     # produce a flame chart (sort by time, do not merge stacks)
        --negate         # switch differential hues (blue<->red)
        --notes TEXT     # add notes comment in SVG (for debugging)
        --help           # this message

    Example: flamegraph.lua --title="Flame Graph: malloc()" trace.txt > graph.svg]]
end

function FlameGraph.GetOptions(argv)
    argv = argv or {}
    local i = 1
    while i <= #argv do
        local option = argv[i]
        i = i + 1
        if option:sub(1, 2) == '--' then
            local value
            option = option:sub(3)
            local eq = option:find('=', 1, true)
            if eq then
                value = option:sub(eq + 1)
                option = option:sub(1, eq - 1)
            end
            option = ALIAS[option] or option
            if value == nil then
                if VALUE_OPTS[option] and argv[i] and argv[i]:sub(1, 2) ~= '--' then
                    value = argv[i]
                    i = i + 1
                else
                    value = 1
                end
            end
            if NUMERIC_INT[option] or NUMERIC_NUM[option] then
                local n = tonumber(value)
                if not n then error("Invalid value for option '" .. option .. "': " .. tostring(value)) end
                if NUMERIC_INT[option] then n = math.floor(n + 0.5) end
                value = n
            end
            options[option] = value
        end
    end
    if options.help and options.help ~= 0 then print(FlameGraph.usage()) end
end

function FlameGraph.CheckOptions(a)
    -- internals
    a.ypad1 = a.fontsize * 3;      -- pad top, include title
    a.ypad2 = a.fontsize * 2 + 10; -- pad bottom, include labels
    a.ypad3 = a.fontsize * 2;      -- pad top, include subtitle (optional)
    a.xpad = 10;                   -- pad left and right
    a.framepad = 1;                -- vertical padding for frames
    a.Events = {};
    a.nameattr = {};

    -- normalize flags (0/nil/false all mean off; Lua treats 0 as true!)
    a.flamechart = (a.flamechart and a.flamechart ~= 0) or false
    a.inverted = (a.inverted and a.inverted ~= 0) or false
    a.stackreverse = (a.stackreverse and a.stackreverse ~= 0) or false
    a.negate = (a.negate and a.negate ~= 0) or false
    a.hash = (a.hash and a.hash ~= 0) or false
    a.random = (a.random and a.random ~= 0) or false
    a.palette = (a.palette and a.palette ~= 0) or false
    if a.encoding == '' then a.encoding = nil end
    -- --total may arrive as a string (upstream declares "total=s" and relies on
    -- perl's implicit numerification; lua must convert or the compare dies)
    a.timemax = a.timemax and tonumber(a.timemax) or nil

    if a.flamechart and a.titletext == "" then
        a.titletext = "Flame Chart";
    end

    if a.titletext == "" then
        if not a.inverted then
            a.titletext = a.titledefault;
        else
            a.titletext = a.titleinverted;
        end
    end

    -- validate minwidth: pixels or percentage of time
    local minwidth_f, minwidth_pct
    if type(a.minwidth) == 'number' then
        -- library callers pass a number; tostring() would mangle 1e-05 and friends
        minwidth_f, minwidth_pct = a.minwidth, false
    else
        local mw = tostring(a.minwidth ~= nil and a.minwidth or 0.1)
        local f = mw:match('^([%d%.]+)%%?$')
        if not f or not tonumber(f) then
            error("Value '" .. mw .. "' is invalid for minwidth, expected a float or float%")
        end
        minwidth_f = tonumber(f)
        minwidth_pct = mw:find('%%$') and true or false
    end
    a.minwidth_f, a.minwidth_pct = minwidth_f, minwidth_pct

    if a.nameattrfile then
        -- The name-attribute file format is a function name followed by a tab then
        -- a sequence of tab separated name=value pairs. One function per line.
        local attrfh = io.open(a.nameattrfile, 'r')
        if not attrfh then error("Can't read " .. a.nameattrfile .. "!\n"); end
        local text = attrfh:read('*a')
        attrfh:close()

        for line in text:gmatch('[^\r\n]+') do
            local funcname, attrtext = line:match('^%s*(%S+)%s*\t+(.+)')
            if not funcname then error("Invalid format in " .. a.nameattrfile); end
            local attrs = {}
            -- tab separated pairs; a value may itself contain spaces, so split
            -- on tabs and then on the FIRST '=' only (as upstream does)
            for attrpair in attrtext:gmatch('[^\t]+') do
                local attr, value = attrpair:match('^%s*([^=]-)%s*=%s*(.-)%s*$')
                if attr then attrs[attr] = value end
            end
            a.nameattr[funcname] = attrs
        end
    end

    if tostring(a.notestext):find('[<>]') then
        error "Notes string can't contain < or >"
    end

    if a.bgcolors == "" or a.bgcolors == nil then
        -- choose a default
        if a.colors == "mem" then
            a.bgcolors = "green";
        elseif ({io=1, wakeup=1, chain=1})[a.colors] then
            a.bgcolors = "blue";
        elseif ({red=1, green=1, blue=1, aqua=1, yellow=1, purple=1, orange=1,
                 teal=1, pink=1, lime=1, brown=1, steel=1, gold=1, grey=1,
                 oracle=1})[a.colors] then
            a.bgcolors = "grey";
        else
            a.bgcolors = "yellow";
        end
    end

    if a.bgcolors == "yellow" then
        a.bgcolor1, a.bgcolor2 = "#eeeeee", "#eeeeb0";   -- background color gradient
    elseif a.bgcolors == "blue" then
        a.bgcolor1, a.bgcolor2 = "#eeeeee", "#e0e0ff";
    elseif a.bgcolors == "green" then
        a.bgcolor1, a.bgcolor2 = "#eef2ee", "#e0ffe0";
    elseif a.bgcolors == "grey" then
        a.bgcolor1, a.bgcolor2 = "#f8f8f8", "#e8e8e8";
    elseif a.bgcolors:match('^#......$') then
        a.bgcolor1, a.bgcolor2 = a.bgcolors, a.bgcolors;
    else
        error("Unrecognized bgcolor option: " .. a.bgcolors)
    end
end

local function rgb(r, g, b)
    return ("rgb($r,$g,$b)"):gsub("%$(%w+)", {r=math.floor(r), g=math.floor(g), b=math.floor(b)});
end

FlameGraph.SVG = {}

function FlameGraph.SVG:new(class)
    self.class = class
    return self
end

function FlameGraph.SVG:header(w, h, encoding)
    encoding = encoding or options.encoding
    local enc_attr = ''
    if encoding and encoding ~= '' then
        enc_attr = (' encoding="' .. encoding .. '"')
    end
    self.svg = {}
    self.svg[1] = ([[
<?xml version="1.0"$encattr standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="$w" height="$h" onload="init(evt)" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<!-- Flame graph stack visualization. See https://github.com/brendangregg/FlameGraph for latest version, and http://www.brendangregg.com/flamegraphs.html for examples. -->
<!-- NOTES: $notestext -->]]):gsub("%$(%w+)", {w=w, h=h, encattr=enc_attr, notestext=options.notestext or ''})
end

function FlameGraph.SVG:include(content, depth)
    local indent = ('  '):rep(depth or 0)
    self.svg[#self.svg+1] = indent..content
end

function FlameGraph.SVG:colorAllocate(r, g, b)
    return rgb(r, g, b);
end

function FlameGraph.SVG:group_start(attr, depth)
    local tag, g_attr = 'g', {}

    if (attr.href) then
        -- default target=_top else links will open within SVG <object>
        tag = 'a'
        g_attr[#g_attr+1] = ([[xlink:href="%s"]]):format(attr.href)
        g_attr[#g_attr+1] = ([[target="%s"]]):format((attr.target or '')..'_top')
        g_attr[#g_attr+1] = attr.a_extra
    end
    for _, key in ipairs{'id', 'class'} do
        if attr[key] then g_attr[#g_attr+1] = ('%s="%s"'):format(key, attr[key]) end
    end
    g_attr[#g_attr+1] = attr.g_extra

    self:include(('<%s%s>'):format(tag, #g_attr > 0 and (' '..table.concat(g_attr, ' ')) or ''), depth)
    if attr.title then self:include(('<title>%s</title>'):format(attr.title), depth+1) end
end

function FlameGraph.SVG:group_end(attr, depth)
    self:include(attr.href and '</a>' or '</g>', depth)
end

function FlameGraph.SVG:filledRectangle(x1, y1, x2, y2, fill, extra, depth)
    local fmt = "%0.1f"
    -- upstream rounds x1/x2 first and derives the width from the rounded
    -- values; keep that so the output matches flamegraph.pl pixel for pixel
    x1, x2 = tonumber(fmt:format(x1)), tonumber(fmt:format(x2))
    local attrs = {
        w = fmt:format(x2-x1),
        h = fmt:format(y2-y1),
        x1 = fmt:format(x1),
        x2 = fmt:format(x2),
        y1 = fmt:format(y1),
        y2 = fmt:format(y2),
        extra = extra or '',
        fill = fill
    }
    self:include(('<rect x="$x1" y="$y1" width="$w" height="$h" fill="$fill" $extra />'):gsub("%$(%w+)", attrs), depth)
end

function FlameGraph.SVG:stringTTF(id, x, y, str, extra, depth)
    local attrs = {
        x = ("%0.2f"):format(x),
        y = ("%0.2f"):format(y),
        str = str,
        id = id and (('id="%s"'):format(id)) or '',
        extra = extra or ''
    }
    self:include(('<text $id x="$x" y="$y" $extra>$str</text>'):gsub("%$(%w+)", attrs), depth)
end

function FlameGraph.SVG:toSVG()
    return table.concat(self.svg, '\n')..'</svg>\n'
end

function FlameGraph.namehash(name)
    -- Generate a vector hash for the name string, weighting early over
    -- later characters. We want to pick the same colors for function
    -- names across different flame graphs. (mirrors upstream namehash)
    local vector, weight, max, mod = 0, 1, 1, 10;
    -- if module name present, trunc to 1st char
    name = name:gsub('.-%^', '', 1)
    for c in name:gmatch('.') do
        local i = math.fmod(string.byte(c), mod);
        vector = vector + (i/(mod-1)) * weight;
        mod = mod+1
        max = max+weight;
        weight = weight*0.7
        if mod > 12 then
            break
        end
    end
    return 1 - vector/max
end

local function name_checksum(name)
    -- Deterministic 32-bit rolling checksum (portable replacement for
    -- perl's unpack("%32W*") + srand): same name -> same value everywhere.
    local h = 0
    for i = 1, #name do
        h = (h*131 + string.byte(name, i)) % 4294967296
    end
    return h
end

function FlameGraph.random_namehash(name)
    -- Deterministic per-name value in [0,1). Same function name keeps the
    -- same color across all flame graphs without needing a palette file.
    return (name_checksum(name) % 1000000007)/1000000007
end

FlameGraph.palettes = {
    java = function(name)
        if name:find('_%[j%]$') then
            return "green"
        elseif name:find('_%[i%]$') then
            return "aqua"
        elseif name:find('^L?%a+/%w') then
            name = name:match('^L?([^/]+)')
            if ({java=1, javax=1, jdk=1, net=1, org=1, com=1, io=1, sun=1})[name] then
                return 'green'
            end
            return "yellow"
        elseif name:find(':::') then
            return "green"
        elseif name:find('::') then
            return "yellow"
        elseif name:find('_%[k%]$') then
            return "orange"
        end
        return "red"
    end,
    perl = function(name)
        if name:find('::') then
            return "yellow"
        elseif name:find('Perl', 1, true) or name:find('%.pl', 1, true) then
            return "green"
        elseif name:find('_%[k%]$') then
            return "orange"
        end
        return "red"
    end,
    js = function(name)
        if name:find('_%[j%]$') then
            return name:find('/', 1, true) and "green" or "aqua"
        elseif name:find('::') then
            return "yellow"
        elseif name:find('/.*%.js') then
            return "green"
        elseif name:find(':', 1, true) then
            return "aqua"
        elseif name:find('^ +$') then
            return "green"
        elseif name:find('_%[k%]', 1, true) then
            return "orange"
        end
        return "red"
    end,
    -- Oracle server kernel layer classification by C function prefix:
    -- a stack colored with this palette shows WHICH Oracle layer burns
    -- the samples (services/waits vs cache vs SQL engine vs PL/SQL ...).
    oracle = function(name)
        local n = name:lower()
        -- wait events and other descriptive labels (they contain spaces, C
        -- functions never do) get their own hue: they are the "why" of a wait
        -- profile, not a kernel layer.
        if name:find(' ') then return "brown" end
        -- non-Oracle (libc/pthread/loader) frames next
        if n:find('^__') or n:find('^_') or n:find('^main$') or n:find('^start_thread$')
            or n:find('^clon') or n:find('^read') or n:find('^writ') or n:find('^poll') or n:find('^epoll')
            or n:find('^select') or n:find('^sigtimedwait') or n:find('^sigwait') or n:find('^sem')
            or n:find('^futex') or n:find('^mmap') or n:find('^mprotect') or n:find('^munmap')
            or n:find('^open') or n:find('^close') or n:find('^ioctl') or n:find('^fsync') or n:find('^lseek')
            or n:find('^nanosleep') or n:find('^clock_') or n:find('^gettimeofday') or n:find('^getpid') then
            return "grey"
        end
        if n:find('^ks') then return "red"          -- kernel services: latch/wait/process/mem
        elseif n:find('^kc') then return "orange"   -- kernel cache: buffers/redo
        elseif n:find('^kd') or n:find('^ka') then return "gold"    -- kernel data/access path
        elseif n:find('^kt') then return "purple"   -- kernel transactions
        elseif n:find('^q') or n:find('^kq') or n:find('^ins') or n:find('^se')
            or n:find('^up') or n:find('^de') then return "blue"    -- SQL layer: parse/exec/DML
        elseif n:find('^kk') or n:find('^kx') or n:find('^ev') or n:find('^ex') or n:find('^ap') or n:find('^au')
            then return "teal"                      -- compile/cursor/optimizer/eval
        elseif n:find('^kp') or n:find('^op') or n:find('^so') or n:find('^oci') then return "green" -- program interface/OCI
        elseif n:find('^p') or n:find('^rp') or n:find('^rr') or n:find('^pe') then return "pink"    -- PL/SQL engine
        elseif n:find('^kg') then return "lime"     -- kernel generic: heap/library cache
        elseif n:find('^kj') then return "brown"    -- RAC lock management
        elseif n:find('^kz') then return "steel"    -- security
        elseif n:find('^k') then return "lime"      -- any other Oracle kernel layer
        elseif n:find('^sk') or n:find('^s') or n:find('^ns') or n:find('^nt') or n:find('^nio')
            or n:find('^npi') or n:find('^nx') then return "steel"  -- OS-dependent / network
        end
        return "grey"
    end,
    wakeup = function() return "aqua" end,
    chain  = function(name) return name:find('_[w]', 1, true) and "aqua" or "blue" end,
    red    = function(_, v1) return rgb(200+55*v1, 50+80*v1, 50+80*v1) end,
    green  = function(_, v1) return rgb(50+60*v1, 200+55*v1, 50+60*v1) end,
    blue   = function(_, v1) return rgb(205+50*v1, 205+50*v1, 80+60*v1) end,
    yellow = function(_, v1) return rgb(175+55*v1, 175+55*v1, 50+20*v1) end,
    purple = function(_, v1) return rgb(190+65*v1, 80+60*v1, 190+65*v1) end,
    aqua   = function(_, v1) return rgb(50+60*v1, 165+55*v1, 165+55*v1) end,
    orange = function(_, v1) return rgb(190+65*v1, 90+65*v1, 0) end,
    teal   = function(_, v1) return rgb(20+80*v1, 140+80*v1, 130+65*v1) end,
    pink   = function(_, v1) return rgb(210+45*v1, 70+70*v1, 120+80*v1) end,
    lime   = function(_, v1) return rgb(120+90*v1, 175+70*v1, 30+60*v1) end,
    brown  = function(_, v1) return rgb(140+80*v1, 80+70*v1, 25+55*v1) end,
    steel  = function(_, v1) return rgb(100+80*v1, 125+65*v1, 155+65*v1) end,
    gold   = function(_, v1) return rgb(195+60*v1, 150+75*v1, 15+65*v1) end,
    grey   = function(_, v1) return rgb(145+75*v1, 145+75*v1, 145+75*v1) end,
    hot    = function(_, v1, v2, v3) return rgb(205+50*v3, 0+230*v1, 0+55*v2) end,
    mem    = function(_, v1, v2, v3) return rgb(0, 190+50*v2, 0+210*v1) end,
    io     = function(_, v1, v2, v3) return rgb(80+60*v1, 80+60*v1, 190+55*v2) end
}

function FlameGraph.color(typ, hash, name, rand)
    local v1, v2, v3
    if hash then
        v1 = FlameGraph.namehash(name)
        v2 = FlameGraph.namehash(name:reverse())
        v3 = v2
    elseif rand then
        v1, v2, v3 = math.random(), math.random(), math.random()
    else
        v1 = FlameGraph.random_namehash(name)
        v2 = v1
        v3 = v1
    end

    local pal = FlameGraph.palettes[typ or '']
    if not pal then return rgb(0, 0, 0) end
    local color = pal(name, v1, v2, v3)

    -- theme palettes resolve to a color palette name: dispatch once more
    if type(color) == 'string' then
        local pal2 = FlameGraph.palettes[color]
        if pal2 then return pal2(name, v1, v2, v3) end
    end
    return color
end

function FlameGraph.color_scale(value, max)
    local r, g, b = 255, 255, 255
    value = options.negate and -value or value
    g = 210*(max-math.abs(value))/max
    if value > 0 then
        b = g
    else
        r = g
    end
    return rgb(r, g, b)
end

function FlameGraph.color_map(a, func)
    if a.palette_map[func] then
        return a.palette_map[func]
    else
        a.palette_map[func] = FlameGraph.color(a.colors, a.hash, func, a.random)
        return a.palette_map[func]
    end
end

function FlameGraph.write_palette(a)
    local keys = {}
    for k, v in pairs(a.palette_map) do keys[#keys+1] = k..'->'..v end
    table.sort(keys)
    local file = io.open(a.pal_file, 'w')
    if not file then return end
    file:write(table.concat(keys, '\n')..'\n')
    file:close()
end

function FlameGraph.read_palette(a)
    local file = io.open(a.pal_file, 'r')
    -- a missing palette file is normal on the first --cp run (upstream does the
    -- same check); only a real read failure is worth reporting
    if not file then return end
    local text = file:read('*a')
    file:close()
    for k, v in text:gmatch('([^%\n]+)%->([^%\n]+)') do
        a.palette_map[k] = v
    end
end

local function reverse(arr)
    local i, j = 1, #arr
    while i < j do
        arr[i], arr[j] = arr[j], arr[i]
        i = i + 1
        j = j - 1
    end
end

local function split(s, sep, plain, occurrence, case_insensitive)
    local r = {}
    for v in s:gsplit(sep, plain, occurrence, case_insensitive) do
        r[#r+1] = v
    end
    return r
end

local function comma_value(amount)
    local formatted, k = tostring(amount), 1
    while k ~= 0 do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    end
    return formatted
end

--parse input(io.lines or string.gmatch)
-- lines: array of "stack;frames... count [count2]" folded stack lines
-- args:  option overrides (options table keys)
function FlameGraph.BuildGraph(lines, overrides)
    overrides = overrides or {}
    -- snapshot effective args: module defaults overridden by caller args.
    -- NEVER mutate the module-level defaults (they must not leak across runs).
    local args = {}
    for k, v in pairs(options) do args[k] = v end
    for k, v in pairs(overrides) do args[k] = v end
    args.palette_map = {}
    args.funcdesc = overrides.funcdesc or {}
    args.depthmax = 0

    FlameGraph.CheckOptions(args)

    local time = 0;
    local ignored = 0;
    local maxdelta = 1;
    local exp = "^ *(.-) +([%d%.]+) *$"

    -- parse input. Upstream sorts the folded lines (or reverses them in flame
    -- chart mode) so that identical stack prefixes merge into adjacent frames;
    -- the tree insertion order below becomes the left-to-right frame order.
    local data = {}
    for idx = 1, #lines do
        data[#data+1] = lines[idx]:gsub('[\r\n]+', '')
    end
    if args.flamechart then reverse(data) else table.sort(data) end

    local stacks = {__ELEMENTS__ = {}}
    local prev_nodes = {}   -- tree nodes of the previously merged stack, by depth
    for _, line in ipairs(data) do
        local stack, samples, samples2 = line:match(exp)
        if stack then
            -- there may be an extra samples column for differentials
            if stack:find(exp) then
                samples2 = samples
                stack, samples = stack:match(exp)
            end

            stack = split(stack, ';')
            --reverse if needed
            if args.stackreverse then reverse(stack) end
            table.insert(stack, 1, '')
            local sub, chain = stacks, nil
            local nodes = {}
            for depth, func in ipairs(stack) do
                -- for chain graphs, annotate waker frames with "_[w]", for later
                -- coloring. This is a hack, but has a precedent ("_[k]" from perf).
                local desc = (args.funcdesc[func:lower()] or ''):gsub('\27%[[%d;]*m', ''):gsub('%$[%w_]+%$', ''):gsub('^%s*%((.*)%)%s*$', '%1')
                if chain then func = func..'_[w]' end
                if not sub[func] then
                    sub[func] = {__STATS__ = {subtree=0, delta=0, calls=0, desc=desc}, __ELEMENTS__ = {}}
                    table.insert(sub.__ELEMENTS__, func)
                end
                local stats = sub[func].__STATS__
                -- upstream flow() semantics: a block that was not open in the
                -- previous (sorted) stack starts at the current time. Frames are
                -- positioned by this absolute start time, so self-time gaps stay
                -- where the sort order puts them (as in flamegraph.pl).
                if prev_nodes[depth] ~= sub[func] then stats.stime = time end
                nodes[depth] = sub[func]
                if depth == #stack then stats.calls = stats.calls+samples end
                stats.subtree = stats.subtree+samples
                stats.delta = stats.delta+((samples2 or samples)-samples)
                maxdelta = math.max(stats.delta, maxdelta)
                sub = sub[func]
                if not chain and func == '--' and args.colors == 'chain' then
                    chain = func
                end
            end
            prev_nodes = nodes
            time = time+(samples2 or samples)
        else
            ignored = ignored+1
        end
    end

    if ignored > 0 then print(("Ignored %d lines with invalid format"):format(ignored)) end

    if time == 0 then
        --emit an error message SVG, for tools automating flamegraph use
        print("ERROR: No stack counts found")
        local im = FlameGraph.SVG:new()
        local imageheight = args.fontsize*5;
        im:header(args.imagewidth, imageheight, args.encoding);
        im:stringTTF(nil, math.floor(args.imagewidth/2), args.fontsize*2, "ERROR: No valid input provided to flamegraph.lua.");
        return im:toSVG();
    end

    if args.countname == "samples" and time < 100 then
        print("Stack count is low ("..time.."). Did something go wrong?")
    end

    if args.timemax and args.timemax < time then
        --only warn is significant (e.g., not rounding etc)
        if args.timemax/time > 0.02 then print(("Specified --total %s is less than actual total %s, so ignored"):format(args.timemax, time)) end
        args.timemax = nil;
    end
    args.timemax = args.timemax or time

    local widthpertime = (args.imagewidth-2*args.xpad)/args.timemax;
    -- minwidth in pixels, or as a percentage of time
    local minwidth_time
    if args.minwidth_pct then
        minwidth_time = args.timemax*args.minwidth_f/100
    else
        minwidth_time = args.minwidth_f/widthpertime
    end

    -- prune too-narrow subtrees and measure the deepest drawn level.
    local function measure(node)
        local maxd = 0
        for _, func in ipairs(node.__ELEMENTS__) do
            local child = node[func]
            if child.__STATS__.subtree >= minwidth_time then
                local d = measure(child)+1
                if d > maxd then maxd = d end
            end
        end
        return maxd
    end
    args.depthmax = math.max(measure(stacks)-1, 0)

    args.imageheight = ((args.depthmax+1)*args.frameheight)+args.ypad1+args.ypad2
    if args.subtitletext ~= "" then args.imageheight = args.imageheight+args.ypad3 end
    args.titlesize = args.fontsize+5
    local im = FlameGraph.SVG:new()
    args.black, args.vdgrey, args.dgrey = im:colorAllocate(0, 0, 0), im:colorAllocate(160, 160, 160), im:colorAllocate(200, 200, 200)
    im:header(args.imagewidth, args.imageheight, args.encoding)
    -- gsub keeps the match for nil/false table values, so render all booleans
    -- as 0/1 before interpolating into the JS template.
    local jsargs = {}
    for k, v in pairs(args) do
        if type(v) == 'boolean' then jsargs[k] = v and 1 or 0 else jsargs[k] = v end
    end
    local inc = ([[
<defs>
    <linearGradient id="background" y1="0" y2="1" x1="0" x2="0" >
        <stop stop-color="$bgcolor1" offset="5%" />
        <stop stop-color="$bgcolor2" offset="95%" />
    </linearGradient>
</defs>
<style type="text/css">
    text { font-family:$fonttype; font-size:${fontsize}px; fill:$black; }
    #search, #ignorecase { opacity:0.1; cursor:pointer; }
    #search:hover, #search.show, #ignorecase:hover, #ignorecase.show { opacity:1; }
    #subtitle { text-anchor:middle; font-color:$vdgrey; }
    #title { text-anchor:middle; font-size:${titlesize}px}
    #unzoom { cursor:pointer; }
    #frames > *:hover { stroke:black; stroke-width:0.5; cursor:pointer; }
    .hide { display:none; }
    .parent { opacity:0.5; }
</style>
<script type="text/ecmascript"><![CDATA[
    "use strict";
    var details, searchbtn, unzoombtn, matchedtxt, svg, searching, currentSearchTerm, ignorecase, ignorecaseBtn;
    function init(evt) {
        details = document.getElementById("details").firstChild;
        searchbtn = document.getElementById("search");
        ignorecaseBtn = document.getElementById("ignorecase");
        unzoombtn = document.getElementById("unzoom");
        matchedtxt = document.getElementById("matched");
        svg = document.getElementsByTagName("svg")[0];
        searching = 0;
        currentSearchTerm = null;

        // use GET parameters to restore a flamegraphs state.
        var params = get_params();
        if (params.x && params.y)
            zoom(find_group(document.querySelector('[x="' + params.x + '"][y="' + params.y + '"]')));
        if (params.s) search(params.s);
    }

    // event listeners
    window.addEventListener("click", function(e) {
        var target = find_group(e.target);
        if (target) {
            if (target.nodeName == "a") {
                if (e.ctrlKey === false) return;
                e.preventDefault();
            }
            if (target.classList.contains("parent")) unzoom(true);
            zoom(target);
            if (!document.querySelector('.parent')) {
                // we have basically done a clearzoom so clear the url
                var params = get_params();
                if (params.x) delete params.x;
                if (params.y) delete params.y;
                history.replaceState(null, null, parse_params(params));
                unzoombtn.classList.add("hide");
                return;
            }

            // set parameters for zoom state
            var el = target.querySelector("rect");
            if (el && el.attributes && el.attributes.y && el.attributes._orig_x) {
                var params = get_params()
                params.x = el.attributes._orig_x.value;
                params.y = el.attributes.y.value;
                history.replaceState(null, null, parse_params(params));
            }
        }
        else if (e.target.id == "unzoom") clearzoom();
        else if (e.target.id == "search") search_prompt();
        else if (e.target.id == "ignorecase") toggle_ignorecase();
    }, false)

    // mouse-over for info
    // show
    window.addEventListener("mouseover", function(e) {
        var target = find_group(e.target);
        if (target) details.nodeValue = "$nametype " + g_to_text(target);
    }, false)

    // clear
    window.addEventListener("mouseout", function(e) {
        var target = find_group(e.target);
        if (target) details.nodeValue = ' ';
    }, false)

    // ctrl-F for search
    // ctrl-I to toggle case-sensitive search
    window.addEventListener("keydown", function (e) {
        if (e.keyCode === 114 || (e.ctrlKey && e.keyCode === 70)) {
            e.preventDefault();
            search_prompt();
        }
        else if (e.ctrlKey && e.keyCode === 73) {
            e.preventDefault();
            toggle_ignorecase();
        }
    }, false)

    // functions
    function get_params() {
        var params = {};
        var paramsarr = window.location.search.substr(1).split('&');
        for (var i = 0; i < paramsarr.length; ++i) {
            var tmp = paramsarr[i].split("=");
            if (!tmp[0] || !tmp[1]) continue;
            params[tmp[0] ]  = decodeURIComponent(tmp[1]);
        }
        return params;
    }
    function parse_params(params) {
        var uri = "?";
        for (var key in params) {
            uri += key + '=' + encodeURIComponent(params[key]) + '&';
        }
        if (uri.slice(-1) == "&")
            uri = uri.substring(0, uri.length - 1);
        if (uri == '?')
            uri = window.location.href.split('?')[0];
        return uri;
    }
    function find_child(node, selector) {
        var children = node.querySelectorAll(selector);
        if (children.length) return children[0];
        return;
    }
    function find_group(node) {
        var parent = node.parentElement;
        if (!parent) return;
        if (parent.id == "frames") return node;
        return find_group(parent);
    }
    function orig_save(e, attr, val) {
        if (e.attributes["_orig_" + attr] != undefined) return;
        if (e.attributes[attr] == undefined) return;
        if (val == undefined) val = e.attributes[attr].value;
        e.setAttribute("_orig_" + attr, val);
    }
    function orig_load(e, attr) {
        if (e.attributes["_orig_"+attr] == undefined) return;
        e.attributes[attr].value = e.attributes["_orig_" + attr].value;
        e.removeAttribute("_orig_"+attr);
    }
    function title_to_label(s) {
        // first line of the title, with any dbcli stats decoration stripped:
        // "func [Unit=...]" and "func (N count, p%; dp%)" reduce to "func".
        var txt = s.split("\n")[0];
        if (/^all /.test(txt)) return txt;
        txt = txt.replace(/ ?\[Unit=[\s\S]*$/, "");
        txt = txt.replace(/ \([^()]*\)$/, "");
        return txt;
    }
    function g_to_text(e) {
        var text = find_child(e, "title").firstChild.nodeValue.split("\n")[0];
        return (text)
    }
    function g_to_func(e) {
        // if there's any manipulation we want to do to the function
        // name before it's searched, do it here before returning.
        return title_to_label(find_child(e, "title").firstChild.nodeValue);
    }
    function update_text(e) {
        var r = find_child(e, "rect");
        var t = find_child(e, "text");
        var w = parseFloat(r.attributes.width.value) -3;
        var txt = title_to_label(find_child(e, "title").textContent);
        t.attributes.x.value = parseFloat(r.attributes.x.value) + 3;

        // Smaller than this size won't fit anything
        if (w < 2 * $fontsize * $fontwidth) {
            t.textContent = "";
            return;
        }

        t.textContent = txt;
        var sl = t.getSubStringLength(0, txt.length);
        // check if only whitespace or if we can fit the entire string into width w
        if (/^ *$/.test(txt) || sl < w)
            return;

        // this isn't perfect, but gives a good starting point
        // and avoids calling getSubStringLength too often
        var start = Math.floor((w/sl) * txt.length);
        for (var x = start; x > 0; x = x-2) {
            if (t.getSubStringLength(0, x + 2) <= w) {
                t.textContent = txt.substring(0, x) + "..";
                return;
            }
        }
        t.textContent = "";
    }

    // zoom
    function zoom_reset(e) {
        if (e.attributes != undefined) {
            orig_load(e, "x");
            orig_load(e, "width");
        }
        if (e.childNodes == undefined) return;
        for (var i = 0, c = e.childNodes; i < c.length; i++) {
            zoom_reset(c[i]);
        }
    }
    function zoom_child(e, x, ratio) {
        if (e.attributes != undefined) {
            if (e.attributes.x != undefined) {
                orig_save(e, "x");
                e.attributes.x.value = (parseFloat(e.attributes.x.value) - x - $xpad) * ratio + $xpad;
                if (e.tagName == "text")
                    e.attributes.x.value = find_child(e.parentNode, "rect[x]").attributes.x.value + 3;
            }
            if (e.attributes.width != undefined) {
                orig_save(e, "width");
                e.attributes.width.value = parseFloat(e.attributes.width.value) * ratio;
            }
        }

        if (e.childNodes == undefined) return;
        for (var i = 0, c = e.childNodes; i < c.length; i++) {
            zoom_child(c[i], x - $xpad, ratio);
        }
    }
    function zoom_parent(e) {
        if (e.attributes) {
            if (e.attributes.x != undefined) {
                orig_save(e, "x");
                e.attributes.x.value = $xpad;
            }
            if (e.attributes.width != undefined) {
                orig_save(e, "width");
                e.attributes.width.value = parseInt(svg.width.baseVal.value) - ($xpad * 2);
            }
        }
        if (e.childNodes == undefined) return;
        for (var i = 0, c = e.childNodes; i < c.length; i++) {
            zoom_parent(c[i]);
        }
    }
    function zoom(node) {
        var attr = find_child(node, "rect").attributes;
        var width = parseFloat(attr.width.value);
        var xmin = parseFloat(attr.x.value);
        var xmax = parseFloat(xmin + width);
        var ymin = parseFloat(attr.y.value);
        var ratio = (svg.width.baseVal.value - 2 * $xpad) / width;

        // XXX: Workaround for JavaScript float issues (fix me)
        var fudge = 0.0001;

        unzoombtn.classList.remove("hide");

        var el = document.getElementById("frames").children;
        for (var i = 0; i < el.length; i++) {
            var e = el[i];
            var a = find_child(e, "rect").attributes;
            var ex = parseFloat(a.x.value);
            var ew = parseFloat(a.width.value);
            var upstack;
            // Is it an ancestor
            if ($inverted == 0) {
                upstack = parseFloat(a.y.value) > ymin;
            } else {
                upstack = parseFloat(a.y.value) < ymin;
            }
            if (upstack) {
                // Direct ancestor
                if (ex <= xmin && (ex+ew+fudge) >= xmax) {
                    e.classList.add("parent");
                    zoom_parent(e);
                    update_text(e);
                }
                // not in current path
                else
                    e.classList.add("hide");
            }
            // Children maybe
            else {
                // no common path
                if (ex < xmin || ex + fudge >= xmax) {
                    e.classList.add("hide");
                }
                else {
                    zoom_child(e, xmin, ratio);
                    update_text(e);
                }
            }
        }
        search();
    }
    function unzoom(dont_update_text) {
        unzoombtn.classList.add("hide");
        var el = document.getElementById("frames").children;
        for(var i = 0; i < el.length; i++) {
            el[i].classList.remove("parent");
            el[i].classList.remove("hide");
            zoom_reset(el[i]);
            if(!dont_update_text) update_text(el[i]);
        }
        search();
    }
    function clearzoom() {
        unzoom();

        // remove zoom state
        var params = get_params();
        if (params.x) delete params.x;
        if (params.y) delete params.y;
        history.replaceState(null, null, parse_params(params));
    }

    // search
    function toggle_ignorecase() {
        ignorecase = !ignorecase;
        if (ignorecase) {
            ignorecaseBtn.classList.add("show");
        } else {
            ignorecaseBtn.classList.remove("show");
        }
        reset_search();
        search();
    }
    function reset_search() {
        var el = document.querySelectorAll("#frames rect");
        for (var i = 0; i < el.length; i++) {
            orig_load(el[i], "fill")
        }
        var params = get_params();
        delete params.s;
        history.replaceState(null, null, parse_params(params));
    }
    function search_prompt() {
        if (!searching) {
            var term = prompt("Enter a search term (regexp " +
                "allowed, eg: ^ext4_)"
                + (ignorecase ? ", ignoring case" : "")
                + "\nPress Ctrl-i to toggle case sensitivity", "");
            if (term != null) search(term);
        } else {
            reset_search();
            searching = 0;
            currentSearchTerm = null;
            searchbtn.classList.remove("show");
            searchbtn.firstChild.nodeValue = "Search"
            matchedtxt.classList.add("hide");
            matchedtxt.firstChild.nodeValue = ""
        }
    }
    function search(term) {
        if (term) currentSearchTerm = term;
        if (currentSearchTerm === null) return;

        var re = new RegExp(currentSearchTerm, ignorecase ? 'i' : '');
        var el = document.getElementById("frames").children;
        var matches = new Object();
        var maxwidth = 0;
        for (var i = 0; i < el.length; i++) {
            var e = el[i];
            var func = g_to_func(e);
            var rect = find_child(e, "rect");
            if (func == null || rect == null)
                continue;

            // Save max width. Only works as we have a root frame
            var w = parseFloat(rect.attributes.width.value);
            if (w > maxwidth)
                maxwidth = w;

            if (func.match(re)) {
                // highlight
                var x = parseFloat(rect.attributes.x.value);
                orig_save(rect, "fill");
                rect.attributes.fill.value = "$searchcolor";

                // remember matches
                if (matches[x] == undefined) {
                    matches[x] = w;
                } else {
                    if (w > matches[x]) {
                        // overwrite with parent
                        matches[x] = w;
                    }
                }
                searching = 1;
            }
        }
        if (!searching)
            return;
        var params = get_params();
        params.s = currentSearchTerm;
        history.replaceState(null, null, parse_params(params));

        searchbtn.classList.add("show");
        searchbtn.firstChild.nodeValue = "Reset Search";

        // calculate percent matched, excluding vertical overlap
        var count = 0;
        var lastx = -1;
        var lastw = 0;
        var keys = Array();
        for (k in matches) {
            if (matches.hasOwnProperty(k))
                keys.push(k);
        }
        // sort the matched frames by their x location
        // ascending, then width descending
        keys.sort(function(a, b){
            return a - b;
        });
        // Step through frames saving only the biggest bottom-up frames
        // thanks to the sort order. This relies on the tree property
        // where children are always smaller than their parents.
        var fudge = 0.0001; // JavaScript floating point
        for (var k in keys) {
            var x = parseFloat(keys[k]);
            var w = matches[keys[k] ];
            if (x >= lastx + lastw - fudge) {
                count += w;
                lastx = x;
                lastw = w;
            }
        }
        // display matched percent
        matchedtxt.classList.remove("hide");
        var pct = 100 * count / maxwidth;
        if (pct != 100) pct = pct.toFixed(1)
        matchedtxt.firstChild.nodeValue = "Matched: " + pct + "%";
    }]@]>
</script>]]):gsub(']@]>',']]>',1):gsub("%$%{?(%w+)%}?",jsargs)
    im:include(inc);
    im:filledRectangle(0, 0, args.imagewidth, args.imageheight, 'url(#background)');
    im:stringTTF("title", math.floor(args.imagewidth/2), args.fontsize*2, args.titletext);
    if args.subtitletext ~= "" then
        im:stringTTF("subtitle", math.floor(args.imagewidth/2), args.fontsize*4, args.subtitletext)
    end
    im:stringTTF("details", args.xpad, args.imageheight-(args.ypad2/2), " ");
    im:stringTTF("unzoom", args.xpad, args.fontsize*2, "Reset Zoom", 'class="hide"');
    im:stringTTF("search", args.imagewidth-args.xpad-100, args.fontsize*2, "Search");
    im:stringTTF("ignorecase", args.imagewidth-args.xpad-16, args.fontsize*2, "ic");
    im:stringTTF("matched", args.imagewidth-args.xpad-100, args.imageheight-(args.ypad2/2), " ");
    if args.palette then FlameGraph.read_palette(args) end

    im:group_start({id = "frames"})
    local escapes = {
        ['&'] = '&amp;',
        ['<'] = '&lt;',
        ['>'] = '&gt;',
        ['"'] = '&quot;'
    }
    local function travel(parent, depth)
        for idx, func in ipairs(parent.__ELEMENTS__) do
            local node = parent[func]
            local stats = node.__STATS__
            local subtree, calls, delta = stats.subtree, stats.calls, stats.delta
            if subtree >= minwidth_time then
                if delta == 0 then delta = nil end
                local x1 = args.xpad+(stats.stime or 0)*widthpertime;
                -- the root spans the whole (possibly --total) range, like upstream
                local x2
                if func == "" and depth == 0 then
                    x2 = args.xpad+args.timemax*widthpertime
                else
                    x2 = args.xpad+((stats.stime or 0)+subtree)*widthpertime
                end
                local y1, y2
                if not args.inverted then
                    y1 = args.imageheight-args.ypad2-(depth+1)*args.frameheight+args.framepad;
                    y2 = args.imageheight-args.ypad2-depth*args.frameheight
                else
                    y1 = args.ypad1+depth*args.frameheight;
                    y2 = args.ypad1+(depth+1)*args.frameheight-args.framepad;
                end

                local samples = ("%.2f"):format(subtree*args.factor)
                local sample_text = comma_value(samples+0)

                local info;
                if func == "" and depth == 0 then
                    info = ("all (%s %s, 100%%)"):format(sample_text, args.countname)
                else
                    local pct1 = ("%.2f"):format((100*samples)/(args.timemax*args.factor)):gsub('%.?0+$', '')
                    local pct2 = ("%.2f"):format((100*calls)/args.timemax):gsub('%.?0+$', '')
                    local pct3 = ("%.2f"):format((100*(samples-calls))/args.timemax):gsub('%.?0+$', '')
                    --clean up SVG breaking characters:
                    local escaped_func = func:gsub('[&<>"]', escapes)
                    --strip any annotation
                    escaped_func = escaped_func:gsub('_%[[kwij]%]$', '', 1)
                    if not delta then
                        info = ("%s [Unit=%s  Samples=%s(%s%%)  Self=%s(%s%%)  Subtree=%s(%s%%)]%s"):format(
                            escaped_func, args.countname,
                            sample_text, pct1,
                            comma_value(calls), pct2,
                            comma_value(samples-calls), pct3,
                            stats.desc ~= "" and ('\nDescription: '..stats.desc:gsub('[&<>"]', escapes)) or ''
                            )
                    else
                        local d = args.negate and -delta or delta
                        local deltapct = ("%.2f"):format((100*d)/(args.timemax*args.factor))
                        deltapct = d > 0 and ("+"..deltapct) or deltapct
                        info = ("%s (%s %s, %s%%; %s%%)"):format(escaped_func, sample_text, args.countname, pct1, deltapct);
                    end
                end
                --shallow clone
                local nameattr = {}
                for k, v in pairs(args.nameattr[func] or {}) do nameattr[k] = v end
                nameattr.title = nameattr.title or info
                im:group_start(nameattr, depth+1);

                local color;
                if func == "--" then
                    color = args.vdgrey;
                elseif func == "-" then
                    color = args.dgrey;
                elseif delta then
                    color = FlameGraph.color_scale(delta, maxdelta)
                elseif args.palette then
                    color = FlameGraph.color_map(args, func)
                else
                    color = FlameGraph.color(args.colors, args.hash, func, args.random);
                end
                im:filledRectangle(x1, y1, x2, y2, color, 'rx="2" ry="2"', depth+2);

                local chars = math.floor((x2-x1)/(args.fontsize*args.fontwidth))
                local text = "";
                -- room for one char plus two dots
                if chars >= 3 then
                    -- strip any annotation
                    func = func:gsub('_%[[kwij]%]$', '', 1)
                    text = func:sub(1, chars)
                    if chars < #func then text = text:sub(1, -3)..'..' end
                    text = text:gsub('[&<>"]', escapes)
                end
                im:stringTTF(nil, x1+3, 3+(y1+y2)/2, text, nil, depth+2)
                im:group_end(nameattr, depth+1)
                travel(node, depth+1)
            end
        end
    end
    travel(stacks, 0)
    im:group_end({})
    if (args.palette) then FlameGraph.write_palette(args) end
    return im:toSVG()
end
-- CLI entry, flamegraph.pl-style: dbcli loads this file as a module chunk with
-- the env table as the only vararg and require() passes the module name, so the
-- branch only fires when the first argument is an option or a readable file.
local arg1 = ...
local function is_cli_arg(s)
    if s:sub(1, 2) == '--' then return true end
    local fh = io.open(s, 'r')
    if fh then fh:close() return true end
    return false
end
if type(arg1) == 'string' and is_cli_arg(arg1) then
    -- upstream sends every warning to stderr (perl warn); keep stdout clean
    -- for the SVG when the command line redirects it to a file
    print = function(...)
        local t = {}
        for i = 1, select('#', ...) do t[i] = tostring(select(i, ...)) end
        io.stderr:write(table.concat(t, '\t') .. '\n')
    end
    if not string.gsplit then
        -- standalone run: split() needs string.gsplit, normally installed by
        -- dbcli (lib/misc.lua) or the test prelude; minimal equivalent here
        function string.gsplit(s, sep, plain)
            local seg_start, find_start, done = 1, 1, false
            return function()
                if done then return end
                if sep == '' then done = true return s end
                local i, j = string.find(s, sep, find_start, plain)
                if not i then
                    done = true
                    return string.sub(s, seg_start)
                end
                local seg = string.sub(s, seg_start, i - 1)
                seg_start, find_start = j + 1, j + 1
                return seg
            end
        end
    end
    local argv = {...}
    FlameGraph.GetOptions(argv)
    if not (options.help and options.help ~= 0) then
        math.randomseed(os.time())
        local lines, files = {}, {}
        for _, a in ipairs(argv) do
            if a:sub(1, 2) ~= '--' then files[#files+1] = a end
        end
        if #files == 0 then
            for line in io.lines() do lines[#lines+1] = line end
        else
            for _, name in ipairs(files) do
                local fh = io.open(name, 'r')
                if not fh then error("can't open input file "..name) end
                for line in fh:lines() do lines[#lines+1] = line end
                fh:close()
            end
        end
        io.write(FlameGraph.BuildGraph(lines))
    end
    return FlameGraph
end
return FlameGraph
