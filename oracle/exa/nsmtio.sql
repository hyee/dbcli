/*[[Check the reason of Smart Scan not working. Usage: @@NAME {[<owner>.][<object_name>[.<partition_name>]] | -mon [-f"filter"]}
    -mon: list non-offload objects from sql monitor reports
    --[[--
        &MON : default={0} mon={1}
        &fil : default={sql_text NOT LIKE '%dbms_stats%' AND sql_text not like '%SQL Analyze%'} f={}
        @check_access_dba: sys.dbms_system={1} default={0}
        @check_access_x  : sys.x$ksppi={1} default={0}
        @check_access_stat: v$sql_monitor_statname={(select group_id from v$sql_monitor_statname where name like '%Eligible bytes%')} default={3,4,5,18}
        @check_access_grid: {
            v$cell_config={
                SELECT name, COUNT(1) misses,max(grid) disks
                FROM   v$cell_config a,
                       XMLTABLE('/cli-output/griddisk' PASSING xmltype(a.confval) COLUMNS --
                                grid VARCHAR2(300) path 'name',
                                name VARCHAR2(300) path 'asmDiskGroupName',
                                cachedBy VARCHAR2(300) path 'cachedBy',
                                cachingPolicy VARCHAR2(300) path 'cachingPolicy',
                                status VARCHAR2(300) path 'status') b
                WHERE  conftype = 'GRIDDISKS'
                AND    (cachingPolicy = 'none' OR cachedBy IS NULL)
                AND    status='active'
                GROUP  BY name}
            default={select cast(null as varchar2(30)) name,cast(null as varchar2(30)) disks,cast(null as number) misses from dual where 1=2}
        }
    --]]--
]]*/

ora _find_object "&V1" 1
SET FEED OFF VERIFY ON
VAR C REFCURSOR
COL "MAX|Dur" for smhd2
COL "SUM|IOS" for TMB2
COL "SUM|BYTES" FOR KMG2
DECLARE
    c          SYS_REFCURSOR;
    block_size INT;
    caches     INT;
    chains     INT;
    partition  VARCHAR2(3);
    deps       VARCHAR2(10):='DISABLED';
    keep       VARCHAR2(20);
    iot        VARCHAR2(20);
    clu        VARCHAR2(3);
    tbs        VARCHAR2(128);
    tmp        VARCHAR2(4000);
    ran        INT := round(dbms_random.value * 1e8);
    xml        VARCHAR2(32767) := '<ROWSET>';
    fmt        VARCHAR2(128) := '<ROW><NAME>%s</NAME><VALUE>%s</VALUE><REF_VALUE>%s</REF_VALUE></ROW>';
    FUNCTION param(nam VARCHAR2) RETURN VARCHAR2 IS
        x VARCHAR2(300);
        y INT;
        t INT;
    BEGIN
        $IF &check_access_x=1 $THEN
            SELECT nvl(MAX(KSPPSTVL),'N/A')
            INTO   X
            FROM   x$ksppcv y JOIN x$ksppi x USING(indx)
            WHERE  KSPPINM=nam;
        $ELSE
            SELECT MAX(VALUE)
            INTO   X
            FROM   v$parameter
            WHERE  name=nam;
            IF X IS NULL THEN
                t := sys.dbms_utility.get_parameter_value(nam, y, x);
                x := nvl(x, '' || y);
            END IF;
        $END
        RETURN x;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NULL;
    END;
    PROCEDURE push(NAME VARCHAR2, VALUE VARCHAR2, REF VARCHAR2 := NULL) IS
        v VARCHAR2(128) := lower(value);
        r VARCHAR2(128) := lower(REF);
    BEGIN
        IF r in ('true','false') AND v in('0','1') THEN
            v:=CASE v WHEN '0' THEN 'false' else 'true' end;
        END IF;
        xml := xml || utl_lms.format_message(fmt, NAME, v, r);
    END;
