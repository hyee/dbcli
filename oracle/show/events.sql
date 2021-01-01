/*[[Show system level enabled events. Usage: @@NAME [-session|-system|-process]
    type: can be session,process or system
    --[[
        &target: session={session} system={system} process={process}
    --]]
]]*/
set feed off

pro write events into default trace file, please run 'loadtrace default' to download to tracefile
alter session set events 'immediate eventdump(&target)';