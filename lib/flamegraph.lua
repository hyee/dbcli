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
  21-Nov-2013   Shawn Sterling  Added consistent palette file option
  17-Mar-2013   Tim Bunce       Added options and more tunables.
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
        if options.inverted ~= 0 then
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
    return ("rgb($r,$g,$b)"):gsub{r=math.floor(r),g=math.floor(g),b=math.floor(b)};
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
<?xml version="1.0"$enc_attr standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="$w" height="$h" onload="init(evt)" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<!-- Flame graph stack visualization. See https://github.com/brendangregg/FlameGraph for latest version, and http://www.brendangregg.com/flamegraphs.html for examples. -->
<!-- NOTES: $notestext -->]]):gsub{w=w,h=h,enc_attr=enc_attr,notestext=option.notestext}
end

function FlameGraph.SVG:include(content)
    self.svg[#self.svg+1] = content
end

function FlameGraph.SVG:colorAllocate(r,g,b)
    return rgb(r,g,b);
end

function FlameGraph.SVG:group_start(attr)
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

    self:include(('<%s %s>\n'):format(tag,table.concat(g_attr,' ')))
    if attr.title then self:include(('<title>%s</title>'):format(attr.title)) end
end

function FlameGraph.SVG:group_end(attr)
    self:include(attr.href and '</a>' or '</g>')
end

function FlameGraph.SVG:filledRectangle(x1, y1, x2, y2, fill, extra)
    local fmt="%0.1f"
    local attrs={
        w =fmt:format(x2-x1),
        h =fmt:format(y2-y1),
        x1=fmt:format(x1),
        x2=fmt:format(x2),
        extra = extra or '',
        fill=fill
    }
    self:include('<rect x="$x1" y="$y1" width="$w" height="$h" fill="$fill" $extra />\n',attrs)
end

function FlameGraph.SVG:stringTTF(id,x,y,str,extra)
    local attrs={
        x=("%0.2f"):format(x),
        y=("%0.2f"):format(y),
        str=str,
        id=id and (('id="%s"'):format(id)) or '',
        extra=extra or ''
    }
    self:include(('<text $id x="$x" y="$y" $extra>$str</text>\n'):format(attrs))
end

function FlameGraph.SVG:svg()
    return table.concat(svg,'')..'</svg>\n'
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
    mem    = function(_, v1, v3, v3) return rgb(0         , 190+50  * v2, 0+210 * v1) end, 
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
    value=options.negate==1 and -value or value
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
        options.palette_map[func]=color(colors,nil,func)
        return options.palette_map[func]
    end
end

function FlameGraph.write_palette()
    local keys={}
    for k,v in pairs(options.palette_map) do keys[#keys+1]=k..'->'..v end
    table.sort(keys)
    local file=io.open(options.pal_file,'w')
    file:write(table.concat('keys','\n')..'\n')
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

local Node,Tmp={},{}

function FlameGraph.flow(last,this,v,d)
    local len_name,len_a,len_b=1,#last,#this
    local len_name=math.min(math.min(#last,#this))

    for i=1,math.min(len_a,len_b) do
        if len_name==1 and last[i]~=this[i] then
            len_name=math.max(1,i-1)
        end
    end
    local fmt='%s;%s'
    for i=len_a,len_name,-1 do
        local k=fmt:format(last[i],i)
        local n,t=fmt:format(k,v)
        t,Tmp[k]=Tmp[k] or {},nil        
        if not Node[n] then Node[n]={} end
        Node[n].stime,Node[n].delta=t.stime,t.delta
    end

    for i=len_same,len_b,1 do
        local k=fmt:format(this[i],i)
        if not Tmp[k] then Tmp[k]={} end
        Tmp[k].stime=v
        if d then Tmp[k].delta=(Tmp[k].delta or 0) + (len_b==i and d or 0) end
    end
    return this
end

function FlameGraph.buildSVG()
    Node,tmp={},{}
    local Data={}
    local SortedData={}
    local last = {};
    local time = 0;
    local delta = undef;
    local ignored = 0;
    local line;
    local maxdelta = 1;
end

return FlameGraph