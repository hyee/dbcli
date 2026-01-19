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
col io,offload_in,offload_out for kmg2
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

        IF dbid1 = dbid2 and (st1,ed1) overlaps (st2,ed2) THEN
            raise_application_error(-20001,'The snapshot ranges must not overlap each other in case of dbids are the same.');
        END IF;
        title := 'Comparing AWR snapshots(dbid='||dbid1||' | '||st1||' | '||ed1||') with (dbid='||dbid2||' | '||st2||' | '||ed2||'):';
    END IF;

    OPEN :c FOR
    WITH r AS(
        SELECT  /*+opt_param('_fix_control' '26552730:0') 
                opt_param('_no_or_expansion' 'true') 
                opt_param('_optimizer_cbqt_or_expansion' 'off')*/
                signature,
                grp,
                dbid,
                MAX(sql_id) keep(dense_rank LAST ORDER BY ela * (1+log(20, execs))) sql_id,
                plan_hash,
                count(distinct sql_id) sqls,
                SUM(execs) execs,
                '|' "|",
                ROUND(SUM(ela) / SUM(execs),2) avg_ela,
                ROUND(SUM(cpu_time) / SUM(execs),2) cpu_time,
                ROUND(SUM(io_time) / SUM(execs),2) io_time,
                ROUND(SUM(buff) / SUM(execs),2) buff,
                nullif(ROUND(SUM(reads) / SUM(execs),2),0) reads,
                nullif(ROUND(SUM(writes) / SUM(execs),2),0) writes,
                nullif(ROUND(SUM(dxwrites) / SUM(execs),2),0) dxwrites,
                nullif(ROUND(SUM(io) / SUM(execs),2),0) io,
                nullif(ROUND(SUM(ofl_in) / SUM(execs),2),0) ofl_in,
                nullif(ROUND(SUM(ofl_out) / SUM(execs),2),0) ofl_out,
                nullif(ROUND(SUM(rows_processed) / SUM(execs),2),0) "ROWS#"
        FROM   (SELECT  /*+outline_leaf use_hash(s)*/
                        dbid,
                        CASE WHEN dbid=dbid1 and end_interval_time+0 between st1 and ed1 THEN 'PRE' ELSE 'POST' END grp,
                        plan_hash_value plan_hash,
                        sql_id,
                        nvl(nullif(force_matching_signature,0),plan_hash_value) signature,
                        SUM(elapsed_time) ela,
                        SUM(executions) execs,
                        SUM(cpu_time) cpu_time,
                        SUM(iowait) io_time,
                        SUM(buffer_gets) buff,
                        SUM(readreq) reads,
                        SUM(writereq) writes,
                        SUM(direct_writes) dxwrites,
                        SUM(cellio) io,
                        SUM(oflin) ofl_in,
                        SUM(oflout) ofl_out,
                        SUM(rows_processed) rows_processed
                FROM    &awr$sqlstat
                WHERE  plan_hash_value > 0
                AND    (dbid=dbid1 and end_interval_time+0 between st1 and ed1 
                     or dbid=dbid2 and end_interval_time+0 between st2 and ed2)
                AND   (&filter)
                AND   ('&instance' is null or instance_number=0+'&instance')
                GROUP  BY 
                        dbid,plan_hash_value, sql_id, force_matching_signature,
                        CASE WHEN dbid=dbid1 and end_interval_time+0 between st1 and ed1 THEN 'PRE' ELSE 'POST' END
                HAVING SUM(executions_delta) > 0)
        GROUP  BY dbid,grp,plan_hash,&sql
    $IF DBMS_DB_VERSION.VERSION > 11 AND &snap=2 $THEN    
        UNION ALL
        SELECT  signature,
                'POST' grp,
                '&dbid'+0 dbid,
                MAX(sql_id) keep(dense_rank LAST ORDER BY ela * (1+log(20, execs))) sql_id,
                plan_hash,
                count(distinct sql_id) sqls,
                SUM(execs) execs,
                '|' "|",
                round(SUM(ela) / SUM(execs),2) ela,
                round(SUM(cpu_time) / SUM(execs),2) cpu_time,
                round(SUM(io_time) / SUM(execs),2) io_time,
                round(SUM(buff) / SUM(execs),2) buff,
                nullif(ROUND(SUM(reads) / SUM(execs),2),0) reads,
                nullif(ROUND(SUM(writes) / SUM(execs),2),0) writes,
                nullif(ROUND(SUM(dxwrites) / SUM(execs),2),0) dxwrites,
                nullif(ROUND(SUM(io) / SUM(execs),2),0) io,
                nullif(ROUND(SUM(ofl_in) / SUM(execs),2),0) ofl_in,
                nullif(ROUND(SUM(ofl_out) / SUM(execs),2),0) ofl_out,
                nullif(ROUND(SUM(rows_processed) / SUM(execs),2),0) "ROWS#"
        FROM   (SELECT  plan_hash_value plan_hash,
                        sql_id,
                        nvl(nullif(force_matching_signature,0),plan_hash_value) signature,
                        SUM(delta_elapsed_time) ela,
                        SUM(delta_execution_count) execs,
                        SUM(delta_cpu_time) cpu_time,
                        SUM(delta_user_io_wait_time) io_time,
                        SUM(delta_buffer_gets) buff,
                        SUM(delta_physical_read_requests) reads,
                        SUM(delta_physical_write_requests) writes,
                        SUM(delta_direct_writes) dxwrites,
                        SUM(delta_io_interconnect_bytes) io,
                        SUM(delta_cell_offload_elig_bytes) ofl_in,
                        SUM(io_cell_offload_returned_bytes/greatest(1,executions)*delta_execution_count) ofl_out,
                        SUM(delta_rows_processed) rows_processed
                FROM   gv$sqlstats
                WHERE  &snap = 2
                AND    sys_context('userenv','dbid')='&dbid'
                AND   (&filter)
                AND   ('&instance' is null or inst_id=0+'&instance')
                AND    plan_hash_value > 0
                GROUP  BY plan_hash_value, sql_id, force_matching_signature
                HAVING SUM(delta_execution_count) > 0)
        GROUP  BY plan_hash,&sql
    $END
    ),
    r1 AS(
        SELECT sum(decode(grp,'POST',all_ela/all_execs))  over(partition by &sql)/
            sum(decode(grp,'PRE',all_ela/all_execs)) over(partition by &sql) avg_diff,
            a.*,
            SYS_OP_COMBINED_HASH(&sql) hv,
            max(decode(grp,'POST',avg_ela*execs)) over(PARTITION BY &sql)/2 sig_weight
        FROM (SELECT r.*,
                    SUM(execs*avg_ela) over(partition by &sql,grp) all_ela,
                    SUM(execs) over(partition by &sql,grp) all_execs,
                    COUNT(distinct grp) OVER(PARTITION BY &sql) grps,
                    count(distinct grp) over(partition by plan_hash) plans 
            FROM   r) a
        WHERE grps>1 and (&same)
    ),
    r2 AS(
        SELECT /*+materialized*/ r.*,rownum seq 
        FROM (
            SELECT  dense_rank() over(order by sig_weight desc,avg_diff,hv) "#",
                    ratio_to_report(sig_weight) over() "Weight",
                    r1.*
            FROM    r1
            WHERE (avg_diff &diff)
            ORDER by "Weight" desc,avg_diff,hv,grp desc,avg_ela*execs desc) r
        WHERE "#"<=50
    ),
    txt AS(
        SELECT  sql_id,
                coalesce(CASE WHEN (select dbid from v$database)=dbid THEN
                    extractvalue(dbms_xmlgen.getxmltype(replace(q'~
                        select trim(to_char(substr(regexp_replace(sql_text,'\s+',' '),1,300))) sql_text
                        from   gv$sqlstats b
                        where  sql_id='#sql#'
                        and    rownum<2~',
                        '#sql#',sql_id)),
                    '//ROW/SQL_TEXT') END,
                    extractvalue(dbms_xmlgen.getxmltype(replace(replace(q'~
                        select trim(to_char(substr(regexp_replace(sql_text,'\s+',' '),1,300))) sql_text
                        from   dba_hist_sqltext b
                        where  dbid=#dbid#
                        and    sql_id='#sql#'
                        and    rownum<2~',
                        '#sql#',sql_id),'#dbid#',dbid)),
                    '//ROW/SQL_TEXT')) sql_text
        FROM   (
            SELECT /*+no_merge*/ distinct dbid,sql_id 
            FROM (SELECT max(sql_id) keep(dense_rank last order by grp) sql_id,
                         max(dbid) keep(dense_rank last order by grp) dbid
                  FROM r2 GROUP BY signature)
        )
    )
    SELECT /*+outline_leaf use_hash(r2 txt)*/
        r2.*,
        '||' "||",
        txt.sql_text
    FROM r2 LEFT JOIN txt ON(r2.sql_id=txt.sql_id)
    ORDER BY r2.seq;

    DBMS_OUTPUT.PUT_LINE(title);
    DBMS_OUTPUT.PUT_LINE(rpad('=',length(title),'='));
END;
/

print c