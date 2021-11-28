/*[[
    Get table's current compression type. Usage: @@NAME [<owner>.]<table_name>[.<partition_name>] [<rows>|-all] [-f"<filter>"] [-dx]
    -dx : Use no parallel direct path read
    rows: Maximum number of rows to scan, default as 2 millions, use '-all' to unlimite the scan rows.

    [|             grid:{topic='Compression Type'}              |
     | Type       | Insert Time(1 vs DoP 4) | Compression Ratio | CU Size | Max Data Size | Max Rows |
     |BASIC       | 4.85/2.64               | OZIP              |         |               |          |
     |OLTP        | 8.13/2.54               | OZIP              |         |               |          |
     |Query Low   | 2.88/1.83               | 2.52 (LZO)        |  32K    |   1MB         |     4K   |
     |Query High  | 8.13/4.91               | 3.87 (ZLIB)       | 32K-64K |   1MB         |     8K   |
     |Archive Low | 11.71/7.63              | 4.08 (ZLIB)       | 64-128K |   3MB         |    16K   |
     |Archive High| 17.63/12.73             | 4.86 (BZ2)        |  128K   |   10MB        |    64K   |]
    For DBIM, the CU size is 32MB and data rows can > 50,000

    Sample Output:
    ==============
    SQL> @@NAME ssb.lineorder 10000000
    OBJECT_ID DATA_OBJECT_ID PARTITION_NAME COMPESSION_TYPE BLOCKS    ROWS    Rows/Block
    --------- -------------- -------------- --------------- ------ ---------- ----------
    22577              22483                HCC_QUERY_HIGH   9,311 10,000,000       1074
    --TOTAL--                               HCC_QUERY_HIGH   9,311 10,000,000       1074

    --[[
        @ver   : 12.1={}
        @check_access_comp: sys.dbms_compression={}
        @check_access_obj: dba_objects/dba_tables={dba_} default={all_}
        @check_access_seg: dba_segments={1} default={0}
        &filter: default={@ROWS@} f={where (&0) @ROWS@}
        &dx    : default={--} dx={}
        &v2    : default={2e6} all={A}
        &px    : default={parallel(4)} dx={no_parallel}

    --]]
]]*/
set feed off verify off printsize 10000

findobj "&V1" "" 1
var cur REFCURSOR "&OBJECT_TYPE: &OBJECT_OWNER..&OBJECT_NAME"
DECLARE
    TYPE t_rid IS TABLE OF ROWID;
    TYPE t_rec IS TABLE OF VARCHAR2(500);
    v_rids t_rid;
    v_recs t_rec;
    v_stmt VARCHAR2(4000);
    v_cur  SYS_REFCURSOR;
    v_oid  INT;
    v_did  INT;
    v_own  VARCHAR2(128) := :object_owner;
    v_nam  VARCHAR2(128) := :object_name;
    v_typ  VARCHAR2(40)  := :object_type;
    v_snam VARCHAR2(40)  := :object_subname;
    v_tops VARCHAR2(40)  := :v2;
    v_sub  VARCHAR2(128);
    v_rows INT := 0;
    v_pid  INT := 0;
    v_ptyp INT := 0;
    v_cnt  INT := 0;
    v_cnt2 INT := 0;
    v_ctyp INT := 0;
    v_xml  CLOB := '<ROWSET>';
    v_dx   VARCHAR2(128);
    v_sm   INT;
    v_dobj INT;
    v_part VARCHAR2(512);
    v_len  INT;
    v_blocks INT;
    v_bsize  INT;
    v_sample VARCHAR2(512);
    PROCEDURE extr(c VARCHAR2) IS
    BEGIN
        v_oid := regexp_substr(c, '[^,]+', 1, 1);
        v_did := regexp_substr(c, '[^,]+', 1, 2);
        v_rows:= regexp_substr(c, '[^,]+', 1, 3);
        v_sub := regexp_substr(c, '[^,]+', 1, 4);
    END;

    PROCEDURE flush_xml IS
        v_row VARCHAR2(2000);
    BEGIN
        IF v_cnt < 1 THEN
            RETURN;
        END IF;
        v_row := utl_lms.format_message(chr(10) || '<ROW><COMTYP>%s</COMTYP><OID>%s</OID><DID>%s</DID><PART>%s</PART><CNT>%s</CNT><R>%s</R></ROW>',
                                        ''||v_ptyp,
                                        ''||v_oid,
                                        ''||v_did,
                                        ''||v_sub,
                                        ''||v_cnt,
                                        ''||v_cnt2);
        dbms_lob.writeappend(v_xml, length(v_row), v_row);
    END;
