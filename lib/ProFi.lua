--[[
    ProFi v1.3, by Luke Perkin 2012. MIT Licpackere http://www.opensource.org/licenses/mit-license.php.

    Example:
        ProFi = require 'ProFi'
        ProFi:start()
        some_function()
        another_function()
        coroutine.resume( some_coroutine )
        ProFi:stop()
        ProFi:writeReport( 'MyProfilingReport.txt' )

    API:
    *Arguments are specified as: type/name/default.
        ProFi:start( string/once/nil )
        ProFi:stop()
        ProFi:checkMemory( number/interval/0, string/note/'' )
        ProFi:writeReport( string/filename/'ProFi.txt' )
        ProFi:reset()
        ProFi:setHookCount( number/hookCount/0 )
        ProFi:setGetTimeMethod( function/getTimeMethod/os.clock )
        ProFi:setInspect( string/methodName, number/levels/1 )
]]

-----------------------
-- Locals:
-----------------------
local debug,table,string=debug,table,string
local ProFi = {}
local onDebugHook, sortByDurationDesc, sortByCallCount, getTime
local DEFAULT_DEBUG_HOOK_COUNT = 0
local FORMAT_HEADER_LINE       = "| %-50s: %-40s: %-20s: %-12s: %-12s: %-12s: %-12s|\n"
local FORMAT_OUTPUT_LINE       = "| %s: %-12s: %-12s: %-12s: %-12s|\n"
local FORMAT_INSPECTION_LINE   = "> %s: %-12s\n"
local FORMAT_TOTALTIME_LINE    = "| TOTAL TIME = %f\n"
local FORMAT_MEMORY_LINE        = "| %-20s: %-16s: %-16s| %s\n"
local FORMAT_HIGH_MEMORY_LINE  = "H %-20s: %-16s: %-16sH %s\n"
local FORMAT_LOW_MEMORY_LINE   = "L %-20s: %-16s: %-16sL %s\n"
local FORMAT_TITLE             = "%-50.50s: %-40.40s: %-20s"
local FORMAT_LINENUM           = "%4i"
local FORMAT_TIME              = "%04.3f"
local FORMAT_RELATIVE          = "%03.2f%%"
local FORMAT_COUNT             = "%7i"
local FORMAT_KBYTES             = "%7i Kbytes"
local FORMAT_MBYTES             = "%7.1f Mbytes"
local FORMAT_MEMORY_HEADER1    = "\n=== HIGH & LOW MEMORY USAGE ===============================\n"
local FORMAT_MEMORY_HEADER2    = "=== MEMORY USAGE ==========================================\n"
local FORMAT_BANNER            = [[
###############################################################################################################
#####  ProFi, a lua profiler. This profile was generated on: %s
#####  ProFi is created by Luke Perkin 2012 under the MIT Licpackere, www.locofilm.co.uk
#####  Version 1.3. Get the most recent version at this gist: https://gist.github.com/2838755
###############################################################################################################

]]

-----------------------
-- Public Methods:
-----------------------

--[[
    Starts profiling any method that is called between this and ProFi:stop().
    Pass the parameter 'once' to so that this methodis only run once.
    Example:
        ProFi:start( 'once' )
]]
function ProFi:start( param )
    if param == 'once' then
        if self:shouldReturn() then
            return
        else
            self.should_run_once = true
        end
    end
    self.has_started  = true
    self.has_finished = false
    self:resetReports( self.reports )
    self:startHooks()
    self.startTime = getTime()
end

--[[
    Stops profiling.
]]
function ProFi:stop()
    if self:shouldReturn() then
        return
    end
    self.stopTime = getTime()
    self:stopHooks()
    self.has_finished = true
end

function ProFi:checkMemory( interval, note )
    local time = getTime()
    local interval = interval or 0
    if self.lastCheckMemoryTime and time < self.lastCheckMemoryTime + interval then
        return
    end
    self.lastCheckMemoryTime = time
    local memoryReport = {
        ['time']   = time;
        ['memory'] = collectgarbage('count');
        ['note']   = note or '';
    }
    table.insert( self.memoryReports, memoryReport )
    self:setHighestMemoryReport( memoryReport )
    self:setLowestMemoryReport( memoryReport )
end

