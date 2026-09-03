/*[[
    Compare SQL pefromance by difference snapshot ranges. Usage: type `help @@NAME` for more details.
    * @@NAME [-awr] <yymmddhh24mi> <yymmddhh24mi> [<yymmddhh24mi>]                     : compare between snapshot ranges
    * @@NAME -gv   [<yymmddhh24mi> [<yymmddhh24mi>]]                                   : compare between awr snapshots and delta stats of gv$sqlstats
    * @@NAME -dbid <dbid1,yymmddhh24mi,yymmddhh24mi> <dbid2,yymmddhh24mi,yymmddhh24mi> : compare awr snapshots between two dbids

    Compare groups:
    ===============
    -m  : default, group by force_matching_signature
    -sql: group by SQL ID
    
    Filter diff:
    ============
    -regress           : only list the regressed SQLs
    -improve           : only list the improved SQLs
    -adj["<op><diff>"] : filter the avg_diff. i.e.: adj">=2"

    Other options:
    ==============
    -f"<filter>"       : additional filter on dba_hist_sqlstat/gv$sqstat
    -same              : exclude same plans that exists in both `PRE` and `POST`
    
    --[[
            &snap   :   awr={1} gv={2} dbid={3}
            &diff   :   default={=avg_diff} regress={>=1.2} improve={<=0.8} adj={}
            &filter :   default={1=1} f={}
            &sql    :    m={signature} sql={signature,sql_id}
            &same   :   default={1=1} same={plans=1 or grp='PRE'}
            &v1     :   deafult={&starttime}
            &v2     :   default={&endtime}
    --]]--
]]*/
ORA _sqlstat
col Weight,avg_diff for pct3 break
col avg_ela,cpu_time,io_time for usmhd2
col buff,reads,writes,dxwrites,execs,rows# for tmb1
col io,ofl_in,ofl_out for kmg2
col hv,sig_weight,plans,grps,all_ela,all_execs,seq,dbid noprint
col signature,# break
set autohide col
set verify off feed off
var c refcursor
DECLARE
    st1 DATE;
    ed1 DATE;
    st2 DATE;
    ed2 DATE;
    dbid1 INT := '&dbid';
    dbid2 INT;
    v1    VARCHAR2(128) := '&v1';
    v2    VARCHAR2(128) := '&v2';
    v3    VARCHAR2(128) := '&v3';
    title VARCHAR2(200);
