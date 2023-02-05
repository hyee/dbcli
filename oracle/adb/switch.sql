/*[[Switch the database service and consumer group of the current session. Usage: @@NAME <LOW|MEDIUM|HIGH|TP|TPURGENT>
    --[[
        @ARGS: 1
        @CHECK_ACCESS_CS: CS_SESSION={}
    --]]
]]*/

EXEC CS_SESSION.SWITCH_SERVICE(:V1);