BEGIN
    IF regexp_substr(v_typ,'\S+') NOT IN('TABLE','MATERIALIZED') THEN
        raise_application_error(-20001,'Invalid object type: '||v_typ);
    END IF;

    v_stmt := q'[
        WITH FUNCTION GET_DOBJ(rid VARCHAR2) RETURN INT DETERMINISTIC IS
        PRAGMA UDF;
            v_id INT := 0;
            v_p  SIMPLE_INTEGER :=0;
            v_c  CHAR(1);
        BEGIN
            FOR i IN 1..6 LOOP
                v_c :=substr(rid,i,1);
                v_p :=CASE WHEN v_c  = '+' THEN  -19
                           WHEN v_c  = '/' THEN  -16
                           WHEN v_c >= 'a' THEN  71
                           WHEN v_c >= 'A' THEN  65
                           WHEN v_c >= '0' THEN  -4                           
                           ELSE -18
                      END;
                v_id := v_id+(ascii(v_c)-v_p)*power(64,6-i);
            END LOOP;
            RETURN v_id;
        END;
        OBJS AS(SELECT * FROM &check_access_obj.objects WHERE owner = '&object_owner' AND object_name = '&object_name')
        SELECT /*+leading(b a) use_hash(b a) no_merge(a) no_merge(b)*/ 
               a.rid,
               b.object_id||','||
               b.data_object_id||','||
               a.cnt||','||
               b.subobject_name obj
        FROM   (SELECT get_dobj(sub) dobj, rid,cnt
                FROM   (SELECT /*+use_hash_aggregation GBY_PUSHDOWN index_ffs(a) &px*/
                               SUBSTR(ROWID, 1, 6) sub,
                               MIN(ROWID) rid, 
                               count(1) cnt
                        FROM   &object_owner..&object_name @PART@ a &filter
                        GROUP  BY SUBSTR(ROWID, 1, 6), SUBSTR(ROWID, 1, 15))) a,
               OBJS b
        WHERE  b.owner = '&object_owner'
        AND    b.object_name = '&object_name'
        AND    b.data_object_id = a.dobj
        ORDER BY 1]';
    IF :object_subname IS NOT NULL THEN
        v_part:=regexp_substr(v_typ, '\S+$') || '(' || v_snam || ')';
    END IF;

    IF q'~&filter~'!='@ROWS@' THEN
        IF trim(v_tops) !='A' THEN
            v_stmt := REPLACE(v_stmt, '@ROWS@','AND ROWNUM<='||v_tops);
        END IF;
    ELSIF trim(v_tops) !='A' THEN
        SELECT MAX(avg_row_len)*1.2,NULLIF(max(blocks),0)
        INTO   v_len,v_blocks
        FROM   (SELECT avg_row_len,num_rows,blocks
                FROM   &check_access_obj.tables
                WHERE  v_typ IN ('TABLE','MATERIALIZED')
                AND    owner = v_own
                AND    table_name = v_nam
                UNION ALL
                SELECT avg_row_len,num_rows,blocks
                FROM   &check_access_obj.tab_partitions
                WHERE  v_typ = 'TABLE PARTITION'
                AND    table_owner = v_own
                AND    table_name = v_nam
                AND    partition_name = v_snam
                UNION ALL
                SELECT avg_row_len,num_rows,blocks
                FROM   &check_access_obj.tab_subpartitions
                WHERE  v_typ = 'TABLE SUBPARTITION'
                AND    table_owner = v_own
                AND    table_name = v_nam
                AND    subpartition_name = v_snam);

        $IF &check_access_seg=1 $THEN
            SELECT SUM(blocks),sum(bytes)/sum(blocks)
            INTO   v_blocks,v_bsize
            FROM   dba_segments b
            WHERE  owner = v_own
            AND    segment_name = v_nam
            AND    nvl(partition_name, '_') = COALESCE(v_snam, partition_name, '_');
        $ELSE
            SELECT value INTO v_bsize FROM v$parameter WHERE name='db_block_size';
        $END

        v_sample := round(v_tops/(v_bsize/nvl(v_len,256))*100/v_blocks,4);
        IF v_sample+0 >=80 THEN 
            v_sample := NULL;
        ELSIF v_sample IS NULL THEN
            v_stmt := REPLACE(v_stmt, '@ROWS@','WHERE ROWNUM<='||v_tops);
        ELSE
            v_sample := 'SAMPLE BLOCK ('||greatest(1e-3,v_sample)||')';
        END IF;
    END IF;
    v_stmt := REPLACE(v_stmt, '@ROWS@');
    v_stmt := REPLACE(v_stmt, '@PART@',v_part||v_sample);

    v_cnt := sys.dbms_utility.get_parameter_value('_small_table_threshold',v_sm,v_dx);
    v_cnt := sys.dbms_utility.get_parameter_value('_serial_direct_read',v_cnt2,v_dx);
    --dbms_output.put_line(v_stmt);
    --return;
    &dx EXECUTE IMMEDIATE 'alter session set "_small_table_threshold"=1  "_serial_direct_read"=always';
    BEGIN
        v_cnt  := 0;
        v_cnt2 := 0;
        OPEN v_cur FOR v_stmt;
        LOOP
            FETCH v_cur BULK COLLECT
                INTO v_rids, v_recs LIMIT 8192;
            EXIT WHEN v_rids.COUNT = 0;
            FOR I IN 1 .. v_rids.COUNT LOOP
                extr(v_recs(i));
                v_stmt:=utl_lms.format_message(q'[sys.dbms_compression.get_compression_type('%s', '%s', '%s', '%s')]',v_own, v_nam, v_rids(i), v_sub);
                v_ctyp := sys.dbms_compression.get_compression_type(v_own, v_nam, v_rids(i), v_sub);
                IF v_pid != v_oid OR v_ptyp != v_ctyp THEN
                    flush_xml;
                    v_pid  := v_oid;
                    v_ptyp := v_ctyp;
                    v_cnt  := 0;
                    v_cnt2 := 0;
                END IF;
                v_cnt  := v_cnt + 1;
                v_cnt2 := v_cnt2 + v_rows;
            END LOOP;
        END LOOP;
        flush_xml;
        CLOSE v_cur;
        &dx EXECUTE IMMEDIATE 'alter session set "_small_table_threshold"='||v_sm||'  "_serial_direct_read"='||v_dx;
    EXCEPTION WHEN OTHERS THEN
        &dx EXECUTE IMMEDIATE 'alter session set "_small_table_threshold"='||v_sm||'  "_serial_direct_read"='||v_dx;
        dbms_output.put_line(v_stmt);
        RAISE;
    END;

    dbms_lob.writeappend(v_xml, 9, '</ROWSET>');

    OPEN :cur FOR
        SELECT NVL(''||OBJECT_ID,'--TOTAL--') OBJECT_ID,
               DATA_OBJECT_ID,
               PARTITION_NAME,
               decode(COMTYP,
                       1,'NOCOMPRESS',
                       2,'ADVANCED',
                       4,'HCC_QUERY_HIGH',
                       8,'HCC_QUERY_LOW',
                       16,'HCC_ARCHIVE_HIGH',
                       32,'HCC_ARCHIVE_LOW',
                       64,'OLTP',
                       128,'LOB_HIGH',
                       256,'LOB_MEDIUM',
                       512,'LOB_LOW',
                       1024,'INDEX_ADVANCED_HIGH',
                       2048,'INDEX_ADVANCED_LOW',
                       4096,'BASIC',
                       8192,'INMEMORY_NOCOMPRESS',
                       16384,'INMEMORY_DML',
                       32768,'INMEMORY_QUERY_LOW',
                       65536,'INMEMORY_QUERY_HIGH',
                       131072,'INMEMORY_CAPACITY_LOW',
                       262144,'INMEMORY_CAPACITY_HIGH') COMPESSION_TYPE,
              SUM(BLOCKS) BLOCKS,
              SUM(NUM_ROWS) "ROWS",
              ROUND(SUM(NUM_ROWS)/SUM(BLOCKS),2) "Rows/Block"
        FROM  XMLTABLE('/ROWSET/ROW' passing(xmltype(v_xml)) COLUMNS
                            COMTYP INT PATH 'COMTYP',
                            OBJECT_ID INT PATH 'OID',
                            DATA_OBJECT_ID INT PATH 'DID',
                            PARTITION_NAME VARCHAR2(128) PATH 'PART',
                            BLOCKS INT PATH 'CNT',
                            NUM_ROWS INT PATH 'R') a
        GROUP BY COMTYP,ROLLUP((OBJECT_ID,DATA_OBJECT_ID,PARTITION_NAME))
        ORDER BY a.object_id nulls last,2,3,4,5;
END;
/
col blocks,rows for K0
col object_id,data_object_id,partition_name break
print cur