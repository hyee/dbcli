/*[[Check database patch info. Usage: @@NAME [<patch_number>]
    --[[
        @ver: 12.1={}
    --]]
]]*/

set feed off
var cur refcursor
BEGIN
    IF :V1 IS NOT NULL THEN
        open :cur for select xmltransform(dbms_qopatch.is_patch_installed(:V1), dbms_qopatch.get_opatch_xslt) "Patch installed?" from dual;
    ELSE
        open :cur for select xmltransform(dbms_qopatch.get_opatch_lsinventory, dbms_qopatch.get_opatch_xslt) from dual;
    END IF;
END;
/