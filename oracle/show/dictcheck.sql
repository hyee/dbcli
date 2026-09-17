/*[[
    Check the data dictionary with DBMS_DICTIONARY_CHECK.FULL and print the inconsistencies found.
    Usage: @@NAME [-repair]
    -repair : Repair the inconsistencies found instead of only reporting them (default: false)
    --[[
        &repair: default={false} repair={true}
        @check_access_obj: sys.dbms_dictionary_check={1}
    --]]
]]*/

exec sys.dbms_dictionary_check.full(repair=>&repair);