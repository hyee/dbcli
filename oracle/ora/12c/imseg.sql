/*[[Show inmemory info of a specific table. Usage: @@NAME [owner.]<table_name>[.partition_name] [column_name|*] [-d] [-f"filter"]
   -d: details into instance level
   
   Some parameters to control the in-memory behaviors:
   * inmemory_size
   * inmemory_query
   * inmemory_force
   * IMSS: _inmemory_dynamic_scans(AUTO/DISABLE/FORCE)
   * IMA: _always_vector_transformation(default false)
   * IMA: _key_vector_predicate_enabled
   * IMA: _optimizer_vector_transformation
   * IME: inmemory_expressions_usage
   * IME: inmemory_virtual_columns
   * POP: inmemory_trickle_repopulate_servers_percent
   * POP: inmemory_max_populate_servers
   * GD : _globaldict_enable(0:disable,1: JoinGroups Only, 2:ALL)
   * NUMBER for QUERY LOW: inmemory_optimized_arithmetic
   * PushDownAgg: _kdz_pcode_flags
          0x001 : No PCODE
          0x002 : No range pred eval
          0x004 : No reorder preds
          0x008 : No selective eval
          0x010 : No LIKE push-down
          0x020 : No agg/gby push-down
          0x040 : No constant fold opt
          0x080 : No popcnt use for eval
          0x100 : No complex eva push-down
          0x200 : No proj rowset push-down
          0x400 : No IME pcode support
          0x800 : Dict engine for proj
         0x1000 : Atomized proj exprs
         0x2000 : No lob pred push-down
         0x4000 : Don't save in cursor
         0x8000 : Enable pcode compilation for HCC / CC1 tables.
        0x10000 : No selective dict eval
        0x20000 : No deferred constants 
   IME Operations:
       EXEC DBMS_INMEMORY_ADMIN.IME_OPEN_CAPTURE_WINDOW;
       EXEC DBMS_INMEMORY_ADMIN.IME_CLOSE_CAPTURE_WINDOW;
       EXEC DBMS_INMEMORY_ADMIN.IME_POPULATE_EXPRESSIONS;
       EXEC DBMS_INMEMORY_ADMIN.IME_CAPTURE_EXPRESSIONS('WINDOW/CUMULATIVE/CURRENT');
       EXEC DBMS_INMEMORY_ADMIN.IME_OPEN_CAPTURE_WINDOW;
   
   --[[
       @check_access_obj: dba_objects={dba_} default={all_}
       @check_access_exp: DBA_IM_EXPRESSIONS={DBA_IM_EXPRESSIONS} default={USER_IM_EXPRESSIONS}
       @check_access_jp:  CDB_JOINGROUPS={CDB_JOINGROUPS} DBA_JOINGROUPS={DBA_JOINGROUPS} default={USER_JOINGROUPS}
       @ver: 18={,SUM(NUMDELTA) DELTA} 12.1={}
       &inst  : default={inst} d={inst_id}
       &filter: default={1=1} f={}
       &is_test: default={}, test={--}
       &in_test: default={0} test={1}
   --]]
]]*/
ORA _find_object "&V1"

SET FEED OFF verify off
col allocate,cu_used,col_used format kmg
col data_rows,blocks,invalid,scans,distcnt,EVALUATION_COUNT format %,.0f

var cols1  VARCHAR
var cols2  VARCHAR
var typs   VARCHAR
var target VARCHAR
var mins   VARCHAR
var cnv    VARCHAR
DECLARE
    cname VARCHAR2(128) := UPPER(:V2);
    cols VARCHAR2(32767) := 'DECODE(col#';
    cnv  VARCHAR2(32767) := 'DECODE(cid';
    typs VARCHAR2(32767) := 'DECODE(col#';
    mins VARCHAR2(32767) := 'COUNT(1) ACT_CNT';
    cnt  PLS_INTEGER     := 0;