--[[
    Writes the profile report to a file.
    Param: [filename:string:optional] defaults to 'ProFi.txt' if not specified.
]]
function ProFi:writeReport( filename )
    if #self.reports > 0 or #self.memoryReports > 0 then
        filename = filename or 'ProFi.txt'
        self:sortReportsWithSortMethod( self.reports, self.sortMethod )
        self:writeReportsToFilename( filename )
        print( string.format("[ProFi]\t Report written to %s", filename) )
    end
end

--[[
    Resets any profile information stored.
]]
function ProFi:reset()
    self.reports = {}
    self.titles={}
    self.hookfunc=nil
    self.reportsByTitle = {}
    self.memoryReports  = {}
    self.highestMemoryReport = nil
    self.lowestMemoryReport  = nil
    self.has_started  = false
    self.has_finished = false
    self.should_run_once = false
    self.lastCheckMemoryTime = nil
    self.hookCount = self.hookCount or DEFAULT_DEBUG_HOOK_COUNT
    self.sortMethod = self.sortMethod or sortByDurationDesc
    self.inspect = nil
    self.currentLevel = 0
    self.sequpackere = 0
    self.previousCall=nil
end

--[[
    Set how often a hook is called.
    See http://pgl.yoyo.org/luai/i/debug.sethook for information.
    Param: [hookCount:number] if 0 ProFi counts every time a function is called.
    if 2 ProFi counts every other 2 function calls.
]]
function ProFi:setHookCount( hookCount )
    self.hookCount = hookCount
end

--[[
    Set how the report is sorted when written to file.
    Param: [sortType:string] either 'duration' or 'count'.
    'duration' sorts by the time a method took to run.
    'count' sorts by the number of times a method was called.
]]
function ProFi:setSortMethod( sortType )
    if sortType == 'duration' then
        self.sortMethod = sortByDurationDesc
    elseif sortType == 'count' then
        self.sortMethod = sortByCallCount
    end
end

--[[
    By default the getTime method is os.clock (CPU time),
    If you wish to use other time methods pass it to this function.
    Param: [getTimeMethod:function]
]]
function ProFi:setGetTimeMethod( getTimeMethod )
    getTime = getTimeMethod
end

--[[
    Allows you to inspect a specific method.
    Will write to the report a list of methods that
    call this method you're inspecting, you can optionally
    provide a levels parameter to traceback a number of levels.
    Params: [methodName:string] the name of the method you wish to inspect.
            [levels:number:optional] the amount of levels you wish to traceback, defaults to 1.
]]
function ProFi:setInspect( methodName, levels )
    if self.inspect then
        self.inspect.methodName = methodName
        self.inspect.levels = levels or 1
    else
        self.inspect = {
            ['methodName'] = methodName;
            ['levels'] = levels or 1;
        }
    end
end

-----------------------
-- Implementations methods:
-----------------------

function ProFi:shouldReturn( )
    return self.should_run_once and self.has_finished
end


function ProFi:getTitleFromFuncInfo( funcInfo )
    local name,source,linedefined= (funcInfo.name or 'anonymous')..'('..funcInfo.what..')',
       funcInfo.short_src or 'C_FUNC',funcInfo.linedefined or 0
    linedefined = string.format( FORMAT_LINENUM, linedefined )
    return string.format(FORMAT_TITLE, source, name, linedefined)
end

function ProFi:createFuncReport( title )
    local funcReport = {
        ['title']         = title;
        ['count']         = 0;
        ['timer']         = 0;
        ['backs']         = 0;
        ['sequpackere']      = 0;
        ['level']         = 0;
    }
    return funcReport
end

function ProFi:getFuncReport( funcInfo )
    local title = self:getTitleFromFuncInfo( funcInfo )
    local funcReport = self.reportsByTitle[ title ]
    if not funcReport then
        funcReport = self:createFuncReport( title )
        self.reportsByTitle[ title ] = funcReport
        table.insert( self.reports, funcReport )
    end
    return funcReport
end

function ProFi:startHooks()
    debug.sethook( onDebugHook, 'cr', self.hookCount )
end

function ProFi:stopHooks()
    debug.sethook()
end

function ProFi:sortReportsWithSortMethod( reports, sortMethod )
    if reports then
        table.sort( reports, sortMethod )
    end
end

