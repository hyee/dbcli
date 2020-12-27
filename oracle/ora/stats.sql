/*[[
Get preferences and stats of the target object. Usage: @@NAME {[owner] | [owner.]<object_name>[.partition_name]} [-advise]

-advise: execute SQL Statistics Advisor on the target table, refer to v$stats_advisor_rules

Sameple Output:
===============
ORCL> ORA STATS                                                                                     
    Preferences                                                                                     
    ***********                                                                                     
    System Prefs - APPROXIMATE_NDV               : TRUE                               (TRUE/FALSE)  
    System Prefs - AUTOSTATS_TARGET              : AUTO                               (ALL/AUTO/ORAC
    System Prefs - CASCADE                       : DBMS_STATS.AUTO_CASCADE            (TRUE/FALSE/nu
    System Prefs - CONCURRENT                    : FALSE                              (MANUAL/AUTOMA
    System Prefs - DEBUG                         : 0                                  (1[AUTO_TLIST_
    System Prefs - DEGREE                        : NULL                               (n/32766(DEFAU
    System Prefs - ESTIMATE_PERCENT              : DBMS_STATS.AUTO_SAMPLE_SIZE        (0(AUTO_SAMPLE
    System Prefs - GRANULARITY                   : AUTO                               (Partitioned: 
    System Prefs - INCREMENTAL                   : FALSE                              (Partitioned: 
    System Prefs - INCREMENTAL_INTERNAL_CONTROL  : TRUE                               (Partitioned: 
    System Prefs - METHOD_OPT                    : FOR ALL COLUMNS SIZE AUTO          (FOR ALL [INDE
    System Prefs - NO_INVALIDATE                 : DBMS_STATS.AUTO_INVALIDATE         (TRUE/FALSE/nu
    System Prefs - PUBLISH                       : TRUE                               (TRUE/FALSE)  
    System Prefs - SKIP_TIME                     :                                                  
    System Prefs - STALE_PERCENT                 : 10                                               
    System Prefs - STATS_RETENTION               :                                                  
    System Prefs - SYS_FLAGS                     : 1                                  (0/1(DSC_SYS_F
    System Prefs - TABLE_CACHED_BLOCKS           : 1                                  (0(AUTO_TABLE_
    System Prefs - TRACE                         : 0                                  (0(disable),1(
    ------------------------------------------------------------------------------------------------
    System Stats - IOTFRSPEED                    : 4          (transfer speed in KB/ms)             
    System Stats - IOSEEKTIM                     : 10         (latency  in ms)                      
    System Stats - SREADTIM                      : 12         (time to read 1 block  in ms = IOSEEKT
    System Stats - MREADTIM                      : 26         (time to read n blocks in ms = IOSEEKT
    System Stats - CPUSPEED                      :            (workload CPU speed in GHZ)           
    System Stats - CPUSPEEDNW                    : .9371      (noworkload CPU speed in GHZ)         
    System Stats - MBRC                          : 8          (_db_file_optimizer_read_count)       
    System Stats - MAXTHR                        :            (maximum throughput that the I/O subsy
    System Stats - SLAVETHR                      :            (average parallel slave I/O throughput
    System Stats -    maximum mbrc               : 24.7742    (buffer cache size in blocks / session
    System Stats -    single cost / block        : 1          (by definition)                       
    System Stats -    multi  cost / block        : .2708      (1/MBRC * MREADTIM/SREADTIM)          
    ------------------------------------------------------------------------------------------------
    Statistics History Retention                 : 31 days    (Avail: 2019-03-12 22:02:19.933 -04:00
                                                                                                    
                                                                                                    
    Table Level                                                                                     
    ***********                                                                                     
    Index Level                                                                                     
    ***********                                                                                     
    Partition Level                                                                                 
    ***************                                                                                 
    SubPartition Level                                                                              
    ***************                                                                                 

    --[[
       @check_access_dba: dba_tables={dba_} default={all_}
       &advise          : default={0} advise={1}
       @notes           : 12.1={,t.notes} default={}
    --]]
]]*/
ora _find_object "&V1" 1
set feed off serveroutput on printsize 10000 verify off
pro Preferences
pro ***********
DECLARE
    input       varchar2(128) := :V1;
    owner       varchar2(128) := :object_owner;
    object_name varchar2(128) := :object_name;
    partname    varchar2(128) := :object_subname;
    typ         varchar2(100) := :object_type;
    st          date;
    et          date;
    status      varchar2(300);
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
    prefs t:= t('ANDV_ALGO_INTERNAL_OBSERVE', 'TRUE/FALSE',
                'APPROXIMATE_NDV','TRUE/FALSE',
                'APPROXIMATE_NDV_ALGORITHM','REPEAT OR HYPERLOGLOG/ADAPTIVE SAMPLING/HYPERLOGLOG',
                'AUTOSTATS_TARGET','ALL/AUTO/ORACLE/Z(DEFAULT_AUTOSTATS_TARGET)',
                'AUTO_STATS_ADVISOR_TASK','TRUE/FALSE',
                'AUTO_STAT_EXTENSIONS','ON/OFF',
                'AUTO_TASK_STATUS','HIGH FREQUENCY STATISTICS: ON/OFF',
                'AUTO_TASK_MAX_RUN_TIME','HIGH FREQUENCY STATISTICS: Max run secs',
                'AUTO_TASK_INTERVAL','HIGH FREQUENCY STATISTICS: Interval in secs',
                'CASCADE','TRUE/FALSE/null(AUTO_CASCADE)',
                'CONCURRENT','MANUAL/AUTOMATIC/ALL/OFF/FALSE/TRUE',
                'COORDINATOR_TRIGGER_SHARD','TRUE/FALSE',
                'DEBUG','1[AUTO_TLIST_ONLY],2[MANUAL_TLIST],4[PARALLEL_SYNOP],8[CLOB_SQL],16[FORCE_TF],32[BATCHINGSQL]',
                'DEGREE','n/32766(DEFAULT_DEGREE_VALUE)/32767(DEFAULT_DEGREE)/32768(AUTO_DEGREE)',
                'ENABLE_HYBRID_HISTOGRAMS','0:disable 1/2/3',
                'ENABLE_TOP_FREQ_HISTOGRAMS','0:disable 1/2/3',
                'ESTIMATE_PERCENT','0(AUTO_SAMPLE_SIZE)/[0.000001-100]/101(DEFAULT_ESTIMATE_PERCENT)',
                'GATHER_AUTO','AFTER_LOAD/ALWAYS',
                'GATHER_SCAN_RATE','HADOOP_ONLY/ON/OFF',
                'GLOBAL_TEMP_TABLE_STATS','SHARED/SESSION',
                'GRANULARITY','Partition: AUTO/ALL/DEFAULT/GLOBAL/PARTITION/SUBPARTITION/GLOBAL AND PARTITION/PART AND SUBPART/GLOBAL AND SUBPART/APPROX_GLOBAL AND PARTITION',
                'INCREMENTAL','Partition: TRUE/FALSE, fix controls: 13583722/16726844',
                'INCREMENTAL_INTERNAL_CONTROL','Partition: TRUE/FALSE',
                'INCREMENTAL_LEVEL','Partition: TABLE/PARTITION synopses',
                'INCREMENTAL_STALENESS','Partition: ALLOW_MIXED_FORMAT,USE_STALE_PERCENT,USE_LOCKED_STATS/NULL',
                'JOB_OVERHEAD','-1',
                'JOB_OVERHEAD_PERC','1',
                'MAINTAIN_STATISTICS_STATUS','TRUE/FALSE',
                'METHOD_OPT','FOR ALL [INDEXED|HIDDEN] COLUMNS [SIZE {integer|REPEAT|AUTO|SKEWONLY}]/Z(DEFAULT_METHOD_OPT)',
                'MON_MODS_ALL_UPD_TIME','',
                'NO_INVALIDATE','TRUE/FALSE/null(AUTO_INVALIDATE)',
                'OPTIONS','GATHER/GATHER AUTO/Z(DEFAULT_OPTIONS)(additional schema/system: GATHER STALE/GATHER EMPTY/LIST AUTO/LIST STALE/LIST EMPTY)',
                'PREFERENCE_OVERRIDES_PARAMETER','TRUE/FALSE',
                'PUBLISH','TRUE/FALSE',
                'REAL_TIME_STATISTICS','ON/OFF',
                'ROOT_TRIGGER_PDB','FALSE/TRUE',
                'SCAN_RATE','0',
                'SKIP_TIME','',
                'SNAPSHOT_UPD_TIME','',
                'SPD_RETENTION_WEEKS','53',
                'STATS_MODEL','ON/OFF',
                'STATS_MODEL_INTERNAL_CONTROL','0',
                'STATS_MODEL_INTERNAL_MINRSQ','0.9',
                'STALE_PERCENT','10',
                'STATS_RETENTION','',
                'STAT_CATEGORY','OBJECT_STATS,SYNOPSES,REALTIME_STATS/Z(DEFAULT_STAT_CATEGORY)',
                'SYS_FLAGS','0/1(DSC_SYS_FLAGS_DUBIOUS_DONE)',
                'TABLE_CACHED_BLOCKS','0(AUTO_TABLE_CACHED_BLOCKS)/n',
                'TRACE','0(disable),1(DBMS_OUTPUT_TRC),2(SESSION_TRC),4(TAB_TRC),8(IND_TRC),16(COL_TRC),32(AUTOST_TRC),...524288',
                'WAIT_TIME_TO_UPDATE_STATS','15');
