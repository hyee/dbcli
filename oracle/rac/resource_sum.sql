/*[[Summarize the global resources]]*/
SELECT *
FROM   (SELECT master#, TYPE, SUM(cnt) cnt, Round(100 * ratio_to_report(SUM(cnt)) OVER(), 4) pct
        FROM   TABLE(gv$(CURSOR (
        	              SELECT substr(resource_name, instr(resource_name, '[', 1, 3) + 1, 2) TYPE,
                                 master_node master#,
                                 COUNT(*) cnt
                          FROM   v$ges_resource
                          GROUP  BY substr(resource_name, instr(resource_name, '[', 1, 3) + 1, 2), master_node)))
        GROUP  BY master#, TYPE
        ORDER  BY PCT DESC)
WHERE  ROWNUM <= 50
