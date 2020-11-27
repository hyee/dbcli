/*[[
    Get SQL text and online stats. Usage: @@NAME <sql_id> [inst_id] [-q|-l|<child_no>|<snap_id> that used for parsing bind values]
    When parameter #3 is input:
        -q      : List all bind captures
        -l      : Use the last bind capture to replace the SQL text
        <number>: Use bind capture of the input child_number/snap_id to replace the SQL text

    Sample Output:
    ==============
    ORCL> ora sql g6px76dmjv1jy                                                                                                                            
       TOP_SQL       PHV     PLAN_LINE PROGRAM# EVENT  AAS                                                                                             
    ------------- ---------- --------- -------- ------ ---                                                                                             
    g6px76dmjv1jy 3702721588         2          ON CPU  49                                                                                             
    g6px76dmjv1jy 3702721588         2     7294 ON CPU  44                                                                                             
    g6px76dmjv1jy 3702721588         2     7292 ON CPU  26                                                                                             
    b6usrg82hwsa3 3702721588         2    12703 ON CPU   2                                                                                                                                                                                                                                               
                                                                                                                                                       
       PHV     PROGRAM#    ACS    OUTLINE USER# EXEC PARSE ALL_ELA|AVG_ELA  CPU  IO CC CL AP PL_JAVA  BUFF CELLIO WRITE READ OFLIN OFLOUT ROWS# FETCHES
    ---------- -------- --------- ------- ----- ---- ----- -------+------- ----- -- -- -- -- ------- ----- ------ ----- ---- ----- ------ ----- -------
    3702721588 0        SHAREABLE         SYS     66    66   2.21m|  2.01s 1.96s  0  0  0  0       0 365     0  B  0  B 0  B  0  B   0  B     1       1
                                                                  |                                                                                    
                                                                                                                                                                                                                                                                                          
    Result written to D:\dbcli\cache\orcl\clob_1.txt                                                                                                   
    SQL_TEXT                                                                                                                                           
    ---------------------------------------------------------------------------------------------------------------------------------------------------
    select count(*) from wri$_optstat_opr o, wri$_optstat_opr_tasks t where o.id = t.op_id(+) and o.operation = 'gather_database_stats (auto)' and (not
     '//error'),   '^<error>ORA-200[0-9][0-9]') or  not regexp_like(   extract(xmltype('<notes>' || t.notes || '</notes>'), '//error'),   '^<error>ORA-

    --[[
        @VER12: 12.1={} default={--}
        @VER: 11.2={} DEFAULT={--}
        @check_access_hist: dba_hist_sqltext={} default={--}
        @check_access_bind: dba_hist_sqlbind={1} default={0} 
        @ARGS: 1
        &V3  : default={} q={Q} l={L}
    --]]
]]*/
set colwrap 150 feed off 
COL AVG_ELA,ALL_ELA,CPU,IO,CC,CL,AP,PL_JAVA FORMAT USMHD2
COL CELLIO,READ,WRITE,CELLIO,OFLIN,OFLOUT FORMAT KMG
COL buff for tmb
VAR c REFCURSOR;
VAR b REFCURSOR "Bind List"
VAR src  VARCHAR2;
VAR inst VARCHAR2;
VAR txt  CLOB;
SET BYPASSEMPTYRS ON VERIFY OFF

