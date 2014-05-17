WITH r AS(
    SELECT nvl(to_date(nullif(:V1,'a'),'yymmdd'),trunc(sysdate)) d,
           TRIM(nullif(:V2,'a')) item,
           0+NVL(:V3,NVL2(nullif(:V2,'a'),'0','30'))+0 minutes,
           nvl(:V4,7) showdays
    FROM   DUAL
), 
r1 as (SELECT d "Date",
               o "Item",
               t1 costs,
               t1 - LAG(t1) OVER(PARTITION BY flag,o ORDER BY d) cost_diff,
               rows#,
               rows# - LAG(rows#) OVER(PARTITION BY flag,o ORDER BY d) rows_diff,
               to_char(started,'HH24:MI:SS ') started,
               to_char(completed,'HH24:MI:SS ') completed,
               to_char(LAG(completed) OVER(PARTITION BY flag,o ORDER BY d),'YYYY-MM-DD HH24:MI:SS') previous_completed,
               ROUND(com_cost - LAG(com_cost) OVER(PARTITION BY flag,o ORDER BY d)) com_diff,
               to_char(max(completed) over(PARTITION BY flag,d),'HH24:MI:SS ')  all_completed
        FROM   (SELECT a.*,
                       round(1440 * (completed-started),1) t1,
                       round(1440 * (completed-baseline),1) com_cost
                FROM   (SELECT flag,                               
                               TRUNC(log_dtime) d,
                               SUBSTR(operation_name, 1, INSTR(operation_name, '-') - 1) o,
                               MIN(log_dtime) started,
                               MAX(log_dtime) completed,
                               SUM(row_cnt) rows#,
                               MIN(MIN(log_dtime)) OVER(PARTITION BY flag,TRUNC(log_dtime)) baseline
                        FROM   (SELECT MOD(TRUNC(log_dtime) - TRUNC(SYSDATE - 1000), r.showdays) flag,
                                       a.*,
                                       MAX(DECODE(operation_name,
                                                  'pkg_cis_pnr_extract.p_indx_tab_load-000',
                                                  log_dtime)) over(PARTITION BY TRUNC(log_dtime)) start_time
                                FROM   PIPSBRR2CV92.ods_process_log a,r
                                WHERE  log_dtime BETWEEN trunc(r.d-r.showdays*2+1) AND r.d+0.99999                                      
                                AND    program_ID = 'RI2700')
                        WHERE  log_dtime >= nvl(start_time-5e-5, log_dtime)
                        GROUP  BY flag,
                                  TRUNC(log_dtime),
                                  SUBSTR(operation_name, 1, INSTR(operation_name, '-') - 1)
                        ) a
                )
       )
SELECT r1.* FROM  r1, r
WHERE   costs>=r.minutes AND "Date">r.d-r.showdays
AND    (item IS NULL OR "Item"= item)
ORDER  BY 1 desc,completed DESC, started DESC
