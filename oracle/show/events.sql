/*[[Show system level enabled events. Usage: @@NAME [-t"<type>"]
    type: can be session,process or system
    --[[
        &target: default={session} t={}
    --]]
]]*/
set feed off

pro write events into default trace file, please run 'loadtrace default' to download to tracefile
alter session set events 'immediate eventdump(&target)';