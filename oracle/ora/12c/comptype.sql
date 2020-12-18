/*[[
    Get table's current compression type. Usage: @@NAME [<owner>.]<table_name>[.<partition_name>] [<rows>|-f"<filter>"] [-dx]
    -dx : Use no parallel direct path read
    rows: Maximum number of rows to scan, default as 3 millions.

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
        @check_access_obj: dba_objects={dba_objects} default={all_objects}
        &filter: default={@ROWS@} f={where &0}
        &dx    : default={--} dx={}
        &v2    : default={3e6}
        &px    : default={parallel(a 8)} dx={no_parallel}

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
    v_dx   VARCHAR2(128);
    v_sm   INT;
    v_dobj INT;
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
    IF regexp_substr(:object_type,'\S+') NOT IN('TABLE','CAL_MONTH_SALES_MV') THEN
        raise_application_error(-20001,'Invalid object type: '||:object_type);
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
                v_p :=CASE WHEN v_c >= 'a' THEN  71
                           WHEN v_c >= 'A' THEN  65
                           WHEN v_c >= '0' THEN  -4
                           WHEN v_c  = '+' THEN  -19
                           ELSE -18
                      END;
                v_id := v_id+(ascii(v_c)-v_p)*power(64,6-i);
            END LOOP;
            RETURN v_id;
        END;
        OBJS AS(SELECT * FROM &check_access_obj WHERE owner = '&object_owner' AND object_name = '&object_name')
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
        v_stmt := REPLACE(v_stmt, '@PART@', regexp_substr(:object_type, '\S+$') || '(' || :object_subname || ')');
    ELSE
        v_stmt := REPLACE(v_stmt, '@PART@');
    END IF;

    IF :V2 IS NOT NULL THEN
        v_stmt := REPLACE(v_stmt, '@ROWS@','WHERE ROWNUM<='||:v2);
    ELSE
        v_stmt := REPLACE(v_stmt, '@ROWS@');
    END IF;

    v_cnt := sys.dbms_utility.get_parameter_value('_small_table_threshold',v_sm,v_dx);
    v_cnt := sys.dbms_utility.get_parameter_value('_serial_direct_read',v_cnt2,v_dx);
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