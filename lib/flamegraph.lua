--[[--
  flamegraph.pl       flame stack grapher.
  
  This takes stack samples and renders a call graph, allowing hot functions
  and codepaths to be quickly identified.  Stack samples can be generated using
  tools such as DTrace, perf, SystemTap, and Instruments.
  
  USAGE: ./flamegraph.pl [options] input.txt > graph.svg
  
         grep funcA input.txt | ./flamegraph.pl [options] > graph.svg
  
  Then open the resulting .svg in a web browser, for interactivity: mouse-over
  frames for info, click to zoom, and ctrl-F to search.
  
  Options are listed in the usage message (--help).
  
  The input is stack frames and sample counts formatted as single lines.  Each
  frame in the stack is semicolon separated, with a space and count at the end
  of the line.  These can be generated for Linux perf script output using
  stackcollapse-perf.pl, for DTrace using stackcollapse.pl, and for other tools
  using the other stackcollapse programs.  Example input:
  
   swapper;start_kernel;rest_init;cpu_idle;default_idle;native_safe_halt 1
  
  An optional extra column of counts can be provided to generate a differential
  flame graph of the counts, colored red for more, and blue for less.  This
  can be useful when using flame graphs for non-regression testing.
  See the header comment in the difffolded.pl program for instructions.
  
  The input functions can optionally have annotations at the end of each
  function name, following a precedent by some tools (Linux perf's _[k]):
      _[k] for kernel
      _[i] for inlined
      _[j] for jit
      _[w] for waker
  Some of the stackcollapse programs support adding these annotations, eg,
  stackcollapse-perf.pl --kernel --jit. They are used merely for colors by
  some palettes, eg, flamegraph.pl --color=java.
  
  The output flame graph shows relative presence of functions in stack samples.
  The ordering on the x-axis has no meaning; since the data is samples, time
  order of events is not known.  The order used sorts function names
  alphabetically.
  
  While intended to process stack samples, this can also process stack traces.
  For example, tracing stacks for memory allocation, or resource usage.  You
  can use --title to set the title to reflect the content, and --countname
  to change "samples" to "bytes" etc.
  
  There are a few different palettes, selectable using --color.  By default,
  the colors are selected at random (except for differentials).  Functions
  called "-" will be printed gray, which can be used for stack separators (eg,
  between user and kernel stacks).
  
  HISTORY
  
  This was inspired by Neelakanth Nadgir's excellent function_call_graph.rb
  program, which visualized function entry and return trace events.  As Neel
  wrote: "The output displayed is inspired by Roch's CallStackAnalyzer which
  was in turn inspired by the work on vftrace by Jan Boerhout".  See:
  https://blogs.oracle.com/realneel/entry/visualizing_callstacks_via_dtrace_and
  
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
  
  11-Oct-2014 Adrien Mahieux  Added zoom.
  21-Nov-2013 Shawn Sterling  Added consistent palette file option
  17-Mar-2013 Tim Bunce       Added options and more tunables.
  15-Dec-2011 Dave Pacheco    Support for frames with whitespace.
  10-Sep-2011 Brendan Gregg   Created this.
--]]--

local tonumber, type, print, table,string,error,math = tonumber, type, print, table,string,error,math
local unpack=table.unpack or unpack

local options={
    encoding = nil,
    fonttype = "Verdana",
    imagewidth = 1200,          -- max width, pixels
    frameheight = 16,           -- max height is dynamic
    fontsize = 12,              -- base text size
    fontwidth = 0.59,           -- avg width relative to fontsize
    minwidth = 0.1,             -- min function width, pixels
    nametype = "Function:",     -- what are the names in the data?
    countname = "samples",      -- what are the counts in the data?
    colors = "hot",             -- color theme
    bgcolors = "",              -- background color theme
    nameattrfile = nil,         -- file holding function attributes
    timemax = nil,              -- (override the) sum of the counts
    factor = 1,                 -- factor to scale counts by
    hash = 0,                   -- color by function name
    palette = 0,                -- if we use consistent palettes (default off)
    palette_map = {} ,          -- palette map hash
    pal_file = "palette.map",   -- palette map file name
    stackreverse = 0,           -- reverse stack order, switching merge end
    inverted = 0,               -- icicle graph
    flamechart = 0,             -- produce a flame chart (sort by time, do not merge stacks)
    negate = 0,                 -- switch differential hues
    titletext = "",             -- centered heading
    titledefault = "Flame Graph",   -- overwritten by --title
    titleinverted = "Icicle Graph", --   "    "
    searchcolor = "rgb(230,0,230)", -- color for search highlighting
    notestext = "",           -- embedded notes in SVG
    subtitletext = "",        -- second level title (optional)
    funcdesc = {},
    help = 0
}
local FlameGraph={}

function FlameGraph.usage()
    return [[
    Usage  : flamegraph.lua [options] infile > <outfile>.svg
    Options:
        --title TEXT     # change title text
        --subtitle TEXT  # second level title (optional)
        --width NUM      # width of image (default 1200)
        --height NUM     # height of each frame (default 16)
        --minwidth NUM   # omit smaller functions (default 0.1 pixels)
        --fonttype FONT  # font type (default "Verdana")
        --fontsize NUM   # font size (default 12)
        --countname TEXT # count type label (default "samples")
        --nametype TEXT  # name type label (default "Function:")
        --colors PALETTE # set color palette. choices are: hot (default), mem,
                         # io, wakeup, chain, java, js, perl, red, green, blue,
                         # aqua, yellow, purple, orange
        --bgcolors COLOR # set background colors. gradient choices are yellow
                         # (default), blue, green, grey; flat colors use "#rrggbb"
        --hash           # colors are keyed by function name hash
        --cp             # use consistent palette (palette.map)
        --reverse        # generate stack-reversed flame graph
        --inverted       # icicle graph
        --flamechart     # produce a flame chart (sort by time, do not merge stacks)
        --negate         # switch differential hues (blue<->red)
        --notes TEXT     # add notes comment in SVG (for debugging)
        --help           # this message

    Example: flamegraph.lua --title="Flame Graph: malloc()" trace.txt > graph.svg]]
end

function FlameGraph.GetOptions(args)
    for _,option in ipairs(args) do
        local value,val
        if option:find('=',1,true) then
            option,value=option:match('^(.-)=(.*)')
            if type(options[option])=="number" then
                val=tonumber(value)
                if not val then error('Invalid value for option value: '..value) end
                value=val
            end 
        else
            value=options[option] and 1 or true
        end
        options[option]=value
    end
    if options['help']==1 then print(FlameGraph.usage()) end
end

function FlameGraph.CheckOptions()
    -- internals
    options.ypad1 = options.fontsize * 3;      -- pad top, include title
    options.ypad2 = options.fontsize * 2 + 10; -- pad bottom, include labels
    options.ypad3 = options.fontsize * 2;      -- pad top, include subtitle (optional)
    options.xpad = 10;                  -- pad lefm and right
    options.framepad = 1;       -- vertical padding for frames
    options.depthmax = 0;
    options.Events={};
    options.nameattr={};

    if options.flamechart and options.titletext == "" then
        options.titletext = "Flame Chart";
    end

    if options.titletext == "" then
        if options.inverted then
            options.titletext = options.titledefault;
        else
            options.titletext = options.titleinverted;
        end
    end

    if options.nameattrfile then
        -- The name-attribute file format is a function name followed by a tab then
        -- a sequence of tab separated name=value pairs.
        local attrfh=io.open(options.nameattrfile,'r')
        if not attrfh then error("Can't read "..options.nameattrfile.."!\n"); end
        local text=attrfh:read('*a')
        attrfh:close()

        local funcname, attrtext=text:match('(%S+)\t+(.+)')
        if not funcname then error("Invalid format in "..options.nameattrfile); end
        local attrs={}
        for attr,value in attrtext:gmatch('(%S+)%s*=%s*(%S+)') do
            attrs[attr]=value
        end
        options.nameattr[funcname]=attrs
    end

    if options.notestext:find('[<>]') then
        error "Notes string can't contain < or >"
    end

    if options.bgcolors == "" then
        -- choose a default
        if options.colors == "mem" then
            options.bgcolors = "green";
        elseif ({io=1,wakeup=1,chain=1})[options.colors] then
            options.bgcolors = "blue";
        elseif ({red=1,green=1,blue=1,aqua=1,yellow=1,purple=1,orange=1})[options.colors] then
            options.bgcolors = "grey";
        else 
            options.bgcolors = "yellow";
        end
    end

    if options.bgcolors == "yellow" then
        options.bgcolor1,options.bgcolor2 = "#eeeeee","#eeeeb0";       -- background color gradient start
    elseif options.bgcolors == "blue" then
        options.bgcolor1,options.bgcolor2 = "#eeeeee","#e0e0ff";
    elseif options.bgcolors == "green" then
        options.bgcolor1,options.bgcolor2 = "#eef2ee", "#e0ffe0";
    elseif options.bgcolors == "grey" then
        options.bgcolor1 = "#f8f8f8"; options.bgcolor2 = "#e8e8e8";
    elseif options.bgcolors:match('^#......$') then
        options.bgcolor1,options.bgcolor2 = options.bgcolors,options.bgcolors;
    else
        error("Unrecognized bgcolor option: "..options.bgcolors)
    end
end

local function rgb(r,g,b)
    return ("rgb($r,$g,$b)"):gsub("%$(%w+)",{r=math.floor(r),g=math.floor(g),b=math.floor(b)});
end

FlameGraph.SVG={}

function FlameGraph.SVG:new(class)
    self.class=class
    return self
end

function FlameGraph.SVG:header(w,h)
    local enc_attr=options.encoding and (' encoding="'..options.encoding..'"') or ''
    self.svg={}
    self.svg[1]=([[
<?xml version="1.0"$encattr standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="$w" height="$h" onload="init(evt)" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<!-- Flame graph stack visualization. See https://github.com/brendangregg/FlameGraph for latest version, and http://www.brendangregg.com/flamegraphs.html for examples. -->
<!-- NOTES: $notestext -->]]):gsub("%$(%w+)",{w=w,h=h,encattr=options.enc_attr or '',notestext=options.notestext})
end

function FlameGraph.SVG:include(content,depth)
    local indent=('  '):rep(depth or 0)
    self.svg[#self.svg+1] = indent..content
end

function FlameGraph.SVG:colorAllocate(r,g,b)
    return rgb(r,g,b);
end

function FlameGraph.SVG:group_start(attr,depth)
    local tag,g_attr = 'g',{}

    if (attr.href) then
        -- default target=_top else links will open within SVG <object>
        tag='a'
        g_attr[#g_attr+1]=([[xlink:href="%s"]]):format(attr.href)
        g_attr[#g_attr+1]=([[target="%s"]]):format((attr.target or '')..'_top')
        g_attr[#g_attr+1]=attr.a_extra
    end
    for _,key in ipairs{'id','class'} do
        if attr[key] then g_attr[#g_attr+1]=('%s="%s"'):format(key,attr[key]) end
    end
    g_attr[#g_attr+1]=attr.g_extra

    self:include(('<%s%s>'):format(tag,#g_attr>0 and (' '..table.concat(g_attr,' ')) or ''),depth)
    if attr.title then self:include(('<title>%s</title>'):format(attr.title),depth+1) end
end

function FlameGraph.SVG:group_end(attr,depth)
    self:include(attr.href and '</a>' or '</g>',depth)
end

function FlameGraph.SVG:filledRectangle(x1, y1, x2, y2, fill, extra,depth)
    local fmt="%0.1f"
    local attrs={
        w =fmt:format(x2-x1),
        h =fmt:format(y2-y1),
        x1=fmt:format(x1),
        x2=fmt:format(x2),
        y1=fmt:format(y1),
        y2=fmt:format(y2),
        extra = extra or '',
        fill=fill
    }
    self:include(('<rect x="$x1" y="$y1" width="$w" height="$h" fill="$fill" $extra />'):gsub("%$(%w+)",attrs),depth)
end

function FlameGraph.SVG:stringTTF(id,x,y,str,extra,depth)
    local attrs={
        x=("%0.2f"):format(x),
        y=("%0.2f"):format(y),
        str=str,
        id=id and (('id="%s"'):format(id)) or '',
        extra=extra or ''
    }
    self:include(('<text $id x="$x" y="$y" $extra>$str</text>'):gsub("%$(%w+)",attrs),depth)
end

function FlameGraph.SVG:toSVG()
    return table.concat(self.svg,'\n')..'</svg>\n'
end

function FlameGraph.namehash(name)
    local vector,weight,max,mod = 0,1,1,10;
    -- if module name present, trunc to 1st char
    name=name:gsub('.-%^','',1)
    for c in name:gmatch('.') do
        local i= math.fmod(string.byte(c),mod);
        vector = vector+(i/mod) * weight;
        mod    = mod+1
        max    = max+weight;
        weight = weight*0.7
        if mod > 12 then 
            return 1 - vector / max
        end
    end
end

FlameGraph.palettes={
    java=function(name)
        if name:find('_%[j%]$') then
            return "green"
        elseif name:find('_%[i%]$') then
            return "aqua"
        elseif name:find('_%[k%]$') then
            return "orange"
        elseif name:find('::') then
            return "yellow"
        else
            name=name:match('^L?([^/]+)')
            if ({java=1,javax=1,jdk=1,net=1,org=1,com=1,io=1,sun=1})[name] then
                return 'green'
            end
            return "red"
        end
    end,
    perl=function(name)
        if name:find('::') then
            return "yellow"
        elseif name:find('Perl',1,true) or name:find('.pl',1,true) then
            return "green"
        elseif name:find('_%[k%]$') then
            return "orange"
        end
        return "red"
    end,
    js=function(name)
        if name:find('_%[j%]$') then
            return name:find('/',1,true) and "green" or "aqua"
        elseif name:find('::') then
            return "yellow"
        elseif name:find('.js',1,true) or name:find('^ +$') then
            return "green"
        elseif name:find(':',1,true) then
            return "aqua"
        elseif name:find('_[k]',1,true) then
            return "orange"
        end
        return "red"
    end,
    wakeup = function() return "aqua" end,
    chain  = function(name) return name:find('_[w]',1,true) and "aqua" or "blue" end,
    red    = function(_, v1, v2, v3) return rgb(200+55*v1, 50 +80*v1, 50+80*v1) end, 
    green  = function(_, v1, v2, v3) return rgb(50 +60*v1, 200+55*v1, 50+60*v1) end, 
    blue   = function(_, v1, v2, v3) return rgb(205+50*v1, 205+50*v1, 80+60*v1) end, 
    yellow = function(_, v1, v2, v3) return rgb(175+55*v1, 175+55*v1, 50+20*v1) end, 
    purple = function(_, v1, v2, v3) return rgb(190+65*v1, 80 +60*v1, 190+65*v1) end, 
    aqua   = function(_, v1, v2, v3) return rgb(50 +60*v1, 165+55*v1, 165+55*v1) end, 
    orange = function(_, v1, v2, v3) return rgb(190+65*v1, 90 +65*v1, 0) end, 
    hot    = function(_, v1, v2, v3) return rgb(205+50*v3 , 0  +230 * v1, 0+55 * v2) end, 
    mem    = function(_, v1, v2, v3) return rgb(0         , 190+50  * v2, 0+210 * v1) end, 
    io     = function(_, v1, v2, v3) return rgb(80 + 60*v1, 80 + 60 * v1, 190+55 * v2) end
}

function FlameGraph.color(typ, hash, name)
    local v1,v2,v3
    if hash then
        v1 = FlameGraph.namehash(name)
        v2 = FlameGraph.namehash(name:reverse())
        v3 = v2
    else 
        v1,v2,v3=math.random(),math.random(),math.random()
    end
    
    local scheme={
        hot={r=205 + math.floor(50*v3),g=0+math.floor(230 * v1),b=0+math.floor(55 * v2)},
        mem={r=0,g=190+math.floor(50 * v2),b=0+math.floor(210 * v1)},
        io={r=80 + math.floor(60*v1),g=80 + math.floor(60*v1),b=190+math.floor(55 * v2)}
    }
    if not FlameGraph.palettes[typ or 'x'] then return rgb(0,0,0) end
    local color=FlameGraph.palettes[typ](name,v1,v2,v3)

    if FlameGraph.palettes[color] then
        color=FlameGraph.palettes[color](name,v1,v2,v3)
    end
    return color
end

function FlameGraph.color_scale(value,max)
    local r,g,b=255,255,255
    value=options.negate and -value or value
    g=210*(max-math.abs(value))/max
    if value>0 then
        b=g
    else
        r=g
    end
    return rgb(r,g,b)
end

function FlameGraph.color_map(colors,func)
    if options.palette_map[func] then
        return options.palette_map[func]
    else
        options.palette_map[func]=FlameGraph.color(colors,nil,func)
        return options.palette_map[func]
    end
end

function FlameGraph.write_palette()
    local keys={}
    for k,v in pairs(options.palette_map) do keys[#keys+1]=k..'->'..v end
    table.sort(keys)
    local file=io.open(options.pal_file,'w')
    file:write(table.concat(keys,'\n')..'\n')
    file:close()
end

function FlameGraph.read_palette() 
    local file=io.open(options.pal_file,'r')
    if not file then error("can't open file "..options.pal_file) end
    local text=file:read('*a')
    file:close()
    for k,v in text:gmatch('[^\n]+%->(%S+)\n') do
        options.palette_map[k]=v
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

local function split(s,sep,plain,occurrence,case_insensitive)
    local r={}
    for v in s:gsplit(sep,plain,occurrence,case_insensitive) do
        r[#r+1]=v
    end
    return r
end

local function comma_value(amount)
    local formatted,k = amount
    while k~=0 do  
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    end
    return formatted
end

local Node,Tmp={},{}

-- flow() merges two stacks, storing the merged frames and value data in %Node.
function FlameGraph.flow(last,this,v,d)
    local len_name,len_a,len_b=1,#last,#this
    for i=1,math.min(len_a,len_b) do
        if len_name==1 and last[i]~=this[i] then
            len_name=math.max(1,i-1)
            break
        end
    end
    local fmt='%s;%s'

    -- a unique ID is constructed from "func;depth;etime";
    -- func-depth isn't unique, it may be repeated later.
    for i=len_a,len_name,-1 do
        local k=fmt:format(last[i],i)
        local n,t=fmt:format(k,v)
        t,Tmp[k]=Tmp[k] or {},nil        
        if not Node[n] then Node[n]={} end
        Node[n].stime,Node[n].delta=t.stime,t.delta
    end

    for i=len_name,len_b,1 do
        local k=fmt:format(this[i],i)
        if not Tmp[k] then Tmp[k]={} end
        Tmp[k].stime=v
        if d then Tmp[k].delta=(Tmp[k].delta or 0) + (len_b==i and d or 0) end
    end
    return this
end

--parse input(io.lines or string.gmatch)
function FlameGraph.BuildGraph(lines,args)
    local time = 0;
    local delta = nil;
    local ignored = 0;
    local line;
    local maxdelta = 1;
    local exp="^ *(.-) +([%d%.]+) *$"
    FlameGraph.CheckOptions()
    args=args or {}
    for option,value in pairs(options) do
        if args[option]==nil then 
            args[option]=value 
        end
        if args[option]==0 then args[option]=nil end
    end
    local stacks={__ELEMENTS__={}}
    if not args.depthmax then args.depthmax=0 end
    for _,line in ipairs(lines) do
        local stack,samples,samples2=line:match(exp)
        if stack then
            -- there may be an extra samples column for differentials
            -- XXX todo: redo these REs as one. It's repeated below.
            if stack:find(exp) then
                samples2=samples
                stack,samples=stack:match(exp)
            end

            stack=split(stack,';')
            --reverse if needed
            if args.stackreverse then reverse(stack) end
            table.insert(stack,1,'')
            local sub,chain=stacks
            for depth,func in ipairs(stack) do
                -- for chain graphs, annotate waker frames with "_[w]", for later
                -- coloring. This is a hack, but has a precedent ("_[k]" from perf).
                local desc=(args.funcdesc[func:lower()] or ''):gsub('\27%[[%d;]*m',''):gsub('%$[%w_]+%$',''):gsub('^%s*%((.*)%)%s*$','%1')
                if chain then func=func..'_[w]' end
                if not sub[func] then
                    sub[func]={__STATS__={subtree=0,delta=0,calls=0,desc=desc},__ELEMENTS__={}}
                    table.insert(sub.__ELEMENTS__,func)
                end
                local stats=sub[func].__STATS__
                if depth==#stack then stats.calls=stats.calls+samples end
                stats.subtree=stats.subtree+samples
                stats.delta=stats.delta+((samples2 or samples)-samples)
                maxdelta = math.max(stats.delta,maxdelta)
                sub=sub[func]
                if args.depthmax< depth then args.depthmax = depth end
                if not chain and func=='--' and args.colors=='chain' then
                    chain=func
                end
            end
            time=time+(samples2 or samples)
        else
            ignored = ignored + 1
        end
    end

    --In flame chart mode, just reverse the data so time moves from left to right.
    --[[
    if args.flamechart then
        reverse(data)
    else
        table.sort(data,function(a,b) return a[1]<b[1] end)
    end
    --]]

   
    if ignored>0 then print(("Ignored %d lines with invalid format"):format(ignored)) end

    if time==0 then
        --emit an error message SVG, for tools automating flamegraph use
        print("ERROR: No stack counts found")
        local im=FlameGraph.SVG:new()
        local imageheight = args.fontsize * 5;
        im:header(args.imagewidth, imageheight);
        im:stringTTF(nil, math.floor(args.imagewidth / 2), args.fontsize * 2, "ERROR: No valid input provided to flamegraph.pl.");
        return im:toSVG();
    end

    if args.timemax and args.timemax < time then
        --only warn is significant (e.g., not rounding etc)
        if args.timemax/time > 0.02 then print(("Specified --total %s is less than actual total %s, so ignored"):format(args.timemax,time)) end
        args.timemax=nil;
    end
    args.timemax = args.timemax or time

    local widthpertime = (args.imagewidth - 2 * args.xpad) / args.timemax;
    local minwidth_time = args.minwidth / widthpertime;
    --prune blocks that are too narrow and determine max depth
    
    args.imageheight = ((args.depthmax + 1) * args.frameheight) + args.ypad1 + args.ypad2
    if args.subtitletext ~= "" then args.imageheight=args.imageheight+args.ypad3 end
    args.titlesize = args.fontsize + 5
    local im = FlameGraph.SVG:new()
    args.black,args.vdgrey,args.dgrey=im:colorAllocate(0, 0, 0),im:colorAllocate(160, 160, 160),im:colorAllocate(200, 200, 200)
    args.inverted=args.inverted or 0
    im:header(args.imagewidth,args.imageheight)
    local inc=([[
<defs>
    <linearGradient id="background" y1="0" y2="1" x1="0" x2="0" >
        <stop stop-color="$bgcolor1" offset="5%" />
        <stop stop-color="$bgcolor2" offset="95%" />
    </linearGradient>
</defs>
<style type="text/css">
    text { font-family:$fonttype; font-size:${fontsize}px; fill:$black; }
    #search { opacity:0.1; cursor:pointer; }
    #search:hover, #search.show { opacity:1; }
    #subtitle { text-anchor:middle; font-color:$vdgrey; }
    #title { text-anchor:middle; font-size:${titlesize}px}
    #unzoom { cursor:pointer; }
    #frames > *:hover { stroke:black; stroke-width:0.5; cursor:pointer; }
    .hide { display:none; }
    .parent { opacity:0.5; }
</style>
<script type="text/ecmascript"><![CDATA[
    "use strict";
    var details, searchbtn, unzoombtn, matchedtxt, svg, searching;
    function init(evt) {
        details = document.getElementById("details").firstChild;
        searchbtn = document.getElementById("search");
        unzoombtn = document.getElementById("unzoom");
        matchedtxt = document.getElementById("matched");
        svg = document.getElementsByTagName("svg")[0];
        searching = 0;
    }

    window.addEventListener("click", function(e) {
        var target = find_group(e.target);
        if (target) {
            if (target.nodeName == "a") {
                if (e.ctrlKey === false) return;
                e.preventDefault();
            }
            if (target.classList.contains("parent")) unzoom();
            zoom(target);
        }
        else if (e.target.id == "unzoom") unzoom();
        else if (e.target.id == "search") search_prompt();
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
    window.addEventListener("keydown",function (e) {
        if (e.keyCode === 114 || (e.ctrlKey && e.keyCode === 70)) {
            e.preventDefault();
            search_prompt();
        }
    }, false)

    // functions
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
    function g_to_text(e) {
        var text = find_child(e, "title").firstChild.nodeValue.replace(/\n.*/,"");
        return (text)
    }
    function g_to_func(e) {
        var func = g_to_text(e);
        // if there's any manipulation we want to do to the function
        // name before it's searched, do it here before returning.
        return (func);
    }
    var texts={}
    function update_text(e,undo) {
        var r = find_child(e, "rect");
        var t = find_child(e, "text");
        var w = parseFloat(r.attributes.width.value) -3;
        var txt = find_child(e, "title").textContent.replace(/\\([^(]*\\)\$/,"");
        if(txt && texts[txt]===undefined) texts[txt]=t.textContent||'';
        txt=undo===true?texts[txt]||'':txt;
        t.attributes.x.value = parseFloat(r.attributes.x.value) + 3;

        // Smaller than this size won't fit anything
        if (w < 2 * $fontsize * $fontwidth) {
            t.textContent = "";
            return;
        }
        
        t.textContent = txt;
        // Fit in full text width
        if (/^ *\$/.test(txt) || txt.length>0&&t.getSubStringLength(0, txt.length) < w)
            return;

        for (var x = txt.length - 2; x > 0; x--) {
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
    }
    function unzoom() {
        unzoombtn.classList.add("hide");
        var el = document.getElementById("frames").children;
        for(var i = 0; i < el.length; i++) {
            el[i].classList.remove("parent");
            el[i].classList.remove("hide");
            zoom_reset(el[i]);
            update_text(el[i],true);
        }
    }

    // search
    function reset_search() {
        var el = document.querySelectorAll("#frames rect");
        for (var i = 0; i < el.length; i++) {
            orig_load(el[i], "fill")
        }
    }
    function search_prompt() {
        if (!searching) {
            var term = prompt("Enter a search term (regexp " +
                "allowed, eg: ^ext4_)", "");
            if (term != null) {
                search(term)
            }
        } else {
            reset_search();
            searching = 0;
            searchbtn.classList.remove("show");
            searchbtn.firstChild.nodeValue = "Search"
            matchedtxt.classList.add("hide");
            matchedtxt.firstChild.nodeValue = ""
        }
    }
    function search(term) {
        var re = new RegExp(term);
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
</script>]]):gsub(']@]>',']]>',1):gsub("%$%{?(%w+)%}?",args)
    im:include(inc);
    im:filledRectangle(0, 0, args.imagewidth, args.imageheight, 'url(#background)');
    im:stringTTF("title", math.floor(args.imagewidth / 2), args.fontsize * 2, args.titletext);
    if args.subtitletext ~= "" then
        im:stringTTF("subtitle", math.floor(args.imagewidth / 2), args.fontsize * 4, args.subtitletext)
    end
    im:stringTTF("details", args.xpad, args.imageheight - (args.ypad2 / 2), " ");
    im:stringTTF("unzoom", args.xpad, args.fontsize * 2, "Reset Zoom", 'class="hide"');
    im:stringTTF("search", args.imagewidth - args.xpad - 100, args.fontsize * 2, "Search");
    im:stringTTF("matched", args.imagewidth - args.xpad - 100, args.imageheight - (args.ypad2 / 2), " ");
    if args.palette then FlameGraph.read_palette() end

    im:group_start({id = "frames"})
    local escapes={
        ['&']='&amp;',
        ['<']='&lt;',
        ['>']='&gt;',
        ['"']='&quot;'
    }
    local function travel(parent,depth,x)
        for idx,func in ipairs(parent.__ELEMENTS__) do
            local node=parent[func]
            local stats=node.__STATS__
            local subtree,calls,delta=stats.subtree,stats.calls,stats.delta
            if subtree >= minwidth_time then
                if delta==0 then delta=nil end
                local x1=x;
                local x2=x + subtree * widthpertime;
                local y1,y2
                if args.inverted==0 then
                    y1 = args.imageheight - args.ypad2 - (depth + 1) * args.frameheight + args.framepad;
                    y2 = args.imageheight - args.ypad2 - depth * args.frameheight
                else
                    y1 = args.ypad1 + depth * args.frameheight;
                    y2 = args.ypad1 + (depth + 1) * args.frameheight - args.framepad;
                end

                local samples = ("%.2f"):format(subtree * args.factor)
                local sample_text=comma_value(samples+0)

                local info;
                if func == "" and depth == 0 then
                    info = ("all (%s %s, 100%%)"):format(sample_text,args.countname)
                else
                    local pct1=("%.2f"):format((100 * samples) / (args.timemax * args.factor)):gsub('%.?0+$','')
                    local pct2=("%.2f"):format((100 * calls) / args.timemax):gsub('%.?0+$','')
                    local pct3=("%.2f"):format((100 * (samples-calls)) / args.timemax):gsub('%.?0+$','')
                    --clean up SVG breaking characters:
                    local escaped_func = func:gsub('[&<>"]',escapes)
                    --strip any annotation
                    escaped_func=escaped_func:gsub('_%[[kwij]%]$','',1)
                    if not delta then
                        info =("%s [Unit=%s  Samples=%s(%s%%)  Self=%s(%s%%)  Subtree=%s(%s%%)]%s"):format(
                            escaped_func,args.countname,
                            sample_text,pct1,
                            comma_value(calls),pct2,
                            comma_value(samples-calls),pct3,
                            stats.desc~="" and ('\nDescription: '..stats.desc:gsub('[&<>"]',escapes)) or ''
                            )
                    else
                        local d= args.negate and -delta or delta
                        local deltapct = ("%.2f"):format((100 * d) / (args.timemax * args.factor))
                        deltapct = d > 0 and ("+"..deltapct) or deltapct
                        info = ("%s (%s %s, %s%%; %s%%)"):format(escaped_func,sample_text,args.countname,pct1,deltapct);
                    end
                end
                --shallow clone
                local nameattr = {}
                for k,v in pairs(args.nameattr[func] or {}) do nameattr[k]=v end
                nameattr.title=nameattr.title or info
                im:group_start(nameattr,depth+1);

                local color;
                if func == "--" then
                    color = args.vdgrey;
                elseif func == "-" then
                    color = args.dgrey;
                elseif delta then
                    color = FlameGraph.color_scale(delta, maxdelta)
                elseif args.palette then
                    color = FlameGraph.color_map(args.colors, func)
                else
                    color = FlameGraph.color(args.colors, args.hash, func);
                end
                im:filledRectangle(x1, y1, x2, y2, color, 'rx="2" ry="2"',depth+2);

                local chars = math.floor((x2 - x1) / (args.fontsize * args.fontwidth))
                local text = "";
                -- room for one char plus two dots
                if  chars >= 3 then
                    -- strip any annotation
                    func = func:gsub('_%[[kwij]%]$','',1)
                    text = func:sub(1,chars)
                    if chars < #func then text=text:sub(1,-3)..'..' end
                    text=text:gsub('[&<>"]',escapes)
                end
                im:stringTTF(nil, x1 + 3, 3 + (y1 + y2) / 2, text,nil,depth+2)
                im:group_end(nameattr,depth+1)
                travel(node,depth+1,x)
                x=x2
            end
        end
    end
    travel(stacks,0,args.xpad)
    im:group_end({})
    if (args.palette) then FlameGraph.write_palette() end
    return im:toSVG()
end
return FlameGraph