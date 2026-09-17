/*[[Show gv$pdbs
    --[[
        @check_version: 12.1={}
    --]]
]]*/

--set pivot 30 PIVOTSORT NAME
set colsize 32
SELECT * FROM gv$pdbs ORDER BY con_id, inst_id;