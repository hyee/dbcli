/*[[
    Details the in-memory information of a specific table. Usage: @@NAME [owner.]<table_name>[.partition_name] [column_name|*] [-d] [-f"<filter>"] [-test]

    Parameters:
        column_name: Report the CUs of that single column.
        *          : Report the CUs of every in-memory column.
        -d         : Report every instance separately, instead of collapsing the rows of one storage unit into a single row. Applies to the table-level report only.
        -f         : Apply an expression to the reported rows, such as -f"num_rows>0". The expression is evaluated against the columns of the in-memory views (NUM_ROWS, USED_LEN, INVALID_BLOCKS, ...), not against the rows of the table.
        -test      : Also read the real rows of every reported CU rowid range, and append their ACT_CNT, ACT_DIST, ACT_MIN and ACT_MAX after the CU statistics so the two can be compared. Applies to the column-level report only, and it scans the table.

    Without a column the first result set summarizes the IMCU and the SMU headers of every storage unit. With a column it reports the CUs of that column, one row per storage unit and column, where OVERLAPS counts how many other CUs of the same column cover the same row range. The three remaining result sets list the IM expressions of the object, its join groups, and the statistics captured for its IM expressions.

    The object must be populated into the in-memory pool: the script aborts with 'The table has not been populated, or is not an in-memory table!' when gv$im_column_level holds no compressed column for it, which is also the case when inmemory_size is 0, when the object is not marked INMEMORY, or while the population has not started yet.

    Some parameters to control the in-memory behaviors:
        * inmemory_size
        * inmemory_query
        * inmemory_force
        * IMSS: _inmemory_dynamic_scans(AUTO/DISABLE/FORCE)
        * IMA : _always_vector_transformation(default false)
        * IMA : _key_vector_predicate_enabled
        * IMA : _optimizer_vector_transformation
        * IME : inmemory_expressions_usage
        * IME : inmemory_virtual_columns
        * POP : inmemory_trickle_repopulate_servers_percent
        * POP : inmemory_max_populate_servers
        * GD  : _globaldict_enable(0:disable, 1:JoinGroups Only, 2:ALL)
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
             0x8000 : Enable pcode compilation for HCC / CC1 tables
            0x10000 : No selective dict eval
            0x20000 : No deferred constants

    IME Operations:
        EXEC DBMS_INMEMORY_ADMIN.IME_OPEN_CAPTURE_WINDOW;
        EXEC DBMS_INMEMORY_ADMIN.IME_CAPTURE_EXPRESSIONS('WINDOW/CUMULATIVE/CURRENT');
        EXEC DBMS_INMEMORY_ADMIN.IME_CLOSE_CAPTURE_WINDOW;
        EXEC DBMS_INMEMORY_ADMIN.IME_POPULATE_EXPRESSIONS;

    --[[
        @check_access_obj: dba_objects={dba_} default={all_}
        @check_access_exp: DBA_IM_EXPRESSIONS={DBA_IM_EXPRESSIONS} default={USER_IM_EXPRESSIONS}
        @check_access_jp:  CDB_JOINGROUPS={CDB_JOINGROUPS} DBA_JOINGROUPS={DBA_JOINGROUPS} default={USER_JOINGROUPS}
        @ver: 18={,SUM(NUMDELTA) DELTA} 12.1={}
        @ARGS: 1
        &inst    : default={inst} d={inst_id}
        &filter  : default={1=1} f={}
        &is_test : default={}, test={--}
        &in_test : default={0} test={1}
    --]]
]]*/
ora _find_object "&V1"

set feed off verify off
col allocate,cu_used,col_used format kmg
col data_rows,blocks,invalid,scans,distcnt,evaluation_count format %,.0f

var cols1  VARCHAR
var cols2  VARCHAR
var typs   VARCHAR
var target VARCHAR
var mins   VARCHAR
var cnv    VARCHAR
DECLARE
    cname VARCHAR2(128) := upper(:v2);
    cols  VARCHAR2(32767) := 'DECODE(col#';
    cnv   VARCHAR2(32767) := 'DECODE(cid';
    typs  VARCHAR2(32767) := 'DECODE(col#';
    mins  VARCHAR2(32767) := 'COUNT(1) ACT_CNT';
    cnt   PLS_INTEGER := 0;