function ProFi:writeReportsToFilename( filename )
    local file, err = io.open( filename, 'w' )
    assert( file, err )
    self:writeBannerToFile( file )
    if #self.reports > 0 then
        self:writeProfilingReportsToFile( self.reports, file )
    end
    if #self.memoryReports > 0 then
        self:writeMemoryReportsToFile( self.memoryReports, file )
    end
    file:close()
end

function ProFi:writeProfilingReportsToFile( reports, file )
    local totalTime = self.stopTime - self.startTime
    local totalTimeOutput =  string.format(FORMAT_TOTALTIME_LINE, totalTime)
    file:write( totalTimeOutput )
    local header = string.format( FORMAT_HEADER_LINE, "FILE", "FUNCTION", "LINE", "TIME", "RELATIVE", "CALLS","RETURNS" )
    file:write( header )
    local ratio=(totalTime-(self.hookfunc.timer or 0))/totalTime
     for i, funcReport in ipairs( reports ) do
         local cost          = funcReport.timer
         if funcReport ~= self.hookfunc then  cost=cost*ratio end
        local timer         = string.format(FORMAT_TIME, cost)
        local count         = string.format(FORMAT_COUNT, funcReport.count)
        local backs         = string.format(FORMAT_COUNT, funcReport.backs)
        local relTime         = string.format(FORMAT_RELATIVE, (cost / totalTime) * 100 )
        local outputLine    = string.format(FORMAT_OUTPUT_LINE, funcReport.title, timer, relTime, count ,backs)
        file:write( outputLine )
        if funcReport.inspections then
            self:writeInpsectionsToFile( funcReport.inspections, file )
        end
    end
end

function ProFi:writeMemoryReportsToFile( reports, file )
    file:write( FORMAT_MEMORY_HEADER1 )
    self:writeHighestMemoryReportToFile( file )
    self:writeLowestMemoryReportToFile( file )
    file:write( FORMAT_MEMORY_HEADER2 )
    for i, memoryReport in ipairs( reports ) do
        local outputLine = self:formatMemoryReportWithFormatter( memoryReport, FORMAT_MEMORY_LINE )
        file:write( outputLine )
    end
end

function ProFi:writeHighestMemoryReportToFile( file )
    local memoryReport = self.highestMemoryReport
    local outputLine   = self:formatMemoryReportWithFormatter( memoryReport, FORMAT_HIGH_MEMORY_LINE )
    file:write( outputLine )
end

function ProFi:writeLowestMemoryReportToFile( file )
    local memoryReport = self.lowestMemoryReport
    local outputLine   = self:formatMemoryReportWithFormatter( memoryReport, FORMAT_LOW_MEMORY_LINE )
    file:write( outputLine )
end

function ProFi:formatMemoryReportWithFormatter( memoryReport, formatter )
    local time       = string.format(FORMAT_TIME, memoryReport.time)
    local kbytes     = string.format(FORMAT_KBYTES, memoryReport.memory)
    local mbytes     = string.format(FORMAT_MBYTES, memoryReport.memory/1024)
    local outputLine = string.format(formatter, time, kbytes, mbytes, memoryReport.note)
    return outputLine
end

function ProFi:writeBannerToFile( file )
    local banner = string.format(FORMAT_BANNER, os.date())
    file:write( banner )
end

function ProFi:writeInpsectionsToFile( inspections, file )
    local inspectionsList = self:sortInspectionsIntoList( inspections )
    file:write('\n==^ INSPECT ^======================================================================================================== COUNT ===\n')
    for i, inspection in ipairs( inspectionsList ) do
        local line             = string.format(FORMAT_LINENUM, inspection.line)
        local title         = string.format(FORMAT_TITLE, inspection.source, inspection.name, line)
        local count         = string.format(FORMAT_COUNT, inspection.count)
        local outputLine    = string.format(FORMAT_INSPECTION_LINE, title, count )
        file:write( outputLine )
    end
    file:write('===============================================================================================================================\n\n')
end

