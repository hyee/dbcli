local env=env
local flame_alias = {
    title='titletext', subtitle='subtitletext', width='imagewidth', height='frameheight',
    total='timemax', notes='notestext', nameattr='nameattrfile', reverse='stackreverse',
    cp='palette', color='colors', countname='countname', colors='colors', minwidth='minwidth',
    fontsize='fontsize', fontwidth='fontwidth', fonttype='fonttype', factor='factor',
    inverted='inverted', hash='hash', random='random', flamechart='flamechart', negate='negate',
    bgcolors='bgcolors', searchcolor='searchcolor', nametype='nametype', encoding='encoding'
}
local flame_flags = { stackreverse=1, inverted=1, hash=1, random=1, flamechart=1, negate=1, palette=1 }
local flame_num = { imagewidth=1, frameheight=1, timemax=1, fontsize=1, fontwidth=1, factor=1 }

local function flame_help()
    return [[
Generate a flame graph (SVG) from folded stack data. Usage: @@NAME <file|variable> [<output>|<variable>] [key=value ...] [flags]
    The input is folded stacks: semicolon separated frames with a count at the
    end, e.g. "func_a;func_b;func_c 31" (an optional second count makes a
    differential graph). Each argument is resolved as a dbcli variable (VAR)
    first, then as a file; a bare file name resolves under the cache folder.
    The SVG is written next to the cache and its path is printed.
    hprof.sql / prof.sql call @@NAME automatically as
    "@@NAME folded svgname countname=us" after profiling.

    Options (key=value):
        title=TEXT        graph title (default "Flame Graph"; "Icicle Graph"
                          when inverted)
        subtitle=TEXT     second heading line
        colors=PALETTE    hot(default) mem io wakeup chain java js perl red green
                          blue aqua yellow purple orange teal pink lime brown
                          steel gold grey oracle (oracle = one hue per Oracle
                          kernel layer, ks/kc/kd/kt/q/kk/op/p/kg/kj...)
        bgcolors=COLOR    yellow(default) blue green grey, or #rrggbb
        countname=TEXT    what one count is (default "samples"; prof/hprof pass
                          countname=us for microseconds)
        minwidth=N[%]     skip frames narrower than N pixels, or N% of the total
        width=NUM         image width in pixels (default 1200)
        height=NUM        frame height in pixels (default 16)
        fontsize=NUM      base text size (default 12)
        fonttype=FONT     font family (default Verdana)
        factor=NUM        scale all counts by NUM (default 1)
        total=NUM         pretend the total is NUM, the root frame spans the
                          full width (must exceed the real total)
        notes=TEXT        note comment embedded into the SVG (no < or >)
        nameattr=FILE     per-function attribute file: "func<TAB>href=url..."
        nametype=TEXT     hover prefix (default "Function:")
        searchcolor=COLOR highlight color of search hits
        encoding=NAME     XML encoding attribute, e.g. encoding=UTF-8

    Flags (bare word, or =on / =1 / =true):
        hash              classic positional name-hash coloring
        random            truly random colors on every run
        reverse           reverse each stack before merging
        inverted          icicle graph, root on top, title "Icicle Graph"
        flamechart        keep input order, do not merge identical stacks
        negate            swap the differential hues (blue <-> red)
        cp                consistent palette, colors pinned via palette.map

    Examples:
        @@NAME hprof_3.collapsedstack.txt
        @@NAME folded svgname countname=us
        @@NAME cache\o19c\37.collapsedstack.txt title="ORA short stacks" colors=oracle
        @@NAME d:/data/perf.folded width=1600 minwidth=0.5% inverted
        @@NAME my.folded total=1000000 title=demo hash
        ora prof "some_proc;"                       (auto-flames via prof.sql)
        ora hprof DATA_PUMP_DIR t.txt "some_proc;"  (auto-flames via hprof.sql)

    The SVG is interactive: hover for stats, click to zoom, ctrl-F to search,
    ctrl-I toggles ignore-case, and the URL keeps ?x=&y=&s= so a zoomed or
    filtered view can be shared or bookmarked.
]]
end

-- flame <file|variable> [<output>|<variable>] [key=value ...]: render folded
-- stacks ("a;b;c count" lines) into an SVG flame graph under the cache folder.
-- An argument that names a dbcli variable (VAR) is read from the variable
-- instead of the file system; key=value options go to env.flamegraph.BuildGraph.
local function flame(...)
    local cnt = select('#', ...)
    if cnt == 0 or not env.flamegraph then
        print((flame_help():gsub('@@NAME', 'flame')))
        if cnt > 0 and not env.flamegraph then print("flamegraph module is not loaded.") end
        return
    end
    local overrides, name, output = {}, nil, nil
    for i = 1, cnt do
        local arg = tostring(select(i, ...))
        local k, v = arg:match('^([^=]+)=(.*)$')
        k = k and flame_alias[k:lower()] or nil
        if k then
            if flame_flags[k] then
                v = (v == '' or v == 'on' or v == '1' or v == 'true') and 1 or 0
            end
            if flame_num[k] then v = tonumber(v) or v end
            overrides[k] = v
        elseif not name then
            name = arg
        elseif flame_flags[flame_alias[arg:lower()] or ''] then
            overrides[flame_alias[arg:lower()]] = 1
        elseif not output then
            output = arg
        else
            print("flame: extra argument '"..arg.."' is ignored.")
        end
    end
    local varmod = env.var
    local is_var = varmod and varmod.inputs and varmod.inputs[name:upper()] and true or false
    local data
    if is_var then
        data = varmod.get_input(name)
        if data == nil or data == '' then return end -- nothing profiled (e.g. a list-only run), skip quietly
    else
        local file = env.resolve_file(name)
        local fh = io.open(file, 'r')
        if not fh then
            return print("flame: input '"..name.."' is neither a variable nor a readable file.")
        end
        data = fh:read('*a')
        fh:close()
        output = output or file:match('[^\\/]+$'):gsub('%.[^.]+$','')..'.svg'
    end
    if output and varmod and varmod.inputs and varmod.inputs[output:upper()] then
        output = varmod.get_input(output)
        if output == nil or output == '' then return end
    end
    local lines = {}
    for line in tostring(data):gsplit('[\r\n]+') do
        if line ~= '' then lines[#lines+1] = line end
    end
    local ok, svg = pcall(env.flamegraph.BuildGraph, lines, overrides)
    if not ok then return print('flame: '..tostring(svg)) end
    output = output or 'flamegraph.svg'
    if not output:lower():match('%.svg$') then output = output..'.svg' end
    print('FlameGraph is saved as '..env.write_cache(output, svg))
end

env.set_command(nil,"FLAME",flame_help,flame,false,30)
return flame
