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
	select * from gv$database order by inst_id
]] &check_access_pdb,'-',[[/*grid={topic='database_properties'}*/
	select * from database_properties order by 1
]]}