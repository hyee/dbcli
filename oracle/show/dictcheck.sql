/*[[
    Run dbms_dictionary_check.full([repair=>true]). Usage: @@NAME [-repair]
    --[[
        &repair: default={false} repair={true}
        @check_access_obj: sys.dbms_dictionary_check={1}
    --]] 
]]*/

exec sys.dbms_dictionary_check.full(repair=>&repair);