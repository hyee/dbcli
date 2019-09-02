/*[[Show LRU info]]*/
select inst_id,'DBW'||decode(sign(dbwr_num-10),-1,''||dbwr_num,chr(87+dbwr_num)) dbwr_num,addr,SET_ID,
	   cnum_set "Work Set|Blocks",cnum_repl "REPL Chain|Blocks",anum_repl "Aux Chain|Blocks",
	   cnum_write "All Dirty|Blocks", anum_write "Aux Dirty|Blocks"
from x$kcbwds where cnum_set>0
order by 1,2,set_id;