BEGIN
    IF '&snap' = '1' THEN
        st2 := to_date(v2,'yymmddhh24miss');
        IF st2 IS NULL THEN
            raise_application_error(-20001,'Parameters: <yymmddhh24mi> <yymmddhh24mi> [<yymmddhh24mi>]');
        END IF;
        st1   := nvl(to_date(v1,'yymmddhh24miss'),sysdate-7);
        ed1   := st2 - numtodsinterval(1,'minute');
        ed2   := nvl(to_date(v3,'yymmddhh24miss'),sysdate+1);
        dbid2 := dbid1;
        title := 'Comparing AWR snapshots(dbid='||dbid1||' [ '||st1||' | '||ed1||' ] vs [ '||st2||' | '||ed2||' ]):';
    ELSIF '&snap' = '2' THEN
        st1   := nvl(to_date(v1,'yymmddhh24miss'),sysdate-3);
        ed1   := nvl(to_date(v2,'yymmddhh24miss'),sysdate+1);
        title := 'Comparing AWR snapshots(dbid='||dbid1||' | '||st1||' | '||ed1||') with GV$SQLSTATS:'; 

        IF dbms_db_version.version < 12 THEN
            raise_application_error(-20001,'The feature is only supported from Oracle 12c.');
        END IF;
    ELSIF '&snap' = '3' THEN
        dbid1 := trim(regexp_substr(v1,'[^,]+',1,1));
        st1   := nvl(to_date(trim(regexp_substr(v1,'[^,]+',1,2)),'yymmddhh24miss'),sysdate-7);
        ed1   := nvl(to_date(trim(regexp_substr(v1,'[^,]+',1,3)),'yymmddhh24miss'),sysdate+1);
        dbid2 := trim(regexp_substr(v2,'[^,]+',1,1));
        st2   := nvl(to_date(trim(regexp_substr(v2,'[^,]+',1,2)),'yymmddhh24miss'),sysdate-7);
        ed2   := nvl(to_date(trim(regexp_substr(v2,'[^,]+',1,3)),'yymmddhh24miss'),sysdate+1);

        IF dbid1 IS NULL OR dbid2 IS NULL THEN
            raise_application_error(-20001,'Parameters: -dbid <dbid1,yymmddhh24mi,yymmddhh24mi> <dbid2,yymmddhh24mi,yymmddhh24mi>');
        END IF;

        IF dbid1 = dbid2 AND (st1,ed1) OVERLAPS (st2,ed2) THEN
            raise_application_error(-20001,'The snapshot ranges must not overlap each other in case of dbids are the same.');
        END IF;
        title := 'Comparing AWR snapshots(dbid='||dbid1||' | '||st1||' | '||ed1||') with (dbid='||dbid2||' | '||st2||' | '||ed2||'):';
    END IF;

    OPEN :c FOR
    WITH r AS(
        SELECT  /*+opt_param('_fix_control' '26552730:0') 
                opt_param('_no_or_expansion' 'true')
                opt_param('parallel_execution_enabled', 'false')
                opt_param('_optimizer_cbqt_or_expansion' 'off')*/
                signature,
                grp,
                dbid,
                max(sql_id) KEEP(dense_rank LAST ORDER BY ela * (1+log(20, execs))) sql_id,
                plan_hash,
                count(DISTINCT sql_id) sqls,
                sum(execs) execs,
                '|' "|",
                round(sum(ela) / sum(execs),2) avg_ela,
                round(sum(cpu_time) / sum(execs),2) cpu_time,
                round(sum(io_time) / sum(execs),2) io_time,
                round(sum(buff) / sum(execs),2) buff,
                nullif(round(sum(reads) / sum(execs),2),0) reads,
                nullif(round(sum(writes) / sum(execs),2),0) writes,
                nullif(round(sum(dxwrites) / sum(execs),2),0) dxwrites,
                nullif(round(sum(io) / sum(execs),2),0) io,
                nullif(round(sum(ofl_in) / sum(execs),2),0) ofl_in,
                nullif(round(sum(ofl_out) / sum(execs),2),0) ofl_out,
                nullif(round(sum(rows_processed) / sum(execs),2),0) "ROWS#"
        FROM   (SELECT  dbid,
                        CASE WHEN dbid=dbid1 AND end_interval_time+0 BETWEEN st1 AND ed1 THEN 'PRE' ELSE 'POST' END grp,
                        plan_hash_value plan_hash,
                        sql_id,
                        nvl(nullif(force_matching_signature,0),plan_hash_value) signature,
                        sum(elapsed_time) ela,
                        sum(exec) execs,
                        sum(cpu_time) cpu_time,
                        sum(iowait) io_time,
                        sum(buffer_gets) buff,
                        sum(readreq) reads,
                        sum(writereq) writes,
                        sum(direct_writes) dxwrites,
                        sum(cellio) io,
                        sum(oflin) ofl_in,
                        sum(oflout) ofl_out,
                        sum(rows_processed) rows_processed
                FROM (SELECT a.*,
                             a.executions+CASE WHEN flag_=1 AND first_value(flag_) over(PARTITION BY dbid,instance_number,sql_id,plan_hash_value,instance_start ORDER BY snap_id RANGE BETWEEN 1 FOLLOWING AND 1 FOLLOWING) IS NULL then 1 else 0 end exec
                      FROM   &awr$sqlstat a
                      WHERE  plan_hash_value > 0
                      AND   (dbid=dbid1 AND end_interval_time+0 BETWEEN st1 AND ed1 OR 
                             dbid=dbid2  AND end_interval_time+0 BETWEEN st2 AND ed2)
                      AND   (&filter)
                      AND   ('&instance' IS NULL OR instance_number=0+'&instance')) a
                GROUP  BY dbid,plan_hash_value, sql_id, force_matching_signature,
                          CASE WHEN dbid=dbid1 AND end_interval_time+0 BETWEEN st1 AND ed1 THEN 'PRE' ELSE 'POST' END
                HAVING sum(exec) > 0)
        GROUP  BY dbid,grp,plan_hash,&sql
    $IF dbms_db_version.version > 11 AND &snap=2 $THEN    
        UNION ALL
        SELECT  signature,
                'POST' grp,
                '&dbid'+0 dbid,
                max(sql_id) KEEP(dense_rank LAST ORDER BY ela * (1+log(20, execs))) sql_id,
                plan_hash,
                count(DISTINCT sql_id) sqls,
                sum(execs) execs,
                '|' "|",
                round(sum(ela) / sum(execs),2) ela,
                round(sum(cpu_time) / sum(execs),2) cpu_time,
                round(sum(io_time) / sum(execs),2) io_time,
                round(sum(buff) / sum(execs),2) buff,
                nullif(round(sum(reads) / sum(execs),2),0) reads,
                nullif(round(sum(writes) / sum(execs),2),0) writes,
                nullif(round(sum(dxwrites) / sum(execs),2),0) dxwrites,
                nullif(round(sum(io) / sum(execs),2),0) io,
                nullif(round(sum(ofl_in) / sum(execs),2),0) ofl_in,
                nullif(round(sum(ofl_out) / sum(execs),2),0) ofl_out,
                nullif(round(sum(rows_processed) / sum(execs),2),0) "ROWS#"
        FROM   (SELECT  plan_hash_value plan_hash,
                        sql_id,
                        nvl(nullif(force_matching_signature,0),plan_hash_value) signature,
                        sum(delta_elapsed_time) ela,
                        sum(delta_execution_count) execs,
                        sum(delta_cpu_time) cpu_time,
                        sum(delta_user_io_wait_time) io_time,
                        sum(delta_buffer_gets) buff,
                        sum(delta_physical_read_requests) reads,
                        sum(delta_physical_write_requests) writes,
                        sum(delta_direct_writes) dxwrites,
                        sum(delta_io_interconnect_bytes) io,
                        sum(delta_cell_offload_elig_bytes) ofl_in,
                        sum(io_cell_offload_returned_bytes/greatest(1,executions)*delta_execution_count) ofl_out,
                        sum(delta_rows_processed) rows_processed
                FROM   gv$sqlstats
                WHERE  &snap = 2
                AND    sys_context('userenv','dbid')='&dbid'
                AND   (&filter)
                AND   ('&instance' IS NULL OR inst_id=0+'&instance')
                AND    plan_hash_value > 0
                GROUP  BY plan_hash_value, sql_id, force_matching_signature
                HAVING sum(delta_execution_count) > 0)
        GROUP  BY plan_hash,&sql
    $END
    ),
    r1 AS(
        SELECT sum(decode(grp,'POST',all_ela/all_execs))  OVER(PARTITION BY &sql)/
            sum(decode(grp,'PRE',all_ela/all_execs)) OVER(PARTITION BY &sql) avg_diff,
            a.*,
            sys_op_combined_hash(&sql) hv,
            max(decode(grp,'POST',avg_ela*execs)) OVER(PARTITION BY &sql)/2 sig_weight
        FROM (SELECT r.*,
                    sum(execs*avg_ela) OVER(PARTITION BY &sql,grp) all_ela,
                    sum(execs) OVER(PARTITION BY &sql,grp) all_execs,
                    count(DISTINCT grp) OVER(PARTITION BY &sql) grps,
                    count(DISTINCT grp) OVER(PARTITION BY plan_hash) plans 
            FROM   r) a
        WHERE grps>1 AND (&same)
    ),
    r2 AS(
        SELECT /*+materialized*/ r.*,ROWNUM seq 
        FROM (
            SELECT  dense_rank() OVER(ORDER BY sig_weight DESC,avg_diff,hv) "#",
                    ratio_to_report(sig_weight) OVER() "Weight",
                    r1.*
            FROM    r1
            WHERE (avg_diff &diff)
            ORDER BY "Weight" DESC,avg_diff,hv,grp DESC,avg_ela*execs DESC) r
        WHERE "#"<=50
    ),
    txt AS(
        SELECT  sql_id,
                coalesce(CASE WHEN (SELECT dbid FROM v$database)=dbid THEN
                    extractvalue(dbms_xmlgen.getxmltype(replace(q'~
                        SELECT --+cursor_sharing_force
                               trim(to_char(substr(regexp_replace(sql_text,'\s+',' '),1,300))) sql_text
                        FROM   gv$sqlstats b
                        WHERE  sql_id='#sql#'
                        AND    ROWNUM<2~',
                        '#sql#',sql_id)),
                    '//ROW/SQL_TEXT') END,
                    extractvalue(dbms_xmlgen.getxmltype(replace(replace(q'~
                        SELECT --+cursor_sharing_force
                               trim(to_char(substr(regexp_replace(sql_text,'\s+',' '),1,300))) sql_text
                        FROM   dba_hist_sqltext b
                        WHERE  dbid=#dbid#
                        AND    sql_id='#sql#'
                        AND    ROWNUM<2~',
                        '#sql#',sql_id),'#dbid#',dbid)),
                    '//ROW/SQL_TEXT')) sql_text
        FROM   (
            SELECT /*+no_merge*/ DISTINCT dbid,sql_id 
            FROM (SELECT max(sql_id) KEEP(dense_rank LAST ORDER BY grp) sql_id,
                         max(dbid) KEEP(dense_rank LAST ORDER BY grp) dbid
                  FROM r2 GROUP BY signature)
        )
    )
    SELECT /*+outline_leaf use_hash(r2 txt)*/
        r2.*,
        '||' "||",
        txt.sql_text
    FROM r2 LEFT JOIN txt ON(r2.sql_id=txt.sql_id)
    ORDER BY r2.seq;

    dbms_output.put_line(title);
    dbms_output.put_line(rpad('=',length(title),'='));
END;
/

print c