/*[[Show SGA stats]]*/
set feed off


pro SGA Components:
PRo ===============
select * from gv$sga_dynamic_components order by 1,2;

pro SGA Advise:
PRo ===============
SELECT * FROM gV$SGA_TARGET_ADVICE order by 1,2;

pro SGA STATS:
PRo ==========
SELECT INST_ID,POOL,NVL2(POOL,decode(NAME,'free memory','free memory','used memory'),NAME) typ,Round(SUM(bytes)/1024/1024,2) MB 
FROM GV$SGASTAT 
GROUP BY INST_ID,POOL,NVL2(POOL,decode(NAME,'free memory','free memory','used memory'),NAME) 
ORDER BY 1,2;

pro SGA Parameters:
pro ================
ora param sga