DECLARE
    sql_text  CLOB;
    text      CLOB;
    inst      INT := regexp_substr(:V2,'^\d+$');
    child     INT := regexp_substr(:V3,'^\d+$');
    BINDS     XMLTYPE := XMLTYPE('<BINDS/>');
    name      VARCHAR2(128);
    ELEM      XMLTYPE;
    BIND_VAL  SYS.ANYDATA;
    BIND_TYPE VARCHAR2(128);
    DTYPE     VARCHAR2(128);
    STR_VAL   VARCHAR2(32767);
    CUR       SYS_REFCURSOR;
    NOT_NULL  BOOLEAN;
    opname    VARCHAR2(128);
    occu      PLS_INTEGER := 1;
    last_cap  VARCHAR2(20);
    PROCEDURE repl(format VARCHAR2,value VARCHAR2,defaults VARCHAR2:=NULL) IS
        val VARCHAR2(32767);
        fmt VARCHAR2(300):=format;
    BEGIN
        IF opname IN('EXECUTE','DECLARE','BEGIN','CALL') THEN
            IF last_cap IS NULL THEN
                STR_VAL := NAME;
                RETURN;
            END IF;
            occu := 0;
        END IF;
        IF VALUE IS NULL AND defaults IS NULL THEN
            fmt := REPLACE(fmt,q'['%s']','%s');
        ELSIF instr(value,'''')>0 THEN
            fmt := REPLACE(fmt,q'['%s']','q''!%s!''');
        END IF;
        val := utl_lms.format_message(fmt,COALESCE(value,defaults,'NULL'));
        STR_VAL := val;
        text := regexp_replace(text,'#!'||name||'!#',val,1,occu,'i');
    END;