BEGIN
    IF &mon=1 THEN
        OPEN :c FOR
            WITH r AS
             (SELECT ROWNUM r, a.*
              FROM   (SELECT MAX(sql_id) keep(dense_rank LAST ORDER BY dur, sql_exec_id) sq_id,
                             MAX(sql_exec_id) keep(dense_rank LAST ORDER BY dur) sq_exec_id,
                             MAX(sql_exec_start) keep(dense_rank LAST ORDER BY dur, sql_exec_id, sql_id) sq_exec_start,
                             PLAN_HASH,
                             PLAN_LINE,
                             MAX(owner) owner,
                             MAX(object_name) object_name,
                             MAX(dur) dur,
                             COUNT(1) execs,
                             SUM(REQS) reqs,
                             SUM(BYTES) BYTES
                      FROM   (
                                SELECT  sql_id,
                                        sql_exec_id,
                                        sql_exec_start,
                                        PLAN_LINE_ID PLAN_LINE,
                                        SQL_PLAN_HASH_VALUE PLAN_HASH,
                                        ROUND(MAX(LAST_REFRESH_TIME - FIRST_REFRESH_TIME) * 86400) DUR,
                                        SUM(nvl(PHYSICAL_READ_REQUESTS,0)+nvl(PHYSICAL_WRITE_REQUESTS,0)) REQS,
                                        SUM(nvl(PHYSICAL_READ_BYTES,0)+nvl(PHYSICAL_WRITE_BYTES,0)) BYTES,
                                        MAX(PLAN_OBJECT_OWNER) OWNER,
                                        MAX(PLAN_OBJECT_NAME) OBJECT_NAME
                                FROM   gv$sql_plan_monitor
                                WHERE  PLAN_OPERATION||' '|| PLAN_OPTIONS IN (
                                          'TABLE ACCESS STORAGE FULL',
                                          'INDEX STORAGE FAST FULL SCAN',
                                          'INDEX STORAGE FAST FULL SCAN FIRST ROWS',
                                          'TABLE ACCESS STORAGE FULL FIRST ROWS',
                                          'TABLE ACCESS STORAGE SAMPLE',
                                          'INDEX STORAGE SAMPLE FAST FULL SCAN')
                                AND    (nvl(OTHERSTAT_GROUP_ID,0) NOT IN (&check_access_stat) OR --
                                        PLAN_OBJECT_NAME IS NOT NULL AND --coord process
                                        OTHERSTAT_GROUP_ID IS NULL AND --
                                        FIRST_CHANGE_TIME IS NULL)
                                GROUP  BY sql_id, sql_exec_id, sql_exec_start, PLAN_LINE_ID, SQL_PLAN_HASH_VALUE
                                HAVING SUM(nullif(NVL(nvl(PHYSICAL_READ_REQUESTS,0)+nvl(PHYSICAL_WRITE_REQUESTS,0),0), NVL2(FIRST_CHANGE_TIME, 0, 1024))) >= 512) --
                      GROUP  BY PLAN_HASH, PLAN_LINE --
                      HAVING SUM(reqs) >= 1024
                      ORDER  BY reqs DESC, sq_exec_id DESC) a), --
            r1 AS(SELECT /*+materialize*/ r.*,
                         substr(regexp_replace(trim(substr(sql_text,1,512)),'\s+',' '),1,200) sql_text
                  FROM r JOIN gv$sql_monitor r1
                  ON (r.sq_id=r1.sql_id and r.sq_exec_id=r1.sql_exec_id and r.sq_exec_start=r1.sql_exec_start and r1.px_server# is null and r1.sql_text is not null)
                  WHERE (&fil)
                  ORDER BY r)
            SELECT  sq_id sql_id,
                    sq_exec_id sql_exec_id,
                    plan_hash,
                    plan_line line#,
                    to_char(sq_exec_start) "SQL_START|OBJ_OWNER",
                   --owner,
                    object_name "OBJECT|NAME",
                    dur "MAX|DUR",
                    execs "SUM|EXE",
                    reqs "SUM|IOS",
                    bytes "SUM|BYTES",
                    sql_text
            FROM r1 WHERE ROWNUM<=40
            UNION ALL
               SELECT '-' A,NULL B,NULL C,NULL D,NULL,NULL,NULL E,NULL F,NULL reqs,NULL H,null I FROM DUAL
            UNION ALL
            SELECT * FROM (
                SELECT NULL A,NULL B,NULL C,null D,'| '||owner,object_name,max(dur) E,sum(execs) F,sum(reqs) reqs,sum(bytes) H,null I
                FROM   r1
                GROUP  BY owner,object_name
                ORDER  BY reqs DESC
            ) WHERE ROWNUM<=10;
        RETURN;
    END IF; 
    IF :object_name IS NOT NULL THEN
        SELECT SUM(blocks)
        INTO   block_size
        FROM   dba_segments
        WHERE  owner = :object_owner
        AND    segment_name = :object_name
        AND    nvl(partition_name, '_') = coalesce(:object_subname, partition_name, '_');

        SELECT MAX(CNT)
        INTO   caches
        FROM (
            SELECT inst_id,COUNT(1) cnt
            FROM   dba_objects b,gv$bh a
            WHERE  a.objd=b.data_object_id
            AND    b.owner=:object_owner
            AND    b.object_name=:object_name
            AND    nvl(b.subobject_name,' ') = NVL(:object_subname,' ')
            GROUP  BY inst_id
        );

        IF :object_type like 'TABLE%' or :object_type like 'MAT%'THEN
            SELECT NVL(MAX(CHAIN_CNT),0),
                   NVL(MAX(DEPENDENCIES),'DISABLED'),
                   NVL(MAX(CASE WHEN cache='Y' or BUFFER_POOL='KEEP' THEN 'KEEP' END),'DEFAULT'),
                   MAX(PARTITIONED),
                   NVL(MAX(IOT_TYPE),'NULL'),
                   NVL(MAX(CLUSTERING),'NO')
            INTO   chains,deps,keep,partition,iot,clu
            FROM   DBA_TABLES
            WHERE  owner = :object_owner
            AND    table_name = :object_name;

            IF partition='YES' AND (chains=0 OR keep='DEFAULT') THEN
                SELECT NVL(MAX(CHAIN_CNT),0),NVL(MAX(KEPT),KEEP)
                INTO   chains,keep
                FROM   (
                    SELECT SUM(CHAIN_CNT) CHAIN_CNT,MAX(DECODE(BUFFER_POOL,'KEEP','KEEP')) KEPT
                    FROM   DBA_TAB_PARTITIONS
                    WHERE  table_owner = :object_owner
                    AND    table_name = :object_name
                    AND    partition_name = nvl(:object_subname,partition_name)
                    UNION  ALL
                    SELECT SUM(CHAIN_CNT),MAX(DECODE(BUFFER_POOL,'KEEP','KEEP')) KEPT
                    FROM   DBA_TAB_SUBPARTITIONS
                    WHERE  table_owner = :object_owner
                    AND    table_name = :object_name
                    AND    subpartition_name = nvl(:object_subname,subpartition_name)); 
            END IF;
            --smart Scan will not work with Inter-Block Chaining and Can cause Performance Degradation (Doc ID 2120974.1)
            push('Table Chain Blocks', chains, '0 (Doc ID 2120974.1)');
            push('Table Dependencies', deps, 'DISABLED');
            push('Table Buffer Pool', keep, 'DEFAULT');
            push('Table IOT', iot, 'NULL');
            push('Table Clustering', clu, 'NO');
        ELSIF :object_type LIKE 'INDEX%' THEN
            SELECT NVL(MAX(REPLACE(INDEX_TYPE,'NORMAL/REV','REVERSE')),'NORMAL'),
                   NVL(MAX(CASE WHEN BUFFER_POOL='KEEP' THEN 'KEEP' END),'DEFAULT')
            INTO   deps,keep
            FROM   DBA_INDEXES
            WHERE  owner = :object_owner
            AND    index_name = :object_name;
            push('Index Type', deps, '*NORMAL/BITMAP');
            push('Index Buffer Pool', keep, 'DEFAULT');
        END IF;
    END IF;
    FOR R IN(SELECT 'Tablespace '||TABLESPACE_NAME TBS,ALLOCATION_TYPE||','||DECODE(SEGMENT_SPACE_MANAGEMENT,'AUTO','ASSM','LMT') MGMT 
             FROM    dba_tablespaces 
             WHERE (ALLOCATION_TYPE='UNIFORM' or SEGMENT_SPACE_MANAGEMENT='MANUAL') AND CONTENTS='PERMANENT'
             AND   (:object_name IS NULL AND TABLESPACE_NAME!='SYSTEM' OR 
                    TABLESPACE_NAME IN(SELECT TABLESPACE_NAME 
                                       FROM   DBA_SEGMENTS
                                       WHERE  owner = :object_owner
                                       AND    segment_name = :object_name
                                       AND    nvl(partition_name, '_') = coalesce(:object_subname, partition_name, '_'))) 
    ) LOOP
        push(r.tbs,r.mgmt,'AUTOALLOCATE,ASSM: Uniform tbs can lead to inconsistent Level 1 BMB High/low HWM for direct load(bug 25773041)');
    END LOOP;

    FOR R IN(SELECT Distinct b.dg,upper(b.value) val,b.misses,b.disks
             FROM    dba_data_files a, 
                     (select '+'||a.name dg,b.value,grid.misses,grid.disks
                      from v$asm_diskgroup a 
                      join v$asm_attribute b using(group_number)
                      left join (&check_access_grid) grid on(a.name=grid.name)
                      where b.name='cell.smart_scan_capable') b
             WHERE regexp_substr(a.file_name,'[^\\/]+')=b.dg
             AND   (upper(b.value)='FALSE' OR b.misses>0)
             AND   (:object_name IS NULL AND TABLESPACE_NAME!='SYSTEM' OR 
                    TABLESPACE_NAME IN(SELECT TABLESPACE_NAME 
                                       FROM   DBA_SEGMENTS
                                       WHERE  owner = :object_owner
                                       AND    segment_name = :object_name
                                       AND    nvl(partition_name, '_') = coalesce(:object_subname, partition_name, '_'))) 
    ) LOOP
        IF r.val='FALSE' THEN
            push('Diskgoup '||r.dg,r.val,'true &lt;= cell.smart_scan_capable');
        END IF;

        IF r.misses>0 THEN
            push('Diskgoup '||r.dg,r.misses,'0 &lt;= flashcache on griddisks(i.e.:'||r.disks||')');
        END IF;
    END LOOP;

    --EXADATA and SuperCluster : Check if long running transactions are preventing min active scn from progressing, resulting in Storage Indexes not being used (Doc ID 2081483.1)
    SELECT ROUND((SYSDATE-MIN(TO_DATE(START_TIME,'MM/DD/YY HH24:MI:SS')))*24,2)
    INTO   tmp
    FROM   GV$TRANSACTION;
    push('Longest Transaction', tmp, '&lt; 48 hours (Doc ID 2081483.1)');
    push('Param _small_table_threshold', param('_small_table_threshold'), CASE WHEN block_size IS NOT NULL THEN 'Current '||lower(:object_type)||': '||block_size||' blocks, '||nvl(caches,0)||' cached' END);
    push('Param _serial_direct_read', param('_serial_direct_read'), 'auto,always,true');
    push('Param _object_statistics', param('_object_statistics'), 'true');
    push('Param _smu_debug_mode', nvl(param('_smu_debug_mode'), '0'), '!= 134217728');
    
    push('Param _enable_minscn_cr', param('_enable_minscn_cr'), 'true');
    --Exadata: How to diagnose smart scan and wrong results (Doc ID 1260804.1)
    push('Param cell_offload_processing', param('cell_offload_processing'), 'true');
    push('Param cell_offload_decryption', param('cell_offload_decryption'), 'true');
    push('Param _cell_offload_hybridcolumnar', param('_cell_offload_hybridcolumnar'), 'true');
    push('Param _kcfis_cell_passthru_enabled', param('_kcfis_cell_passthru_enabled'), 'false');
    push('Param _kcfis_rdbms_blockio_enabled', param('_kcfis_rdbms_blockio_enabled'), 'false');
    push('Param _kcfis_storageidx_disabled', param('_kcfis_storageidx_disabled'), 'false');
    push('Param _kcfis_storageidx_set_membership_disabled', param('_kcfis_storageidx_set_membership_disabled'), 'false');
    push('Param _kcfis_cell_passthru_fromcpu_enabled', param('_kcfis_cell_passthru_fromcpu_enabled'), 'true');
    push('Param _kdz_pcode_flags', param('_kdz_pcode_flags'), '0');
    push('Param _enable_columnar_cache', param('_enable_columnar_cache'), '1');
    push('Param _key_vector_offload', param('_key_vector_offload'), 'predicate');
    push('Param _rowsets_enabled', param('_rowsets_enabled'), 'true');
    push('Param _rdbms_internal_fplib_enabled', param('_rdbms_internal_fplib_enabled'), 'false');
    push('Param _bloom_filter_enabled', param('_bloom_filter_enabled'), 'true');
    push('Param _bloom_predicate_offload', param('_bloom_predicate_offload'), 'true');
    push('Param _bloom_predicate_pushdown_to_storage', param('_bloom_predicate_pushdown_to_storage'), 'true');
    push('Recursive SQL', '', 'Smart scan turn off for recursive SQL such as DDL,trigger,dbms_sql,TABLE function(fixctl 25167306)');
    $IF &check_access_dba=1 $THEN
        sys.dbms_system.read_ev(10949, tmp);
    $ELSE
        tmp := nvl(regexp_substr(param('event'), '10949.*?level *([1-9]+)'), 0);
    $END
    push('Event #10949', tmp, 0);
    SELECT SERVER INTO tmp FROM V$SESSION WHERE SID = userenv('SID');
    push('Server Mode', tmp, 'NON-SHARED');
    --Exadata: Database Performance Degrades when Database is in Timezone Upgrade Mode (Doc ID 1583297.1)
    SELECT property_value INTO tmp FROM sys.database_properties WHERE property_name = 'DST_UPGRADE_STATE';
    push('DST_UPGRADE_STATE', tmp, 'NONE');
    xml := xml || '</ROWSET>';
    OPEN :c FOR
        SELECT *
        FROM   XMLTABLE('/ROWSET/ROW' PASSING XMLTYPE(XML) COLUMNS NAME VARCHAR2(50) PATH 'NAME',
                        VALUE VARCHAR2(15) PATH 'VALUE',
                        REFERENCE VARCHAR2(300) PATH 'REF_VALUE')
        ORDER  BY 1;
END;
/

PRO Diagnostic: alter session set events '10358 trace name context forever, level 2:10384 trace name context forever,level 16384:trace[nsmtio] disk low'
PRO or        : alter session set events '10358 trace name context forever, level 2:trace[nsmtio:px_control] disk high';