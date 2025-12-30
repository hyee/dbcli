/*[[
    Get table's current compression type. Usage: @@NAME [<owner>.]<table_name>[.<partition_name>] [<rows>|-all] [-f"<filter>"] [-dx|-sample]
    -dx : Use no parallel direct path read
    rows: Maximum number of rows to scan, default as 2 millions, use '-all' to unlimite the scan rows.

    [|             grid:{topic='Compression Type'}              |
     | Type       | Insert Time(1 vs DoP 4) | Compression Ratio | CU Size | Max Data Size | Max Rows |
     |BASIC       | 4.85/2.64               | OZIP              |         |               |          |
     |OLTP        | 8.13/2.54               | OZIP              |         |               |          |
     |Query Low   | 2.88/1.83               | 2.52 (LZO)        |  32K    |   1MB         |     4K   |
     |Query High  | 8.13/4.91               | 3.87 (ZLIB)       | 32K-64K |   1MB         |     8K   |
     |Archive Low | 11.71/7.63              | 4.08 (ZLIB)       | 64K-128K|   3MB         |    16K   |
     |Archive High| 17.63/12.73             | 4.86 (BZ2)        |  128K   |   10MB        |    64K   |]
    For DBIM, the CU size is 32MB and data rows can > 50,000
    
    Use "alter session set events 'trace[ADVCMP_COMP] disk=lowest'" and move table to see the detailed compression rate

    Sample Output:
    ==============
    SQL> @@NAME ssb.lineorder 10000000
    OBJECT_ID DATA_OBJECT_ID PARTITION_NAME COMPESSION_TYPE HEADER_BLOCKS BLOCKS UNKOWNS    ROWS    Rows/Block
    --------- -------------- -------------- --------------- ------------- ------ ------- ---------- ----------
    30820              22483                HCC_QUERY_HIGH          9,185 36,754      52 10,000,000     273.63
    --TOTAL--                               HCC_QUERY_HIGH          9,185 36,754      52 10,000,000     273.63

    --[[
        @ver   : 12.1={}
        &null_extent: default={SELECT '' pname,0 f,0 grp,0 xid,0 bid,0 eid from dual WHERE 1=2}
        @check_access_comp: sys.dbms_compression={}
        @check_access_obj: dba_objects/dba_tables={dba_} default={all_}
        @check_access_seg: dba_segments={1} default={0}
        @check_access_extents: {
            dba_extents={SELECT /*+materialize table_stats(SYS.X$KTFBUE SAMPLE BLOCKS=512) table_stats(SYS.SEG$ SAMPLE BLOCKS=1024)*/ 
                  nvl(partition_name,' ') pname,
                  CASE WHEN RELATIVE_FNO=1024 THEN trunc(block_id/power(2,22)) ELSE RELATIVE_FNO END f,
                  extent_id xid,
                  trunc(mod(block_id,power(2,22))/GREATEST(1,TRUNC(8*2E6/@TOP@))/8192) grp,
                  mod(block_id,power(2,22)) bid, mod(block_id,power(2,22))+blocks-1 eid
            FROM DBA_EXTENTS 
            WHERE owner = '&object_owner' 
            AND   segment_name = '&object_name'  @PART2@}
            default={&null_extent}
        }
        &extent: default={&check_access_extents} f={&null_extent} sample={&null_extent}
        &filter: default={@ROWS@} f={where (&0) @ROWS@}
        &full  : default={full(a)} f={none}
        &dx    : default={--} dx={}
        &v2    : default={2e6} all={A}
        &px    : default={no_parallel} dx={no_parallel} dx={parallel(4)} f={parallel(4)}
        &sp    : default={0} sample={1}

    --]]
]]*/
set feed off verify off printsize 10000

findobj "&V1" "" 1
var cur REFCURSOR "&OBJECT_TYPE: &OBJECT_OWNER..&OBJECT_NAME"
DECLARE
    TYPE t_rid IS TABLE OF ROWID;
    TYPE t_rec IS TABLE OF VARCHAR2(500);
    TYPE ttypes IS TABLE OF VARCHAR2(1) INDEX BY PLS_INTEGER;
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
    v_pext PLS_INTEGER := -1;
    v_cnt  INT := 0;
    v_cnt2 INT := 0;
    v_cnt3 INT := 0;
    v_errs INT := 0;
    v_ctyp INT := 0;
    v_xml  CLOB := '<ROWSET>';
    v_dx   VARCHAR2(128);
    v_sm   INT;
    v_dobj INT;
    v_part VARCHAR2(512);
    v_len  INT;
    v_blks INT;
    v_bsize  INT;
    v_sample VARCHAR2(512);
    v_comps  ttypes;
    v_fmt    VARCHAR2(80):=q'[sys.dbms_compression.get_compression_type('%s', '%s', '%s', '%s')]';
    v_parttype VARCHAR2(30);
    v_subtype  VARCHAR2(30);

    PROCEDURE extr(c VARCHAR2) IS
    BEGIN
        v_oid := trim(substr(c, 1, 10));
        v_did := trim(substr(c,11, 10));
        v_rows:= trim(substr(c,21, 10));
        v_blks:= trim(substr(c,31, 10));
        v_sub := substr(c,41);
    END;

    PROCEDURE flush_xml IS
        v_row VARCHAR2(2000);
    BEGIN
        IF v_cnt < 1 THEN
            RETURN;
        END IF;
        v_row := utl_lms.format_message(chr(10) || '<ROW><COMTYP>%s</COMTYP><OID>%s</OID><DID>%s</DID><PART>%s</PART><BLK>%s</BLK><ERR>%s</ERR><CNT>%s</CNT><R>%s</R></ROW>',
                                        ''||v_ptyp,
                                        ''||v_oid,
                                        ''||v_did,
                                        ''||v_sub,
                                        ''||v_cnt3,
                                        ''||v_errs,
                                        ''||v_cnt,
                                        ''||v_cnt2);
        dbms_lob.writeappend(v_xml, length(v_row), v_row);
    END;

