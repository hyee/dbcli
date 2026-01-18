/*[[
Get preferences/stats of the target object or compare stats. Usage: @@NAME {[owner] | [owner.]<object_name>[.partition_name]} [-pending|<yymmddhh24mi>] [<yymmddhh24mi>] [-advise]

    -advise               : execute SQL Statistics Advisor on the target table, refer to v$stats_advisor_rules

    Compare Stats:
    ==============
        -t"<stattab>"                  ：compare the stattab stats with current stats
        -pending       [<yymmddhh24mi>]：compare the pending stats with current/historical stats
        <yymmddhh24mi> [<yymmddhh24mi>]: compare the stats of 2 historical stats

    Trace Flags [DBMS_STATS.SET_GLOBAL_PREFS('TRACE',<flag>)]:
    ==========================================================
        0     : disable
        1     : use dbms_output.put_line instead of writing into trace file
        2     : enable dbms_stat trace only at session level
        4     : trace table stats
        8     : trace index stats
        16    : trace column stats
        32    : trace auto stats - logs to sys.stats_target$_log
        64    : trace scaling
        128   : dump backtrace on error
        256   : dubious stats detection
        512   : auto stats job
        1024  : parallel execution tracing
        2048  : print query before execution
        4096  : partition prune tracing
        8192  : trace stat differences
        16384 : trace extended column stats gathering(11.1+)
        32768 : trace approximate NDV (number distinct values) gathering(11.2+)
        65536 : trace "online gather optimizer statistics"(12.1+)
        131072: Automatic DOP trace
        262144: System statistics trace(12.2+)
        524288: trace Statistics Advisor

    --[[
       @check_access_dba: dba_tables={dba_} default={all_}
       &advise          : default={0} advise={1}
       @notes           : 12.1={,t.notes} default={}
       @notes2          : 18.1={t.notes} default={}
       @im              : 12.2={} default={--}
       @scanrate        : 12.2={,scanrate*1024*1024 scan_rate} default={}
       &t               : default={} t={}
       @check_access_sys: {
        sys.wri$_optstat_tab_history={
            SELECT CASE WHEN type='Pending' THEN 'PENDING' 
                   ELSE to_char(savetime+numtodsinterval(1,'minute'),'YYMMDDHH24MI') 
                   END "#",A.* FROM (
                SELECT CASE WHEN savetime>sysdate THEN 'Pending' 
                       WHEN row_number() OVER(ORDER BY CASE WHEN savetime<=sysdate THEN savetime END DESC NULLS LAST)=1 THEN 'Current'
                       ELSE 'History' END TYPE,a.*,
                       CASE WHEN rowcnt > 0 THEN ROUND(samplesize/ rowcnt, 4) END "Samples(%)"
                FROM (
                    SELECT h.obj#,h.FLAGS,ROWCNT,BLKCNT,AVGRLN,SAMPLESIZE &scanrate,
                           cast(h.savtime at time zone to_char(systimestamp,'TZH:TZM') as date) savetime, 
                           analyzetime
                    FROM   dba_objects o, sys.wri$_optstat_tab_history h
                    WHERE  o.object_id = h.obj#
                    AND    o.owner=own
                    AND    o.object_name=nam
                    AND    nvl(o.subobject_name,' ') = NVL(sub,' ')
                    UNION ALL
                    SELECT h.obj#,h.FLAGS,ROWCNT,BLKCNT,AVGRLN,SAMPLESIZE &scanrate,
                           cast(h.savtime at time zone to_char(systimestamp,'TZH:TZM') as date) savetime, 
                           analyzetime
                    FROM   v$fixed_table t, sys.wri$_optstat_tab_history h
                    WHERE  t.object_id = h.obj#
                    AND    'SYS'=own
                    AND    t.name=nam) a
            ORDER BY savetime DESC) a WHERE ROWNUM<=16}

        default={
            SELECT CASE WHEN type='Pending' THEN 'PENDING' 
                   ELSE to_char("TIMESTAMP"+numtodsinterval(1,'minute'),'YYMMDDHH24MI') 
                   END "#",A.*
            FROM (
                SELECT 'Pending' type,OWNER,TABLE_NAME,PARTITION_NAME,SUBPARTITION_NAME,
                       LAST_ANALYZED "TIMESTAMP" 
                FROM   &check_access_dba.tab_pending_stats
                WHERE  owner=own
                AND    table_name=nam
                AND    nvl(sub,' ') = COALESCE(PARTITION_NAME,SUBPARTITION_NAME,' ')
                UNION ALL
                SELECT Decode(SEQ,1,'Current','History') type,OWNER,TABLE_NAME,PARTITION_NAME,SUBPARTITION_NAME,savetime
                FROM (
                    SELECT A.*,ROW_NUMBER() OVER(ORDER BY STATS_UPDATE_TIME DESC) SEQ,
                           cast(STATS_UPDATE_TIME at time zone to_char(systimestamp,'TZH:TZM') as date) savetime
                    FROM   &check_access_dba.tab_stats_history A
                    WHERE  owner=own
                    AND    table_name=nam
                    AND    nvl(sub,' ') = COALESCE(PARTITION_NAME,SUBPARTITION_NAME,' ')
                    ORDER BY SEQ)
                WHERE ROWNUM<=15) a}
        }
    --]]
]]*/
ora _find_object "&V1" 1
set feed off serveroutput on printsize 10000 verify off

