/*[[Check the reason of Smart Scan not working. Usage: @@NAME [<owner>.][<object_name>[.<partition_name>]]
    --[[--
        @check_access_dba: sys.dbms_system={1} default={0}
        @check_access_x  : sys.x$ksppi={1} default={0}
    --]]--
]]*/

ora _find_object "&V1" 1
SET FEED OFF VERIFY ON
VAR C REFCURSOR
DECLARE
    block_size INT;
    caches     INT;
    chains     INT;
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
    BEGIN
        xml := xml || utl_lms.format_message(fmt, NAME, lower(VALUE), lower(REF));
    END;
BEGIN
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

        IF :object_type like 'TABLE%' THEN
            SELECT NVL(MAX(CHAIN_CNT),0)
            INTO   chains
            FROM   DBA_TABLES
            WHERE  owner = :object_owner
            AND    table_name = :object_name
            AND    :object_subname IS NULL;

            IF chains=0 THEN
                SELECT NVL(MAX(CHAIN_CNT),0)
                INTO   chains
                FROM   (
                    SELECT SUM(CHAIN_CNT) CHAIN_CNT
                    FROM   DBA_TAB_PARTITIONS
                    WHERE  table_owner = :object_owner
                    AND    table_name = :object_name
                    AND    partition_name = nvl(:object_subname,partition_name)
                    UNION  ALL
                    SELECT SUM(CHAIN_CNT)
                    FROM   DBA_TAB_SUBPARTITIONS
                    WHERE  table_owner = :object_owner
                    AND    table_name = :object_name
                    AND    subpartition_name = nvl(:object_subname,subpartition_name)); 
            END IF;
            --smart Scan will not work with Inter-Block Chaining and Can cause Performance Degradation (Doc ID 2120974.1)
            push('Table Chain Blocks', chains, '0 (Doc ID 2120974.1)');
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

    push('_small_table_threshold', param('_small_table_threshold'), CASE WHEN block_size IS NOT NULL THEN 'Current '||lower(:object_type)||': '||block_size||' blocks, '||nvl(caches,0)||' cached' END);
    --EXADATA and SuperCluster : Check if long running transactions are preventing min active scn from progressing, resulting in Storage Indexes not being used (Doc ID 2081483.1)
    SELECT ROUND((SYSDATE-MIN(TO_DATE(START_TIME,'MM/DD/YY HH24:MI:SS')))*24,2)
    INTO   tmp
    FROM   GV$TRANSACTION;
    push('Longest Transaction', tmp, '&lt; 48 hours (Doc ID 2081483.1)');
    push('_serial_direct_read', param('_serial_direct_read'), 'auto,always,true');
    push('_smu_debug_mode', nvl(param('_smu_debug_mode'), '0'), '!= 134217728');
    push('_enable_minscn_cr', param('_enable_minscn_cr'), 'true');
    --Exadata: How to diagnose smart scan and wrong results (Doc ID 1260804.1)
    push('cell_offload_processing', param('cell_offload_processing'), 'true');
    push('_kcfis_cell_passthru_enabled', param('_kcfis_cell_passthru_enabled'), 'false');
    push('_kcfis_rdbms_blockio_enabled', param('_kcfis_rdbms_blockio_enabled'), 'false');
    push('_kcfis_storageidx_disabled', param('_kcfis_storageidx_disabled'), 'false');
    push('_kcfis_storageidx_set_membership_disabled', param('_kcfis_storageidx_set_membership_disabled'), 'false');
    push('_kcfis_cell_passthru_fromcpu_enabled', param('_kcfis_cell_passthru_fromcpu_enabled'), 'true');
    push('_kdz_pcode_flags', param('_kdz_pcode_flags'), '0');
    push('_enable_columnar_cache', param('_kdz_pcode_flags'), '1');
    push('_key_vector_offload', param('_key_vector_offload'), 'predicate');
    push('_rowsets_enabled', param('_rowsets_enabled'), 'true');
    push('_bloom_filter_enabled', param('_bloom_filter_enabled'), 'true');
    push('_bloom_predicate_offload', param('_bloom_predicate_offload'), 'true');
    push('_bloom_predicate_pushdown_to_storage', param('_bloom_predicate_pushdown_to_storage'), 'true');
    push('Recursive SQL', '', 'Smart scan turn off for recursive SQL such as DDL,trigger,dbms_sql,TABLE function');
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
        FROM   XMLTABLE('/ROWSET/ROW' PASSING XMLTYPE(XML) COLUMNS NAME VARCHAR2(128) PATH 'NAME',
                        VALUE VARCHAR2(128) PATH 'VALUE',
                        REFERENCE VARCHAR2(300) PATH 'REF_VALUE')
        ORDER  BY 1;
END;
/

PRO Diagnostic: alter session set events '10358 trace name context forever, level 2:10384 trace name context forever,level 16384:trace[nsmtio] disk low'
PRO or        : alter session set events '10358 trace name context forever, level 2:trace[nsmtio|px_control] disk low'