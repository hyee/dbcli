/*[[Show gv$pdbs]]*/

--set pivot 30 PIVOTSORT NAME
set COLSIZE 32
select * from gv$pdbs order by con_id,inst_id;