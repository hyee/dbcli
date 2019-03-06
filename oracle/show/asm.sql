/*[[Show asm disk groups
   --[[
       @fg: 11={,listagg(failgroup,',') within group(order by failgroup) failgroup}
   ]]--
]]*/
set feed off verify on
col reads,writes for tmb
col BYTES_READ,BYTES_WRITTEN for kmg
col AVG_R_TIME,AVG_W_TIME,AVG_TIME for usmhd0

select * from v$asm_diskgroup order by 1;
SELECT GROUP_NUMBER,
       NAME,
       SUM(ONLINES) ONLINES,
       SUM(OFFLINES) OFFLINES,
       SUM(NORMALS) NORMALS,
       SUM(ABNORMALS) ABNORMALS,
       SUM(ERRORS) ERRORS,
       SUM(READS) READS,
       SUM(BYTES_READ) BYTES_READ,
       SUM(AVG_R_TIME) AVG_R_TIME,
       SUM(WRITES) WRITES,
       SUM(BYTES_WRITTEN) BYTES_WRITTEN,
       SUM(AVG_W_TIME) AVG_W_TIME,
       SUM(AVG_TIME) AVG_TIME &fg
FROM   (SELECT group_number, NAME FROM v$asm_diskgroup) NATURAL
RIGHT JOIN   (SELECT GROUP_NUMBER,
               failgroup,
               COUNT(decode(MODE_STATUS, 'ONLINE', 1)) ONLINES,
               COUNT(decode(MODE_STATUS, 'OFFLINE', 1)) OFFLINES,
               COUNT(decode(STATE, 'NORMAL', 1)) NORMALS,
               SUM(decode(STATE, 'NORMAL', 0, 1)) ABNORMALS,
               SUM(READ_ERRS + WRITE_ERRS) errors,
               SUM(READS) READS,
               SUM(BYTES_READ) BYTES_READ,
               round(1e4 * SUM(READ_TIME) / nullif(SUM(READS), 0)) avg_r_time,
               SUM(WRITES) WRITES,
               SUM(BYTES_WRITTEN) BYTES_WRITTEN,
               round(1e4 * SUM(WRITE_TIME) / nullif(SUM(WRITES), 0)) avg_w_time,
               round(1e4 * SUM(READ_TIME+WRITE_TIME) / nullif(SUM(WRITES+READS), 0)) avg_time
        FROM   v$asm_disk
        GROUP  BY GROUP_NUMBER, failgroup)
GROUP  BY GROUP_NUMBER, NAME
ORDER  BY 1;

var x refcursor;
declare
   c sys_refcursor;
   grps VARCHAR2(4000);
BEGIN
   
   select LISTAGG('''#'||GROUP_NUMBER||''' AS DISKGROUP#'||GROUP_NUMBER||'',',') within group(order by GROUP_NUMBER) into grps from v$asm_diskgroup;
   OPEN C for '
        SELECT *
        FROM  (SELECT NAME, READ_ONLY,VALUE, ''#'' || group_number grp FROM V$ASM_ATTRIBUTE WHERE NAME NOT LIKE ''template%'')
        PIVOT (MAX(VALUE) FOR grp IN('||grps||'))
        ORDER BY name';
   
   :x := c;
END;
/