BEGIN
    IF :OBJECT_TYPE not like 'TABLE%' THEN
        raise_application_error(-20001,'Invalid object type:'||:OBJECT_TYPE);
    END IF;
    FOR R IN (SELECT COLUMN_NAME n, INTERNAL_COLUMN_ID CID,data_type
              FROM   &check_access_obj.tab_cols a
              WHERE  owner = :object_owner
              AND    table_name = :object_name
              AND    column_name in(select distinct column_name from gv$im_column_level b where a.owner=b.owner and a.table_name=b.table_name and INMEMORY_COMPRESSION!='NO INMEMORY')
              AND    HIDDEN_COLUMN = 'NO'
              AND    (nullif(cname,'*') IS NULL OR upper(column_name) = cname)
              ORDER  BY 2) LOOP
        cols := cols || ',' || r.cid || ',"' || r.n || '"';
        typs := typs || ',' || r.cid || ',''' || r.data_type || '''';
        cnv  := cnv || ',' || r.cid || ',min'|| r.cid;
        mins := mins || ',''''||' || 'min("' || r.n || '") min'||r.cid || ',' || '''''||max("' || r.n || '") max'||r.cid || ',' || 'APPROX_COUNT_DISTINCT("' || r.n || '") dist'||r.cid;
        cnt  := cnt + 1;
    END LOOP;
    
    IF cnt = 0 THEN
        raise_application_error(-20001,'The table has not been populated, or is not an in-memory table!');
    END IF;
    cnv    := cnv||') act_min';
    :cnv   := replace(cnv,'min','dist')||','||cnv||','||replace(cnv,'min','max');
    cols   := cols || ',-1,null)';
    :cols1 := cols;
    :cols2 := replace(cols,'"','''');
    :mins  := mins;
    :typs  := typs||')';
    :target:= :object_owner||'.'||:object_name||nullif(' PARTITION('||:object_subname||')',' PARTITION()');
END;
/

var c1 refcursor "IMCU & IMSMU Summary of &target";
var c2 refcursor "IM Expressions";
var c3 refcursor "IM Join Groups";
var c4 refcursor "IM Expression Stats"
DECLARE
    c1    SYS_REFCURSOR;
    c2    SYS_REFCURSOR;
    c3    SYS_REFCURSOR;
    c4    SYS_REFCURSOR;
    cname VARCHAR2(128) := UPPER(:V2);
    own   VARCHAR2(128) := :object_owner;
    oname VARCHAR2(128) := :object_name;
    sub   VARCHAR2(128) := :object_subname; 
    dids  SYS.ODCIOBJECTLIST;
    cols  SYS.ODCICOLINFOLIST;
    oid   INT := :object_id;
    cid   INT;
    res   XMLTYPE;
    hdl  NUMBER;