BEGIN
    IF regexp_substr(v_typ,'\S+') NOT IN('TABLE','MATERIALIZED') THEN
        raise_application_error(-20001,'Invalid object type: '||v_typ);
    END IF;

    SELECT  NVL(MAX(PARTITIONING_TYPE),'NONE'),NVL(MAX(SUBPARTITIONING_TYPE),'NONE')
    INTO    v_parttype,v_subtype
    FROM    &check_access_obj.part_tables
    WHERE   owner=v_own
    AND     table_name=v_nam;

    IF v_subtype='NONE' AND v_parttype!='NONE' THEN
        v_parttype:=' PARTITION';
    ELSIF v_subtype!='NONE' THEN
        v_parttype:=' SUBPARTITION';
    ELSE
        v_parttype:=NULL;
    END IF;

    v_stmt := q'[
        WITH FUNCTION id(rid VARCHAR2,len SIMPLE_INTEGER) RETURN INT DETERMINISTIC IS
            PRAGMA UDF;
            v_id INT := 0;
            v_p  SIMPLE_INTEGER :=0;
            v_c  CHAR(1);
        BEGIN
            FOR i IN 1..len LOOP
                v_c :=substr(rid,i,1);
                v_p :=CASE WHEN v_c  = '+' THEN  -19
                           WHEN v_c  = '/' THEN  -16
                           WHEN v_c >= 'a' THEN  71
                           WHEN v_c >= 'A' THEN  65
                           WHEN v_c >= '0' THEN  -4                           
                           ELSE -18
                      END;
                v_id := v_id+(ascii(v_c)-v_p)*power(64,len-i);
            END LOOP;
            RETURN v_id;
        END;
        OBJS AS(SELECT /*+materialize*/ object_id,data_object_id,nvl(subobject_name,' ') pname 
                FROM &check_access_obj.objects a 
                WHERE data_object_id is not null and owner = '&object_owner' AND object_name = '&object_name' @PART1@),
        EXTS AS(&extent)
        SELECT * FROM (
            SELECT /*+leading(b a) use_hash(b a) use_hash(e) no_merge(a) &px*/ 
                   a.rid,
                   rpad(b.object_id,10)||rpad(b.data_object_id,10)||rpad(a.cnt,10)
                   ||rpad(nvl(nvl2(e.f,lead(a.blk) over(partition by e.pname,e.f,e.xid order by a.blk)-a.blk,0),0),10)
                   ||nvl2(trim(b.pname),b.pname,'') obj
            FROM   OBJS b
            JOIN   (SELECT /*+use_hash_aggregation no_merge GBY_PUSHDOWN rowid(a) &full*/
                           MIN(ROWID) rid, count(1) cnt,
                           id(substr(MIN(ROWID),1,6),6) dobj,
                           id(substr(MIN(ROWID),7,3),3) f, 
                           id(substr(MIN(ROWID),10,6),6) blk
                    FROM   &object_owner..&object_name @PART@ a &filter
                    GROUP  BY SUBSTR(ROWID, 1, 15)) a
            ON (b.data_object_id = a.dobj)
            LEFT JOIN EXTS e 
            ON(b.pname=e.pname and e.f=a.f and e.grp=trunc(a.blk/GREATEST(1,TRUNC(8*2E6/@TOP@))/8192) and a.blk between e.bid and e.eid)
            ORDER BY a.dobj,a.f,a.blk
        ) WHERE ROWNUM<=1E5]'; --slow performance of sys.dbms_compression.get_compression_type
    IF instr(v_typ,v_parttype)>1 THEN
        v_stmt := replace(replace(v_stmt,'@PART1@','and subobject_name='''||v_snam||''''),'@PART2@','and partition_name='''||v_snam||'''');
    ELSE
        v_stmt := replace(replace(v_stmt,'@PART1@'),'@PART2@');
    END IF;
    
    IF v_snam IS NOT NULL THEN
        v_part:=regexp_substr(v_typ, '\S+$') || '(' || v_snam || ')';
    END IF;

    IF q'~&filter~'!='@ROWS@' THEN
        IF trim(v_tops) !='A' THEN
            v_stmt := REPLACE(REPLACE(v_stmt, '@ROWS@','AND ROWNUM<='||v_tops),'@TOP@',v_tops);
        END IF;
    ELSIF trim(v_tops) !='A' THEN
        IF &sp=1 THEN
            SELECT MAX(avg_row_len)*1.2,NULLIF(max(blocks),0)
            INTO   v_len,v_blks
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
                INTO   v_blks,v_bsize
                FROM   dba_segments b
                WHERE  owner = v_own
                AND    segment_name = v_nam
                AND    nvl(partition_name, '_') = COALESCE(v_snam, partition_name, '_');
            $ELSE
                SELECT value INTO v_bsize FROM v$parameter WHERE name='db_block_size';
            $END
        END IF;
        
        v_sample := round(v_tops/(v_bsize/nvl(v_len,256))*100/v_blks,4);
        IF v_sample+0 >=80 THEN 
            v_sample := NULL;
        ELSIF v_sample IS NULL THEN
            v_stmt := REPLACE(v_stmt, '@ROWS@','WHERE ROWNUM<='||v_tops);
        ELSE
            v_sample := ' SAMPLE BLOCK ('||greatest(1e-3,v_sample)||',1) SEED(1)';
        END IF;
    END IF;
    v_stmt := REPLACE(v_stmt,'@TOP@','2E6');
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
        v_cnt3 := 0;
        v_errs := 0;
        OPEN v_cur FOR v_stmt;
        LOOP
            FETCH v_cur BULK COLLECT
                INTO v_rids, v_recs LIMIT 8192;
            EXIT WHEN v_rids.COUNT = 0;
            FOR I IN 1 .. v_rids.COUNT LOOP
                extr(v_recs(i));
                --v_stmt:= sys.utl_lms.format_message(v_fmt,v_own, v_nam, v_rids(i), v_sub);
                v_ctyp := sys.dbms_compression.get_compression_type(v_own, v_nam, v_rids(i), v_sub);

                IF v_pid != v_oid OR v_ptyp != v_ctyp THEN
                    flush_xml;
                    v_pid  := v_oid;
                    v_ptyp := v_ctyp;
                    v_cnt  := 0;
                    v_cnt2 := 0;
                    v_cnt3 := 0;
                    v_errs := 0;

                    IF v_ctyp>1 AND NOT v_comps.exists(v_ctyp) AND v_snam IS NULL THEN
                        v_comps(v_ctyp) := 'Y';
                        BEGIN
                            dbms_output.put_line('===============================================');
                            sys.dbms_compression.dump_compression_map(v_own,v_nam,v_ctyp);
                            dbms_output.put_line('===============================================');
                        EXCEPTION WHEN OTHERS THEN NULL;
                        END;
                    END IF;
                END IF;

                IF v_blks=0 AND v_ctyp NOT IN(4,8,16,32) THEN
                    v_blks := 1;
                ELSIF v_blks=0 THEN
                    v_errs := v_errs + 1;
                END IF;
                v_cnt  := v_cnt + 1;
                v_cnt2 := v_cnt2 + v_rows;
                v_cnt3 := v_cnt3 + v_blks;
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
                       262144,'INMEMORY_CAPACITY_HIGH',
                       524288,'INMEMORY_AUTO',
                       1048576,'MEMSPEED_QUERY_LOW',
                       2097152,'MEMSPEED_QUERY_HIGH',
                       4194304,'MEMSPEED_ARCHIVE',
                       to_char(COMTYP)) COMPESSION_TYPE,
              SUM(HEADER_BLOCKS) HEADER_BLOCKS,
              ROUND(NULLIF(SUM(BLOCKS),0)/NULLIF(SUM(HEADER_BLOCKS-ERRS),0)*SUM(HEADER_BLOCKS)) BLOCKS,
              NULLIF(SUM(ERRS),0) UNKOWNS,
              SUM(NUM_ROWS) "ROWS",
              ROUND(SUM(NUM_ROWS)/NULLIF(SUM(BLOCKS),0),2) "Rows/Block"
        FROM  XMLTABLE('/ROWSET/ROW' passing(xmltype(v_xml)) COLUMNS
                            COMTYP INT PATH 'COMTYP',
                            OBJECT_ID INT PATH 'OID',
                            DATA_OBJECT_ID INT PATH 'DID',
                            PARTITION_NAME VARCHAR2(128) PATH 'PART',
                            HEADER_BLOCKS INT PATH 'CNT',
                            BLOCKS INT PATH 'BLK',
                            ERRS INT PATH 'ERR',
                            NUM_ROWS INT PATH 'R') a
        GROUP BY COMTYP,ROLLUP((OBJECT_ID,DATA_OBJECT_ID,PARTITION_NAME))
        ORDER BY a.object_id nulls last,2,3,4,5;
END;
/
col header_blocks,blocks,rows for K0
col object_id,data_object_id,partition_name break -
print cur