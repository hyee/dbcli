/*[[Get preferences and stats of the target object. Usage: @@NAME [[owner.]<object_name>[.partition_name]] [-advise]
    
    -advise: execute SQL Statistics Advisor on the target table
    --[[
       @check_access_dba: dba_tables={dba_} default={all_}
       &advise          : default={0} advise={1}
    --]]
]]*/
ora _find_object "&V1" 1
set feed off serveroutput on printsize 10000
pro Preferences
pro ***********
DECLARE
    owner       varchar2(30)  := :object_owner;
    object_name varchar2(128) := :object_name;
    partname    varchar2(128) := :object_subname;
    typ         varchar2(100) := :object_type;
    st          date;
    et          date;
    status      varchar2(100);
    val         number;
    numrows     int;
    numblks     int;
    avgrlen     int;
    cachedblk   int;
    cachehit    int;
    im_imcu_count  INT;
    im_block_count INT;
    type t is table of varchar2(100);
    --SOURCE:  SYS.OPTSTAT_HIST_CONTROL$/SYS.OPTSTAT_USER_PREFS$
    prefs t:= t('ANDV_ALGO_INTERNAL_OBSERVE',
                'APPROXIMATE_NDV',
                'APPROXIMATE_NDV_ALGORITHM',
                'AUTOSTATS_TARGET',
                'AUTO_STAT_EXTENSIONS',
                'CASCADE',
                'CONCURRENT',
                'DEBUG',
                'DEGREE',
                'ENABLE_HYBRID_HISTOGRAMS',
                'ENABLE_TOP_FREQ_HISTOGRAMS',
                'ESTIMATE_PERCENT',
                'GATHER_AUTO',
                'GATHER_SCAN_RATE',
                'GLOBAL_TEMP_TABLE_STATS',
                'GRANULARITY',
                'INCREMENTAL',
                'INCREMENTAL_INTERNAL_CONTROL',
                'INCREMENTAL_LEVEL',
                'INCREMENTAL_STALENESS',
                'JOB_OVERHEAD',
                'JOB_OVERHEAD_PERC',
                'METHOD_OPT',
                'MON_MODS_ALL_UPD_TIME',
                'NO_INVALIDATE',
                'OPTIONS',
                'PREFERENCE_OVERRIDES_PARAMETER',
                'PUBLISH',
                'SCAN_RATE',
                'SKIP_TIME',
                'SNAPSHOT_UPD_TIME',
                'SPD_RETENTION_WEEKS',
                'STALE_PERCENT',
                'STATS_RETENTION',
                'STAT_CATEGORY',
                'SYS_FLAGS',
                'TABLE_CACHED_BLOCKS',
                'TRACE',
                'WAIT_TIME_TO_UPDATE_STATS');