BEGIN
    dbms_output.enable(null);
    IF typ IS NOT NULL and typ NOT like 'TABLE%' THEN
        RAISE_APPLICATION_ERROR(-20001,'Only table is supported!');
    END IF;

    $IF DBMS_DB_VERSION.VERSION<11 $THEN
        for i in 0..prefs.count/2 loop
            begin
                status :=rpad('Param - '||prefs(i*2+1),45)||': '||rpad(dbms_stats.get_param(prefs(i*2+1)),35);
                if prefs(i*2+2) is not null then
                    status := status || '('||prefs(i*2+2)||')';
                end if;
                dbms_output.put_line(status);
            exception when others then null;
            end;
        end loop;    
    $ELSE
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
        for i in 0..prefs.count/2 loop
            begin
                status :=rpad(initcap(nvl(typ,'system')||' ')||'Prefs - '||prefs(i*2+1),45)||': '||rpad(dbms_stats.get_prefs(prefs(i*2+1),owner,object_name),35);
                if prefs(i*2+2) is not null then
                    status := status || '('||prefs(i*2+2)||')';
                end if;
                dbms_output.put_line(status);
            exception when others then null;
            end;
        end loop;
    $END
    
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
        SELECT r,pname, to_char(nvl(round(nvl(calc,pval1),4),0),'999990.999')||nullif(' ('||formula||')',' ()') value
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
                    SELECT NAME, decode(TYPE, 3, to_number(VALUE)) VALUE
                    FROM   v$parameter
                    WHERE  NAME = 'sessions'
                    UNION ALL
                    SELECT NAME, decode(TYPE, 3, to_number(VALUE)) VALUE
                    FROM   v$parameter
                    WHERE  NAME = 'db_block_size') DIMENSION BY(NAME) MEASURES(VALUE) 
        DIMENSION BY(pname)
        MEASURES(pval1,r, CAST(NULL AS NUMBER) AS calc, CAST(NULL AS VARCHAR2(120)) AS formula)
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
             formula ['MREADTIM'] = 'time to read n blocks in ms = IOSEEKTIM + db_block_size * MBRC / IOTFRSPEED',
             formula ['SREADTIM'] = 'time to read 1 block  in ms = IOSEEKTIM + db_block_size / IOTFRSPEED',
             formula ['IOSEEKTIM'] = 'latency  in ms',
             formula ['IOTFRSPEED'] = 'transfer speed in KB/ms',
             formula ['   multi  cost / block'] = '1/MBRC * MREADTIM/SREADTIM',
             formula ['   single cost / block'] = 'by definition',
             formula ['   maximum mbrc'] = 'buffer cache size in blocks / sessions',
             formula ['CPUSPEED'] = 'workload CPU speed in MHZ',
             formula ['CPUSPEEDNW'] = 'noworkload CPU speed in MHZ',
             formula ['MAXTHR'] = 'maximum throughput that the I/O subsystem can deliver',
             formula ['SLAVETHR'] = 'average parallel slave I/O throughput'
        ) ORDER BY r) LOOP
        dbms_output.put_line(rpad('System Stats - '||c.pname,45)||': '||c.value);
    END LOOP;
    dbms_output.put_line(rpad('-',120,'-'));
    dbms_output.put_line(rpad('Statistics History Retention',45) ||': '||rpad(dbms_stats.GET_STATS_HISTORY_RETENTION||' days',10)||' (Avail: '||to_char(dbms_stats.GET_STATS_HISTORY_AVAILABILITY,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')||')');
END;
/
set BYPASSEMPTYRS on
pro 
pro   
var c1 REFCURSOR "&OBJECT_TYPE INFO"
var c2 REFCURSOR "&OBJECT_TYPE COLUMN INFO"
var c3 REFCURSOR "&OBJECT_TYPE INDEX INFO"
var c4 REFCURSOR "&OBJECT_TYPE CHILD PARTS"
col "Samples(%)" for pct
DECLARE
    typ VARCHAR2(30):=:OBJECT_TYPE;
    c1 SYS_REFCURSOR;
    c2 SYS_REFCURSOR;
    c3 SYS_REFCURSOR;
    c4 SYS_REFCURSOR;
BEGIN
    IF typ='TABLE' THEN
        OPEN c1 FOR 
            select 
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
                t.last_analyzed
            from &check_access_dba.tables t
            where owner = :object_owner
            and table_name = :object_name;
        OPEN c2 FOR
            SELECT t1.COLUMN_NAME,
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
                   round((nvl(t.SAMPLE_SIZE,0)+t.NUM_NULLS)/nullif(NUM_ROWS,0),4) "Samples(%)",
                   t.NUM_DISTINCT,
                   t.NUM_NULLS,
                   ROUND(decode(t1.histogram,'HYBRID',NULL,greatest(0,num_rows-t.NUM_NULLS)/GREATEST(t.NUM_DISTINCT, 1)), 2) cardinality,
                   t.GLOBAL_STATS,
                   t.USER_STATS,
                   t1.DATA_DEFAULT "DEFAULT",
                   t.LAST_ANALYZED &notes
            FROM   &check_access_dba.tab_cols t1,&check_access_dba.tab_col_statistics t,
                   (select table_name,num_rows from &check_access_dba.tables where owner = :object_owner and table_name = :object_name) t2
            WHERE  t2.table_name=t1.table_name
            AND    t1.table_name = :object_name
            AND    t1.owner = :object_owner
            AND    t.table_name = :object_name
            AND    t.owner = :object_owner
            AND    t1.column_name=t.column_name;

        OPEN C3 FOR
            WITH I AS (SELECT /*+no_merge opt_param('cursor_sharing' 'force')*/ 
                               I.*,nvl(c.LOCALITY,'GLOBAL') LOCALITY,
                               PARTITIONING_TYPE||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                        SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                        FROM   (SELECT /*+no_merge*/* FROM all_part_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                        START  WITH column_position = 1
                                        CONNECT BY PRIOR column_position = column_position - 1]'),'//V') PARTITIONED_BY,
                               nullif(SUBPARTITIONING_TYPE,'NONE')||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                        SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                        FROM   (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                        START  WITH column_position = 1
                                        CONNECT BY PRIOR column_position = column_position - 1]'),'//V') SUBPART_BY
                        FROM   &check_access_dba.INDEXES I,&check_access_dba.PART_INDEXES C
                        WHERE  C.OWNER(+) = I.OWNER
                        AND    C.INDEX_NAME(+) = I.INDEX_NAME
                        AND    I.TABLE_OWNER = :object_owner
                        AND    I.TABLE_NAME = :object_name)
            SELECT /*INTERNAL_DBCLI_CMD*/ --+opt_param('_optim_peek_user_binds','false')
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
            SELECT PARTITION_NAME,
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
                   t.last_analyzed
            FROM   &check_access_dba.tab_partitions t
            WHERE  table_owner = :object_owner
            AND    table_name = :object_name
            AND    partition_name =nvl(:object_subname,partition_name)
            ORDER  BY partition_position;
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
            WHERE  table_owner = :object_owner
            AND    table_name = :object_name
            AND    partition_name =nvl(:object_subname,partition_name)
            ORDER  BY partition_position;
        OPEN C2 FOR
            SELECT PARTITION_NAME,
                   COLUMN_NAME,
                   HISTOGRAM,
                   ROUND(decode(histogram,'HYBRID',NULL,greatest(0,num_rows-NUM_NULLS)/GREATEST(NUM_DISTINCT, 1)), 2) cardinality,
                   NUM_BUCKETS BUCKETS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0)+t.NUM_NULLS)/nullif(NUM_ROWS,0),4) "Samples(%)",
                   NUM_NULLS,
                   NUM_DISTINCT,
                   GLOBAL_STATS,
                   USER_STATS,
                   t.last_analyzed  &notes
            FROM   &check_access_dba.PART_COL_STATISTICS t,
                   (select table_name,num_rows from &check_access_dba.tab_partitions p where p.table_owner = :object_owner and p.table_name = :object_name and p.partition_name=:object_subname) t1
            WHERE  t.table_name = :object_name
            AND    owner = :object_owner
            AND    t1.table_name=t.table_name
            AND    PARTITION_NAME =:object_subname
            AND    partition_name =nvl(:object_subname,partition_name);
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
            WHERE  i.table_name = :object_name
            AND    i.table_owner = :object_owner
            AND    i.owner = t.index_owner
            AND    i.index_name = t.index_name
            AND    t.partition_name =nvl(:object_subname,t.partition_name);

        OPEN C4 FOR
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
            WHERE  table_owner = :object_owner
            AND    table_name = :object_name
            AND    subpartition_name =nvl(:object_subname,subpartition_name)
            ORDER  BY SUBPARTITION_POSITION;
    ELSIF typ='TABLE PARTITION' THEN
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
            WHERE  table_owner = :object_owner
            AND    table_name = :object_name
            AND    subpartition_name =nvl(:object_subname,subpartition_name)
            ORDER  BY SUBPARTITION_POSITION;
        OPEN C2 FOR
            SELECT p.PARTITION_NAME,
                   t.SUBPARTITION_NAME,
                   t.COLUMN_NAME,
                   NUM_BUCKETS BUCKETS,
                   t.SAMPLE_SIZE,
                   round((nvl(t.SAMPLE_SIZE,0)+t.NUM_NULLS)/nullif(NUM_ROWS,0),4) "Samples(%)",
                   NUM_NULLS,
                   NUM_DISTINCT,
                   t.GLOBAL_STATS,
                   t.USER_STATS,
                   t.last_analyzed &notes
            FROM   &check_access_dba.SUBPART_COL_STATISTICS t, &check_access_dba.tab_subpartitions p
            WHERE  t.table_name = :object_name
            AND    t.owner = :object_owner
            AND    t.subpartition_name = p.subpartition_name
            AND    t.owner = p.table_owner
            AND    t.table_name = p.table_name
            AND    t.subpartition_name =:object_subname;
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
            WHERE  i.table_name = :object_name
            AND    i.table_owner = :object_owner
            AND    i.owner = t.index_owner
            AND    i.index_name = t.index_name
            AND    t.subpartition_name =nvl(:object_subname,t.subpartition_name);
    END IF;

    :C1 := C1;
    :C2 := C2;
    :C3 := C3;
    :C4 := C4;
END;
/

PRINT C1;
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