BEGIN
    IF :object_type NOT LIKE 'TABLE%' THEN
        raise_application_error(-20001, 'Invalid object type:' || :object_type);
    END IF;
    FOR r IN (SELECT column_name n, internal_column_id cid, data_type
              FROM   &check_access_obj.tab_cols a
              WHERE  owner = :object_owner
              AND    table_name = :object_name
              AND    column_name IN (SELECT DISTINCT column_name
                                     FROM   gv$im_column_level b
                                     WHERE  a.owner = b.owner
                                     AND    a.table_name = b.table_name
                                     AND    inmemory_compression != 'NO INMEMORY')
              AND    hidden_column = 'NO'
              AND    (nullif(cname, '*') IS NULL OR upper(column_name) = cname)
              ORDER  BY 2) LOOP
        cols := cols || ',' || r.cid || ',"' || r.n || '"';
        typs := typs || ',' || r.cid || ',''' || r.data_type || '''';
        cnv  := cnv || ',' || r.cid || ',min' || r.cid;
        mins := mins || ',''''||' || 'min("' || r.n || '") min' || r.cid || ',' || '''''||max("' || r.n || '") max' || r.cid || ',' || 'APPROX_COUNT_DISTINCT("' || r.n || '") dist' || r.cid;
        cnt := cnt + 1;
    END LOOP;

    IF cnt = 0 THEN
        raise_application_error(-20001, 'The table has not been populated, or is not an in-memory table!');
    END IF;
    cnv      := cnv || ') act_min';
    :cnv     := replace(cnv, 'min', 'dist') || ',' || cnv || ',' || replace(cnv, 'min', 'max');
    cols     := cols || ',-1,null)';
    :cols1   := cols;
    :cols2   := replace(cols, '"', '''');
    :mins    := mins;
    :typs    := typs || ')';
    :target  := :object_owner || '.' || :object_name || nullif(' PARTITION(' || :object_subname || ')', ' PARTITION()');
END;
/

var c1 refcursor "IMCU & IMSMU Summary of &target";
var c2 refcursor "IM Expressions";
var c3 refcursor "IM Join Groups";
var c4 refcursor "IM Expression Stats"
DECLARE
    c1      SYS_REFCURSOR;
    c2      SYS_REFCURSOR;
    c3      SYS_REFCURSOR;
    c4      SYS_REFCURSOR;
    cname   VARCHAR2(128) := upper(:v2);
    own     VARCHAR2(128) := :object_owner;
    oname   VARCHAR2(128) := :object_name;
    sub     VARCHAR2(128) := :object_subname;
    dids    sys.odcisecobjtable;
    cols    sys.odcicolinfolist2;
    oid     INT := :object_id;
    cid     INT;
    res     XMLTYPE;
    hdl     NUMBER;
