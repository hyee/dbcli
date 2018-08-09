CREATE OR REPLACE NONEDITIONABLE PACKAGE print_cursor IS
    FUNCTION describe(tab            IN OUT NOCOPY dbms_tf.table_t,
                      stmt           VARCHAR2,
                      rows           POSITIVE := NULL,
                      print_datatype PLS_INTEGER := NULL,
                      sort_columns   NATURALN := 0,
                      null_value     VARCHAR2 := '<NULL>',
                      trim_value     SIGNTYPE := 1,
                      to_json        SIGNTYPE := 0,
                      max_col_width  NATURALN := 128,
                      cols           PLS_INTEGER := NULL,
                      row_pattern    VARCHAR2 := '/ROWSET/ROW',
                      col_pattern    VARCHAR2 := '*',
                      name_pattern   VARCHAR2 := 'name()',
                      value_pattern  VARCHAR2 := '') RETURN dbms_tf.describe_t;

    PROCEDURE fetch_rows(stmt           VARCHAR2,
                         rows           POSITIVE := NULL,
                         print_datatype PLS_INTEGER := NULL,
                         sort_columns   NATURALN := 0,
                         null_value     VARCHAR2 := '<NULL>',
                         trim_value     SIGNTYPE := 1,
                         to_json        SIGNTYPE := 0,
                         max_col_width  NATURALN := 128,
                         cols           PLS_INTEGER := NULL);
    PROCEDURE fetch_rows(stmt IN OUT NOCOPY SYS_REFCURSOR, rows POSITIVEN := 1000, cols POSITIVEN := 128);
    FUNCTION pivot(tab            TABLE, --input "DUAL"
                   stmt           VARCHAR2,
                   rows           POSITIVE := 3, -- rows to be printed
                   print_datatype SIGNTYPE := 0, -- whether to print the data_type
                   sort_columns   SIGNTYPE := 0, -- whether to sort the column names
                   null_value     VARCHAR2 := '<NULL>', --null displayed value
                   trim_value     SIGNTYPE := 1, -- whether to trim white spaces from the string and replace multiple white spaces as single empty space
                   to_json        SIGNTYPE := 0, -- whether to print the values as JSON format
                   max_col_width  NATURALN := 128) --maximum print chars of a column 
     RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_cursor;

    FUNCTION print(tab TABLE, stmt VARCHAR2, rows POSITIVE := 50, print_mode NATURALN := 3) RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_cursor;
    FUNCTION show(tab TABLE, stmt VARCHAR2, rows POSITIVEN := 1000, cols POSITIVEN := 128, print_mode NATURALN := 0) RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_cursor;
    FUNCTION show(tab TABLE, cur IN OUT NOCOPY SYS_REFCURSOR, rows POSITIVEN := 1000, cols POSITIVEN := 128, print_mode NATURALN := 0) RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_cursor;

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
    FUNCTION show(tab           TABLE,
                  stmt          xmltype,
                  rows          POSITIVEN := 1000,
                  cols          POSITIVEN := 128,
                  print_mode    NATURALN := 0,
                  noop2         VARCHAR2 := NULL,
                  noop3         NATURALN := 0,
                  noop4         NATURALN := 0,
                  noop5         NATURALN := 0,
                  noop6         NATURALN := 0,
                  row_pattern   VARCHAR2 := '/ROWSET/ROW',
                  col_pattern   VARCHAR2 := '*',
                  name_pattern  VARCHAR2 := 'name()',
                  value_pattern VARCHAR2 := '') RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_cursor;

    FUNCTION pivot(tab            TABLE, --input "DUAL"
                   stmt           xmltype,
                   rows           POSITIVE := 3, -- rows to be printed
                   print_datatype SIGNTYPE := 0, -- whether to print the data_type
                   sort_columns   SIGNTYPE := 0, -- whether to sort the column names
                   null_value     VARCHAR2 := '<NULL>', --null displayed value
                   trim_value     SIGNTYPE := 1, -- whether to trim white spaces from the string and replace multiple white spaces as single empty space
                   to_json        SIGNTYPE := 0, -- whether to print the values as JSON format
                   max_col_width  NATURALN := 128,
                   noop6          NATURALN := 0,
                   row_pattern    VARCHAR2 := '/ROWSET/ROW',
                   col_pattern    VARCHAR2 := '*',
                   name_pattern   VARCHAR2 := 'name()',
                   value_pattern  VARCHAR2 := '') RETURN TABLE
        PIPELINED TABLE POLYMORPHIC USING print_cursor;
END print_cursor;
/
CREATE OR REPLACE NONEDITIONABLE PACKAGE BODY print_cursor IS
    FUNCTION describe(tab            IN OUT NOCOPY dbms_tf.table_t,
                      stmt           VARCHAR2,
                      rows           POSITIVE := NULL,
                      print_datatype PLS_INTEGER := NULL,
                      sort_columns   NATURALN := 0,
                      null_value     VARCHAR2 := '<NULL>',
                      trim_value     SIGNTYPE := 1,
                      to_json        SIGNTYPE := 0,
                      max_col_width  NATURALN := 128,
                      cols           PLS_INTEGER := NULL,
                      row_pattern    VARCHAR2 := '/ROWSET/ROW',
                      col_pattern    VARCHAR2 := '*',
                      name_pattern   VARCHAR2 := 'name()',
                      value_pattern  VARCHAR2 := '') RETURN dbms_tf.describe_t IS
    BEGIN
        RETURN print_table.describe(tab            => tab,
                                    stmt           => stmt,
                                    rows           => rows,
                                    print_datatype => print_datatype,
                                    sort_columns   => sort_columns,
                                    null_value     => null_value,
                                    trim_value     => trim_value,
                                    to_json        => to_json,
                                    max_col_width  => max_col_width,
                                    cols           => cols);
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
    BEGIN
        print_table.fetch_rows(stmt           => stmt,
                               rows           => rows,
                               print_datatype => print_datatype,
                               sort_columns   => sort_columns,
                               null_value     => null_value,
                               trim_value     => trim_value,
                               to_json        => to_json,
                               max_col_width  => max_col_width,
                               cols           => cols);
    END;
    PROCEDURE fetch_rows(stmt IN OUT NOCOPY SYS_REFCURSOR, rows POSITIVEN := 1000, cols POSITIVEN := 128) IS
    BEGIN
        print_table.fetch_rows(stmt => stmt, rows => rows, cols => cols);
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
    BEGIN
        print_table.fetch_rows(stmt          => stmt,
                               rows          => rows,
                               cols          => cols,
                               sort_columns  => sort_columns,
                               null_value    => null_value,
                               trim_value    => trim_value,
                               to_json       => to_json,
                               max_col_width => max_col_width,
                               row_pattern   => row_pattern,
                               col_pattern   => col_pattern,
                               name_pattern  => name_pattern,
                               value_pattern => value_pattern);
    END;
END;
/