DECLARE
    input       varchar2(128) := :V1;
    owner       varchar2(128) := :object_owner;
    object_name varchar2(128) := :object_name;
    partname    varchar2(128) := :object_subname;
    typ         varchar2(100) := :object_type;
    st          date;
    et          date;
    status      varchar2(300);
    pval        varchar2(300);
    len         int;
    val         number;
    numrows     int;
    numblks     int;
    avgrlen     int;
    cachedblk   int;
    cachehit    int;
    im_imcu_count  INT;
    im_block_count INT;
    type t is table of varchar2(300);
    LST    SYS.ODCIOBJECTLIST := SYS.ODCIOBJECTLIST();
    --SOURCE:  SYS.OPTSTAT_HIST_CONTROL$/SYS.OPTSTAT_USER_PREFS$
    --         SYS.DBMS_STATS_INTERNAL.FILL_IN_PARAMS/FILL_IN_PARAMS_WITH_NO_PREFS
    prefs t:= t('ANDV_ALGO_INTERNAL_OBSERVE','FALSE', 'TRUE/FALSE',
                'APPROXIMATE_NDV','TRUE','TRUE/FALSE',
                'APPROXIMATE_NDV_ALGORITHM','REPEAT OR HYPERLOGLOG','REPEAT OR HYPERLOGLOG/ADAPTIVE SAMPLING/HYPERLOGLOG',
                'AUTO_STAT_EXTENSIONS','OFF','ON/OFF',
                'AUTO_STATS_ADVISOR_TASK','TRUE','TRUE/FALSE',
                'AUTO_TASK_INTERVAL', '900','HIGH FREQUENCY STATISTICS: Interval in secs',
                'AUTO_TASK_MAX_RUN_TIME', '3600','HIGH FREQUENCY STATISTICS: Max run secs',
                'AUTO_TASK_STATUS','OFF','HIGH FREQUENCY STATISTICS: ON/OFF, see SYS.STATS_TARGET$/dba_auto_stat_executions',
                'AUTOSTATS_TARGET','AUTO','ALL/AUTO/ORACLE/Z(DEFAULT_AUTOSTATS_TARGET)', 
                'BLOCK_SAMPLE', 'FALSE','TABLE: TRUE/FALSE,whether sample in block level',
                'CASCADE', 'DBMS_STATS.AUTO_CASCADE','TRUE/FALSE/null(AUTO_CASCADE),cascade collect index stats',
                'CONCURRENT','OFF', 'MANUAL/AUTOMATIC/ALL/OFF/FALSE/TRUE',
                'COORDINATOR_TRIGGER_SHARD','FALSE', 'TRUE/FALSE',
                'DEBUG','0','1[AUTO_TLIST_ONLY],2[MANUAL_TLIST],4[PARALLEL_SYNOP],8[CLOB_SQL],16[FORCE_TF],32[BATCHINGSQL]',
                'DEGREE','NULL','n/32766(DEFAULT_DEGREE_VALUE)/32767(DEFAULT_DEGREE)/32768(AUTO_DEGREE)',
                'ENABLE_HYBRID_HISTOGRAMS','3','0:disable 1/2/3',
                'ENABLE_TOP_FREQ_HISTOGRAMS','3','0:disable 1/2/3',
                'ESTIMATE_PERCENT','DBMS_STATS.AUTO_SAMPLE_SIZE','0(AUTO_SAMPLE_SIZE)/[0.000001-100]/101(DEFAULT_ESTIMATE_PERCENT)',
                'FORCE', 'FALSE','TRUE/FALSE',
                'GATHER_AUTO','AFTER_LOAD', 'AFTER_LOAD/ALWAYS',
                'GATHER_SCAN_RATE','HADOOP_ONLY','HADOOP_ONLY/ON/OFF',
                'GLOBAL_TEMP_TABLE_STATS','SESSION', 'SHARED/SESSION',
                'GRANULARITY','AUTO','Partition: AUTO/ALL/DEFAULT/GLOBAL/PARTITION/SUBPARTITION/GLOBAL AND PARTITION/PART AND SUBPART/GLOBAL AND SUBPART/APPROX_GLOBAL AND PARTITION',
                'INCREMENTAL','FALSE','Partition: TRUE/FALSE, fix controls: 13583722/16726844',
                'INCREMENTAL_INTERNAL_CONTROL','TRUE', 'Partition: TRUE/FALSE',
                'INCREMENTAL_LEVEL','PARTITION','Partition: TABLE/PARTITION synopses',
                'INCREMENTAL_STALENESS','ALLOW_MIXED_FORMAT','Partition: ALLOW_MIXED_FORMAT,USE_STALE_PERCENT,USE_LOCKED_STATS/NULL',
                'JOB_OVERHEAD','-1','-1',
                'JOB_OVERHEAD_PERC','1','1',
                'MAINTAIN_STATISTICS_STATUS','FALSE', 'TRUE/FALSE',
                'METHOD_OPT','FOR ALL COLUMNS SIZE AUTO','FOR ALL [INDEXED|HIDDEN] COLUMNS [SIZE {integer|REPEAT|AUTO|SKEWONLY}]/Z(DEFAULT_METHOD_OPT)',
                'MON_MODS_ALL_UPD_TIME','','',
                'NO_INVALIDATE','DBMS_STATS.AUTO_INVALIDATE','TRUE/FALSE/null(AUTO_INVALIDATE(_optimizer_invalidation_period))',
                'OBJ_FILTER_LIST','','',
                'OPTIONS','GATHER','GATHER/GATHER AUTO/Z(DEFAULT_OPTIONS)(additional schema/system: GATHER STALE/GATHER EMPTY/LIST AUTO/LIST STALE/LIST EMPTY)',
                'PREFERENCE_OVERRIDES_PARAMETER','FALSE', 'TRUE/FALSE',
                'PUBLISH','TRUE','TRUE/FALSE',
                'REAL_TIME_STATISTICS','OFF','ON/OFF',
                'ROOT_TRIGGER_PDB','FALSE','FALSE/TRUE',
                'SCAN_RATE','0','0',
                'SKIP_TIME','','',
                'SNAPSHOT_UPD_TIME','','',
                'SPD_RETENTION_WEEKS','53','53',
                'STATS_MODEL','OFF','ON/OFF',
                'STATS_MODEL_INTERNAL_CONTROL','0','0',
                'STATS_MODEL_INTERNAL_MINRSQ','0.9','0.9',
                'STALE_PERCENT','10','10',
                'STATS_RETENTION','','',
                'STAT_CATEGORY','OBJECT_STATS, REALTIME_STATS','OBJECT_STATS,SYNOPSES,REALTIME_STATS/Z(DEFAULT_STAT_CATEGORY)',
                'SYS_FLAGS','1','0/1(DSC_SYS_FLAGS_DUBIOUS_DONE)',
                'TABLE_CACHED_BLOCKS','1','0(AUTO_TABLE_CACHED_BLOCKS)/n',
                'TRACE','0','0(disable),1(DBMS_OUTPUT_TRC),2(SESSION_TRC),4(TAB_TRC),8(IND_TRC),16(COL_TRC),32(AUTOST_TRC[sys.stats_target$_log]),...524288',
                'WAIT_TIME_TO_UPDATE_STATS','15','15');