BEGIN
    $IF dbms_db_version.version>12 OR dbms_db_version.release>1 $THEN
    OPEN c2 FOR
        SELECT *
        FROM   &check_access_exp
        WHERE  object_number = oid
        AND    upper(column_name) = nvl(nullif(cname, '*'), upper(column_name));
    OPEN c3 FOR
        WITH gp AS
         (SELECT *
          FROM   &check_access_jp
          WHERE  table_owner = own
          AND    table_name = oname
          AND    upper(column_name) = nvl(nullif(cname, '*'), upper(column_name)))
        SELECT *
        FROM   &check_access_jp
        WHERE  gd_address IN (SELECT gd_address FROM gp)
        ORDER  BY gd_address, flags;
    OPEN c4 FOR
        SELECT *
        FROM   &check_access_obj.expression_statistics
        WHERE  owner = own
        AND    table_name = oname
        AND    (nullif(cname, '*') IS NULL OR upper(expression_text) LIKE '%"' || cname || '"%')
        ORDER  BY last_modified DESC;
    $END

    SELECT sys.odcisecobj(NULL, NULL, data_object_id, subobject_name)
    BULK   COLLECT INTO dids
    FROM   &check_access_obj.objects a
    WHERE  object_name = oname
    AND    owner = own
    AND    data_object_id IS NOT NULL
    AND    (sub IS NULL OR subobject_name = sub);

    IF cname IS NULL THEN
        OPEN c1 FOR
            WITH im AS (
                SELECT *
                FROM   (SELECT a.*,
                               listagg(inst_id, ',') WITHIN GROUP(ORDER BY inst_id) OVER(PARTITION BY objd, startdba) inst,
                               SUM(scancnt) OVER(PARTITION BY objd, startdba) scans,
                               SUM(invalid) OVER(PARTITION BY objd, startdba) invalids,
                               row_number() OVER(PARTITION BY objd, startdba
                                                 ORDER BY total_rows DESC, decode(inst_id, userenv('instance'), 0, inst_id)) r
                        FROM   gv$(CURSOR(
                                   SELECT /*+ordered use_hash(h0 m h1)*/
                                          userenv('instance') inst_id,
                                          h0.imcu_addr,
                                          h0.part,
                                          h0.num_cols,
                                          h0.allocated_len,
                                          h0.used_len,
                                          h0.num_rows,
                                          h0.num_blocks,
                                          h0.num_disk_extents num_extents,
                                          h1.*,
                                          edba - sdba blocks,
                                          /*--BAD performance
                                          (SELECT COUNT(1) FROM v$imeu_header h2
                                           WHERE  h2.objd=h0.objd
                                           AND    h2.IS_HEAD_PIECE>0
                                           AND    h2.IMEU_ADDR=h0.IMCU_ADDR) IMEUs,*/
                                          dbms_utility.data_block_address_file(sdba) file#,
                                          dbms_utility.data_block_address_block(sdba) block#,
                                          dbms_rowid.rowid_create(1, h0.objd,
                                                                  dbms_utility.data_block_address_file(sdba),
                                                                  dbms_utility.data_block_address_block(sdba),
                                                                  1) start_rowid,
                                          dbms_rowid.rowid_create(1, h0.objd,
                                                                  dbms_utility.data_block_address_file(edba),
                                                                  dbms_utility.data_block_address_block(edba + 1),
                                                                  1) end_rowid
                                   FROM   (SELECT /*+ordered use_hash(h)*/
                                                  o.objname part,
                                                  h.*, to_number(imcu_addr, lpad('X', 16, 'X')) addr
                                           FROM   table(dids) o, v$im_header h
                                           WHERE  h.objd = o.objschema + 0
                                           AND    is_head_piece > 0) h0,
                                          (SELECT /*+ordered use_hash(m)*/
                                                  dataobj, m.imcu_addr,
                                                  MIN(start_dba) sdba,
                                                  MAX(end_dba) edba
                                           FROM   table(dids) o, v$im_tbs_ext_map m
                                           WHERE  o.objschema + 0 = m.dataobj
                                           GROUP  BY dataobj, imcu_addr) m,
                                          (SELECT /*+ordered use_hash(h1)*/
                                                  DISTINCT *
                                           FROM   table(dids) o, v$im_smu_head h1
                                           WHERE  o.objschema + 0 = h1.objd) h1
                                   WHERE  userenv('instance') = nvl(:instance, userenv('instance'))
                                   AND    h0.objd = m.dataobj
                                   AND    h0.addr = m.imcu_addr
                                   AND    m.dataobj = h1.objd
                                   AND    m.sdba = h1.startdba)) a
                        WHERE  (&filter))
                WHERE r = 1 OR :inst = 'inst_id')
            SELECT /*+ordered use_hash(a)*/
                   &inst inst,
                   objd dataobj,
                   part,
                   '|' "|",
                   nvl('' || imcu_addr, '**** TOTAL ****') imcu_addr,
                   MAX(num_cols) cols,
                   SUM(allocated_len) allocate,
                   SUM(used_len) cu_used,
                   startdba,
                   file# file#,
                   block# block#,
                   MIN(start_rowid) start_rowid,
                   MAX(end_rowid) end_rowid,
                   SUM(num_extents) extents,
                   SUM(num_blocks) blocks,
                   SUM(invalid_blocks) invalid,
                   '|' "|",
                   SUM(num_rows) total_rows,
                   SUM(invalid_rows) invalid,
                   '|' "|",
                   SUM(scans) scans,
                   SUM(invalids) invalid,
                   SUM(repopsub) repopsub,
                   SUM(chunks) chunks,
                   SUM(final) final,
                   SUM(clonecnt) clones &ver
            FROM   im
            GROUP  BY ROLLUP((objd, startdba, part, imcu_addr, file#, block#)), &inst
            ORDER  BY dataobj NULLS FIRST, startdba, &inst;
    ELSE
        SELECT sys.odcicolinfo(NULL, internal_column_id, column_name, data_type, NULL, NULL, NULL, NULL, NULL, NULL)
        BULK   COLLECT INTO cols
        FROM   &check_access_obj.tab_cols a
        WHERE  owner = own
        AND    table_name = oname
        AND    column_name IN (SELECT DISTINCT column_name
                               FROM   gv$im_column_level b
                               WHERE  a.owner = b.owner
                               AND    a.table_name = b.table_name
                               AND    inmemory_compression != 'NO INMEMORY')
        AND    (cname = '*' OR upper(column_name) = cname)
        AND    rownum <= 1000;

        IF cols.count = 0 THEN
            raise_application_error(-20001, 'The table or column is not in-memory, or the data has not been populated!');
        END IF;

        OPEN c1 FOR
            WITH ima AS
               (SELECT /*+materialize*/ * FROM
                   (SELECT a.*, row_number() OVER(PARTITION BY objd, startdba, column_name
                                                  ORDER BY distcnt DESC, decode(inst_id, userenv('instance'), 0, inst_id)) r
                    FROM   gv$(CURSOR(
                              SELECT /*+ORDERED USE_HASH(cu M H1 cs)
                                        swap_join_inputs(cs)
                                        opt_param('_bloom_filter_enabled' 'false')*/
                                     userenv('instance') inst_id,
                                     h0.part,
                                     h0.imcu_addr,
                                     h0.head_piece_address,
                                     h0.num_cols,
                                     h0.allocated_len,
                                     h0.used_len,
                                     h0.num_rows,
                                     h0.num_blocks,
                                     h0.num_disk_extents num_extents,
                                     h1.*,
                                     edba - sdba blocks,
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
                                     dbms_rowid.rowid_create(1, h0.objd,
                                                             dbms_utility.data_block_address_file(sdba),
                                                             dbms_utility.data_block_address_block(sdba),
                                                             1) start_rowid,
                                     dbms_rowid.rowid_create(1, h0.objd,
                                                             dbms_utility.data_block_address_file(edba),
                                                             dbms_utility.data_block_address_block(edba + 1),
                                                             1) end_rowid,
                                     cu.column_number col#,
                                     cu.dictionary_entries distcnt,
                                     cu.segment_dictionary_address,
                                     cu.length clength,
                                     cs.colname column_name,
                                     cs.coltypename dtype,
                                     decode(cs.coltypename
                                          ,'NUMBER'       ,to_char(utl_raw.cast_to_number(minimum_value))
                                          ,'FLOAT'        ,to_char(utl_raw.cast_to_number(minimum_value))
                                          ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(minimum_value))
                                          ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(minimum_value))
                                          ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(minimum_value))
                                          ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(minimum_value))
                                          ,'TIMESTAMP'    , lpad(to_number(substr(minimum_value, 1, 2), 'XX') - 100, 2, 0) ||
                                                            lpad(to_number(substr(minimum_value, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                                            lpad(to_number(substr(minimum_value, 5, 2), 'XX'), 2, 0) || '-' ||
                                                            lpad(to_number(substr(minimum_value, 7, 2), 'XX'), 2, 0) || ' ' ||
                                                            lpad(to_number(substr(minimum_value, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(minimum_value, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(minimum_value, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                                            nvl(substr(to_number(substr(minimum_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
                                          ,'TIMESTAMP WITH TIME ZONE',
                                                            lpad(to_number(substr(minimum_value, 1, 2), 'XX') - 100, 2, 0) ||
                                                            lpad(to_number(substr(minimum_value, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                                            lpad(to_number(substr(minimum_value, 5, 2), 'XX'), 2, 0) || '-' ||
                                                            lpad(to_number(substr(minimum_value, 7, 2), 'XX'), 2, 0) || ' ' ||
                                                            lpad(to_number(substr(minimum_value, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(minimum_value, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(minimum_value, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                                            nvl(substr(to_number(substr(minimum_value, 15, 8), 'XXXXXXXX'), 1, 6), '0') || ' ' ||
                                                            nvl(to_number(substr(minimum_value, 23, 2), 'XX') - 20, 0) || ':' ||
                                                            nvl(to_number(substr(minimum_value, 25, 2), 'XX') - 60, 0)
                                          ,'DATE',lpad(to_number(substr(minimum_value, 1, 2), 'XX') - 100, 2, 0) ||
                                                  lpad(to_number(substr(minimum_value, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                                  lpad(to_number(substr(minimum_value, 5, 2), 'XX'), 2, 0) || '-' ||
                                                  lpad(to_number(substr(minimum_value, 7, 2), 'XX'), 2, 0) || ' ' ||
                                                  lpad(to_number(substr(minimum_value, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                                  lpad(to_number(substr(minimum_value, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                                  lpad(to_number(substr(minimum_value, 13, 2), 'XX') - 1, 2, 0)
                                          ,  '' || minimum_value) min_v,
                                     decode(cs.coltypename
                                          ,'NUMBER'       ,to_char(utl_raw.cast_to_number(maximum_value))
                                          ,'FLOAT'        ,to_char(utl_raw.cast_to_number(maximum_value))
                                          ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(maximum_value))
                                          ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(maximum_value))
                                          ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(maximum_value))
                                          ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(maximum_value))
                                          ,'TIMESTAMP'    , lpad(to_number(substr(maximum_value, 1, 2), 'XX') - 100, 2, 0) ||
                                                            lpad(to_number(substr(maximum_value, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                                            lpad(to_number(substr(maximum_value, 5, 2), 'XX'), 2, 0) || '-' ||
                                                            lpad(to_number(substr(maximum_value, 7, 2), 'XX'), 2, 0) || ' ' ||
                                                            lpad(to_number(substr(maximum_value, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(maximum_value, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(maximum_value, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                                            nvl(substr(to_number(substr(maximum_value, 15, 8), 'XXXXXXXX'), 1, 6), '0')
                                          ,'TIMESTAMP WITH TIME ZONE',
                                                            lpad(to_number(substr(maximum_value, 1, 2), 'XX') - 100, 2, 0) ||
                                                            lpad(to_number(substr(maximum_value, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                                            lpad(to_number(substr(maximum_value, 5, 2), 'XX'), 2, 0) || '-' ||
                                                            lpad(to_number(substr(maximum_value, 7, 2), 'XX'), 2, 0) || ' ' ||
                                                            lpad(to_number(substr(maximum_value, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(maximum_value, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                                            lpad(to_number(substr(maximum_value, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                                            nvl(substr(to_number(substr(maximum_value, 15, 8), 'XXXXXXXX'), 1, 6), '0') || ' ' ||
                                                            nvl(to_number(substr(maximum_value, 23, 2), 'XX') - 20, 0) || ':' ||
                                                            nvl(to_number(substr(maximum_value, 25, 2), 'XX') - 60, 0)
                                          ,'DATE',lpad(to_number(substr(maximum_value, 1, 2), 'XX') - 100, 2, 0) ||
                                                  lpad(to_number(substr(maximum_value, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                                  lpad(to_number(substr(maximum_value, 5, 2), 'XX'), 2, 0) || '-' ||
                                                  lpad(to_number(substr(maximum_value, 7, 2), 'XX'), 2, 0) || ' ' ||
                                                  lpad(to_number(substr(maximum_value, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                                  lpad(to_number(substr(maximum_value, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                                  lpad(to_number(substr(maximum_value, 13, 2), 'XX') - 1, 2, 0)
                                          ,  '' || maximum_value) max_v
                              FROM   (SELECT /*+ordered use_hash(h)*/
                                             o.objname part,
                                             h.*, to_number(imcu_addr, lpad('X', 16, 'X')) addr
                                      FROM   table(dids) o, v$im_header h
                                      WHERE  h.objd = o.objschema + 0
                                      AND    is_head_piece > 0) h0,
                                     (SELECT /*+ordered use_hash(m)*/
                                             dataobj, m.imcu_addr,
                                             MIN(start_dba) sdba,
                                             MAX(end_dba) edba
                                      FROM   table(dids) o, v$im_tbs_ext_map m
                                      WHERE  o.objschema + 0 = m.dataobj
                                      GROUP  BY dataobj, imcu_addr) m,
                                     (SELECT /*+ordered use_hash(h1)*/
                                             DISTINCT *
                                      FROM   table(dids) o, v$im_smu_head h1
                                      WHERE  o.objschema + 0 = h1.objd) h1,
                                      v$im_col_cu cu,
                                      table(cols) cs
                             WHERE  userenv('instance') = nvl(:instance, userenv('instance'))
                             AND    h0.objd = m.dataobj
                             AND    h0.addr = m.imcu_addr
                             AND    m.dataobj = h1.objd
                             AND    m.sdba = h1.startdba
                             AND    h0.objd = cu.objd
                             AND    h0.head_piece_address = cu.head_piece_address
                             AND    cu.column_number = cs.tablename + 0)) a
                    WHERE (&filter))
                WHERE r = 1),
            ov AS
               (SELECT /*+parallel(4) ordered use_hash(b)*/
                       objd, column_name, a.startdba,
                       SUM(CASE WHEN
                                 a.dtype IN ('NUMBER', 'FLOAT', 'BINARY_DOUBLE', 'BINARY_FLOAT', 'BINARY_INTEGER')
                                 AND (b.min_v + 0 BETWEEN a.min_v + 0 AND a.max_v + 0 OR
                                      b.max_v + 0 BETWEEN a.min_v + 0 AND a.max_v + 0)
                                OR
                                 a.dtype NOT IN ('NUMBER', 'FLOAT', 'BINARY_DOUBLE', 'BINARY_FLOAT', 'BINARY_INTEGER')
                                 AND (b.min_v BETWEEN a.min_v AND a.max_v OR
                                      b.max_v BETWEEN a.min_v AND a.max_v)
                             THEN 1 ELSE 0 END) - 1 overlaps
                FROM   ima a
                JOIN   ima b
                USING  (inst_id, objd, column_name)
                GROUP  BY objd, column_name, a.startdba)
            SELECT /*+ordered use_hash(a)*/
                   objd dataobj,
                   part,
                   &is_test '|' "|",
                   MAX(imcu_addr) imcu_addr,
                   AVG(allocated_len) allocate,
                   AVG(used_len) cu_used,
                   AVG(clength) col_used,
                   startdba,
                   MIN(start_rowid) start_rowid,
                   MAX(end_rowid) end_rowid,
                   AVG(num_blocks) blocks,
                   AVG(invalid_blocks) invalid,
                   &is_test '|' "|",
                   col# cid,
                   MAX(column_name) column_name,
                   AVG(num_rows) total_rows,
                   AVG(distcnt) distcnt,
                   AVG(invalid_rows) stales,
                   &is_test '|' "|",
                   decode(MAX('' || segment_dictionary_address), '00', 'GD', 'GD+JG') dict,
                   MAX(overlaps) overlaps,
                   substr(MIN(min_v), 1, 32) min_v,
                   substr(MAX(max_v), 1, 32) max_v
            FROM   ima
            NATURAL JOIN ov
            GROUP  BY objd, startdba, part, col#
            ORDER  BY objd, startdba, col#;

            $IF &in_test=1 $THEN
                hdl := dbms_xmlgen.newcontext(c1);
                res := dbms_xmlgen.getxmltype(hdl);
                dbms_xmlgen.closecontext(hdl);
                OPEN c1 FOR
                    WITH test AS
                     (SELECT /*+monitor ordered parallel(8) use_nl(b) rowid(b)*/
                             a.*, &mins
                      FROM   (SELECT DISTINCT *
                              FROM   xmltable('/ROWSET/ROW' PASSING res COLUMNS dataobj NUMBER PATH 'DATAOBJ',
                                              start_rowid VARCHAR2(18) PATH 'START_ROWID',
                                              end_rowid VARCHAR2(18) PATH 'END_ROWID')
                              ORDER  BY 2) a,
                             &target b
                      WHERE  b.rowid BETWEEN a.start_rowid AND a.end_rowid
                      GROUP  BY dataobj, start_rowid, end_rowid)
                    SELECT a.*, '|' "|", act_cnt, &cnv
                    FROM   xmltable('/ROWSET/ROW' PASSING res COLUMNS dataobj NUMBER PATH 'DATAOBJ',
                                    part VARCHAR2(30) PATH 'PART',
                                    imcu_addr VARCHAR2(16) PATH 'IMCU_ADDR',
                                    allocate NUMBER PATH 'ALLOCATE',
                                    cu_used NUMBER PATH 'CU_USED',
                                    col_used NUMBER PATH 'COL_USED',
                                    startdba NUMBER PATH 'STARTDBA',
                                    start_rowid VARCHAR2(18) PATH 'START_ROWID',
                                    end_rowid VARCHAR2(18) PATH 'END_ROWID',
                                    blocks NUMBER PATH 'BLOCKS',
                                    invalid NUMBER PATH 'INVALID',
                                    cid NUMBER PATH 'CID',
                                    column_name VARCHAR2(30) PATH 'COLUMN_NAME',
                                    total_rows NUMBER PATH 'TOTAL_ROWS',
                                    distcnt NUMBER PATH 'DISTCNT',
                                    stales NUMBER PATH 'STALES',
                                    dict VARCHAR2(10) PATH 'DICT',
                                    overlaps NUMBER PATH 'OVERLAPS',
                                    min_v VARCHAR2(129) PATH 'MIN_V',
                                    max_v VARCHAR2(129) PATH 'MAX_V') a,
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