BEGIN
    BEGIN
      SELECT * 
      INTO   sql_text,:src,:inst
      FROM(select sql_fulltext sql_text,'gv$active_session_history' src,'inst_id' inst from gv$sqlarea where sql_id='&v1'
           &check_access_hist  union all select sql_text,'dba_hist_active_sess_history','instance_number' inst from dba_hist_sqltext src where sql_id='&v1'
      ) WHERE ROWNUM<2;
    EXCEPTION WHEN OTHERS THEN
        :src := 'gv$active_session_history';
        :inst:= 'inst_id';
        :txt := '';
        OPEN :c FOR SELECT '<No Result>' SQL_TEXT FROM DUAL;
        RETURN;
    END;

    IF child IS NOT NULL OR upper(:V3) in ('-L','L') THEN
        dbms_lob.createtemporary(text,true);
        dbms_lob.append(text,sql_text);
        dbms_lob.writeappend(text,1,' ');
        text   := regexp_replace(text,'^\s*/\*.*?\*/');
        text   := regexp_replace(text,q'{([^0-9a-zA-Z'$_#]):("?)([0-9a-zA-Z$_#]+)\2([^0-9a-zA-Z'$_#])}','\1#!:\3!#\4');
        opname := upper(REGEXP_SUBSTR(text,'\w+'));

        FOR r IN (WITH qry AS
                      (SELECT a.*, dense_rank() over(ORDER BY captured,r DESC) seq
                       FROM   (SELECT a.*, decode(MAX(was_captured) over(PARTITION BY r), 'YES', 0, 1) captured
                               FROM   (SELECT MAX(LAST_CAPTURED) OVER(PARTITION BY child_number,inst_id) || child_number || ':' || INST_ID r,
                                              ''||child_number c,
                                              was_captured,
                                              position,
                                              NAME,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              inst_id,
                                              last_captured,
                                              'GV$SQL_BIND_CAPTURE' SRC
                                       FROM   gv$sql_bind_capture a
                                       WHERE  sql_id = '&v1'
                                       AND    child_number=nvl(child,child_number)
                                       AND    inst_id=nvl(inst,inst_id)
                                       $IF &check_access_bind=1 $THEN
                                       UNION ALL
                                       SELECT MAX(LAST_CAPTURED) OVER(PARTITION BY DBID,SNAP_ID,INSTANCE_NUMBER)||DBID||':'|| SNAP_ID || ':' || INSTANCE_NUMBER,
                                              ''||SNAP_ID c,
                                              was_captured,
                                              position,
                                              NAME,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              instance_number,
                                              last_captured,
                                              'DBA_HIST_SQLBIND' SRC
                                       FROM   dba_hist_sqlbind a
                                       WHERE  sql_id = '&v1'
                                       AND    snap_id=nvl(child,snap_id)
                                       AND    instance_number=nvl(inst,instance_number)
                                       $END
                                       ) a) a)
                      SELECT inst_id inst,
                             position pos#,
                             qry.NAME,
                             datatype,
                             datatype_string,
                             value_string,
                             value_anydata,
                             to_char(qry.last_captured) last_captured,
                             src
                      FROM   qry
                      WHERE  seq = 1
                      ORDER  BY position) LOOP
            name     := r.name;
            DTYPE    := r.datatype_string;
            BIND_VAL := r.value_anydata;
            NOT_NULL := BIND_VAL IS NOT NULL;
            last_cap := r.last_captured;
            CASE REGEXP_REPLACE(DTYPE,'\(\d+\)')
                WHEN 'NUMBER' THEN
                    repl('%s',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSNUMBER(BIND_VAL) END,'TO_NUMBER(NULL)');
                WHEN 'BINARY_DOUBLE' THEN
                    repl('TO_BINARY_DOUBLE(%s)',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSBDOUBLE(BIND_VAL) END);
                WHEN 'BINARY_FLOAT' THEN
                    repl('TO_BINARY_FLOAT(%s)',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSNUMBER(BIND_VAL) END);
                WHEN 'VARCHAR' THEN
                    repl('''%s''',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSVARCHAR(BIND_VAL) END);
                WHEN 'VARCHAR2' THEN
                    repl('''%s''',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSVARCHAR2(BIND_VAL) END);
                WHEN 'CHAR' THEN
                    repl('''%s''',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSCHAR(BIND_VAL) END);
                WHEN 'NCHAR' THEN
                    repl('TO_NCHAR(''%s'')',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSNCHAR(BIND_VAL) END);
                WHEN 'NVARCHAR2' THEN
                    repl('TO_NCHAR(''%s'')',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSNVARCHAR2(BIND_VAL) END);
                WHEN 'CLOB' THEN
                    repl('TO_CLOB(%s)','');
                WHEN 'BLOB' THEN
                    repl('TO_BLOB(%s)','');
                WHEN 'DATE' THEN
                    repl(q'[TO_DATE('%s','YYYY-MM-DD HH24:MI:SS')]',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSDATE(BIND_VAL) END);
                WHEN 'TIMESTAMP' THEN
                    repl(q'[TO_TIMESTAMP('%s','YYYY-MM-DD HH24:MI:SSxff')]',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSTIMESTAMP(BIND_VAL) END);
                WHEN 'TIMESTAMP (TZ)' THEN
                    repl(q'[TO_TIMESTAMP_TZ('%s','YYYY-MM-DD HH24:MI:SSxff TZH:TZM')]',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSTIMESTAMPTZ(BIND_VAL) END);
                WHEN 'TIMESTAMP (LTZ)' THEN
                    repl(q'[TO_TIMESTAMP_TZ('%s','YYYY-MM-DD HH24:MI:SSxff TZH:TZM')]',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSTIMESTAMPLTZ(BIND_VAL) END);
                WHEN 'RAW' THEN
                    repl(q'[HEXTORAW('%s')]',RAWTOHEX(CASE WHEN NOT_NULL THEN ANYDATA.ACCESSRAW(BIND_VAL) END));
                WHEN 'ROWID' THEN
                    repl('CAST(''%s'' AS ROWID)',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSVARCHAR2(BIND_VAL) END);
                WHEN 'UROWID' THEN
                    repl('CAST(''%s'' AS UROWID)',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSUROWID(BIND_VAL) END);
                WHEN 'INTERVAL DAY TO' THEN
                    repl('TO_DSINTERVAL(''%s'')',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSVARCHAR2(BIND_VAL) END);
                WHEN 'INTERVAL YEAR TO' THEN
                    repl('TO_YMINTERVAL(''%s'')',CASE WHEN NOT_NULL THEN ANYDATA.ACCESSVARCHAR2(BIND_VAL) END);
                ELSE
                    IF DTYPE IN('CURSOR','NESTED TABLE','VARRAY') THEN
                        repl(name||'/*%s*/',dtype);
                    ELSE
                        repl('NULL/*'||name||':%s*/',dtype);
                    END IF;
            END CASE;
            SELECT XMLELEMENT("BIND",
                      XMLELEMENT("inst", r.inst),
                      XMLELEMENT("pos", r.pos#),
                      XMLELEMENT("name", r.name),
                      XMLELEMENT("value", nvl(str_val,r.value_string)),
                      XMLELEMENT("dtype", dtype),
                      XMLELEMENT("last_captured", r.last_captured),
                      XMLELEMENT("src", r.src))
            INTO   ELEM
            FROM   DUAL;
            BINDS := BINDS.APPENDCHILDXML('/*', ELEM);
        END LOOP;
        text := trim(regexp_replace(text,'#!(:[0-9a-zA-Z$_#]+)!#','\1'));
        sql_text := text;
        OPEN cur FOR SELECT text SQL_TEXT FROM DUAL;
        OPEN :b FOR
            SELECT EXTRACTVALUE(COLUMN_VALUE, '//inst') + 0 inst,
                   EXTRACTVALUE(COLUMN_VALUE, '//pos') + 0 pos#,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//name') AS VARCHAR2(128)) NAME,
                   EXTRACTVALUE(COLUMN_VALUE, '//value') replace_text,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//dtype') AS VARCHAR2(30)) data_type,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//last_captured') AS VARCHAR2(20)) last_captured,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//src') AS VARCHAR2(30)) SOURCE
            FROM   TABLE(XMLSEQUENCE(EXTRACT(BINDS, '/BINDS/BIND')));
    ELSIF upper(:V3) in ('-Q','Q') THEN
        OPEN CUR FOR
            SELECT * FROM (
                SELECT * 
                FROM (  SELECT INST_ID,CHILD_NUMBER "Child#/Snap#",MAX(LAST_CAPTURED) LAST_CAPTURED,COUNT(NULLIF(WAS_CAPTURED,'NO'))||'/'||COUNT(1) Captures,'GV$SQL_BIND_CAPTURE' SOUCE_VIEW
                        FROM   gv$sql_bind_capture a
                        WHERE  sql_id = '&v1'
                        AND    inst_id=nvl(inst,inst_id)
                        GROUP  BY INST_ID,CHILD_NUMBER
                        $IF &check_access_bind=1 $THEN
                        UNION ALL
                        SELECT INSTANCE_NUMBER,SNAP_ID,MAX(LAST_CAPTURED) LAST_CAPTURED,COUNT(NULLIF(WAS_CAPTURED,'NO'))||'/'||COUNT(1) Captures,'DBA_HIST_SQLBIND' SOUCE_VIEW
                        FROM   dba_hist_sqlbind a
                        WHERE  sql_id = '&v1'
                        AND    instance_number=nvl(inst,instance_number)
                        GROUP  BY INSTANCE_NUMBER,SNAP_ID
                        $END
                ) 
                WHERE nvl(LAST_CAPTURED,SYSDATE) BETWEEN nvl(to_date(:starttime,'YYMMDDHH24MISS'),sysdate-7) and nvl(to_date(:endtime,'YYMMDDHH24MISS'),sysdate)
                ORDER BY 3 DESC,2 DESC,1
            ) WHERE ROWNUM<=50;
    ELSE
        OPEN cur FOR SELECT SQL_TEXT SQL_TEXT FROM DUAL;
    END IF;
    :c   := cur;
    :txt := sql_text;
END;
/
PRINT b;
PRINT c;
save txt last_sql_&V1..txt

pro 
SELECT *
FROM   (SELECT &VER top_level_sql_id top_sql,
               COUNT(1) aas,
               NVL(event, 'ON CPU') event,
               sql_plan_hash_value phv,
               &VER sql_plan_line_id plan_line,
               &VER NVL(TRIM(SQL_PLAN_OPERATION||' '||SQL_PLAN_OPTIONS),TOP_LEVEL_CALL_NAME) OPERATION,
               PLSQL_ENTRY_OBJECT_ID program#
        FROM   &src
        WHERE  sql_id = :V1
        AND    &inst=nvl(regexp_substr(:V2,'^\d+$')+0,&inst)
        AND    sample_time+0 BETWEEN nvl(to_date(:starttime,'YYMMDDHH24MISS'),sysdate-7) and nvl(to_date(:endtime,'YYMMDDHH24MISS'),sysdate)
        GROUP  BY sql_plan_hash_value, PLSQL_ENTRY_OBJECT_ID, event
                  &VER ,sql_plan_line_id,top_level_sql_id,NVL(TRIM(SQL_PLAN_OPERATION||' '||SQL_PLAN_OPTIONS),TOP_LEVEL_CALL_NAME)
        ORDER  BY aas DESC)
WHERE  ROWNUM <= 10;

SELECT PLAN_HASH_VALUE PHV,
       program_id || NULLIF('#' || program_line#, '#0') program#,
       &ver trim(chr(10) from ''||&ver12 decode(is_reoptimizable,'Y','REOPTIMIZABLE'||chr(10))||decode(is_resolved_adaptive_plan,'Y','RESOLVED_ADAPTIVE_PLAN'||chr(10))||
       &ver decode(IS_BIND_SENSITIVE, 'Y', 'IS_BIND_SENSITIVE'||chr(10)) || decode(IS_BIND_AWARE, 'Y', 'BIND_AWARE'||chr(10)) || decode(IS_SHAREABLE, 'Y', 'SHAREABLE'||chr(10)))
       &ver ACS,
       TRIM('/' FROM SQL_PROFILE 
       &ver || '/' || SQL_PLAN_BASELINE
       ) OUTLINE,
       parsing_schema_name user#,
       SUM(EXEC) AS EXEC,
       SUM(PARSE_CALLS) parse,
       round(SUM(elapsed_time),3) all_ela,
       '|' "|",
       round(SUM(elapsed_time)/SUM(EXEC),3) avg_ela,
       round(SUM(cpu_time)/SUM(EXEC),3) CPU,
       round(SUM(USER_IO_WAIT_TIME)/SUM(EXEC),3) io,
       round(SUM(CONCURRENCY_WAIT_TIME)/SUM(EXEC),3) cc,
       round(SUM(CLUSTER_WAIT_TIME)/SUM(EXEC),3) cl,
       round(SUM(APPLICATION_WAIT_TIME)/SUM(EXEC),3) ap,
       round(SUM(PLSQL_EXEC_TIME + JAVA_EXEC_TIME)/SUM(EXEC),3) pl_java,
       round(SUM(BUFFER_GETS)/SUM(EXEC),3) AS BUFF,
       &ver round(SUM(IO_INTERCONNECT_BYTES)/SUM(EXEC),3)  cellio,
       &ver round(SUM(PHYSICAL_WRITE_BYTES)/SUM(EXEC),3)  AS WRITE,
       &ver round(SUM(PHYSICAL_READ_BYTES)/SUM(EXEC),3)  AS READ,
       &ver round(SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES)/SUM(EXEC),3)  oflin,
       &ver round(SUM(IO_CELL_OFFLOAD_RETURNED_BYTES)/SUM(EXEC),3)  oflout,
       round(sum(ROWS_PROCESSED)/SUM(EXEC),3)  rows#,
       round(sum(fetches)/SUM(EXEC),3)  fetches
FROM   (SELECT greatest(EXECUTIONS + users_executing, 1) exec,a.* 
        FROM   gv$SQL a 
        WHERE  SQL_ID=:V1 
        AND    inst_id=nvl(regexp_substr(:V2,'^\d+$')+0,inst_id))
GROUP  BY SQL_ID,
          PLAN_HASH_VALUE,
          &ver12 is_reoptimizable,is_resolved_adaptive_plan,
          &ver IS_BIND_SENSITIVE,
          &ver IS_BIND_AWARE,
          &ver IS_SHAREABLE,
          program_id,
          program_line#,
          SQL_PROFILE,
          &ver SQL_PLAN_BASELINE,
          parsing_schema_name;
          