BEGIN
    $IF dbms_db_version.version>12 OR dbms_db_version.release>1 $THEN
    OPEN c2 FOR
        SELECT *
        FROM   &check_access_exp
        WHERE  object_number = oid
        AND    UPPER(column_name) = NVL(nullif(cname,'*'), UPPER(column_name));
    OPEN c3 FOR
        WITH gp AS
         (SELECT *
          FROM   &check_access_jp
          WHERE  table_owner = own
          AND    table_name = oname
          AND    UPPER(column_name) = NVL(nullif(cname,'*'), UPPER(column_name)))
        SELECT * FROM &check_access_jp WHERE GD_ADDRESS IN (SELECT GD_ADDRESS FROM gp) ORDER BY GD_ADDRESS, flags;
    OPEN c4 FOR 
        SELECT * FROM &check_access_obj.EXPRESSION_STATISTICS
        WHERE  owner = own
        AND    table_name = oname
        AND   (nullif(cname,'*') IS NULL OR upper(EXPRESSION_TEXT) LIKE '%"'||cname||'"%')
        ORDER  BY LAST_MODIFIED DESC;
    $END

    SELECT SYS.ODCIOBJECT(DATA_OBJECT_ID,SUBOBJECT_NAME)
    BULK   COLLECT INTO dids
    FROM   &check_access_obj.objects a
    WHERE  object_name = oname
    AND    owner = own
    AND    DATA_OBJECT_ID IS NOT NULL
    AND    (sub IS NULL OR subobject_name = sub);

    IF cname IS NULL THEN
        OPEN c1 FOR
            WITH im AS (
                SELECT * FROM 
                   (SELECT a.*, 
                           listagg(inst_id,',') within group(order by inst_id) over(partition by objd,startdba) inst,
                           SUM(SCANCNT)  over(partition by objd,startdba) SCANS,
                           SUM(INVALID)  over(partition by objd,startdba) INVALIDS,
                           row_number()  over(partition by objd,startdba order by total_rows desc,decode(inst_id,USERENV('instance'),0,inst_id)) r
                    FROM gv$(CURSOR(
                          SELECT /*+ordered use_hash(h0 m h1)*/
                                 USERENV('instance') inst_id,
                                 h0.IMCU_ADDR,
                                 h0.part,
                                 h0.NUM_COLS,
                                 h0.ALLOCATED_LEN,
                                 h0.used_len,
                                 h0.num_rows,
                                 h0.num_blocks,
                                 h0.NUM_DISK_EXTENTS num_extents,
                                 h1.*,
                                 edba-sdba blocks,
                                 /*--BAD performance
                                 (SELECT COUNT(1) FROM v$imeu_header h2 
                                  WHERE  h2.objd=h0.objd
                                  AND    h2.IS_HEAD_PIECE>0
                                  AND    h2.IMEU_ADDR=h0.IMCU_ADDR) IMEUs,*/
                                 dbms_utility.data_block_address_file(sdba) file#,
                                 dbms_utility.data_block_address_block(sdba) block#,
                                 dbms_rowid.rowid_create(1,h0.objd,
                                                         dbms_utility.data_block_address_file(sdba),
                                                         dbms_utility.data_block_address_block(sdba),
                                                         1) start_rowid,
                                 dbms_rowid.rowid_create(1,h0.objd,
                                                         dbms_utility.data_block_address_file(edba),
                                                         dbms_utility.data_block_address_block(edba+1),
                                                         1) end_rowid                        
                          FROM   (SELECT /*+ordered use_hash(h)*/
                                         o.OBJECTNAME part,
                                         h.*, to_number(IMCU_ADDR, lpad('X', 16, 'X')) addr
                                  FROM   table(dids) o,V$IM_HEADER h
                                  WHERE  h.objd=o.OBJECTSCHEMA+0
                                  AND    IS_HEAD_PIECE > 0) h0,
                                 (SELECT /*+ordered use_hash(m)*/
                                         DATAOBJ,m.IMCU_ADDR,
                                         MIN(start_dba) sdba,
                                         MAX(end_dba) edba
                                  FROM   table(dids) o,v$im_tbs_ext_map m
                                  WHERE  o.OBJECTSCHEMA+0 = m.dataobj
                                  GROUP  BY DATAOBJ,IMCU_ADDR) m,
                                 (SELECT /*+ordered use_hash(h1)*/ 
                                         DISTINCT *
                                  FROM   table(dids) o,V$IM_SMU_HEAD h1
                                  WHERE  o.OBJECTSCHEMA+0 = h1.objd) h1
                         WHERE h0.objd=m.dataobj
                         AND   h0.addr=m.IMCU_ADDR
                         AND   m.dataobj=h1.objd
                         AND   m.sdba=h1.startdba)) a
                    WHERE  inst_id=nvl(:instance,inst_id)
                    AND    (&filter) )
                WHERE r=1 or :inst='inst_id')
            SELECT /*+ordered use_hash(a)*/  
                   &inst inst,
                   objd dataobj,
                   part,
                   '|' "|",
                   NVL(''||IMCU_ADDR,'**** TOTAL ****') IMCU_ADDR,
                   MAX(NUM_COLS) cols,
                   SUM(ALLOCATED_LEN) allocate,
                   SUM(USED_LEN) cu_used,
                   startdba,
                   file# file#,
                   block# block#,
                   MIN(START_ROWID) START_ROWID,
                   MAX(END_ROWID) END_ROWID,
                   SUM(num_extents) EXTENTs,
                   SUM(num_blocks) blocks,
                   SUM(INVALID_BLOCKS) INVALID,
                   '|' "|",
                   SUM(num_rows) TOTAL_ROWS,
                   SUM(INVALID_ROWS) INVALID,
                   '|' "|",
                   SUM(SCANS) SCANS,
                   SUM(INVALIDS) INVALID,
                   SUM(REPOPSUB) REPOPSUB,
                   SUM(CHUNKS) CHUNKS,
                   SUM(FINAL) FINAL,
                   SUM(CLONECNT) CLONES &ver
            FROM   im
            GROUP  BY ROLLUP((objd, startdba, part,IMCU_ADDR,file#,block#)), &inst
            ORDER  BY dataobj nulls first, startdba,&inst;       
    ELSE
        SELECT SYS.ODCICOLINFO(null,INTERNAL_COLUMN_ID,column_name, DATA_TYPE,null,null,null,null,null,null)
        BULK   COLLECT INTO cols
        FROM   &check_access_obj.tab_cols a
        WHERE  owner = own
        AND    table_name = oname
        AND    column_name in(select distinct column_name from gv$im_column_level b where a.owner=b.owner and a.table_name=b.table_name and INMEMORY_COMPRESSION!='NO INMEMORY')
        AND    (cname ='*' OR upper(column_name) = cname);
        
        IF cols.count = 0 THEN
            raise_application_error(-20001,'The table or column is not in-memory, or the data has not been populated!');
        END IF;
    
        OPEN c1 FOR
            WITH ima AS
               (SELECT /*+materialize*/ * FROM
                   (SELECT a.*,row_number() over(partition by objd,startdba,column_name 
                             order by distcnt desc,decode(inst_id,USERENV('instance'),0,inst_id)) r
                    FROM   gv$(CURSOR(
                              SELECT /*+ORDERED USE_HASH(cu M H1 cs) 
                                        swap_join_inputs(cs)
                                        opt_param('_bloom_filter_enabled' 'false')*/
                                     USERENV('instance') inst_id,
                                     h0.part,
                                     h0.IMCU_ADDR,
                                     h0.HEAD_PIECE_ADDRESS,
                                     h0.NUM_COLS,
                                     h0.ALLOCATED_LEN,
                                     h0.used_len,
                                     h0.num_rows,
                                     h0.num_blocks,
                                     h0.NUM_DISK_EXTENTS num_extents,
                                     h1.*,
                                     edba-sdba blocks,
                                     /*--BAD performance
                                      (SELECT listagg(SQL_EXPRESSION,chr(10)) within group(order by SQL_EXPRESSION)
                                      FROM   v$imeu_header h2, v$im_imecol_cu eu
                                      WHERE  h2.objd=h0.objd
                                      AND    h2.IS_HEAD_PIECE>0
                                      AND    h2.IMEU_ADDR=h0.IMCU_ADDR
                                      AND    h2.HEAD_PIECE_ADDRESS=eu.IMEU_HEAD_PIECE_ADDR
                                      AND    eu.objd=h0.objd
                                      AND    INTERNAL_COLUMN_NUMBER=cid) EXPR,*/
                                     dbms_utility.data_block_address_file(sdba) file#,
                                     dbms_utility.data_block_address_block(sdba) block#,
                                     dbms_rowid.rowid_create(1,h0.objd,
                                                             dbms_utility.data_block_address_file(sdba),
                                                             dbms_utility.data_block_address_block(sdba),
                                                             1) start_rowid,
                                     dbms_rowid.rowid_create(1,h0.objd,
                                                             dbms_utility.data_block_address_file(edba),
                                                             dbms_utility.data_block_address_block(edba+1),
                                                             1) end_rowid,
                                     cu.COLUMN_NUMBER col#,
                                     cu.DICTIONARY_ENTRIES distcnt,
                                     cu.SEGMENT_DICTIONARY_ADDRESS,
                                     cu.LENGTH CLENGTH,
                                     cs.COLNAME column_name,
                                     cs.coltypename dtype,
                                     decode(cs.coltypename
                                          ,'NUMBER'       ,to_char(utl_raw.cast_to_number(MINIMUM_VALUE))
                                          ,'FLOAT'        ,to_char(utl_raw.cast_to_number(MINIMUM_VALUE))
                                          ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(MINIMUM_VALUE))
                                          ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(MINIMUM_VALUE))
                                          ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(MINIMUM_VALUE))
                                          ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(MINIMUM_VALUE))
                                          ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                            nvl(substr(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')
                                          ,'TIMESTAMP WITH TIME ZONE',
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX'),2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX'),2,0)|| ' ' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                            nvl(substr(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                                            nvl(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 23,2),'XX')-20,0)||':'||
                                                            nvl(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 25, 2), 'XX')-60,0)
                                          ,'DATE',lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                  lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                  lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                  lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                  lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                  lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                  lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX')-1,2,0)
                                          ,  ''||MINIMUM_VALUE) min_v,
                                     decode(cs.coltypename
                                          ,'NUMBER'       ,to_char(utl_raw.cast_to_number(MAXIMUM_VALUE))
                                          ,'FLOAT'        ,to_char(utl_raw.cast_to_number(MAXIMUM_VALUE))
                                          ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(MAXIMUM_VALUE))
                                          ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(MAXIMUM_VALUE))
                                          ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(MAXIMUM_VALUE))
                                          ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(MAXIMUM_VALUE))
                                          ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                            nvl(substr(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')
                                          ,'TIMESTAMP WITH TIME ZONE',
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX'),2,0)|| '-' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX'),2,0)|| ' ' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                            lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                            nvl(substr(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                                            nvl(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 23,2),'XX')-20,0)||':'||
                                                            nvl(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 25, 2), 'XX')-60,0)
                                          ,'DATE',lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                  lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                  lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                  lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                  lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                  lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                  lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX')-1,2,0)
                                          ,  ''||MAXIMUM_VALUE) max_v
                              FROM   (SELECT /*+ordered use_hash(h)*/
                                             o.OBJECTNAME part,
                                             h.*, to_number(IMCU_ADDR, lpad('X', 16, 'X')) addr
                                      FROM   table(dids) o,V$IM_HEADER h
                                      WHERE  h.objd=o.OBJECTSCHEMA+0
                                      AND    IS_HEAD_PIECE > 0) h0,
                                     (SELECT /*+ordered use_hash(m)*/
                                             DATAOBJ,m.IMCU_ADDR,
                                             MIN(start_dba) sdba,
                                             MAX(end_dba) edba
                                      FROM   table(dids) o,v$im_tbs_ext_map m
                                      WHERE  o.OBJECTSCHEMA+0 = m.dataobj
                                      GROUP  BY DATAOBJ,IMCU_ADDR) m,
                                     (SELECT /*+ordered use_hash(h1)*/ 
                                             DISTINCT *
                                      FROM   table(dids) o,V$IM_SMU_HEAD h1
                                      WHERE  o.OBJECTSCHEMA+0 = h1.objd) h1,
                                      v$im_col_cu cu,
                                      table(cols) cs
                             WHERE h0.objd=m.dataobj
                             AND   h0.addr=m.IMCU_ADDR
                             AND   m.dataobj=h1.objd
                             AND   m.sdba=h1.startdba
                             AND   h0.objd=cu.objd
                             AND   h0.HEAD_PIECE_ADDRESS = CU.HEAD_PIECE_ADDRESS
                             AND   cu.COLUMN_NUMBER=cs.TABLENAME+0)) a
                    WHERE inst_id=nvl(:instance,inst_id)
                    AND   (&filter))
                WHERE r=1),
            ov AS(
               SELECT /*+parallel(4) ordered use_hash(b)*/ 
                  objd,column_name,a.startdba,SUM(
                    CASE WHEN
                      a.dtype in('NUMBER','FLOAT','BINARY_DOUBLE','BINARY_FLOAT','BINARY_INTEGER')
                          AND (b.min_v+0 between a.min_v+0 and a.max_v+0 or 
                               b.max_v+0 between a.min_v+0 and a.max_v+0)
                        OR
                      a.dtype not in('NUMBER','FLOAT','BINARY_DOUBLE','BINARY_FLOAT','BINARY_INTEGER')
                          AND (b.min_v between a.min_v and a.max_v or 
                               b.max_v between a.min_v and a.max_v)
                    THEN 1 ELSE 0 END
                   )-1 overlaps
               FROM  ima a join ima b using (inst_id,objd,column_name)
               group by objd,column_name,a.startdba)
            SELECT /*+ordered use_hash(a)*/  
                   objd dataobj,
                   part,
                   &is_test '|' "|",
                   MAX(IMCU_ADDR) IMCU_ADDR,
                   AVG(ALLOCATED_LEN) allocate,
                   AVG(USED_LEN) cu_used,
                   AVG(CLENGTH) col_used,
                   startdba,
                   min(start_rowid) start_rowid,
                   max(end_rowid) end_rowid,
                   AVG(NUM_BLOCKS) blocks,
                   AVG(INVALID_BLOCKS) INVALID,
                   &is_test '|' "|",
                   col# cid,
                   max(column_name) column_name,
                   AVG(NUM_ROWS) TOTAL_ROWS,
                   AVG(distcnt) distcnt,
                   AVG(INVALID_ROWS) stales,
                   &is_test '|' "|",
                   decode(MAX('' || SEGMENT_DICTIONARY_ADDRESS), '00', 'GD', 'GD+JG') dict,
                   max(Overlaps) Overlaps,
                   substr(MIN(MIN_V),1,32) MIN_V,
                   substr(MAX(MAX_V),1,32) MAX_V
            FROM   ima natural join ov
            GROUP  BY objd, startdba, part,col#
            ORDER  BY objd, startdba,col#;

            $IF &in_test=1 $THEN
                hdl := dbms_xmlgen.newcontext(c1);
                res := dbms_xmlgen.getxmltype(hdl);
                dbms_xmlgen.closecontext(hdl);
                OPEN c1 FOR 
                    WITH test AS
                     (SELECT /*+monitor ordered parallel(8) use_nl(b) rowid(b)*/
                       a.*, &mins
                      FROM   (SELECT DISTINCT *
                              FROM   xmltable('/ROWSET/ROW' passing res columns DATAOBJ NUMBER path 'DATAOBJ',
                                              START_ROWID VARCHAR2(18) path 'START_ROWID',
                                              END_ROWID VARCHAR2(18) path 'END_ROWID')
                              ORDER  BY 2) a,
                             &target b
                      WHERE  b.rowid BETWEEN a.start_rowid AND a.end_rowid
                      GROUP  BY dataobj, start_rowid, end_rowid)
                    SELECT a.*, '|' "|",ACT_CNT, &cnv
                    FROM   xmltable('/ROWSET/ROW' passing res columns DATAOBJ NUMBER path 'DATAOBJ',
                                    PART VARCHAR2(30) path 'PART',
                                    IMCU_ADDR VARCHAR2(16) path 'IMCU_ADDR',
                                    ALLOCATE NUMBER path 'ALLOCATE',
                                    CU_USED NUMBER path 'CU_USED',
                                    COL_USED NUMBER path 'COL_USED',
                                    STARTDBA NUMBER path 'STARTDBA',
                                    START_ROWID VARCHAR2(18) path 'START_ROWID',
                                    END_ROWID VARCHAR2(18) path 'END_ROWID',
                                    BLOCKS NUMBER path 'BLOCKS',
                                    INVALID NUMBER path 'INVALID',
                                    CID NUMBER path 'CID',
                                    COLUMN_NAME VARCHAR2(30) path 'COLUMN_NAME',
                                    TOTAL_ROWS NUMBER path 'TOTAL_ROWS',
                                    DISTCNT NUMBER path 'DISTCNT',
                                    STALES NUMBER path 'STALES',
                                    DICT VARCHAR2(10) path 'DICT',
                                    OVERLAPS NUMBER path 'OVERLAPS',
                                    MIN_V VARCHAR2(129) path 'MIN_V',
                                    MAX_V VARCHAR2(129) path 'MAX_V') a,
                           test b
                    WHERE  a.dataobj = b.dataobj
                    AND    a.start_rowid = b.start_rowid
                    AND    a.end_rowid = b.end_rowid;
            $END
    END IF;
    :c1 := c1;
    :c2 := c2;
    :c3 := c3;
    :c4 := c4;
END;
/

set rownum on printsize 5000
print c1
set rownum off
print c2
print c3
print c4