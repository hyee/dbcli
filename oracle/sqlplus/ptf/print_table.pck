CREATE OR REPLACE NONEDITIONABLE PACKAGE print_table AS
    /*
    Examples:
    =========
       select * from print_table.pivot(all_users);
       with r as (select * from dba_objects where rownum<100) select * from print_table.pivot(r,10,to_json=>1);
       with r as (select * from all_indexes where rownum<2) select * from print_table.pivot(r,1,print_datatype=>1);
       
       select * from print_cursor.show(dual,'dba_tab_cols');
       select * from print_cursor.show(dual,'dba_tab_cols',30,5);
       select * from print_cursor.pivot(dual,'select * from dba_scheduler_jobs',print_datatype=>1);
       select * from print_cursor.print(dual,'dba_views');
       select * from print_cursor.print(dual,'all_indexes',10,1);
       select * from print_cursor.print(dual,'all_indexes',10,10);
       
       WITH r AS (SELECT * FROM dba_objects WHERE ROWNUM<2) SELECT * FROM print_cursor.show(r,dbms_Xmlgen.getxmltype('select * from dba_objects where rownum<99'));
       SELECT * FROM print_cursor.show(dual,dbms_Xmlgen.getxmltype('select * from dba_objects where rownum<99'),10,8,value_pattern=>'node()');
       SELECT * FROM print_cursor.pivot(dual,dbms_Xmlgen.getxmltype('select * from dba_objects where rownum<99'),10,8,value_pattern=>'node()');
       
       SELECT * FROM print_cursor.pivot(dual,dbms_Xmlgen.getxmltype('select * from dba_objects where rownum<97'),10);
       with r as (select * from dba_objects where rownum<2) SELECT * FROM print_cursor.pivot(r,dbms_Xmlgen.getxmltype('select * from dba_objects where rownum<97'),1);
       
    */
    DEFAULT_FETCH_ROWS CONSTANT PLS_INTEGER := 1000;
    DEFAULT_PIVOT_ROWS CONSTANT PLS_INTEGER := 3;
    DEFAULT_LINE_WIDTH CONSTANT PLS_INTEGER := 128;
    DEFAULT_PRINT_COLS CONSTANT PLS_INTEGER := 128;
    FUNCTION describe_cursor(cur IN OUT NOCOPY BINARY_INTEGER, print_mode NATURALN := 0, based_table VARCHAR2 := NULL) RETURN dbms_tf.columns_new_t;
    FUNCTION cursor_to_rowset(cur IN OUT NOCOPY BINARY_INTEGER, rows NATURALN, print_mode NATURALN := 0, based_table VARCHAR2 := NULL)
        RETURN dbms_tf.row_set_t;

    FUNCTION describe(tab            IN OUT NOCOPY dbms_tf.table_t,
                      rows           NATURALN := 3,
                      print_datatype SIGNTYPE := 0,
                      sort_columns   SIGNTYPE := 0,
                      null_value     VARCHAR2 := '<NULL>',
                      trim_value     SIGNTYPE := 1,
                      to_json        SIGNTYPE := 0,
                      max_col_width  NATURALN := 128,
                      col_prefix     VARCHAR2 := 'ROW#',
                      row_pattern    VARCHAR2 := '/ROWSET/ROW',
                      col_pattern    VARCHAR2 := '*',
                      name_pattern   VARCHAR2 := 'name()',
                      value_pattern  VARCHAR2 := '') RETURN dbms_tf.describe_t;

    PROCEDURE fetch_rows(rows           NATURALN := 3,
                         print_datatype SIGNTYPE := 0,
                         sort_columns   SIGNTYPE := 0,
                         null_value     VARCHAR2 := '<NULL>',
                         trim_value     SIGNTYPE := 1,
                         to_json        SIGNTYPE := 0,
                         max_col_width  NATURALN := 128);

    FUNCTION pivot(tab            TABLE,
                   rows           NATURALN := 3, -- rows to be printed
                   print_datatype SIGNTYPE := 0, -- whether to print the data_type
                   sort_columns   SIGNTYPE := 0, -- whether to sort the column names
                   null_value     VARCHAR2 := '<NULL>', --null displayed value
                   trim_value     SIGNTYPE := 1, -- whether to trim white spaces from the string and replace multiple white spaces as single empty space
                   to_json        SIGNTYPE := 0, -- whether to print the values as JSON format
                   max_col_width  NATURALN := 128) --maximum print chars of a column 
     RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_table;

    FUNCTION describe(stmt           VARCHAR2,
                      tab            IN OUT NOCOPY dbms_tf.table_t,
                      rows           POSITIVE := NULL,
                      print_datatype PLS_INTEGER := NULL,
                      sort_columns   NATURALN := 0,
                      null_value     VARCHAR2 := '<NULL>',
                      trim_value     SIGNTYPE := 1,
                      to_json        SIGNTYPE := 0,
                      max_col_width  NATURALN := 128,
                      cols           PLS_INTEGER := NULL) RETURN dbms_tf.describe_t;

    PROCEDURE fetch_rows(stmt           VARCHAR2,
                         rows           POSITIVE := NULL,
                         print_datatype PLS_INTEGER := NULL,
                         sort_columns   NATURALN := 0,
                         null_value     VARCHAR2 := '<NULL>',
                         trim_value     SIGNTYPE := 1,
                         to_json        SIGNTYPE := 0,
                         max_col_width  NATURALN := 128,
                         cols           PLS_INTEGER := NULL);
    /* print and pivot the result of refcursor or select-statement
    */
    FUNCTION pivot(stmt           VARCHAR2,
                   tab            TABLE, --input "DUAL"
                   rows           POSITIVE := 3, -- rows to be printed
                   print_datatype SIGNTYPE := 0, -- whether to print the data_type
                   sort_columns   SIGNTYPE := 0, -- whether to sort the column names
                   null_value     VARCHAR2 := '<NULL>', --null displayed value
                   trim_value     SIGNTYPE := 1, -- whether to trim white spaces from the string and replace multiple white spaces as single empty space
                   to_json        SIGNTYPE := 0, -- whether to print the values as JSON format
                   max_col_width  NATURALN := 128) --maximum print chars of a column 
     RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_table;

    /* show the result of refcursor or select-statement
    */
    FUNCTION show(stmt VARCHAR2,
                  tab  TABLE, --input "DUAL"
                  rows POSITIVEN := 1000,
                  cols PLS_INTEGER := NULL) -- rows to be printed
     RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_table;

    /*Print formatted the result of select-statement.
      This functions is mainly used in database command-line such as SQL*Plus
      in order to automatically format the output. It will convert all columns as VARCHAR2 datatypes,
      and automatically re-calc each column width.
      
      Parameters:
      ============
          @tab         dual
          @stmt        sql statement/table name
          @rows        top N rows to be printed
          @print_mode   0: disable auto re-calc/trunc the max column width
                        1: force the column width as the column-name width
                        2: calc the column width by excluding the column-name
                        3: auto calc the column width and maximum width as 128 bytes 
                       >3: auto calc the column width and maximum width as <print_mode> bytes
    */
    FUNCTION print(stmt       VARCHAR2,
                   tab        TABLE, --input "DUAL"
                   rows       POSITIVE := 50,
                   print_mode NATURALN := 3) RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_table;

    PROCEDURE fetch_rows(stmt IN OUT NOCOPY SYS_REFCURSOR, rows POSITIVEN := 1000, cols POSITIVEN := 128);
    FUNCTION show(stmt IN OUT NOCOPY SYS_REFCURSOR, tab TABLE, rows POSITIVEN := 1000, cols POSITIVEN := 128) RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_table;

    PROCEDURE fetch_rows(stmt          XMLTYPE,
                         rows          POSITIVEN := 1000,
                         cols          POSITIVEN := 128,
                         sort_columns  NATURALN := 0,
                         null_value    VARCHAR2 := '<NULL>',
                         trim_value    NATURALN := 1,
                         to_json       NATURALN := 0,
                         max_col_width NATURALN := 128,
                         noop6         NATURALN := 0,
                         row_pattern   VARCHAR2 := '/ROWSET/ROW',
                         col_pattern   VARCHAR2 := '*',
                         name_pattern  VARCHAR2 := 'name()',
                         value_pattern VARCHAR2 := '');

    PROCEDURE xml_to_cursor(cur           OUT SYS_REFCURSOR,
                            val           xmltype,
                            row_limit     POSITIVEN := DEFAULT_FETCH_ROWS,
                            row_pattern   VARCHAR2 := '/ROWSET/ROW',
                            col_pattern   VARCHAR2 := '*',
                            name_pattern  VARCHAR2 := 'name()',
                            value_pattern VARCHAR2 := '',
                            based_table   VARCHAR2 := '');
    FUNCTION xml_to_cursor(val           xmltype,
                           row_limit     POSITIVEN := DEFAULT_FETCH_ROWS,
                           row_pattern   VARCHAR2 := '/ROWSET/ROW',
                           col_pattern   VARCHAR2 := '*',
                           name_pattern  VARCHAR2 := 'name()',
                           value_pattern VARCHAR2 := '',
                           based_table   VARCHAR2 := '') RETURN BINARY_INTEGER;