function ProFi:sortInspectionsIntoList( inspections )
    local inspectionsList = {}
    for k, inspection in pairs(inspections) do
        inspectionsList[#inspectionsList+1] = inspection
    end
    table.sort( inspectionsList, sortByCallCount )
    return inspectionsList
end

function ProFi:resetReports( reports )
    for i, report in ipairs( reports ) do
        report.timer = 0
        report.count = 0
        report.inspections = nil
    end
end

function ProFi:getInspectionsFromReport( funcReport )
    local inspections = funcReport.inspections
    if not inspections then
        inspections = {}
        funcReport.inspections = inspections
    end
    return inspections
end

function ProFi:getInspectionWithKeyFromInspections( key, inspections )
    local inspection = inspections[key]
    if not inspection then
        inspection = {
            ['count']  = 0;
        }
        inspections[key] = inspection
    end
    return inspection
end

function ProFi:shouldInspect( funcInfo )
    return self.inspect and self.inspect.methodName == funcInfo.name
end

function ProFi:doInspection( inspect, funcReport )
    local inspections = self:getInspectionsFromReport( funcReport )
    local levels = 5 + inspect.levels
    local currentLevel = 5
    while currentLevel < levels do
        local funcInfo = debug.getinfo(currentLevel, 'nS' )
        if funcInfo then
            local source = funcInfo.short_src or '[C]'
            local name = funcInfo.name or 'anonymous'
            local line = funcInfo.linedefined
            local key = source..name..line
            local inspection = self:getInspectionWithKeyFromInspections( key, inspections )
            inspection.source = source
            inspection.name = name
            inspection.line = line
            inspection.count = inspection.count + 1
            currentLevel = currentLevel + 1
        else
            break
        end
    end
end


function ProFi:onFunctionCall( funcInfo ,tim)
    local funcReport = self:getFuncReport( funcInfo )
    if not funcReport.title:find("[C]",1,true) then
        self.currentLevel,self.sequpackere=self.currentLevel+1,self.sequpackere+1
    end
    --[[if funcReport.callTime then
                funcReport.timer = funcReport.timer + (tim - funcReport.callTime)
            end]]
    funcReport.callTime,funcReport.count,funcReport.sequpackere,funcReport.level =
        tim,funcReport.count+1,self.sequpackere,self.currentLevel
    if self.previousCall then
        self.previousCall.timer=self.previousCall.timer + (tim - self.previousCall.callTime)
    end
    self.previousCall=funcReport
    if self:shouldInspect( funcInfo ) then
        self:doInspection( self.inspect, funcReport )
    end

end

function ProFi:onFunctionReturn( funcInfo ,tim)
    local funcReport = self:getFuncReport( funcInfo )
    self.currentLevel=funcReport.level-1
    if funcReport.callTime then
        funcReport.timer = funcReport.timer + (tim - funcReport.callTime)
    end
    funcReport.callTime,funcReport.backs,funcReport.level=tim,funcReport.backs+1,self.currentLevel
end

function ProFi:setHighestMemoryReport( memoryReport )
    if not self.highestMemoryReport then
        self.highestMemoryReport = memoryReport
    else
        if memoryReport.memory > self.highestMemoryReport.memory then
            self.highestMemoryReport = memoryReport
        end
    end
end

function ProFi:setLowestMemoryReport( memoryReport )
    if not self.lowestMemoryReport then
        self.lowestMemoryReport = memoryReport
    else
        if memoryReport.memory < self.lowestMemoryReport.memory then
            self.lowestMemoryReport = memoryReport
        end
    end
end

-----------------------
-- Local Functions:
-----------------------

getTime = os.clock

onDebugHook = function( hookType )
    local tim,hooker=getTime(),ProFi.hookfunc
    if not hooker then
        hooker= debug.getinfo( 1, 'nS' )
        hooker.name='onDebugHook'
        hooker=ProFi:getFuncReport(hooker)
        ProFi.hookfunc=hooker
    end

    local funcInfo = debug.getinfo( 2, 'nS' )
    if hookType == "call" then
        ProFi:onFunctionCall( funcInfo,tim )
    elseif hookType == "return" then
        ProFi:onFunctionReturn( funcInfo,tim )
    end
    hooker.count,hooker.backs,hooker.timer=hooker.count+1,hooker.backs+1,hooker.timer+getTime()-tim
end

sortByDurationDesc = function( a, b )
    return a.timer > b.timer
end

sortByCallCount = function( a, b )
    return a.count > b.count
end

-----------------------
-- Return Module:
-----------------------

ProFi:reset()
return ProFi