BEGIN
    IF typ IS NOT NULL and typ NOT like 'TABLE%' THEN
        RAISE_APPLICATION_ERROR(-20001,'Only table is supported!');
    END IF;

    $IF DBMS_DB_VERSION.VERSION<11 $THEN
        for i in 1..prefs.count loop
            begin
                dbms_output.put_line(rpad('Param - '||prefs(i),40)||': '||dbms_stats.get_param(prefs(i)));
            exception when others then null;
            end;
        end loop;    
    $ELSE
        for i in 1..prefs.count loop
            begin
                dbms_output.put_line(rpad(initcap(nvl(typ,'system')||' ')||'Prefs - '||prefs(i),40)||': '||dbms_stats.get_prefs(prefs(i),owner,object_name));
            exception when others then null;
            end;
        end loop;
    $END
    
    prefs := t('iotfrspeed',
               'ioseektim',
                'seadtim',
                'mreadtim',
                'cpuspeed ',
                'cpuspeednw',
                'mbrc',
                'maxthr',
                'slavethr');
    for i in 1..prefs.count loop
        begin
            DBMS_STATS.GET_SYSTEM_STATS(status,st,et,prefs(i),val);
            dbms_output.put_line(rpad('System Stats - '||prefs(i),40)||': '||round(val,3));
        exception when others then null;
        end;
    end loop;
    dbms_output.put_line(rpad('Statistics History Retention',40) ||': '||dbms_stats.GET_STATS_HISTORY_RETENTION||' days(Avail: '||to_char(dbms_stats.GET_STATS_HISTORY_AVAILABILITY,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')||')');
END;
/
set BYPASSEMPTYRS on
pro 
pro   
prompt Table Level
prompt ***********
select 
    TABLE_NAME,
    NUM_ROWS,
    BLOCKS,
    EMPTY_BLOCKS,
    AVG_SPACE,
    CHAIN_CNT,
    AVG_ROW_LEN,
    GLOBAL_STATS,
    USER_STATS,
    SAMPLE_SIZE,
    t.last_analyzed
from &check_access_dba.tables t
where owner = :object_owner
and table_name = :object_name;

SELECT COLUMN_NAME,
       decode(t.DATA_TYPE,
              'NUMBER',t.DATA_TYPE || '(' || decode(t.DATA_PRECISION, NULL, t.DATA_LENGTH || ')', t.DATA_PRECISION || ',' || t.DATA_SCALE || ')'),
              'DATE',t.DATA_TYPE,
              'LONG',t.DATA_TYPE,
              'LONG RAW',t.DATA_TYPE,
              'ROWID',t.DATA_TYPE,
              'MLSLABEL',t.DATA_TYPE,
              t.DATA_TYPE || '(' || t.DATA_LENGTH || ')') || ' ' ||
       decode(t.nullable, 'N', 'NOT NULL', 'n', 'NOT NULL', NULL) col,
       HISTOGRAM,
       NUM_BUCKETS BUCKETS,
       NUM_DISTINCT,
       NUM_NULLS,
       ROUND(((select num_rows from &check_access_dba.tables where owner = :object_owner and table_name = :object_name)-NUM_NULLS)/GREATEST(NUM_DISTINCT, 1), 2) cardinality,
       GLOBAL_STATS,
       USER_STATS,
       SAMPLE_SIZE,
       data_default "DEFAULT",
       t.last_analyzed
FROM   &check_access_dba.tab_cols t
WHERE  table_name = :object_name
AND    owner = :object_owner;

prompt Index Level
prompt ***********
WITH I AS (SELECT /*+no_merge*/ I.*,nvl(c.LOCALITY,'GLOBAL') LOCALITY,
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


prompt Partition Level
prompt ***************

SELECT PARTITION_NAME,
       NUM_ROWS,
       BLOCKS,
       EMPTY_BLOCKS,
       AVG_SPACE,
       CHAIN_CNT,
       AVG_ROW_LEN,
       GLOBAL_STATS,
       USER_STATS,
       SAMPLE_SIZE,
       t.last_analyzed
FROM   &check_access_dba.tab_partitions t
WHERE  table_owner = :object_owner
AND    table_name = :object_name
AND    partition_name =nvl(:object_subname,partition_name)
ORDER  BY partition_position;

SELECT PARTITION_NAME,
       COLUMN_NAME,
       NUM_DISTINCT,
       ROUND(((select num_rows from &check_access_dba.tab_partitions p 
               where p.table_owner = :object_owner and p.table_name = :object_name and p.partition_name=t.partition_name)-NUM_NULLS)
       /GREATEST(NUM_DISTINCT, 1), 2) cardinality,
       HISTOGRAM,
       NUM_BUCKETS BUCKETS,
       NUM_NULLS,
       GLOBAL_STATS,
       USER_STATS,
       SAMPLE_SIZE,
       t.last_analyzed
FROM   &check_access_dba.PART_COL_STATISTICS t
WHERE  table_name = :object_name
AND    owner = :object_owner
AND    PARTITION_NAME =:object_subname
AND    partition_name =nvl(:object_subname,partition_name);

SELECT t.INDEX_NAME,
       t.PARTITION_NAME,
       t.BLEVEL BLev,
       t.LEAF_BLOCKS,
       t.DISTINCT_KEYS,
       t.NUM_ROWS,
       t.AVG_LEAF_BLOCKS_PER_KEY LB_PER_KEY,
       t.AVG_DATA_BLOCKS_PER_KEY DATA_PER_KEY,
       t.CLUSTERING_FACTOR,
       t.GLOBAL_STATS,
       t.USER_STATS,
       t.SAMPLE_SIZE,
       t.last_analyzed
FROM   &check_access_dba.ind_partitions t, &check_access_dba.indexes i
WHERE  i.table_name = :object_name
AND    i.table_owner = :object_owner
AND    i.owner = t.index_owner
AND    i.index_name = t.index_name
AND    t.partition_name =nvl(:object_subname,t.partition_name);



prompt SubPartition Level
prompt ***************

SELECT PARTITION_NAME,
       SUBPARTITION_NAME,
       NUM_ROWS,
       BLOCKS,
       EMPTY_BLOCKS,
       AVG_SPACE,
       CHAIN_CNT,
       AVG_ROW_LEN,
       GLOBAL_STATS,
       USER_STATS,
       SAMPLE_SIZE,
       t.last_analyzed
FROM   &check_access_dba.tab_subpartitions t
WHERE  table_owner = :object_owner
AND    table_name = :object_name
AND    subpartition_name =nvl(:object_subname,subpartition_name)
ORDER  BY SUBPARTITION_POSITION;

SELECT p.PARTITION_NAME,
       t.SUBPARTITION_NAME,
       t.COLUMN_NAME,
       t.NUM_DISTINCT,
       ROUND(p.num_rows/GREATEST(t.NUM_DISTINCT, 1), 2) cardinality,
       t.HISTOGRAM,
       t.NUM_BUCKETS BUCKETS,
       t.NUM_NULLS,
       t.GLOBAL_STATS,
       t.USER_STATS,
       t.SAMPLE_SIZE,
       t.last_analyzed
FROM   &check_access_dba.SUBPART_COL_STATISTICS t, &check_access_dba.tab_subpartitions p
WHERE  t.table_name = :object_name
AND    t.owner = :object_owner
AND    t.subpartition_name = p.subpartition_name
AND    t.owner = p.table_owner
AND    t.table_name = p.table_name
AND    t.subpartition_name =:object_subname;

SELECT t.INDEX_NAME,
       t.PARTITION_NAME,
       t.SUBPARTITION_NAME,
       t.BLEVEL BLev,
       t.LEAF_BLOCKS,
       t.DISTINCT_KEYS,
       t.NUM_ROWS,
       t.AVG_LEAF_BLOCKS_PER_KEY LB_PER_KEY,
       t.AVG_DATA_BLOCKS_PER_KEY DATA_PER_KEY,
       t.CLUSTERING_FACTOR,
       t.GLOBAL_STATS,
       t.USER_STATS,
       t.SAMPLE_SIZE,
       t.last_analyzed
FROM   &check_access_dba.ind_subpartitions t, &check_access_dba.indexes i
WHERE  i.table_name = :object_name
AND    i.table_owner = :object_owner
AND    i.owner = t.index_owner
AND    i.index_name = t.index_name
AND    t.subpartition_name =nvl(:object_subname,t.subpartition_name);

DECLARE
    oname  VARCHAR2(128) := :object_owner;
    tab    VARCHAR2(129) := :object_name;
    tname  VARCHAR2(128) := upper('stats_adv_' || oname || '_' || tab);
    tid    PLS_INTEGER;
    output CLOB;
BEGIN
    NULL;
    $IF &advise=1 $THEN
    BEGIN
        dbms_stats.drop_advisor_task(tname);
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
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
    dbms_output.put_line('Statistics Advisor is running, please use "ora addm '||tid||'" to show the result afterwards.');
    dbms_output.put_line('Or may run following command to see the recommended script:');
    dbms_output.put_line('    select dbms_stats.script_advisor_task('''||tname||''') from dual;');
    $END
END;
/