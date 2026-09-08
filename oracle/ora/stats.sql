/*[[
Get preferences/stats of the target object or compare stats. Usage: @@NAME {[owner] | [owner.]<object_name>[.partition_name]} [-pending|<yymmddhh24mi>] [<yymmddhh24mi>] [-advise]

    -advise               : Execute the SQL Statistics Advisor on the target table, refer to v$stats_advisor_rules

    Compare Stats:
    ==============
        -t"<stattab>"                  : Compare the stats in <stattab> with the current stats
        -pending       [<yymmddhh24mi>]: Compare the pending stats with the current/historical stats
        <yymmddhh24mi> [<yymmddhh24mi>]: Compare the stats between 2 historical timestamps

    Trace Flags [DBMS_STATS.SET_GLOBAL_PREFS('TRACE',<flag>)]:
    ==========================================================
        0     : disable
        1     : use dbms_output.put_line instead of writing into the trace file
        2     : enable the DBMS_STATS trace only at session level
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
       @notes2          : 12.1={t.notes} default={null}
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
    input          VARCHAR2(128) := :v1;
    owner          VARCHAR2(128) := :object_owner;
    object_name    VARCHAR2(128) := :object_name;
    partname       VARCHAR2(128) := :object_subname;
    typ            VARCHAR2(100) := :object_type;
    st             DATE;
    et             DATE;
    status         VARCHAR2(300);
    pval           VARCHAR2(300);
    len            INT;
    val            NUMBER;
    numrows        INT;
    numblks        INT;
    avgrlen        INT;
    cachedblk      INT;
    cachehit       INT;
    im_imcu_count  INT;
    im_block_count INT;

    TYPE t IS TABLE OF VARCHAR2(300);
    lst   sys.odciobjectlist := sys.odciobjectlist();
    --SOURCE:  SYS.OPTSTAT_HIST_CONTROL$/SYS.OPTSTAT_USER_PREFS$
    --         SYS.DBMS_STATS_INTERNAL.FILL_IN_PARAMS/FILL_IN_PARAMS_WITH_NO_PREFS
    prefs t := t('ANDV_ALGO_INTERNAL_OBSERVE','FALSE', 'TRUE/FALSE',
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
                 'WAIT_TIME_TO_UPDATE_STATS','15','15',
                 'DYNAMIC_STATS','ON','ON/OFF/CHOOSE  [for PL/SQL function]');
BEGIN
    IF :v2 IS NOT NULL OR :t IS NOT NULL THEN
        RETURN;
    END IF;
    dbms_output.enable(null);
    dbms_output.put_line('Preferences');
    dbms_output.put_line('***********');
    IF typ IS NOT NULL AND typ NOT LIKE 'TABLE%' THEN
        raise_application_error(-20001,'Only table is supported!');
    END IF;

    $IF dbms_db_version.version>10 $THEN
        IF owner IS NULL THEN
            typ := 'system';
            IF input IS NOT NULL THEN
                SELECT MAX(username)
                INTO   owner
                FROM   all_users
                WHERE  username=upper(input);
                IF owner IS NOT NULL THEN
                    typ := 'schema';
                END IF;
            END IF;
        END IF;
    $ELSE
        typ := '';
    $END

    FOR i IN 0..(prefs.count/3-1) LOOP
        BEGIN
            IF object_name IS NOT NULL THEN
                $IF dbms_db_version.version>10 $THEN
                    pval := substr(dbms_stats.get_prefs(prefs(i*3+1),owner,object_name),1,35);
                $ELSE
                    pval := NULL;
                $END
            ELSE
                pval := substr(dbms_stats.get_param(prefs(i*3+1)),1,35);
            END IF;
            len := length(pval);
            IF pval!=substr(prefs(i*3+2),1,35) THEN
                pval := '$HIR$*'||substr(pval,1,34)||'$NOR$';
                len  := len+1;
            END IF;
            status := rpad(initcap(nvl(typ,'system')||' ')||'Prefs - '||prefs(i*3+1),45)||': '||pval||rpad(' ',35-len);
            IF prefs(i*3+3) IS NOT NULL THEN
                status := status || '('||prefs(i*3+3)||')';
            END IF;
            dbms_output.put_line(status);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    $IF dbms_db_version.version>22 $THEN

    $END

    prefs := t('iotfrspeed', 'ioseektim', 'mbrc','sreadtim', 'mreadtim', 'cpuspeed', 'cpuspeednw',  'maxthr', 'slavethr');
    FOR i IN 1..prefs.count LOOP
        lst.extend();
        lst(lst.count) := sys.odciobject(upper(prefs(i)),null);
        BEGIN
            --source table: sys.aux_stats$
            dbms_stats.get_system_stats(status,st,et,prefs(i),val);
            lst(lst.count).objectname := val;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    dbms_output.put_line(rpad('-',120,'-'));
    --refer to https://github.com/FranckPachot/scripts/blob/master/statistic-gathering/display-system-statistics.txt
    FOR c IN(
        SELECT r,pname,to_char(nvl(round(nvl(calc,pval1),4),0),'999999990.999')||nullif(' ('||formula||')',' ()') value
        FROM   (SELECT rownum r,objectschema pname,objectname+0 pval1 FROM table(lst))
        MODEL
        REFERENCE sga ON
            (SELECT name,value FROM v$sga) DIMENSION BY(name) MEASURES(value)
        REFERENCE parameter ON
            (SELECT name,decode(type,3,to_number(value)) value
             FROM   v$parameter
             WHERE  name = 'db_file_multiblock_read_count'
             AND    ismodified != 'FALSE'
             UNION ALL
             SELECT '_db_file_optimizer_read_count',nvl(max(to_number(value)),8) value
             FROM   v$parameter
             WHERE  name = '_db_file_optimizer_read_count'
             UNION ALL
             SELECT name,decode(type,3,to_number(value)) value
             FROM   v$parameter
             WHERE  name = 'sessions'
             UNION ALL
             SELECT name,decode(type,3,to_number(value)) value
             FROM   v$parameter
             WHERE  name = 'db_block_size') DIMENSION BY(name) MEASURES(value)
        DIMENSION BY(pname)
        MEASURES(pval1,r,cast(NULL AS NUMBER) AS calc,cast(NULL AS VARCHAR2(200)) AS formula)
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
                                * CASE WHEN dbms_db_version.version>11 THEN 1000 ELSE 1 END),  --bug #13097308
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
             formula ['MAXTHR'] = 'maximum serial I/O throughput in bytes/'||CASE WHEN dbms_db_version.version>11 THEN 's' ELSE 'ms' END,
             formula ['SLAVETHR'] = 'average per parallel slave I/O throughput in bytes/'||CASE WHEN dbms_db_version.version>11 THEN 's' ELSE 'ms' END||', parallel I/O cost should be: (<serial_cost> * MAXTHR / (<dop> * SLAVETHR)'
        ) ORDER BY r) LOOP
        dbms_output.put_line(rpad('System Stats - '||c.pname,45)||': '||c.value);
    END LOOP;
    dbms_output.put_line(rpad('-',120,'-'));
    dbms_output.put_line(rpad('Statistics History Retention',45)||': '||
                         rpad(dbms_stats.get_stats_history_retention||' days',10)||
                         ' (Avail: '||to_char(dbms_stats.get_stats_history_availability,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')||')');
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
    own  VARCHAR2(128) := :object_owner;
    nam  VARCHAR2(128) := :object_name;
    sub  VARCHAR2(128) := :object_subname;
    typ  VARCHAR2(128) := :object_type;
    st   VARCHAR2(128) := upper(:v2);
    ed   VARCHAR2(128) := nvl(regexp_substr(:v3,'^\d+$'),to_char(sysdate,'YYMMDDHH24MISS'));
    town VARCHAR2(128);
    tnam VARCHAR2(512) := replace(trim(upper(:t)),' ');
    tz1  VARCHAR2(10)  := to_char(systimestamp,'TZH:TZM');
    ss   TIMESTAMP WITH TIME ZONE := from_tz(to_timestamp(regexp_substr(st,'^\d+$'),'YYMMDDHH24MISS'),tz1);
    es   TIMESTAMP WITH TIME ZONE := from_tz(to_timestamp(ed,'YYMMDDHH24MISS'),tz1);
    c1   SYS_REFCURSOR;
    c2   SYS_REFCURSOR;
    c3   SYS_REFCURSOR;
    c4   SYS_REFCURSOR;
    msg  VARCHAR2(300);
BEGIN
    IF nvl(typ,'X') NOT LIKE 'TABLE%' THEN
        RETURN;
    END IF;

    IF tnam IS NOT NULL THEN
        IF tnam='.' THEN
            raise_application_error(-20001,'Invalid stat table: .');
        END IF;

        IF instr(tnam,'.')=0 THEN
            town := sys_context('userenv','current_schema');
        ELSE
            town := regexp_substr(tnam,'[^\.]+',1,1);
            tnam := regexp_substr(tnam,'[^\.]+',1,2);
        END IF;

        BEGIN
            EXECUTE IMMEDIATE 'SELECT 1 FROM '||town||'.'||tnam||' WHERE STATID IS NULL AND C4 IS NOT NULL';
        EXCEPTION WHEN OTHERS THEN
            IF sqlcode=-904 THEN
                raise_application_error(-20001,'Invalid stats table: '||town||'.'||tnam);
            ELSE
                raise_application_error(-20001,'No access to target stats table: &t, consider create it with: exec dbms_stats.create_stat_table('''||town||''','''||tnam||''');');
            END IF;
        END;
    END IF;

    msg := '| '||typ||' '||own||'.'||nam||trim('.' FROM '.'||sub)||' |';
    dbms_output.put_line(rpad('*',length(msg),'*'));
    dbms_output.put_line(msg);
    dbms_output.put_line('| '||rpad('=',length(msg)-4,'=')||' |');
    dbms_output.put_line(rpad('*',length(msg),'*'));
    OPEN :c5 FOR &check_access_sys;
    IF st IN ('-PENDING','PENDING') THEN
        OPEN :c6 FOR
            SELECT * FROM table(dbms_stats.diff_table_stats_in_pending(own,nam,es,pctthreshold=>0.01));
    ELSIF tnam IS NOT NULL THEN
        OPEN :c6 FOR
            SELECT * FROM table(dbms_stats.diff_table_stats_in_stattab(own,nam,stattab1own=>town,stattab1=>tnam,pctthreshold=>0.01));
    ELSIF ss IS NOT NULL THEN
        OPEN :c6 FOR
            SELECT * FROM table(dbms_stats.diff_table_stats_in_history(own,nam,ss,es,pctthreshold=>0.01));
    ELSIF st IS NOT NULL THEN
        raise_application_error(-20001,'Invalid parameter: '||:v2);
    ELSIF typ='TABLE' THEN
        OPEN c1 FOR
            SELECT /*+outline_leaf*/
                   table_name,
                   num_rows,
                   sample_size samples,
                   round(sample_size/nullif(num_rows,0),4) "Samples(%)",
                   blocks,
                   empty_blocks,
                   avg_space,
                   chain_cnt,
                   avg_row_len,
                   global_stats,
                   user_stats,
                   last_analyzed
                   &im ,t1.notes,IMCU,IM_BLOCK,IM_TIME
            FROM   &check_access_dba.tables t
            LEFT   JOIN (SELECT owner,table_name &im, &notes2 notes,t.IM_IMCU_COUNT IMCU,t.IM_BLOCK_COUNT IM_BLOCK,t.IM_STAT_UPDATE_TIME IM_TIME
                         FROM   &check_access_dba.tab_statistics t
                         WHERE  owner = own
                         AND    table_name = nam
                         AND    rownum<2) t1
            USING  (owner,table_name)
            WHERE  owner = own
            AND    table_name = nam;
        OPEN c2 FOR
            SELECT /*+outline_leaf opt_param('optimizer_dynamic_sampling' 5)*/
                   t1.column_name,
                   decode(t1.data_type,
                          'NUMBER',t1.data_type || '(' || decode(t1.data_precision, NULL, t1.data_length || ')', t1.data_precision || ',' || t1.data_scale || ')'),
                          'DATE',t1.data_type,
                          'LONG',t1.data_type,
                          'LONG RAW',t1.data_type,
                          'ROWID',t1.data_type,
                          'MLSLABEL',t1.data_type,
                          t1.data_type || '(' || t1.data_length || ')') || ' ' ||
                   decode(t1.nullable, 'N', 'NOT NULL', 'n', 'NOT NULL', NULL) col,
                   t.histogram,
                   t.num_buckets buckets,
                   t.sample_size,
                   round((nvl(t.sample_size,0)+t.num_nulls+CASE WHEN nvl(t.sample_size,0)<t.num_distinct THEN t.num_distinct ELSE 0 END)/nullif(num_rows,0),4) "Samples(%)",
                   t.num_distinct,
                   t.num_nulls,
                   round(decode(t1.histogram,'HYBRID',NULL,greatest(0,num_rows-t.num_nulls)/greatest(t.num_distinct, 1)), 2) cardinality,
                   t.global_stats,
                   t.user_stats,
                   t1.data_default "DEFAULT",
                   t.last_analyzed &notes
            FROM   &check_access_dba.tab_cols t1,&check_access_dba.tab_col_statistics t,
                   (SELECT table_name,num_rows
                    FROM   &check_access_dba.tab_statistics t
                    WHERE  owner = own
                    AND    table_name = nam
                    AND    partition_name IS NULL) t2
            WHERE  t2.table_name=t1.table_name
            AND    t1.table_name = nam
            AND    t1.owner = own
            AND    t.table_name = nam
            AND    t.owner = own
            AND    t1.column_name=t.column_name;

        OPEN c3 FOR
            WITH i AS (SELECT /*+outline_leaf*/
                              i.*,nvl(c.locality,'GLOBAL') locality,
                              partitioning_type||extractvalue(dbms_xmlgen.getxmltype(q'[
                                        SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                        FROM   (SELECT /*+CURSOR_SHARING_FORCE opt_param('_connect_by_use_union_all','old_plan_mode') no_merge*/* FROM all_part_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                        START  WITH column_position = 1
                                        CONNECT BY PRIOR column_position = column_position - 1]'),'//V') partitioned_by,
                              nullif(subpartitioning_type,'NONE')||extractvalue(dbms_xmlgen.getxmltype(q'[
                                        SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                        FROM   (SELECT /*+CURSOR_SHARING_FORCE opt_param('_connect_by_use_union_all','old_plan_mode') no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                        START  WITH column_position = 1
                                        CONNECT BY PRIOR column_position = column_position - 1]'),'//V') subpart_by
                       FROM   &check_access_dba.indexes i,&check_access_dba.part_indexes c
                       WHERE  c.owner(+) = i.owner
                       AND    c.index_name(+) = i.index_name
                       AND    i.table_owner = own
                       AND    i.table_name = nam)
            SELECT /*INTERNAL_DBCLI_CMD*/ --+opt_param('optimizer_dynamic_sampling' 5) outline_leaf opt_param('container_data' 'current') leading(i c e) opt_param('_sort_elimination_cost_ratio',5)
                   decode(c.column_position, 1, i.owner, '') owner,
                   decode(c.column_position, 1, i.index_name, '') index_name,
                   decode(c.column_position, 1, i.index_type, '') index_type,
                   decode(c.column_position, 1, decode(i.uniqueness,'UNIQUE','YES','NO'), '') "UNIQUE",
                   decode(c.column_position, 1, nvl(partitioned_by||nullif(','||subpart_by,','),'NO'), '') "PARTITIONED",
                   decode(c.column_position, 1, locality, '') "LOCALITY",
               --decode(c.column_position, 1, (SELECT nvl(MAX('YES'),'NO') FROM all_constraints ac WHERE ac.index_owner = i.owner AND ac.index_name = i.index_name), '') "IS_PK",
                   decode(c.column_position, 1, decode(i.status,'N/A',(SELECT MIN(status) FROM all_ind_partitions p WHERE p.index_owner = i.owner AND p.index_name = i.index_name),i.status), '') status,
                   decode(c.column_position, 1, i.blevel) blevel,
                   decode(c.column_position, 1, i.leaf_blocks) leaf_blocks,
                   decode(c.column_position, 1, i.distinct_keys) distincts,
                   decode(c.column_position, 1, avg_leaf_blocks_per_key) lb_per_key,
                   decode(c.column_position, 1, avg_data_blocks_per_key) db_per_key,
                   decode(c.column_position, 1, i.last_analyzed) last_analyzed,
                   c.column_position no#,
                   c.column_name,
                   e.column_expression column_expr,
                   c.descend
            FROM   &check_access_dba.ind_columns c,  i, &check_access_dba.ind_expressions e
            WHERE  c.index_owner = i.owner
            AND    c.index_name = i.index_name
            AND    c.index_name = e.index_name(+)
            AND    c.index_owner = e.index_owner(+)
            AND    c.column_position = e.column_position(+)
            AND    c.table_owner = e.table_owner(+)
            AND    c.table_name = e.table_name(+)
            ORDER  BY c.index_name, c.column_position;

        OPEN c4 FOR
            SELECT *
            FROM   (SELECT /*+outline_leaf*/
                           partition_name,
                           partition_position position,
                           t.num_rows,
                           t.sample_size,
                           round((nvl(t.sample_size,0))/nullif(num_rows,0),4) "Samples(%)",
                           blocks,
                           empty_blocks,
                           avg_space,
                           chain_cnt,
                           avg_row_len,
                           global_stats,
                           user_stats,
                           last_analyzed,
                           o.created
                    FROM   &check_access_dba.tab_partitions t,&check_access_dba.objects o
                    WHERE  table_owner = own
                    AND    table_name = nam
                    AND    o.owner=own
                    AND    o.object_name=nam
                    AND    o.subobject_name=t.partition_name
                    ORDER  BY created DESC,position)
            WHERE  rownum<=100;
    ELSIF typ='TABLE PARTITION' THEN
        OPEN c1 FOR
            SELECT partition_name,
                   num_rows,
                   t.sample_size,
                   round((nvl(t.sample_size,0))/nullif(num_rows,0),4) "Samples(%)",
                   blocks,
                   empty_blocks,
                   avg_space,
                   chain_cnt,
                   avg_row_len,
                   global_stats,
                   user_stats,
                   t.last_analyzed
            FROM   &check_access_dba.tab_partitions t
            WHERE  table_owner = own
            AND    table_name = nam
            AND    partition_name =nvl(sub,partition_name)
            ORDER  BY partition_position;
        OPEN c2 FOR
            SELECT /*+opt_param('optimizer_dynamic_sampling' 5) outline_leaf*/
                   partition_name,
                   column_name,
                   histogram,
                   round(decode(histogram,'HYBRID',NULL,greatest(0,num_rows-num_nulls)/greatest(num_distinct, 1)), 2) cardinality,
                   num_buckets buckets,
                   t.sample_size,
                   round((nvl(t.sample_size,0)+t.num_nulls+CASE WHEN nvl(t.sample_size,0)<num_distinct THEN num_distinct ELSE 0 END)/nullif(num_rows,0),4) "Samples(%)",
                   num_nulls,
                   num_distinct,
                   global_stats,
                   user_stats,
                   t.last_analyzed  &notes
            FROM   &check_access_dba.part_col_statistics t,
                   (SELECT table_name,num_rows
                    FROM   &check_access_dba.tab_partitions p
                    WHERE  p.table_owner = own
                    AND    p.table_name = nam
                    AND    p.partition_name=sub) t1
            WHERE  t.table_name = nam
            AND    owner = own
            AND    t1.table_name=t.table_name
            AND    partition_name =sub;
        OPEN c3 FOR
            SELECT t.index_name,
                   t.partition_name,
                   t.blevel blev,
                   t.leaf_blocks,
                   t.distinct_keys,
                   t.sample_size,
                   round((nvl(t.sample_size,0))/nullif(t.num_rows,0),4) "Samples(%)",
                   t.avg_leaf_blocks_per_key lb_per_key,
                   t.avg_data_blocks_per_key data_per_key,
                   t.clustering_factor,
                   t.global_stats,
                   t.user_stats,
                   t.last_analyzed
            FROM   &check_access_dba.ind_partitions t, &check_access_dba.indexes i
            WHERE  i.table_name = nam
            AND    i.table_owner = own
            AND    i.owner = t.index_owner
            AND    i.index_name = t.index_name
            AND    t.partition_name =sub;

        OPEN c4 FOR
            SELECT subpartition_name,
                   subpartition_position position,
                   num_rows,
                   sample_size,
                   round((nvl(t.sample_size,0))/nullif(num_rows,0),4) "Samples(%)",
                   blocks,
                   empty_blocks,
                   avg_space,
                   chain_cnt,
                   avg_row_len,
                   global_stats,
                   user_stats,
                   t.last_analyzed
            FROM   &check_access_dba.tab_subpartitions t
            WHERE  table_owner = own
            AND    table_name = nam
            AND    partition_name =sub
            ORDER  BY subpartition_position;
    ELSIF typ='TABLE SUBPARTITION' THEN
        OPEN c1 FOR
            SELECT partition_name,
                   subpartition_name,
                   num_rows,
                   sample_size,
                   round((nvl(t.sample_size,0))/nullif(num_rows,0),4) "Samples(%)",
                   blocks,
                   empty_blocks,
                   avg_space,
                   chain_cnt,
                   avg_row_len,
                   global_stats,
                   user_stats,
                   t.last_analyzed
            FROM   &check_access_dba.tab_subpartitions t
            WHERE  table_owner = own
            AND    table_name = nam
            AND    subpartition_name =sub;
        OPEN c2 FOR
            SELECT t.subpartition_name,
                   t.column_name,
                   num_buckets buckets,
                   t.sample_size,
                   round((nvl(t.sample_size,0)+t.num_nulls+CASE WHEN nvl(t.sample_size,0)<num_distinct THEN num_distinct ELSE 0 END)/nullif(num_rows,0),4) "Samples(%)",
                   num_nulls,
                   num_distinct,
                   t.global_stats,
                   t.user_stats,
                   t.last_analyzed &notes
            FROM   &check_access_dba.subpart_col_statistics t, &check_access_dba.tab_subpartitions p
            WHERE  t.table_name = nam
            AND    t.owner = own
            AND    t.subpartition_name = p.subpartition_name
            AND    t.owner = p.table_owner
            AND    t.table_name = p.table_name
            AND    t.subpartition_name =sub;
        OPEN c3 FOR
            SELECT t.index_name,
                   t.partition_name,
                   t.subpartition_name,
                   t.blevel blev,
                   t.leaf_blocks,
                   t.distinct_keys,
                   t.num_rows,
                   t.sample_size,
                   round((nvl(t.sample_size,0))/nullif(t.num_rows,0),4) "Samples(%)",
                   t.avg_leaf_blocks_per_key lb_per_key,
                   t.avg_data_blocks_per_key data_per_key,
                   t.clustering_factor,
                   t.global_stats,
                   t.user_stats,
                   t.last_analyzed
            FROM   &check_access_dba.ind_subpartitions t, &check_access_dba.indexes i
            WHERE  i.table_name = nam
            AND    i.table_owner = own
            AND    i.owner = t.index_owner
            AND    i.index_name = t.index_name
            AND    t.subpartition_name =sub;
    END IF;

    :c1 := c1;
    :c2 := c2;
    :c3 := c3;
    :c4 := c4;
END;
/
PRINT C1;
PRINT C5;
PRINT C6;
PRINT C2;
PRINT C3;
PRINT C4;

DECLARE
    input  VARCHAR2(128) := :v1;
    oname  VARCHAR2(128) := :object_owner;
    tab    VARCHAR2(128) := :object_name;
    tname  VARCHAR2(128) := upper('stats_adv_' || oname || '_' || tab)||to_char(sysdate,'SSSSS');
    tid    PLS_INTEGER;
    output CLOB;
BEGIN
    NULL;
    $IF &advise=1 $THEN
        IF oname IS NULL AND input IS NOT NULL THEN
            SELECT MAX(username)
            INTO   oname
            FROM   all_users
            WHERE  username=upper(input);
        END IF;
        BEGIN
            dbms_stats.drop_advisor_task(tname);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        output := dbms_stats.create_advisor_task(tname);
        --defines rules that listed in v$stats_advisor_rules
        output := dbms_stats.configure_advisor_obj_filter(task_name          => tname,
                                                          stats_adv_opr_type => 'EXECUTE',
                                                          rule_name          => NULL,
                                                          ownname            => NULL,
                                                          tabname            => NULL,
                                                          action             => 'DISABLE');
        output := dbms_stats.configure_advisor_obj_filter(task_name          => tname,
                                                          stats_adv_opr_type => 'EXECUTE',
                                                          rule_name          => NULL,
                                                          ownname            => oname,
                                                          tabname            => tab,
                                                          action             => 'ENABLE');
        output := dbms_stats.configure_advisor_rule_filter(task_name          => tname,
                                                           stats_adv_opr_type => 'EXECUTE',
                                                           rule_name          => 'UseConcurrent',
                                                           action             => 'DISABLE');
        output := dbms_stats.configure_advisor_rule_filter(task_name          => tname,
                                                           stats_adv_opr_type => 'EXECUTE',
                                                           rule_name          => 'UseGatherSchemaStats',
                                                           action             => 'DISABLE');
        output := dbms_stats.execute_advisor_task(tname);
        SELECT task_id
        INTO   tid
        FROM   dba_advisor_tasks
        WHERE  task_name=tname;
        dbms_output.put_line('Statistics Advisor for "'||nvl(trim('.' FROM oname||'.'||tab),'Database')||'" is running, please use "ora addm '||tid||'" to show the result afterwards.');
        dbms_output.put_line('Or may run following command to see the recommended script:');
        dbms_output.put_line('    select dbms_stats.script_advisor_task('''||tname||''') from dual;');
    $END
END;
/
