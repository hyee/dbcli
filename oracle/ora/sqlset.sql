/*[[
Show/Operate SQL Tuning Sets. Usage: @@NAME <sqlset> [create|load|drop|spa [<sql_id>|-f"<filter>"]]
    @@NAME <sqlset> [<filter>]             : list matched SQLs from target sqlse
    @@NAME <sqlset> create [<description>] : create target sqlset
    @@NAME <sqlset> ref     <description>  : create reference to target sqlset
    @@NAME <sqlset> unref   <ref id>       : remove reference from target sqlset
    @@NAME <sqlset> scan    <filter>       : scan matched SQLs before loading into target sqlset
    @@NAME <sqlset> load    <filter>       : load matched SQLs into target sqlset
    @@NAME <sqlset> drop   [<filter>]      : drop targt sqlset

Parameters:
    <sqlset>: SQLSET_ID or SQLSET_NAME
    <filter>: Can be one of following:
              * <plan_hash_value>
              * <force_matching_signture>
              * <sql_id> [<plan_hash_value>]
              * -f"<customized predicates>"
    --[[
        @check_access_dba: dba_sqlset_statements={dba_} default={all}
        @last_exec: 12.2={last_exec_start_time last_exec,} default={}
        &filter   : default={filter IS NULL or upper(filter) in(upper(sql_id),''||plan_hash_value,parsing_schema_name)} f={}
        &f        : default={0} f={1}
    --]]--
]]*/

set feed off
var c refcursor
col ela,avg_ela for usmhd2
col "cpu,<= %" for pct2
col execs for tmb2