END;
/
CREATE OR REPLACE NONEDITIONABLE PACKAGE BODY print_table AS
    FUNCTION reset_row_count(newrows PLS_INTEGER := NULL) RETURN BOOLEAN IS
        idx     PLS_INTEGER := 0;
        srcrows PLS_INTEGER;
        repfac  dbms_tf.tab_naturaln_t;
    BEGIN
        dbms_tf.xstore_get('idx', idx);
        IF idx > 0 THEN
            dbms_tf.xstore_set('idx', idx + 1024);
            dbms_tf.row_replication(0);
            RETURN FALSE;
        END IF;
    
        IF newrows IS NULL THEN
            RETURN TRUE;
        END IF;
    
        srcrows := dbms_tf.get_env().row_count;
        FOR i IN 1 .. srcrows LOOP
            repfac(i) := CASE
                             WHEN i <= newrows THEN
                              1
                             ELSE
                              0
                         END;
        END LOOP;
        IF newrows > srcrows THEN
            repfac(srcrows) := newrows - srcrows + 1;
        END IF;
        dbms_tf.xstore_set('idx', srcrows);
        dbms_tf.row_replication(repfac);
        RETURN TRUE;
    END;

    PROCEDURE reset_row_count(newrows PLS_INTEGER) IS
        b BOOLEAN;
    BEGIN
        b := reset_row_count(newrows);
    END;

    FUNCTION stmt_to_cursor(stmt VARCHAR2) RETURN BINARY_INTEGER IS
        cur BINARY_INTEGER;
        cnt PLS_INTEGER;
        cmd VARCHAR2(32767) := TRIM(regexp_replace(stmt, '[ ' || chr(10) || chr(13) || chr(9) || ';/]+$'));
    BEGIN
        IF cmd IS NULL THEN
            raise_application_error(-20001, 'Input cursor or statement cannot be null!');
        ELSIF regexp_like(stmt, '^\d+$') THEN
            cur := stmt;
            BEGIN
                IF NOT dbms_sql.is_open(cur) THEN
                    raise_application_error(-20001, 'bad cursor');
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error(-20001, 'Cursor #' || cur || ' doesn''t exist or is closed!');
                
            END;
        ELSE
            IF NOT regexp_like(cmd, '\s') THEN
                cmd := 'select * from ' || cmd;
            END IF;
            cur := dbms_sql.open_cursor;
            dbms_sql.parse(cur, cmd, dbms_sql.native);
            cnt := dbms_sql.execute(cur);
        END IF;
        RETURN cur;
    END;

    FUNCTION describe_cursor(cur IN OUT NOCOPY BINARY_INTEGER, print_mode NATURALN := 0, based_table VARCHAR2 := NULL) RETURN dbms_tf.columns_new_t AS
        descs     dbms_sql.desc_tab3;
        newmeta   dbms_tf.table_metadata_t;
        col_type  dbms_tf.tab_number_t;
        new_cols  dbms_tf.columns_new_t;
        cols      BINARY_INTEGER;
        type_name VARCHAR2(100);
        chr       CHAR(4000);
    BEGIN
        dbms_sql.describe_columns3(cur, cols, descs);
    
        IF based_table IS NOT NULL THEN
            newmeta := dbms_tf.get_env().put_columns;
            cols    := least(cols, newmeta.count);
            FOR i IN 1 .. cols LOOP
                new_cols(i) := newmeta(i);
            END LOOP;
        END IF;
    
        FOR i IN 1 .. cols LOOP
            IF based_table IS NOT NULL THEN
                descs(i).col_type := new_cols(i).type;
                descs(i).col_type_name := new_cols(i).name;
            END IF;
        
            col_type(i) := descs(i).col_type;
            type_name := descs(i).col_type_name;
            CASE descs(i).col_type
                WHEN dbms_tf.type_varchar2 THEN
                    dbms_sql.define_column(cur, i, to_char(NULL), nvl(descs(i).col_max_len, 4000));
                WHEN dbms_tf.type_number THEN
                    dbms_sql.define_column(cur, i, to_NUMBER(NULL));
                WHEN dbms_tf.type_date THEN
                    dbms_sql.define_column(cur, i, to_date(NULL));
                WHEN dbms_tf.type_binary_float THEN
                    dbms_sql.define_column(cur, i, to_binary_float(NULL));
                WHEN dbms_tf.type_binary_double THEN
                    dbms_sql.define_column(cur, i, to_binary_double(NULL));
                WHEN dbms_tf.type_raw THEN
                    dbms_sql.define_column_raw(cur, i, hextoraw('01'), nvl(descs(i).col_max_len, 4000));
                WHEN dbms_tf.type_char THEN
                    dbms_sql.define_column(cur, i, chr, nvl(descs(i).col_max_len, 4000));
                WHEN dbms_tf.type_clob THEN
                    dbms_sql.define_column(cur, i, to_clob(NULL));
                WHEN dbms_tf.type_blob THEN
                    dbms_sql.define_column(cur, i, to_blob(NULL));
                WHEN dbms_tf.type_timestamp THEN
                    dbms_sql.define_column(cur, i, to_timestamp(NULL));
                WHEN dbms_tf.type_timestamp_tz THEN
                    dbms_sql.define_column(cur, i, to_timestamp_tz(NULL));
                WHEN dbms_tf.type_interval_ym THEN
                    dbms_sql.define_column(cur, i, to_yminterval(NULL));
                WHEN dbms_tf.type_interval_ds THEN
                    dbms_sql.define_column(cur, i, to_dsinterval(NULL));
                WHEN dbms_tf.type_timestamp_ltz THEN
                    dbms_sql.define_column(cur, i, systimestamp);
                WHEN dbms_tf.type_edate THEN
                    dbms_sql.define_column(cur, i, to_date(NULL));
                WHEN dbms_tf.type_etimestamp THEN
                    dbms_sql.define_column(cur, i, to_timestamp(NULL));
                WHEN dbms_tf.type_etimestamp_tz THEN
                    dbms_sql.define_column(cur, i, to_timestamp_tz(NULL));
                WHEN dbms_tf.type_einterval_ym THEN
                    dbms_sql.define_column(cur, i, to_yminterval(NULL));
                WHEN dbms_tf.type_einterval_ds THEN
                    dbms_sql.define_column(cur, i, to_dsinterval(NULL));
                WHEN dbms_tf.type_etimestamp_ltz THEN
                    dbms_sql.define_column(cur, i, systimestamp);
                WHEN dbms_sql.rowid_type THEN
                    dbms_sql.define_column_rowid(cur, i, chartorowid(NULL));
                    col_type(i) := dbms_tf.type_rowid;
                WHEN dbms_tf.type_rowid THEN
                    dbms_sql.define_column_rowid(cur, i, chartorowid(NULL));
                WHEN dbms_sql.long_type THEN
                    dbms_sql.define_column_long(cur, i);
                    col_type(i) := dbms_tf.type_varchar2;
                    type_name := 'LONG';
                WHEN dbms_sql.Long_Raw_Type THEN
                    col_type(i) := dbms_tf.type_raw;
                    type_name := 'LONGRAW';
                    dbms_sql.define_column_raw(cur, i, utl_raw.cast_to_raw(NULL), 4000);
                ELSE
                    col_type(i) := dbms_tf.type_varchar2;
                    dbms_sql.define_column(cur, i, to_char(NULL), 4000);
            END CASE;
        
            IF based_table IS NULL THEN
                new_cols(i) := dbms_tf.column_metadata_t(TYPE          => col_type(i),
                                                         max_len       => descs(i).col_max_len,
                                                         NAME          => '"' || TRIM('"' FROM descs(i).col_name) || '"',
                                                         name_len      => descs(i).col_name_len,
                                                         PRECISION     => descs(i).col_precision,
                                                         scale         => descs(i).col_scale,
                                                         type_name     => type_name,
                                                         type_name_len => descs(i).col_type_name_len,
                                                         charsetid     => descs(i).col_charsetid,
                                                         charsetform   => descs(i).col_charsetform);
            END IF;
            IF print_mode > 0 THEN
                new_cols(i).type_name := nvl(type_name, dbms_tf.column_type_name(new_cols(i)));
                new_cols(i).type := dbms_tf.type_varchar2;
                new_cols(i).precision := NULL;
                new_cols(i).scale := NULL;
                IF nvl(new_cols(i).type_name, 'x') != 'LONG' THEN
                    dbms_sql.define_column(cur, i, to_char(NULL), 4000);
                END IF;
            END IF;
        
        END LOOP;
        RETURN new_cols;
    EXCEPTION
        WHEN OTHERS THEN
            IF dbms_sql.is_open(cur) THEN
                dbms_sql.close_cursor(cur);
            END IF;
            RAISE;
    END;

    FUNCTION cursor_to_rowset(cur IN OUT NOCOPY BINARY_INTEGER, rows NATURALN, print_mode NATURALN := 0, based_table VARCHAR2 := NULL)
        RETURN dbms_tf.row_set_t IS
        rowset      dbms_tf.row_set_t;
        colws       dbms_sql.Number_Table;
        descs       dbms_tf.columns_new_t := describe_cursor(cur, print_mode, based_table);
        cols        PLS_INTEGER := descs.count;
        max_width   NATURALN := 128;
        pat         VARCHAR2(30) := '[^' || CHR(10) || CHR(13) || ']+'; --\n\r
        val         VARCHAR2(4000);
        tmp         VARCHAR2(4000);
        piece       VARCHAR2(4000);
        seq         PLS_INTEGER;
        cnt         PLS_INTEGER := 1;
        len         PLS_INTEGER;
        cursor_mode VARCHAR2(30);
    BEGIN
        IF print_mode > 3 THEN
            max_width := print_mode;
        END IF;
    
        FOR i IN 1 .. cols LOOP
            IF print_mode > 0 THEN
                descs(i).name := '"' || substrb(TRIM('"' FROM descs(i).name), 1, max_width) || '"';
                IF print_mode = 2 THEN
                    colws(i) := 1;
                ELSE
                    colws(i) := nvl(lengthb(descs(i).name) - 2, 1);
                END IF;
                descs(i).max_len := colws(i);
            END IF;
            rowset(i).description := descs(i);
        END LOOP;
    
        IF based_table = 'DUMMY' THEN
            FOR i IN 1 .. cols LOOP
                rowset(i).tab_varchar2(cnt) := descs(i).name;
            END LOOP;
            cnt := cnt + 1;
        END IF;
    
        WHILE dbms_sql.fetch_rows(cur) > 0 LOOP
            FOR i IN 1 .. cols LOOP
                CASE descs(i).type
                    WHEN dbms_tf.type_varchar2 THEN
                        IF descs(i).type_name = 'LONG' THEN
                            dbms_sql.column_value_long(cur, i, 4000, 0, rowset(i).tab_varchar2(cnt), len);
                        ELSE
                            dbms_sql.column_value(cur, i, rowset(i).tab_varchar2(cnt));
                        END IF;
                    WHEN dbms_tf.type_number THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_number(cnt));
                    WHEN dbms_tf.type_date THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_date(cnt));
                    WHEN dbms_tf.type_binary_float THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_binary_float(cnt));
                    WHEN dbms_tf.type_binary_double THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_binary_double(cnt));
                    WHEN dbms_tf.type_raw THEN
                        dbms_sql.column_value_raw(cur, i, rowset(i).tab_raw(cnt));
                    WHEN dbms_tf.type_char THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_char(cnt));
                    WHEN dbms_tf.type_clob THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_clob(cnt));
                    WHEN dbms_tf.type_blob THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_blob(cnt));
                    WHEN dbms_tf.type_timestamp THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_timestamp(cnt));
                    WHEN dbms_tf.type_timestamp_tz THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_timestamp_tz(cnt));
                    WHEN dbms_tf.type_interval_ym THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_interval_ym(cnt));
                    WHEN dbms_tf.type_interval_ds THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_interval_ds(cnt));
                    WHEN dbms_tf.type_timestamp_ltz THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_timestamp_ltz(cnt));
                    WHEN dbms_tf.type_edate THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_date(cnt));
                    WHEN dbms_tf.type_etimestamp THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_timestamp(cnt));
                    WHEN dbms_tf.type_etimestamp_tz THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_timestamp_tz(cnt));
                    WHEN dbms_tf.type_einterval_ym THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_interval_ym(cnt));
                    WHEN dbms_tf.type_einterval_ds THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_interval_ds(cnt));
                    WHEN dbms_tf.type_etimestamp_ltz THEN
                        dbms_sql.column_value(cur, i, rowset(i).tab_timestamp_ltz(cnt));
                    WHEN dbms_tf.type_rowid THEN
                        dbms_sql.column_value_rowid(cur, i, rowset(i).tab_rowid(cnt));
                    ELSE
                        dbms_sql.column_value(cur, i, rowset(i).tab_varchar2(cnt));
                END CASE;
            
                IF print_mode > 0 THEN
                    val := '';
                    seq := 1;
                    tmp := rowset(i).tab_varchar2(cnt);
                    IF print_mode = 1 THEN
                        max_width := colws(i);
                    END IF;
                    WHILE TRUE LOOP
                        piece := regexp_substr(tmp, pat, 1, seq);
                        EXIT WHEN piece IS NULL;
                        piece := substrb(rtrim(piece), 1, max_width);
                        val   := val || piece || chr(10);
                        IF print_mode > 1 THEN
                            colws(i) := greatest(nvl(lengthb(piece), 1), colws(i));
                        END IF;
                        seq := seq + 1;
                    END LOOP;
                    rowset(i).description.max_len := colws(i);
                    rowset(i).tab_varchar2(cnt) := TRIM(chr(10) FROM val);
                END IF;
            END LOOP;
            cnt := cnt + 1;
            EXIT WHEN cnt > rows;
        END LOOP;
        dbms_sql.close_cursor(cur);
        IF print_mode = 2 THEN
            FOR i IN 1 .. cols LOOP
                rowset(i).description.name := '"' || substrb(TRIM('"' FROM rowset(i).description.name), 1, colws(i)) || '"';
            END LOOP;
        END IF;
    
        rowset(1).description.type_name_len := cnt - 1;
        RETURN rowset;
    EXCEPTION
        WHEN OTHERS THEN
            IF dbms_sql.is_open(cur) THEN
                dbms_sql.close_cursor(cur);
            END IF;
            RAISE;
    END;

    FUNCTION describe(tab            IN OUT NOCOPY dbms_tf.table_t,
                      rows           NATURALN := 3,
                      print_datatype SIGNTYPE := 0,
                      sort_columns   SIGNTYPE := 0,
                      null_value     VARCHAR2 := '<NULL>',
                      trim_value     SIGNTYPE := 1,
                      to_json        SIGNTYPE := 0,
                      max_col_width  NATURALN := 128,
                      col_prefix     VARCHAR2 := 'ROW#',
                      row_pattern    VARCHAR2 := '/ROWSET/ROW',
                      col_pattern    VARCHAR2 := '*',
                      name_pattern   VARCHAR2 := 'name()',
                      value_pattern  VARCHAR2 := '') RETURN dbms_tf.describe_t AS
        new_cols dbms_tf.columns_new_t;
        idx      PLS_INTEGER := 0;
        descs    dbms_tf.describe_t;
    BEGIN
        FOR i IN 1 .. tab.column.count LOOP
            tab.column(i).pass_through := FALSE;
            tab.column(i).for_read := TRUE;
        END LOOP;
    
        IF col_prefix = 'ROW#' THEN
            new_cols(1) := dbms_tf.column_metadata_t(NAME => 'COLUMN_NAME', TYPE => dbms_tf.type_varchar2, max_len => 128);
            idx := idx + 1;
        END IF;
        IF print_datatype = 1 THEN
            new_cols(2) := dbms_tf.column_metadata_t(NAME => 'DATA_TYPE', TYPE => dbms_tf.type_varchar2, max_len => 128);
            idx := idx + 1;
        END IF;
    
        IF to_json = 0 THEN
            FOR i IN 1 .. rows LOOP
                new_cols(idx + i) := dbms_tf.column_metadata_t(NAME => col_prefix || i, TYPE => dbms_tf.type_varchar2, max_len => max_col_width);
            END LOOP;
        ELSE
            new_cols(idx + 1) := dbms_tf.column_metadata_t(NAME => 'JSON_VAL', TYPE => dbms_tf.type_varchar2, max_len => 4000);
        END IF;
        descs.new_columns := new_cols;
        descs.row_replication := TRUE;
        descs.cstore_num('PRINT_DATATYPE') := print_datatype;
        --dbms_output.enable(NULL);
        RETURN descs;
    END;

    PROCEDURE fetch_rows(rows           NATURALN := 3,
                         print_datatype SIGNTYPE := 0,
                         sort_columns   SIGNTYPE := 0,
                         null_value     VARCHAR2 := '<NULL>',
                         trim_value     SIGNTYPE := 1,
                         to_json        SIGNTYPE := 0,
                         max_col_width  NATURALN := 128) AS
        rowset      dbms_tf.row_set_t;
        news        dbms_tf.row_set_t;
        row_count   PLS_INTEGER;
        col_count   PLS_INTEGER;
        idx         PLS_INTEGER;
        datatype    VARCHAR2(4000);
        val         VARCHAR2(32767);
        val1        VARCHAR2(32767);
        col_sort    dbms_tf.cstore_num_t;
        col_names   dbms_tf.tab_varchar2_t;
        cur         NUMBER;
        cursor_mode VARCHAR2(30);
        printdtype  SIGNTYPE := 0;
    BEGIN
        IF NOT reset_row_count THEN
            RETURN;
        END IF;
        dbms_tf.cstore_get('PRINT_DATATYPE', printdtype);
        dbms_tf.xstore_get('CURSOR_NUMBER', cur);
        IF cur IS NOT NULL AND dbms_tf.cstore_exists('CURSOR_STMT') THEN
            dbms_tf.cstore_get('CURSOR_PRINT', cursor_mode);
            rowset    := cursor_to_rowset(cur, rows);
            row_count := rowset(1).description.type_name_len;
            col_count := rowset.count;
        ELSE
            dbms_tf.get_row_set(rowset, row_count, col_count);
        END IF;
    
        reset_row_count(col_count);
    
        FOR i IN 1 .. col_count LOOP
            col_names(i) := TRIM('"' FROM rowset(i).description.name);
            col_sort(col_names(i)) := i;
        END LOOP;
    
        IF sort_columns > 0 THEN
            idx      := 0;
            datatype := col_sort.first;
            WHILE TRUE LOOP
                idx := idx + 1;
                col_sort(datatype) := idx;
                datatype := col_sort.next(datatype);
                EXIT WHEN datatype IS NULL;
            END LOOP;
        END IF;
    
        row_count := least(rows, row_count);
        FOR i IN 1 .. col_count LOOP
            datatype := col_names(i);
            idx := col_sort(datatype);
            news(1).tab_varchar2(idx) := datatype;
            datatype := nvl(rowset(i).description.type_name, dbms_tf.column_type_name(rowset(i).description));
            IF printdtype = 1 THEN
                IF datatype IN ('CHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR2', 'NUMBER', 'RAW') THEN
                    IF rowset(i).description.precision > 0 OR rowset(i).description.precision > 0 THEN
                        datatype := datatype || '(' || nvl('' || rowset(i).description.precision, '*') || ',' ||
                                    nvl('' || rowset(i).description.precision, '*') || ')';
                    ELSIF rowset(i).description.max_len > 0 THEN
                        datatype := datatype || '(' || rowset(i).description.max_len || ')';
                    END IF;
                END IF;
                news(2).tab_varchar2(idx) := datatype;
            END IF;
            val1 := '[';
            FOR j IN 1 .. row_count LOOP
            
                val := nvl(dbms_tf.col_to_char(rowset(i), j, ''), null_value);
                IF trim_value = 1 THEN
                    val := TRIM(regexp_replace(val, '\s+', ' '));
                END IF;
                val := substrb(val, 1, max_col_width);
                IF to_json = 0 THEN
                    news(printdtype + 1 + j).tab_varchar2(idx) := val;
                ELSIF lengthb(val1) + lengthb(val) < 3990 THEN
                    IF j > 1 THEN
                        val1 := val1 || ' , ';
                    END IF;
                
                    IF datatype NOT LIKE 'NUMBER%' OR datatype = null_value THEN
                        val := '"' || val || '"';
                    END IF;
                    val1 := val1 || val;
                END IF;
            END LOOP;
            IF to_json = 1 THEN
                news(printdtype + 2).tab_varchar2(idx) := val1 || ']';
            END IF;
        END LOOP;
        dbms_tf.put_row_set(news);
    END;

    FUNCTION describe(stmt           VARCHAR2,
                      tab            IN OUT NOCOPY dbms_tf.table_t,
                      rows           POSITIVE := NULL,
                      print_datatype PLS_INTEGER := NULL,
                      sort_columns   NATURALN := 0,
                      null_value     VARCHAR2 := '<NULL>',
                      trim_value     SIGNTYPE := 1,
                      to_json        SIGNTYPE := 0,
                      max_col_width  NATURALN := 128,
                      cols           PLS_INTEGER := NULL) RETURN dbms_tf.describe_t IS
        desc_t   dbms_tf.describe_t;
        rowset   dbms_tf.row_set_t;
        new_cols dbms_tf.columns_new_t;
        ptf      VARCHAR2(30) := TRIM('"' FROM tab.ptf_name);
        cur      NUMBER;
        cnt      PLS_INTEGER := coalesce(cols, print_datatype, 1024);
    BEGIN
        dbms_output.put_line(ptf);
        IF ptf = 'PIVOT' THEN
            desc_t := describe(tab            => tab,
                               rows           => nvl(rows, 3),
                               print_datatype => CASE
                                                     WHEN print_datatype IN (0, 1) THEN
                                                      print_datatype
                                                     WHEN rows = 1 THEN
                                                      1
                                                     ELSE
                                                      0
                                                 END,
                               sort_columns   => sort_columns,
                               null_value     => null_value,
                               trim_value     => trim_value,
                               to_json        => to_json,
                               max_col_width  => max_col_width);
            desc_t.cstore_chr('CURSOR_PRINT') := 'PIVOT';
        ELSIF stmt IS NULL THEN
            IF tab.column.count = 1 AND TRIM('"' FROM tab.column(1).description.name) = 'DUMMY' THEN
                IF cnt = 1024 THEN
                    cnt := 128;
                END IF;
                desc_t := describe(tab            => tab,
                                   rows           => cnt,
                                   print_datatype => 0,
                                   sort_columns   => sort_columns,
                                   null_value     => null_value,
                                   trim_value     => trim_value,
                                   to_json        => to_json,
                                   max_col_width  => max_col_width,
                                   col_prefix     => 'COL#');
                desc_t.cstore_chr('CURSOR_PRINT') := 'DUMMY';
            ELSE
                FOR i IN 1 .. tab.column.count LOOP
                    tab.column(i).pass_through := FALSE;
                    tab.column(i).for_read := TRUE;
                    IF i <= cnt THEN
                        desc_t.new_columns(i) := tab.column(i).description;
                        desc_t.new_columns(i).max_len := nvl(nullif(desc_t.new_columns(i).max_len, 0), max_col_width);
                    END IF;
                END LOOP;
                desc_t.cstore_chr('CURSOR_PRINT') := 'TABLE';
            END IF;
        ELSE
            cur := stmt_to_cursor(stmt);
            IF ptf = 'PRINT' THEN
                rowset := cursor_to_rowset(cur, least(50, nvl(rows, 50)), nvl(print_datatype, 3));
                FOR i IN 1 .. rowset.count LOOP
                    desc_t.new_columns(i) := rowset(i).description;
                END LOOP;
                rowset.delete;
                dbms_session.free_unused_user_memory;
            ELSE
                new_cols := describe_cursor(cur);
                new_cols.delete(cnt + 1, new_cols.count);
                desc_t.new_columns := new_cols;
                IF NOT regexp_like(stmt, '^\d+$') THEN
                    dbms_sql.close_cursor(cur);
                END IF;
                desc_t.cstore_chr('CURSOR_PRINT') := 'TABLE';
            END IF;
            FOR i IN 1 .. tab.column.count LOOP
                tab.column(i).pass_through := FALSE;
                tab.column(i).for_read := TRUE;
            END LOOP;
        END IF;
        desc_t.cstore_chr('CURSOR_STMT') := stmt;
        desc_t.cstore_chr('CURSOR_PTF') := ptf;
        desc_t.row_replication := TRUE;
        RETURN desc_t;
    END;

    PROCEDURE fetch_rows(stmt           VARCHAR2,
                         rows           POSITIVE := NULL,
                         print_datatype PLS_INTEGER := NULL,
                         sort_columns   NATURALN := 0,
                         null_value     VARCHAR2 := '<NULL>',
                         trim_value     SIGNTYPE := 1,
                         to_json        SIGNTYPE := 0,
                         max_col_width  NATURALN := 128,
                         cols           PLS_INTEGER := NULL) IS
        cur         BINARY_INTEGER := stmt_to_cursor(stmt);
        ptf         VARCHAR2(30);
        cursor_mode VARCHAR2(30);
        rowset      dbms_tf.row_set_t;
    BEGIN
        dbms_tf.cstore_get('CURSOR_PTF', ptf);
        IF ptf = 'PIVOT' THEN
            dbms_tf.xstore_set('CURSOR_NUMBER', cur);
            fetch_rows(rows          => nvl(rows, 3),
                       sort_columns  => sort_columns,
                       null_value    => null_value,
                       trim_value    => trim_value,
                       to_json       => to_json,
                       max_col_width => max_col_width);
        ELSE
            IF NOT reset_row_count THEN
                RETURN;
            END IF;
            IF ptf = 'PRINT' THEN
                rowset := cursor_to_rowset(cur, nvl(rows, 50), nvl(print_datatype, 3));
            ELSE
                dbms_tf.cstore_get('CURSOR_PRINT', cursor_mode);
                dbms_output.put_line(cursor_mode);
                rowset := cursor_to_rowset(cur, nvl(rows, 1000), print_mode => 0, based_table => cursor_mode);
            END IF;
            reset_row_count(rowset(1).description.type_name_len + CASE WHEN cursor_mode = 'DUMMY' THEN 1 ELSE 0 END);
            dbms_tf.put_row_set(rowset);
        END IF;
    END;

    PROCEDURE fetch_rows(stmt IN OUT NOCOPY SYS_REFCURSOR, rows POSITIVEN := 1000, cols POSITIVEN := 128) IS
        c PLS_INTEGER;
    BEGIN
        IF NOT reset_row_count THEN
            RETURN;
        END IF;
        c := dbms_sql.to_cursor_number(stmt);
        fetch_rows(stmt => c, rows => rows);
    END;

    PROCEDURE fetch_rows(stmt          XMLTYPE,
                         rows          POSITIVEN := 1000,
                         cols          POSITIVEN := 128,
                         sort_columns  NATURALN := 0,
                         null_value    VARCHAR2 := '<NULL>',
                         trim_value    NATURALN := 1,
                         to_json       NATURALN := 0,
                         max_col_width NATURALN := 128,
                         noop6         NATURALN := 0,
                         row_pattern   VARCHAR2 := '/ROWSET/ROW',
                         col_pattern   VARCHAR2 := '*',
                         name_pattern  VARCHAR2 := 'name()',
                         value_pattern VARCHAR2 := '') IS
        c           PLS_INTEGER;
        cursor_mode VARCHAR2(30);
    BEGIN
        IF NOT reset_row_count THEN
            RETURN;
        END IF;
        dbms_tf.cstore_get('CURSOR_PRINT', cursor_mode);
        c := xml_to_cursor(val           => stmt,
                           row_limit     => nvl(rows, DEFAULT_FETCH_ROWS),
                           row_pattern   => row_pattern,
                           col_pattern   => col_pattern,
                           name_pattern  => name_pattern,
                           value_pattern => value_pattern,
                           based_table   => cursor_mode);
        fetch_rows(stmt           => c,
                   rows           => nvl(rows, DEFAULT_FETCH_ROWS),
                   print_datatype => CASE
                                         WHEN cols = 1 THEN
                                          1
                                         ELSE
                                          0
                                     END,
                   sort_columns   => sort_columns,
                   null_value     => null_value,
                   trim_value     => trim_value,
                   to_json        => to_json,
                   max_col_width  => max_col_width,
                   cols           => cols);
    END;

    PROCEDURE xml_to_cursor(cur           OUT SYS_REFCURSOR,
                            val           xmltype,
                            row_limit     POSITIVEN := DEFAULT_FETCH_ROWS,
                            row_pattern   VARCHAR2 := '/ROWSET/ROW',
                            col_pattern   VARCHAR2 := '*',
                            name_pattern  VARCHAR2 := 'name()',
                            value_pattern VARCHAR2 := '',
                            based_table   VARCHAR2 := '') IS
        tags  dbms_sql.Varchar2_Table;
        types dbms_sql.Varchar2_Table;
        pos   dbms_sql.Number_Table;
        cols  dbms_tf.table_metadata_t;
        names VARCHAR2(32767);
        n     VARCHAR2(130);
        fd    BOOLEAN := FALSE;
        stmt  VARCHAR2(32767);
        vpat  VARCHAR2(300) := nullif(value_pattern, '.');
        FUNCTION q(str VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            IF str IS NULL OR instr(str, '''') = 0 THEN
                RETURN '''' || str || '''';
            ELSIF instr(str, '{') = 0 AND instr(str, '}') = 0 THEN
                RETURN 'q''{' || str || '}''';
            ELSIF instr(str, '!') = 0 THEN
                RETURN 'q''!' || str || '!''';
            ELSE
                RETURN 'q''\' || str || '\''';
            END IF;
        END;
    BEGIN
        OPEN cur FOR
            SELECT * FROM dual WHERE rownum < 1;
    
        IF based_table IS NULL OR based_table IN ('DUMMY', 'PIVOT') THEN
            names := '*';
            stmt  := '
                SELECT n,
                       ''VARCHAR2(''||nvl(MAX(LENGTHB(v)),1)||'')'' v,
                       max(p) p
                FROM   XMLTABLE(' || q(row_pattern || '[position()<=10]/' || col_pattern) ||
                     ' PASSING :xml COLUMNS 
                           n VARCHAR2(128)  PATH ' || q(name_pattern) || ', 
                           v VARCHAR2(4000) PATH ' || q(nvl(value_pattern, '.')) || ',
                           p INT            PATH ''count(preceding-sibling::*)+1'' ) b 
                WHERE n is not null
                GROUP BY n
                ORDER BY 3';
            --dbms_output.put_line(stmt);
            EXECUTE IMMEDIATE stmt BULK COLLECT
                INTO tags, types, pos
                USING val;
        ELSE
            cols := dbms_tf.get_env().put_columns;
            FOR i IN 1 .. cols.count LOOP
                tags(i) := TRIM('"' FROM cols(i).name);
                n := '"' || tags(i) || '"';
                types(i) := TRIM('"' FROM dbms_tf.column_type_name(cols(i)));
                IF types(i) IN ('VARCHAR2', 'CHAR', 'RAW', 'NVARCHAR2', 'NCHAR') THEN
                    types(i) := types(i) || '(' || nvl(nullif(cols(i).max_len, 0), 128) || ')';
                ELSIF regexp_substr(types(i), '[^ ]+') IN ('DATE', 'TIMESTAMP') THEN
                    CASE types(i)
                        WHEN 'DATE' THEN
                            n := 'to_date(' || n || ') ' || n;
                        WHEN 'TIMESTAMP' THEN
                            n := 'to_timestamp(' || n || ') ' || n;
                        ELSE
                            n := 'to_timestamp_tz(' || n || ') ' || n;
                    END CASE;
                    types(i) := 'VARCHAR2(128)';
                    fd := TRUE;
                END IF;
                names := names || n || ',';
            END LOOP;
            names := TRIM(',' FROM names);
            IF NOT fd THEN
                names := '*';
            END IF;
        END IF;
        IF tags.count = 0 THEN
            RETURN;
        END IF;
        CLOSE cur;
        IF vpat IS NOT NULL THEN
            vpat := '/' || vpat;
        END IF;
        stmt := 'select ' || names || ' from xmltable(' || q(row_pattern || '[position()<=' || row_limit || ']') || ' passing :xml columns ';
        FOR i IN 1 .. tags.count LOOP
            IF i > 1 THEN
                stmt := stmt || ',';
            END IF;
            stmt := stmt || chr(10) || '    "' || upper(tags(i)) || '" ' || types(i) || '  path ' ||
                    q(col_pattern || '[' || name_pattern || '="' || tags(i) || '"][1]' || vpat);
            EXIT WHEN lengthb(stmt) > 32500;
        END LOOP;
    
        stmt := stmt || ')';
        --dbms_output.put_line(stmt);
        OPEN cur FOR stmt
            USING val;
    END;

    FUNCTION xml_to_cursor(val           xmltype,
                           row_limit     POSITIVEN := DEFAULT_FETCH_ROWS,
                           row_pattern   VARCHAR2 := '/ROWSET/ROW',
                           col_pattern   VARCHAR2 := '*',
                           name_pattern  VARCHAR2 := 'name()',
                           value_pattern VARCHAR2 := '',
                           based_table   VARCHAR2 := '') RETURN BINARY_INTEGER IS
        cur SYS_REFCURSOR;
    BEGIN
        xml_to_cursor(cur, val, row_limit, row_pattern, col_pattern, name_pattern, value_pattern, based_table);
        RETURN dbms_sql.to_cursor_number(cur);
    END;
END;
/
