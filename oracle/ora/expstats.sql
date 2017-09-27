/*[[Generate the script to import the stats of the input table/sql. Usage: @@NAME <sql_id>|<table_name>
--[[
    @CHECK_ACCESS_PLAN: gv$sql_plan={g},default={}
    @CHECK_ACCESS_AWR: dba_hist_sql_plan={UNION SELECT object_owner, object_name, object_type FROM dba_hist_sql_plan WHERE  object_type IS NOT NULL AND sql_id = v_sqlid}
    @CHECK_ACCESS_IDXVIEW: dba_indexes={dba_indexes}, default={all_indexes}
--]]
]]*/


ora _find_object "&V1" 1
set verify off feed off
var text CLOB;
DECLARE
    v_stgtab VARCHAR2(30) := 'DBCLI_STATS_TABLE';
    v_sqlid  VARCHAR2(30) := :V1;
    TYPE t_tab IS RECORD(
        owner VARCHAR2(30),
        tname VARCHAR2(30));
    TYPE t_tabs IS TABLE OF t_tab INDEX BY PLS_INTEGER;
    v_tabs t_tabs;
    v_text CLOB;
    v_xml  CLOB;
    v_piece VARCHAR2(2000);
    v_start PLS_INTEGER:=1;
    v_pos   PLS_INTEGER:=1;
    PROCEDURE pr(p_text VARCHAR2, flag BOOLEAN DEFAULT TRUE) IS
    BEGIN
        IF flag THEN
            dbms_lob.writeappend(v_text, length(p_text) + 1, p_text || chr(10));
        ELSE
            dbms_lob.writeappend(v_text, length(p_text), p_text);
        END IF;
    END;
BEGIN
    dbms_output.enable(NULL);
    IF :object_owner IS NOT NULL THEN 
       v_tabs(1).OWNER:= :OBJECT_OWNER;
       v_tabs(1).tname:= :OBJECT_NAME;
    ELSE
        WITH r AS
         (SELECT /*+materialize*/DISTINCT *
          FROM   (SELECT object_owner, object_name, object_type
                  FROM   &CHECK_ACCESS_PLAN.v$sql_plan
                  WHERE  object_type IS NOT NULL
                  AND    sql_id = v_sqlid
                  &CHECK_ACCESS_AWR))
        SELECT object_owner, object_name
        BULK   COLLECT
        INTO   v_tabs
        FROM   r
        WHERE  object_type LIKE 'TABLE%'
        UNION
        SELECT /*+ordered push_pred(i) no_merge(i)*/table_owner, table_name
        FROM   r, &CHECK_ACCESS_IDXVIEW i
        WHERE  object_type LIKE 'INDEX%' AND owner = object_owner AND index_name = object_name;
    END IF;
    
    IF v_tabs.count =0 THEN
        raise_application_error(-20001,'Cannot find impacted tables regarding to the input table_name or sql_id!');
    END IF;

    BEGIN
        dbms_stats.drop_stat_table(USER, v_stgtab);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    dbms_stats.create_stat_table(USER, v_stgtab);

    FOR i IN 1 .. v_tabs.count LOOP
        dbms_stats.export_table_stats(v_tabs(i).owner, v_tabs(i).tname, stattab => v_stgtab, statown => USER);
    END LOOP;
    EXECUTE IMMEDIATE q'|alter session set nls_date_format='YYYY-MM-DD HH24:MI:SS'|';
    v_xml := dbms_xmlgen.getxml('select * from '||v_stgtab);
    dbms_stats.drop_stat_table(USER, v_stgtab);
    
    dbms_lob.createtemporary(v_text, TRUE);
    pr('Set define off sqlbl on' || chr(10));
    pr('DECLARE');
    pr('    txt    CLOB;');
    pr('    hdr    NUMBER;');
    pr('    stgtab VARCHAR2(30) := '''||v_stgtab||''';');
    pr('    procedure wr(x varchar2) is begin dbms_lob.writeappend(txt, length(x), x);end;');
    pr(q'[    procedure do_insert(cols varchar2,vals varchar2) is begin execute immediate 'insert into '||stgtab||'('||cols||') values('||vals||')';end;]');
    pr('BEGIN');
    pr(q'[    execute immediate q'|ALTER session SET nls_date_format = 'YYYY-MM-DD HH24:MI:SS'|';]');
    pr('    BEGIN');
    pr('        dbms_stats.drop_stat_table(USER, stgtab);');
    pr('    EXCEPTION WHEN OTHERS THEN NULL;');
    pr('    END;');
    pr('    dbms_stats.create_stat_table(USER, stgtab);');
    $IF DBMS_DB_VERSION.VERSION > 10 $THEN
        v_piece := 'let $last:=name(/ROW/*[last()]) return <r>    do_insert(''{for $i in /ROW/* return concat(name($i),if (name($i)=$last) then "" else ",")}'',' ||CHR(10)||
                  q'[      q'({for $i in /ROW/* return concat("'",data($i),"'",if (name($i)=$last) then "" else ",")})');</r>]';
        FOR r in(SELECT EXTRACTVALUE(xmlquery(v_piece PASSING COLUMN_VALUE RETURNING CONTENT), '/r') stmt
                 FROM   XMLTABLE('/ROWSET/ROW' PASSING XMLTYPE(v_xml)) a) LOOP
            pr(replace(r.stmt,q'[', ']',q'[',']'));
        END LOOP;
        pr('    COMMIT;');
    $ELSE
        pr('    dbms_lob.createtemporary(txt, TRUE);');
        LOOP
            v_pos := INSTR(v_xml,CHR(10),v_start);
            EXIT WHEN v_pos=0;
            v_piece := SUBSTR(v_xml,v_start,v_pos-v_start);
            v_start := v_pos+1;
            pr('    wr(q''['||rtrim(v_piece)||']'');');
        END LOOP;
        pr('    hdr:=dbms_xmlstore.newContext(stgtab);');
        pr('    dbms_output.put_line(dbms_xmlstore.insertXML(hdr,txt)||'' records imported.'');');
    $END
    FOR i in 1..v_tabs.COUNT LOOP
        pr('    dbms_stats.import_table_stats('''||v_tabs(i).owner||''','''|| v_tabs(i).tname||''',stattab => stgtab, statown => USER);');
    END LOOP;
    pr('    dbms_stats.drop_stat_table(USER, stgtab);');
    pr('END;'||CHR(10)||'/');
    :text := v_text;
END;
/
print text
save text exp_stats.sql