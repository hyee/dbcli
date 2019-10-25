/*[[Show Cell IO Reasons. Usage: @@NAME {[<keyword>] [-r]} | {<seconds> [-avg]}
    Parameters:
       <keyword> :  case-insensitive expression
       -r        :  the keyword is a Regular expression instead of a LIKE expression
       <seconds> :  take 2 snapshots with the specific seconds, then print the delta stats
       -avg      :  when <seconds> is specified, devide the delta stats with <seconds> instead of the total stats

    --[[
        @check_access_obj: v$cell_ioreason={}
        @CHECK_ACCESS_SL : SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
        &avg             : default={1} avg={&V2}
        &filter          : {
            like={upper(reason_name) LIKE upper('%&V1%')}
            r={regexp_like(reason_name,'&V1','i')}
        }
    --]]
]]*/
col reqs for tmb
col bytes,avg_bytes for kmg
set verify off feed off sep4k on printsize 1000
var cur refcursor
DECLARE
    v_stmt VARCHAR2(32767);
    v     VARCHAR2(300) := :v1;
BEGIN
    IF regexp_like(:V2,'^\d+$') THEN
        v_stmt :=q'[
            WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
                BEGIN
                    IF ID=1 THEN RETURN SYSTIMESTAMP;END IF;
                    &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
                    RETURN SYSTIMESTAMP;
                END;
                SELECT reason_name,
				       bytes,
				       reqs,
				       ratio_to_report(reqs) over() "%",
				       round(bytes / nullif(reqs,0), 2) avg_bytes,
				       CASE WHEN bytes / nullif(reqs,0) >= 128 * 1024 THEN 'YES' ELSE 'NO' END large_io
                FROM (
                    SELECT /*+ordered use_nl(timer stat) no_expand*/
                           reason_name,n,
                           SUM(v*DECODE(r, 1, -1, 1))/&AVG v
                    FROM   (SELECT /*+no_merge ordered use_nl(timer stat)*/ROWNUM r, sysdate+numtodsinterval(&V2,'second') mr FROM XMLTABLE('1 to 2')) dummy,
                            LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                            LATERAL (SELECT /*+no_merge */ reason_name, metric_name n, metric_value v FROM v$cell_ioreason a WHERE timer.stime IS NOT NULL) stat
                    GROUP  BY reason_name,n
                ) PIVOT(MAX(v) FOR n IN('Per Reason Bytes of IO' bytes, 'Per Reason Number of IOs' reqs))
                WHERE  (:v IS NULL AND bytes > 0 OR :v IS NOT NULL AND (&FILTER)) 
                ORDER  BY reqs DESC]';
        --dbms_output.put_line(v_stmt);
        OPEN :cur FOR v_stmt USING v,v;
    ELSE
        OPEN :cur FOR
			SELECT reason_name,
			       bytes,
			       reqs,
			       ratio_to_report(reqs) over() "%",
			       round(bytes / nullif(reqs,0), 2) avg_bytes,
			       CASE WHEN bytes / nullif(reqs,0) >= 128 * 1024 THEN 'YES' ELSE 'NO' END large_io
			FROM   (SELECT reason_name, metric_name n, SUM(metric_value) v 
				    FROM v$cell_ioreason 
				    WHERE (v IS NULL AND metric_value > 0 OR v IS NOT NULL AND (&FILTER)) 
				    GROUP BY reason_name, metric_name)
			PIVOT(MAX(v) FOR n IN('Per Reason Bytes of IO' bytes, 'Per Reason Number of IOs' reqs))
			ORDER  BY reqs DESC;
    END IF;
END;
/
col "%" for pct
print cur