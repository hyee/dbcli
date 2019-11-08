/*[[
    Get table's current compression type. Usage: @@NAME [<owner>.]<table_name>[.<partition_name>] [<rows>|-f"<filter>"]
    
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
        &filter: default={@ROWS@} f={where &0}
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
    v_sub  VARCHAR2(128);
    v_rows INT := 0;
    v_pid  INT := 0;
    v_ptyp INT := 0;
    v_cnt  INT := 0;
    v_cnt2 INT := 0;
    v_ctyp INT := 0;
    v_xml  CLOB := '<ROWSET>';
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
    v_stmt := q'[
        SELECT /*+leading(b a) use_hash(b a) no_merge(a) no_merge(b)*/ 
               a.rid,
               b.object_id||','||
               b.data_object_id||','||
               a.cnt||','||
               b.subobject_name obj
        FROM   (SELECT (SELECT dbms_rowid.ROWID_OBJECT(ridp) FROM dual) dobj, rid,cnt
                FROM   (SELECT /*+no_merge parallel(8) index_ffs(a)*/
                               MIN(ROWID) rid, 
                               MIN(MIN(ROWID)) OVER(PARTITION BY SUBSTR(ROWID, 1, 6)) ridp,
                               count(1) cnt
                        FROM   &object_owner..&object_name @PART@ a 
                        GROUP  BY SUBSTR(ROWID, 1, 6), SUBSTR(ROWID, 1, 15))) a,
               dba_objects b
        WHERE  b.owner = '&object_owner'
        AND    b.object_name = '&object_name'
        AND    b.data_object_id = a.dobj
        ORDER BY 1]';
    IF :object_subname IS NOT NULL THEN
        v_stmt := REPLACE(v_stmt, '@PART@', regexp_substr(:object_type, '\S+$') || '(' || :object_subname || ')');
    ELSE
        v_stmt := REPLACE(v_stmt, '@PART@');
    END IF;

    IF :V2 IS NOT NULL THEN
        v_stmt := REPLACE(v_stmt, '@ROWS@','WHERE ROWNUM<='||:v2);
    ELSE
        v_stmt := REPLACE(v_stmt, '@ROWS@');
    END IF;

    OPEN v_cur FOR v_stmt;
    LOOP
        FETCH v_cur BULK COLLECT
            INTO v_rids, v_recs LIMIT 4096;
        EXIT WHEN v_rids.COUNT = 0;
        FOR I IN 1 .. v_rids.COUNT LOOP
            extr(v_recs(i));
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
                       64,'BLOCK',
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