BEGIN
    IF :V2 IS NOT NULL OR :T IS NOT NULL THEN
        RETURN;
    END IF;
    dbms_output.enable(null);
    dbms_output.put_line('Preferences');
    dbms_output.put_line('***********');
    IF typ IS NOT NULL and typ NOT like 'TABLE%' THEN
        RAISE_APPLICATION_ERROR(-20001,'Only table is supported!');
    END IF;

    $IF DBMS_DB_VERSION.VERSION>10 $THEN
        IF owner IS NULL THEN
            typ:='system';
            IF input IS NOT NULL THEN
                SELECT MAX(USERNAME) 
                INTO   owner
                FROM   ALL_USERS
                WHERE  USERNAME=upper(input);
                IF owner IS NOT NULL THEN
                    typ:='schema';
                END IF;
            END IF;
        END IF;
    $ELSE
        typ:='';
    $END

    for i in 0..(prefs.count/3-1) loop
        begin
            $IF DBMS_DB_VERSION.VERSION>10 $THEN
                pval:=substr(dbms_stats.get_prefs(prefs(i*3+1),owner,object_name),1,35);
            $ELSE
                pval:=substr(dbms_stats.get_param(prefs(i*3+1)),1,35);
            $END
            len := length(pval);
            IF pval!=substr(prefs(i*3+2),1,35) THEN
                pval := '$HIR$*'||substr(pval,1,34)||'$NOR$';
                len:=len+1;
            END IF;
            status :=rpad(initcap(nvl(typ,'system')||' ')||'Prefs - '||prefs(i*3+1),45)||': '||pval||rpad(' ',35-len);
            if prefs(i*3+3) is not null then
                status := status || '('||prefs(i*3+3)||')';
            end if;
            dbms_output.put_line(status);
        exception when others then null;
        end;
    end loop;
    
    prefs := t('iotfrspeed', 'ioseektim', 'mbrc','sreadtim', 'mreadtim', 'cpuspeed', 'cpuspeednw',  'maxthr', 'slavethr');
    for i in 1..prefs.count loop
        LST.EXTEND();
        LST(LST.COUNT) := SYS.ODCIOBJECT(upper(prefs(i)),null);
        begin
            --source table: sys.aux_stats$
            DBMS_STATS.GET_SYSTEM_STATS(status,st,et,prefs(i),val);
            LST(LST.COUNT).objectname:=val;
        exception when others then null;
        end;
    end loop;

    dbms_output.put_line(rpad('-',120,'-'));
    --refer to https://github.com/FranckPachot/scripts/blob/master/statistic-gathering/display-system-statistics.txt
    FOR C IN(
        SELECT r,pname, to_char(nvl(round(nvl(calc,pval1),4),0),'999999990.999')||nullif(' ('||formula||')',' ()') value
        FROM   (SELECT rownum r,objectschema pname,objectname+0 pval1 FROM TABLE(lst))
        MODEL 
        REFERENCE sga ON 
             (SELECT NAME, VALUE FROM v$sga) DIMENSION BY(NAME) MEASURES(VALUE) 
        REFERENCE parameter ON
             (SELECT NAME, decode(TYPE, 3, to_number(VALUE)) VALUE
                    FROM   v$parameter
                    WHERE  NAME = 'db_file_multiblock_read_count'
                    AND    ismodified != 'FALSE'
                    UNION ALL
                    SELECT '_db_file_optimizer_read_count', NVL(MAX(to_number(VALUE)),8) VALUE
                    FROM   v$parameter
                    WHERE  NAME = '_db_file_optimizer_read_count'
                    UNION ALL
                    SELECT NAME, decode(TYPE, 3, to_number(VALUE)) VALUE
                    FROM   v$parameter
                    WHERE  NAME = 'sessions'
                    UNION ALL
                    SELECT NAME, decode(TYPE, 3, to_number(VALUE)) VALUE
                    FROM   v$parameter
                    WHERE  NAME = 'db_block_size') DIMENSION BY(NAME) MEASURES(VALUE) 
        DIMENSION BY(pname)
        MEASURES(pval1,r, CAST(NULL AS NUMBER) AS calc, CAST(NULL AS VARCHAR2(200)) AS formula)
        RULES(
             calc ['MBRC'] = coalesce(pval1 ['MBRC'], parameter.value ['db_file_multiblock_read_count'], parameter.value ['_db_file_optimizer_read_count'], 8),
             calc ['MREADTIM'] = coalesce(pval1 ['MREADTIM'],pval1 ['IOSEEKTIM'] + (parameter.value ['db_block_size'] * calc ['MBRC']) / pval1 ['IOTFRSPEED']),
             calc ['SREADTIM'] = coalesce(pval1 ['SREADTIM'], pval1 ['IOSEEKTIM'] + parameter.value ['db_block_size'] / pval1 ['IOTFRSPEED']),
             calc ['   multi  cost / block'] = round(1 / calc ['MBRC'] * calc ['MREADTIM'] / calc ['SREADTIM'], 4),
             calc ['   single cost / block'] = 1,
             calc ['   maximum mbrc'] = sga.value ['Database Buffers'] / (parameter.value ['db_block_size'] * parameter.value ['sessions']),
             calc ['IOTFRSPEED'] = pval1 ['IOTFRSPEED']/1024,
             calc ['CPUSPEED'] = pval1 ['CPUSPEED'],
             calc ['CPUSPEEDNW'] = pval1 ['CPUSPEEDNW'],
             calc ['MAXTHR'] = coalesce(pval1['MAXTHR'],parameter.value['db_block_size'] * calc ['MBRC']/calc ['MREADTIM'] 
                                * CASE WHEN dbms_db_version.version>11 then 1000 else 1 end),  --bug #13097308
             calc ['SLAVETHR'] = coalesce(pval1['SLAVETHR'], 0.9* calc ['MAXTHR']),
             r['   maximum mbrc']=98,
             r['   single cost / block']=99,
             r['   multi  cost / block']=100,
             formula ['MBRC'] = CASE
                 WHEN pval1 ['MBRC'] IS NOT NULL THEN
                  'MBRC = Multi-Block Read Count'
                 WHEN parameter.value ['db_file_multiblock_read_count'] IS NOT NULL THEN
                  'db_file_multiblock_read_count'
                 WHEN parameter.value ['_db_file_optimizer_read_count'] IS NOT NULL THEN
                  '_db_file_optimizer_read_count (impacts the CBO estimation)'
                 ELSE
                  '_db_file_optimizer_read_count (impacts the CBO estimation)'
             END,
             formula ['MREADTIM'] = 'time to read n blocks in ms = IOSEEKTIM + db_block_size * MBRC / IOTFRSPEED, default: 26 for 8K, 42 for 16K',
             formula ['SREADTIM'] = 'time to read 1 block  in ms = IOSEEKTIM + db_block_size / IOTFRSPEED, default: 12 for 8K, 14 for 16K',
             formula ['IOSEEKTIM'] = 'latency  in ms',
             formula ['IOTFRSPEED'] = 'transfer speed in KB/ms',
             formula ['   multi  cost / block'] = 'MREADTIM/MBRC/SREADTIM, default: 0.271 for 8K, 0.375 for 16K',
             formula ['   single cost / block'] = 'by definition',
             formula ['   maximum mbrc'] = 'buffer cache size in blocks / sessions',
             formula ['CPUSPEED'] = 'workload CPU speed in MHZ',
             formula ['CPUSPEEDNW'] = 'noworkload CPU speed in MHZ',
             formula ['MAXTHR'] = 'maximum serial I/O throughput in bytes/'||CASE WHEN dbms_db_version.version>11 then 's' else 'ms' end,
             formula ['SLAVETHR'] = 'average per parallel slave I/O throughput in bytes/'||CASE WHEN dbms_db_version.version>11 then 's' else 'ms' end||', parallel I/O cost should be: (<serial_cost> * MAXTHR / (<dop> * SLAVETHR)'
        ) ORDER BY r) LOOP
        dbms_output.put_line(rpad('System Stats - '||c.pname,45)||': '||c.value);
    END LOOP;
    dbms_output.put_line(rpad('-',120,'-'));
    dbms_output.put_line(rpad('Statistics History Retention',45) ||': '||rpad(dbms_stats.GET_STATS_HISTORY_RETENTION||' days',10)||' (Avail: '||to_char(dbms_stats.GET_STATS_HISTORY_AVAILABILITY,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')||')');
END;
/
set autohide on
pro 
pro   
var c1 REFCURSOR "&OBJECT_TYPE INFO"
var c2 REFCURSOR "&OBJECT_TYPE COLUMN INFO"
var c3 REFCURSOR "&OBJECT_TYPE INDEX INFO"
var c4 REFCURSOR "&OBJECT_TYPE TOP 100 CHILD PARTS"
var c5 REFCURSOR "&OBJECT_TYPE STATS HISTORY IN SYSTEM TIMEZONE"
var c6 REFCURSOR "&OBJECT_TYPE STATS DIFF REPORT"
col "Samples(%)" for pct
col rowcnt,blkcnt,samplesize for tmb
col scan_rate for kmg
set printsize 3000

DECLARE
    own  VARCHAR2(128):=:OBJECT_OWNER;
    nam  VARCHAR2(128):=:OBJECT_NAME;
    sub  VARCHAR2(128):=:OBJECT_SUBNAME;
    typ  VARCHAR2(128):=:OBJECT_TYPE;
    st   VARCHAR2(128):=UPPER(:V2);
    ed   VARCHAR2(128):=nvl(regexp_substr(:V3,'^\d+$'),to_char(sysdate,'YYMMDDHH24MISS'));
    town VARCHAR2(128);
    tnam VARCHAR2(512) := replace(trim(upper(:t)),' '); 
    tz1  VARCHAR2(10) := to_char(systimestamp,'TZH:TZM');
    ss   TIMESTAMP WITH TIME ZONE:=from_tz(to_timestamp(regexp_substr(st,'^\d+$'),'YYMMDDHH24MISS'),tz1);
    es   TIMESTAMP WITH TIME ZONE:=from_tz(to_timestamp(ed,'YYMMDDHH24MISS'),tz1);
    c1   SYS_REFCURSOR;
    c2   SYS_REFCURSOR;
    c3   SYS_REFCURSOR;
    c4   SYS_REFCURSOR;
    msg  VARCHAR2(300);

BEGIN
    IF NVL(typ,'X') NOT LIKE 'TABLE%' THEN 
        RETURN;
    END IF;

    IF tnam IS NOT NULL THEN
        IF tnam='.' THEN
            raise_application_error(-20001,'Invalid stat table: .');
        END IF;

        IF instr(tnam,'.')=0 THEN
            town:=sys_context('userenv','current_schema');
        ELSE
            town:=regexp_substr(tnam,'[^\.]+',1,1);
            tnam:=regexp_substr(tnam,'[^\.]+',1,2);
        END IF;

        BEGIN
            EXECUTE IMMEDIATE 'SELECT 1 FROM '||town||'.'||tnam||' WHERE STATID IS NULL AND C4 IS NOT NULL';
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE=-904 THEN
                raise_application_error(-20001,'Invalid stats table: '||town||'.'||tnam);
            ELSE
                raise_application_error(-20001,'No access to target stats table: &t, consider create it with: exec dbms_stats.create_stat_table('''||town||''','''||tnam||''');');
            END IF;
        END;
    END IF;

    msg := '| '||typ||' '||own||'.'||nam||trim('.' FROM '.'||sub)||' |';
    DBMS_OUTPUT.PUT_LINE(RPAD('*',LENGTH(MSG),'*'));
    DBMS_OUTPUT.PUT_LINE(msg);
    DBMS_OUTPUT.PUT_LINE('| '||RPAD('=',LENGTH(MSG)-4,'=')||' |');
    DBMS_OUTPUT.PUT_LINE(RPAD('*',LENGTH(MSG),'*'));
    OPEN :C5 FOR &check_access_sys;
    IF st IN ('-PENDING','PENDING') THEN
        OPEN :c6 FOR 
            SELECT * FROM TABLE(dbms_stats.diff_table_stats_in_pending(own,nam,es,pctthreshold=>0.01));
    ELSIF tnam IS NOT NULL THEN
        OPEN :c6 FOR
            SELECT * FROM TABLE(dbms_stats.diff_table_stats_in_stattab(own,nam,stattab1own=>town,stattab1=>tnam,pctthreshold=>0.01));
    ELSIF ss IS NOT NULL THEN
        OPEN :c6 FOR 
            SELECT * FROM TABLE(dbms_stats.diff_table_stats_in_history(own,nam,ss,es,pctthreshold=>0.01));
    ELSIF st IS NOT NULL THEN
        raise_application_error(-20001,'Invalid parameter: '||:V2);
    ELSIF typ='TABLE' THEN
        OPEN c1 FOR 
            select /*+outline_leaf*/
                TABLE_NAME,
                NUM_ROWS,
                SAMPLE_SIZE SAMPLES,
                round(SAMPLE_SIZE/nullif(NUM_ROWS,0),4) "Samples(%)",
                BLOCKS,
                EMPTY_BLOCKS,
                AVG_SPACE,
                CHAIN_CNT,
                AVG_ROW_LEN,
                GLOBAL_STATS,
                USER_STATS,
                last_analyzed
                &im ,t1.notes,IMCU,IM_BLOCK,IM_TIME
            from &check_access_dba.tables t 
            left join 
                (select owner,table_name &im, &notes2 notes,t.IM_IMCU_COUNT IMCU,t.IM_BLOCK_COUNT IM_BLOCK,t.IM_STAT_UPDATE_TIME IM_TIME
                  from &check_access_dba.tab_statistics t
                  where owner = own
                  and   table_name = nam
                  and   rownum<2) t1
            using (owner,table_name)
            where owner = own
            and   table_name = nam;
        OPEN c2 FOR
            SELECT /*+outline_leaf*/
                   t1.COLUMN_NAME,
                   decode(t1.DATA_TYPE,
                          'NUMBER',t1.DATA_TYPE || '(' || decode(t1.DATA_PRECISION, NULL, t1.DATA_LENGTH || ')', t1.DATA_PRECISION || ',' || t1.DATA_SCALE || ')'),
                          'DATE',t1.DATA_TYPE,
                          'LONG',t1.DATA_TYPE,
                          'LONG RAW',t1.DATA_TYPE,
                          'ROWID',t1.DATA_TYPE,
                          'MLSLABEL',t1.DATA_TYPE,
                          t1.DATA_TYPE || '(' || t1.DATA_LENGTH || ')') || ' ' ||
                   decode(t1.nullable, 'N', 'NOT NULL', 'n', 'NOT NULL', NULL) col,
                   t.HISTOGRAM,
                   t.NUM_BUCKETS BUCKETS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0)+t.NUM_NULLS+CASE WHEN nvl(t.SAMPLE_SIZE,0)<t.NUM_DISTINCT THEN t.NUM_DISTINCT ELSE 0 END)/nullif(NUM_ROWS,0),4) "Samples(%)",
                   t.NUM_DISTINCT,
                   t.NUM_NULLS,
                   ROUND(decode(t1.histogram,'HYBRID',NULL,greatest(0,num_rows-t.NUM_NULLS)/GREATEST(t.NUM_DISTINCT, 1)), 2) cardinality,
                   t.GLOBAL_STATS,
                   t.USER_STATS,
                   t1.DATA_DEFAULT "DEFAULT",
                   t.LAST_ANALYZED &notes
            FROM   &check_access_dba.tab_cols t1,&check_access_dba.tab_col_statistics t,
                   (select /*+cardinality(1)*/ table_name,num_rows
                    from  &check_access_dba.tab_statistics t
                    where owner = own 
                    and   table_name = nam
                    and   partition_name is null) t2
            WHERE  t2.table_name=t1.table_name
            AND    t1.table_name = nam
            AND    t1.owner = own
            AND    t.table_name = nam
            AND    t.owner = own
            AND    t1.column_name=t.column_name;

        OPEN C3 FOR
            WITH I AS (SELECT /*+outline_leaf*/
                               I.*,nvl(c.LOCALITY,'GLOBAL') LOCALITY,
                               PARTITIONING_TYPE||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                        SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                        FROM   (SELECT /*+opt_param('_connect_by_use_union_all','old_plan_mode') no_merge*/* FROM all_part_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                        START  WITH column_position = 1
                                        CONNECT BY PRIOR column_position = column_position - 1]'),'//V') PARTITIONED_BY,
                               nullif(SUBPARTITIONING_TYPE,'NONE')||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                        SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                        FROM   (SELECT /*+opt_param('_connect_by_use_union_all','old_plan_mode') no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                        START  WITH column_position = 1
                                        CONNECT BY PRIOR column_position = column_position - 1]'),'//V') SUBPART_BY
                        FROM   &check_access_dba.INDEXES I,&check_access_dba.PART_INDEXES C
                        WHERE  C.OWNER(+) = I.OWNER
                        AND    C.INDEX_NAME(+) = I.INDEX_NAME
                        AND    I.TABLE_OWNER = own
                        AND    I.TABLE_NAME = nam)
            SELECT /*INTERNAL_DBCLI_CMD*/ --+opt_param('optimizer_dynamic_sampling' 5) outline_leaf opt_param('container_data' 'current') leading(i c e) opt_param('_sort_elimination_cost_ratio',5)
                 DECODE(C.COLUMN_POSITION, 1, I.OWNER, '') OWNER,
                 DECODE(C.COLUMN_POSITION, 1, I.INDEX_NAME, '') INDEX_NAME,
                 DECODE(C.COLUMN_POSITION, 1, I.INDEX_TYPE, '') INDEX_TYPE,
                 DECODE(C.COLUMN_POSITION, 1, DECODE(I.UNIQUENESS,'UNIQUE','YES','NO'), '') "UNIQUE",
                 DECODE(C.COLUMN_POSITION, 1, NVL(PARTITIONED_BY||NULLIF(','||SUBPART_BY,','),'NO'), '') "PARTITIONED",
                 DECODE(C.COLUMN_POSITION, 1, LOCALITY, '') "LOCALITY",
               --DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",
                 DECODE(C.COLUMN_POSITION, 1, decode(I.STATUS,'N/A',(SELECT MIN(STATUS) FROM All_Ind_Partitions p WHERE p.INDEX_OWNER = I.OWNER AND p.INDEX_NAME = I.INDEX_NAME),I.STATUS), '') STATUS,
                 DECODE(C.COLUMN_POSITION, 1, i.BLEVEL) BLEVEL,
                 DECODE(C.COLUMN_POSITION, 1, i.LEAF_BLOCKS) LEAF_BLOCKS,
                 DECODE(C.COLUMN_POSITION, 1, i.DISTINCT_KEYS) DISTINCTS,
                 DECODE(C.COLUMN_POSITION, 1, AVG_LEAF_BLOCKS_PER_KEY) LB_PER_KEY,
                 DECODE(C.COLUMN_POSITION, 1, AVG_DATA_BLOCKS_PER_KEY) DB_PER_KEY,
                 DECODE(C.COLUMN_POSITION, 1, i.LAST_ANALYZED) LAST_ANALYZED,
                 C.COLUMN_POSITION NO#,
                 C.COLUMN_NAME,
                 E.COLUMN_EXPRESSION COLUMN_EXPR,
                 C.DESCEND
            FROM   &check_access_dba.IND_COLUMNS C,  I, &check_access_dba.ind_expressions e
            WHERE  C.INDEX_OWNER = I.OWNER
            AND    C.INDEX_NAME = I.INDEX_NAME
            AND    C.INDEX_NAME = e.INDEX_NAME(+)
            AND    C.INDEX_OWNER = e.INDEX_OWNER(+)
            AND    C.column_position = e.column_position(+)
            AND    c.table_owner = E.table_owner(+)
            AND    c.table_name =e.table_name(+)
            ORDER  BY C.INDEX_NAME, C.COLUMN_POSITION;

        OPEN C4 FOR
            SELECT * FROM (
                SELECT /*+outline_leaf*/
                       PARTITION_NAME,
                       PARTITION_POSITION POSITION,
                       t.NUM_ROWS,
                       t.SAMPLE_SIZE,
                       round((nvl(t.SAMPLE_SIZE,0))/nullif(NUM_ROWS,0),4) "Samples(%)",
                       BLOCKS,
                       EMPTY_BLOCKS,
                       AVG_SPACE,
                       CHAIN_CNT,
                       AVG_ROW_LEN,
                       GLOBAL_STATS,
                       USER_STATS,
                       last_analyzed,
                       o.created
                FROM   &check_access_dba.tab_partitions t,&check_access_dba.objects o
                WHERE  table_owner = own
                AND    table_name = nam
                AND    o.owner=own
                AND    o.object_name=nam
                AND    o.subobject_name=t.partition_name
                ORDER  BY created DESC,POSITION)
            WHERE ROWNUM<=100;
    ELSIF typ='TABLE PARTITION' THEN
        OPEN C1 FOR
            SELECT PARTITION_NAME,
                   NUM_ROWS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0))/nullif(NUM_ROWS,0),4) "Samples(%)",
                   BLOCKS,
                   EMPTY_BLOCKS,
                   AVG_SPACE,
                   CHAIN_CNT,
                   AVG_ROW_LEN,
                   GLOBAL_STATS,
                   USER_STATS,
                   t.last_analyzed
            FROM   &check_access_dba.tab_partitions t
            WHERE  table_owner = own
            AND    table_name = nam
            AND    partition_name =nvl(sub,partition_name)
            ORDER  BY partition_position;
        OPEN C2 FOR
            SELECT /*+opt_param('optimizer_dynamic_sampling' 5) outline_leaf*/ PARTITION_NAME,
                   COLUMN_NAME,
                   HISTOGRAM,
                   ROUND(decode(histogram,'HYBRID',NULL,greatest(0,num_rows-NUM_NULLS)/GREATEST(NUM_DISTINCT, 1)), 2) cardinality,
                   NUM_BUCKETS BUCKETS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0)+t.NUM_NULLS+CASE WHEN nvl(t.SAMPLE_SIZE,0)<NUM_DISTINCT THEN NUM_DISTINCT ELSE 0 END)/nullif(NUM_ROWS,0),4) "Samples(%)",
                   NUM_NULLS,
                   NUM_DISTINCT,
                   GLOBAL_STATS,
                   USER_STATS,
                   t.last_analyzed  &notes
            FROM   &check_access_dba.PART_COL_STATISTICS t,
                   (select table_name,num_rows from &check_access_dba.tab_partitions p where p.table_owner = own and p.table_name = nam and p.partition_name=sub) t1
            WHERE  t.table_name = nam
            AND    owner = own
            AND    t1.table_name=t.table_name
            AND    partition_name =sub;
        OPEN C3 FOR
            SELECT t.INDEX_NAME,
                   t.PARTITION_NAME,
                   t.BLEVEL BLev,
                   t.LEAF_BLOCKS,
                   t.DISTINCT_KEYS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0))/nullif(t.NUM_ROWS,0),4) "Samples(%)",
                   t.AVG_LEAF_BLOCKS_PER_KEY LB_PER_KEY,
                   t.AVG_DATA_BLOCKS_PER_KEY DATA_PER_KEY,
                   t.CLUSTERING_FACTOR,
                   t.GLOBAL_STATS,
                   t.USER_STATS,
                   t.last_analyzed
            FROM   &check_access_dba.ind_partitions t, &check_access_dba.indexes i
            WHERE  i.table_name = nam
            AND    i.table_owner = own
            AND    i.owner = t.index_owner
            AND    i.index_name = t.index_name
            AND    t.partition_name =sub;

        OPEN C4 FOR
            SELECT SUBPARTITION_NAME,
                   SUBPARTITION_POSITION POSITION,
                   NUM_ROWS,
                   SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0))/nullif(NUM_ROWS,0),4) "Samples(%)",
                   BLOCKS,
                   EMPTY_BLOCKS,
                   AVG_SPACE,
                   CHAIN_CNT,
                   AVG_ROW_LEN,
                   GLOBAL_STATS,
                   USER_STATS,
                   t.last_analyzed
            FROM   &check_access_dba.tab_subpartitions t
            WHERE  table_owner = own
            AND    table_name = nam
            AND    partition_name =sub
            ORDER  BY SUBPARTITION_POSITION;
    ELSIF typ='TABLE SUBPARTITION' THEN
        OPEN C1 FOR
            SELECT PARTITION_NAME,
                   SUBPARTITION_NAME,
                   NUM_ROWS,
                   SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0))/nullif(NUM_ROWS,0),4) "Samples(%)",
                   BLOCKS,
                   EMPTY_BLOCKS,
                   AVG_SPACE,
                   CHAIN_CNT,
                   AVG_ROW_LEN,
                   GLOBAL_STATS,
                   USER_STATS,
                   t.last_analyzed
            FROM   &check_access_dba.tab_subpartitions t
            WHERE  table_owner = own
            AND    table_name = nam
            AND    subpartition_name =sub;
        OPEN C2 FOR
            SELECT t.SUBPARTITION_NAME,
                   t.COLUMN_NAME,
                   NUM_BUCKETS BUCKETS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0)+t.NUM_NULLS+CASE WHEN nvl(t.SAMPLE_SIZE,0)<NUM_DISTINCT THEN NUM_DISTINCT ELSE 0 END)/nullif(NUM_ROWS,0),4) "Samples(%)",
                   NUM_NULLS,
                   NUM_DISTINCT,
                   t.GLOBAL_STATS,
                   t.USER_STATS,
                   t.last_analyzed &notes
            FROM   &check_access_dba.SUBPART_COL_STATISTICS t, &check_access_dba.tab_subpartitions p
            WHERE  t.table_name = nam
            AND    t.owner = own
            AND    t.subpartition_name = p.subpartition_name
            AND    t.owner = p.table_owner
            AND    t.table_name = p.table_name
            AND    t.subpartition_name =sub;
        OPEN C3 FOR
            SELECT t.INDEX_NAME,
                   t.PARTITION_NAME,
                   t.SUBPARTITION_NAME,
                   t.BLEVEL BLev,
                   t.LEAF_BLOCKS,
                   t.DISTINCT_KEYS,
                   t.NUM_ROWS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0))/nullif(t.NUM_ROWS,0),4) "Samples(%)",
                   t.AVG_LEAF_BLOCKS_PER_KEY LB_PER_KEY,
                   t.AVG_DATA_BLOCKS_PER_KEY DATA_PER_KEY,
                   t.CLUSTERING_FACTOR,
                   t.GLOBAL_STATS,
                   t.USER_STATS,
                   t.last_analyzed
            FROM   &check_access_dba.ind_subpartitions t, &check_access_dba.indexes i
            WHERE  i.table_name = nam
            AND    i.table_owner = own
            AND    i.owner = t.index_owner
            AND    i.index_name = t.index_name
            AND    t.subpartition_name =sub;
    END IF;
    
    :C1 := C1;
    :C2 := C2;
    :C3 := C3;
    :C4 := C4;
END;
/
PRINT C1;
PRINT C5;
PRINT C6;
PRINT C2;
PRINT C3;
PRINT C4;

DECLARE
    input  VARCHAR2(128) := :V1;
    oname  VARCHAR2(128) := :object_owner;
    tab    VARCHAR2(128) := :object_name;
    tname  VARCHAR2(128) := upper('stats_adv_' || oname || '_' || tab)||to_char(sysdate,'SSSSS');
    tid    PLS_INTEGER;
    output CLOB;
BEGIN
    NULL;
    $IF &advise=1 $THEN
    IF oname IS NULL AND input IS NOT NULL THEN
        SELECT MAX(USERNAME) 
        INTO   oname
        FROM   ALL_USERS
        WHERE  USERNAME=upper(input);
    END IF;
    BEGIN
        dbms_stats.drop_advisor_task(tname);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    output := dbms_stats.create_advisor_task(tname);
    --defines rules that listed in v$stats_advisor_rules
    output := DBMS_STATS.CONFIGURE_ADVISOR_OBJ_FILTER(task_name          => tname,
                                                      stats_adv_opr_type => 'EXECUTE',
                                                      rule_name          => NULL,
                                                      ownname            => NULL,
                                                      tabname            => NULL,
                                                      action             => 'DISABLE');
    output := DBMS_STATS.CONFIGURE_ADVISOR_OBJ_FILTER(task_name          => tname,
                                                      stats_adv_opr_type => 'EXECUTE',
                                                      rule_name          => NULL,
                                                      ownname            => oname,
                                                      tabname            => tab,
                                                      action             => 'ENABLE');
    output := DBMS_STATS.CONFIGURE_ADVISOR_RULE_FILTER(task_name          => tname,
                                                      stats_adv_opr_type => 'EXECUTE',
                                                      rule_name          => 'UseConcurrent',
                                                      action             => 'DISABLE');
    output := DBMS_STATS.CONFIGURE_ADVISOR_RULE_FILTER(task_name          => tname,
                                                       stats_adv_opr_type => 'EXECUTE',
                                                       rule_name          => 'UseGatherSchemaStats',
                                                       action             => 'DISABLE');
    output := DBMS_STATS.EXECUTE_ADVISOR_TASK(tname);
    select task_id into tid from dba_advisor_tasks where task_name=tname;
    dbms_output.put_line('Statistics Advisor for "'||nvl(trim('.' from oname||'.'||tab),'Database')||'" is running, please use "ora addm '||tid||'" to show the result afterwards.');
    dbms_output.put_line('Or may run following command to see the recommended script:');
    dbms_output.put_line('    select dbms_stats.script_advisor_task('''||tname||''') from dual;');
    $END
END;
/