/*[[Show LRU info]]*/
col gid noprint
set feed off
pro x$kcbwds
pro ========
SELECT grouping_id(inst_id,dbwr_num) gid,
	   nvl2(inst_id,''||inst_id,'*') inst,
       nvl2(dbwr_num,'DBW' || decode(sign(dbwr_num - 10), -1, '' || dbwr_num, chr(87 + dbwr_num)),'*') dbwr_num,
       nvl2(SET_ID,set_id,count(1)) set_id,
       SUM(cnum_set) "Work Set|Blocks",
       SUM(cnum_repl) "REPL Chain|Blocks",
       SUM(anum_repl) "Aux Chain|Blocks",
       SUM(cnum_write) "All Dirty|Blocks",
       SUM(anum_write) "Aux Dirty|Blocks"
FROM   TABLE(gv$(CURSOR (SELECT * FROM x$kcbwds WHERE cnum_set > 0)))
GROUP  BY ROLLUP(inst_id, (dbwr_num, addr, SET_ID))
ORDER  BY 1,2, 3, set_id;

pro x$kcbbes
pro ========
SELECT * FROM TABLE(gv$(CURSOR (SELECT * FROM x$kcbbes WHERE GREATEST(reason, priority, savecode) > 0)))
ORDER BY inst_id,indx