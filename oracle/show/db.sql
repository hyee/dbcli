/*[[Show gv$database in pivot mode
    --[[
        @check_access_pdb: {
            pdb/gv$pdbs={,'|',[[select /*grid={topic='gv$pdbs', pivot=10, pivotsort='head'}*/ * from gv$pdbs order by inst_id]]}
            default={}
        }
    --]]
]]*/
set feed off
grid {[[/*grid={topic='gv$database', pivot=10, pivotsort='head'}*/
    SELECT * FROM gv$database ORDER BY inst_id
]] &check_access_pdb,'-',[[/*grid={topic='database_properties'}*/
    SELECT property_name, substr(property_value,1,60) property_value, description FROM database_properties ORDER BY 1
]]}