DECLARE
    sqlset  VARCHAR2(128):=replace(upper(:V1),'"');
    sid     PLS_INTEGER  :=regexp_substr(sqlset,'^\d+$'); 
    v2      VARCHAR2(128):=:V2;
    v3      VARCHAR2(128):=:V3;
    v4      VARCHAR2(128):=:V4;
    op      VARCHAR2(128):=upper(V2);
    usr     VARCHAR2(128):=sys_context('userenv','current_schema');
    fullset VARCHAR2(128);
    filter  VARCHAR2(2000);
    stmt    VARCHAR2(30000);
    active  PLS_INTEGER := 0;
    c       SYS_REFCURSOR;
    dbid    INT;
    TYPE    t IS TABLE OF VARCHAR2(500);
    row     SYS.SQLSET_ROW := SYS.SQLSET_ROW();
    sets    SYS.SQLSET := SYS.SQLSET();
    PROCEDURE check_sqlset(own VARCHAR2:=NULL) IS
        tmp_owner VARCHAR2(128) := nvl(regexp_substr(sqlset,'^([^.]+)\.',1,1,'i',1),own);
        tmp_set   VARCHAR2(128) := regexp_substr(sqlset,'[^.]+$');
    BEGIN
        IF tmp_set IS NULL AND sid IS NULL THEN
            raise_application_error(-20001,'Please specify the SQL Tuning Set name.');
        END IF;

        SELECT id,owner,name,
              (select count(1) 
               FROM &check_access_dba.sqlset_references b 
               WHERE b.sqlset_name=a.name 
               AND   b.sqlset_owner=a.owner 
               AND   rownum<2) 
        INTO   sid,tmp_owner,tmp_set,active
        FROM (
            SELECT id,owner,name
            FROM   &check_access_dba.sqlset
            WHERE  (id=sid  OR upper(name)=tmp_set) 
            AND    upper(owner)=upper(nvl(tmp_owner,owner))
            ORDER  BY decode(upper(owner),upper(tmp_owner),1,upper(user),2,3)) a
        WHERE rownum < 2;
        usr     := tmp_owner;
        sqlset  := tmp_set;
        fullset := usr||'.'||sqlset;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            IF own IS NULL THEN
                raise_application_error(-20001,'No such SQL Tuning Set: '||nvl(sqlset,sid));
            ELSE
                usr     := tmp_owner;
                sqlset  := tmp_set;
                sid     := NULL;
                fullset := usr||'.'||sqlset;
            END IF;
    END;

    FUNCTION sql_filter(sql_id VARCHAR2,phv VARCHAR2,extra VARCHAR2:=NULL) RETURN VARCHAR2 IS
    BEGIN
        IF :f=1 THEN
            RETURN :filter;
        END IF;
        IF sql_id IS NULL THEN
            RETURN '';
        ELSIF regexp_like(sql_id,'^\d+$') THEN
            RETURN sql_id||' IN(plan_hash_value,force_matching_signature'||rtrim(','||extra,',')||')';
        ELSE
            RETURN 'sql_id='''||sql_id||''''
                   ||CASE WHEN regexp_like(phv,'^\d+$') THEN ' AND plan_hash_value='||phv END;
        END IF;
    END;
BEGIN
    sqlset := nullif(sqlset,''||sid);
    dbms_output.enable(null);
    <<BOF>>
    IF coalesce(sqlset,op,''||sid) IS NULL THEN
        OPEN c FOR 
            SELECT decode(nvl(r,1),1,id) sqlset_id,
                   decode(nvl(r,1),1,owner) sqlset_owner,
                   decode(nvl(r,1),1,name) sqlset_name,
                   decode(nvl(r,1),1,created) created,
                   decode(nvl(r,1),1,last_modified) modified,
                   decode(nvl(r,1),1,description) descritpion,
                   ref_id,
                   ref_date,
                   ref_description
            FROM   &check_access_dba.sqlset
            LEFT JOIN (
                   SELECT sqlset_id id,
                          sqlset_owner owner,
                          sqlset_name name,
                          id ref_id,
                          created ref_date,
                          description ref_description,
                          row_number() over(partition by sqlset_id order by id) r
                   FROM &check_access_dba.sqlset_references)
            USING(ID,OWNER,NAME)
            ORDER BY ID,R;
    ELSIF op = 'CREATE' THEN
        IF sid IS NOT NULL THEN
            raise_application_error(-20001,'Invalid new SQL Tuning Set name: '||sid);
        END IF;
        check_sqlset(usr);
        IF sid IS NOT NULL THEN
            raise_application_error(-20001,'Target SQL Tuning Set already exists: '||fullset);
        END IF;
        dbms_output.put_line('SQL Tuning Set is created: '||usr||'.'||sys.dbms_sqltune.create_sqlset(sqlset,v3,usr));
    ELSIF op = 'DROP' THEN
        check_sqlset;
        filter := sql_filter(V3,V4,'sql_seq');
        IF active > 0 THEN
            raise_application_error(-20001,'Target SQL Tuning Set is referenced: '||fullset);
        ELSIF filter IS NULL THEN
            sys.dbms_sqltune.drop_sqlset(sqlset,usr);
            dbms_output.put_line('SQL Tuning Set is dropped: '||fullset);
        ELSE
            sys.dbms_sqltune.delete_sqlset(
                    sqlset_name=>sqlset,
                    sqlset_owner=>usr,
                    basic_filter=>filter);
            dbms_output.put_line('SQLs that match the following filter in SQL Tuning Set '||fullset||' is deleted: '||filter);
        END IF;
    ELSIF op IN ('REF','UNREF') THEN
        check_sqlset;
        IF op='REF' AND v3 IS NULL THEN
            raise_application_error(-20001,'Please specify the description of the reference.');
        ELSIF op='UNREF' AND regexp_substr(v3,'^\d+$') IS NULL THEN
            raise_application_error(-20001,'Please specify the reference ID of the reference.');
        ELSIF op='REF' THEN
            dbms_output.put_line('Ref #'||sys.dbms_sqltune.add_sqlset_reference(
                sqlset_owner=>usr,
                sqlset_name =>sqlset,
                description =>v3)||' is created');
        ELSE
            sys.dbms_sqltune.remove_sqlset_reference(
                sqlset_owner=>usr,
                sqlset_name =>sqlset,
                reference_id=>v3);
        END IF;
        sqlset := null;
        op     := null;
        sid    := null;
        GOTO BOF;
    ELSIF op IN ('SCAN','LOAD') THEN
        check_sqlset;
        filter := sql_filter(V3,V4);
        IF filter IS NULL THEN
            raise_application_error(-20001,'Please specify the predicates for filtering the matched SQLs');
        END IF;

        stmt := 'SELECT %s source,
                        sql_id,
                        plan_hash, 
                        schema,
                        elapsed_time,
                        executions,
                        %s attr1,
                        %s attr2,
                        to_char(substr(sql_text,1,512)) sql_text
                 FROM  (%s) s
                 NATURAL LEFT JOIN T
                 WHERE ('||filter||')
                 AND   command_type in (1, 2, 3, 6, 7, 9, 47, 170, 189)
                 AND   substr(sql_text,1,256) NOT LIKE ''%/*+%dbms_stats%''
                 AND   force_matching_signature > 0
                 AND   plan_hash_value > 0
                 AND   NOT regexp_like(substr(sql_text,1,128),''\* (OPT_DYN_SAMP|DS_SVC|SQL Analyze|AUTO_INDEX:ddl)\W'')';
        stmt := replace(replace('
        WITH t AS(select /*+materialize opt_estimate(query_block rows=0)*/ 1 from v$sqlarea where 1=2)
        SELECT /*+monitor opt_param(''_fix_control'' ''26552730:0'')*/
               source,
               sql_id,
               plan_hash,
               elapsed_time,
               executions,
               schema,attr1,attr2,
               substr(trim(regexp_replace(sql_text,''\s+'','' '')),1,200) sql_text
        FROM (
            SELECT /*+PQ_CONCURRENT_UNION*/a.*,row_number() over(partition by sql_id,plan_hash order by decode(schema,''@schema'',1,2),source) seq
            FROM (
                 '||utl_lms.format_message(stmt,'1','cast(null as varchar2(128))','cast(null as varchar2(128))',
                        'select a.*,''SQLAREA'' source,plan_hash_value plan_hash, parsing_schema_name schema from v$sqlarea a')||'
                 UNION ALL
                 SELECT 2,sql_id,plan_hash,schema,sum(elapsed_time),sum(executions),to_char(min(attr1)),to_char(max(attr2)),max(sql_text)
                 FROM (
                 '||utl_lms.format_message(stmt,'2','begin_snap','snap_id',
                       'select  /*+merge*/ a.*,
                                ''AWR'' source,
                                a.plan_hash_value plan_hash,
                                a.parsing_schema_name schema,
                                b.command_type,b.sql_text,
                                c.begin_snap,
                                c.end_interval_time+0 last_active_time,
                                c.end_interval_time+0 last_load_time,
                                a.fetches_delta fetches,
                                a.end_of_fetch_count_delta end_of_fetch_count,
                                a.sorts_delta sorts,
                                a.executions_delta executions,
                                a.px_servers_execs_delta px_servers_executions,
                                a.loads_delta loads,
                                a.invalidations_delta invalidations,
                                a.parse_calls_delta parse_calls,
                                a.disk_reads_delta disk_reads,
                                a.buffer_gets_delta buffer_gets,
                                a.rows_processed_delta rows_processed,
                                a.cpu_time_delta cpu_time,
                                a.elapsed_time_delta elapsed_time,
                                a.iowait_delta user_io_wait_time,
                                a.clwait_delta cluster_wait_time,
                                a.apwait_delta application_wait_time,
                                a.ccwait_delta concurrency_wait_time,
                                a.direct_writes_delta direct_writes,
                                a.plsexec_time_delta plsql_exec_time,
                                a.javexec_time_delta java_exec_time,
                                a.io_offload_elig_bytes_delta io_offload_eligible_bytes,
                                a.io_interconnect_bytes_delta io_interconnect_bytes,
                                a.physical_read_requests_delta physical_read_requests,
                                a.physical_read_bytes_delta physical_read_bytes,
                                a.physical_write_requests_delta physical_write_requests,
                                a.physical_write_bytes_delta physical_write_bytes,
                                a.optimized_physical_reads_delta optimized_physical_reads,
                                a.cell_uncompressed_bytes_delta cell_uncompressed_bytes,
                                a.io_offload_return_bytes_delta io_offload_return_bytes
                        from (select /*+merge*/ * from dba_hist_sqlstat where dbid=&dbid) a
                        join (select /*+merge*/ * from dba_hist_sqltext where dbid=&dbid) b
                        on    a.sql_id=b.sql_id
                        join (select c.*,lag(snap_id) over(partition by dbid,instance_number order by snap_id) begin_snap 
                              from   dba_hist_snapshot c
                              where  dbid=&dbid) c
                        on    a.instance_number=c.instance_number
                        and   a.snap_id=c.snap_id
                        and   c.begin_snap is not null')||'
                 ) 
                 GROUP BY sql_id,plan_hash,schema
                 UNION ALL
                 '||utl_lms.format_message(stmt,'3','sqlset_owner','sqlset_name',
                       'select a.*,
                               ''SQLSET'' source,
                               a.plan_hash_value plan_hash,
                               a.parsing_schema_name schema 
                        from   &check_access_dba.sqlset_statements a
                        where  sqlset_id != @sid')
                 ||'                 
            ) a
        ) 
        WHERE seq=1
        ORDER BY elapsed_time desc nulls last','@schema',usr),'@sid',sid);
        --dbms_output.put_line(stmt);
        OPEN c FOR stmt;
        LOOP
            FETCH c 
            INTO  row.priority,
                  row.sql_id,
                  row.plan_hash_value,
                  row.elapsed_time,
                  row.executions,
                  row.parsing_schema_name,
                  row.module,
                  row.action,
                  row.sql_text;
            EXIT WHEN c%notfound;
            row.other:='sql_id='''||row.sql_id||''' and plan_hash_value='||row.plan_hash_value;
            sets.extend;
            sets(sets.count) := row;
            row := SYS.SQLSET_ROW();
        END LOOP;
        close c;

        IF op='LOAD' THEN
            OPEN c FOR
                SELECT  /*+opt_param(''_fix_control'' ''26552730:0'')*/
                       value(p) val
                FROM   TABLE(sets) a,
                       TABLE(sys.dbms_sqltune.select_cursor_cache(basic_filter=>to_char(a.other))) p
                WHERE  a.priority=1
                UNION ALL
                SELECT value(p) val
                FROM   TABLE(sets) a,
                       TABLE(sys.dbms_sqltune.select_workload_repository(begin_snap=>a.module,end_snap=>a.action,basic_filter=>to_char(a.other))) p
                WHERE  a.priority=2
                UNION ALL
                SELECT value(p) val
                FROM   TABLE(sets) a,
                       TABLE(sys.dbms_sqltune.select_sqlset(sqlset_owner=>a.module,sqlset_name=>a.action,basic_filter=>to_char(a.other))) p
                WHERE  a.priority=3;
            BEGIN
                sys.dbms_sqltune.load_sqlset(
                    sqlset_owner=>usr,
                    sqlset_name=>sqlset,
                    populate_cursor=>c,
                    load_option=>'MERGE');
                close c;
            EXCEPTION WHEN OTHERS THEN
                close c;
                raise;
            END;
        END IF;

        OPEN c FOR
            SELECT rownum "#",
                   UPPER(decode(priority,1,'SQLAREA',2,'AWR',3,'SQLSET')) source,
                   sql_id,
                   plan_hash_value plan_hash,
                   parsing_schema_name schema,
                   elapsed_time ela,
                   round(ratio_to_report(elapsed_time) over(),4) "<= %",
                   executions execs,
                   round(elapsed_time/nullif(executions,0),2) avg_ela,
                   module attr1,
                   action attr2,
                   to_char(sql_text) sql_text
            FROM   TABLE(sets);
    ELSE
        check_sqlset;
        dbms_output.put_line('SQL Tuning Set '||fullset||':');
        dbms_output.put_line(rpad('=',80,'='));
        OPEN c FOR replace(q'#
            SELECT a.* FROM (
                SELECT sql_seq seq,
                       priority "PRIOR",
                       sql_id,
                       plan_hash_value plan_hash,
                       parsing_schema_name schema,
                       elapsed_time ela,
                       ratio_to_report(elapsed_time) over() "<= %",
                       cpu_time/nullif(elapsed_time,0) cpu,
                       executions execs,
                       elapsed_time/nullif(executions,0) avg_ela,
                       &last_exec
                       trim(regexp_replace(to_char(substr(sql_text,1,200)),'\s+',' ')) sql_text
                FROM   &check_access_dba.sqlset_statements
                WHERE  sqlset_id=:sid
                AND    (@filter@)
                ORDER  BY sql_seq DESC) a
            WHERE rownum<=50#','@filter@',nvl(sql_filter(v2,v3),'1=1')) using sid;
    END IF;
    :c := c;
END;
/