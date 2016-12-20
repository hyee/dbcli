/*[[Generate the script to import the stats of the input table/sql. Usage: @@NAME <sql_id>|<table_name>
]]*/


ora _find_object &V1 1
set verify off
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
            dbms_lob.writeappend(v_text, lengthb(p_text) + 1, p_text || chr(10));
        ELSE
            dbms_lob.writeappend(v_text, lengthb(p_text), p_text);
        END IF;
    END;
BEGIN
    dbms_output.enable(NULL);
    IF :object_owner IS NOT NULL THEN 
       v_tabs(1).OWNER:= :OBJECT_OWNER;
       v_tabs(1).tname:= :OBJECT_NAME;
    ELSE
        WITH r AS
         (SELECT /*+materialize*/*
          FROM   (SELECT object_owner, object_name, object_type
                  FROM   gv$sql_plan
                  WHERE  object_type IS NOT NULL
                  AND    sql_id = v_sqlid
                  UNION
                  SELECT object_owner, object_name, object_type
                  FROM   dba_hist_sql_plan
                  WHERE  object_type IS NOT NULL
                  AND    sql_id = v_sqlid))
        
        SELECT object_owner, object_name
        BULK   COLLECT
        INTO   v_tabs
        FROM   r
        WHERE  object_type LIKE 'TABLE%'
        UNION
        SELECT /*+ordered push_pred(i) no_merge(i)*/table_owner, table_name
        FROM   r, dba_indexes i
        WHERE  object_type LIKE 'INDEX%' AND owner = object_owner AND index_name = object_name;
    END IF;
    
    IF v_tabs.count =0 THEN
        raise_application_error(-20001,'Cannot find impacted tables regarding to the input table_name/sql_id!');
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
    dbms_lob.createtemporary(v_text, TRUE);
    pr('Set define off sqlbl on' || chr(10));
    pr('DECLARE');
    pr('    txt    CLOB;');
    pr('    hdr    NUMBER;');
    pr('    stgtab VARCHAR2(30) := ''DBCLI_STATS_TABLE'';');
    pr('    procedure wr(x varchar2) is begin dbms_lob.writeappend(txt, lengthb(x), x);end;');
    pr('BEGIN');
    pr(q'[    execute immediate q'|ALTER session SET nls_date_format = 'YYYY-MM-DD HH24:MI:SS'|';]');
    pr('    dbms_lob.createtemporary(txt, TRUE);');
    v_xml := dbms_xmlgen.getxml('select * from '||v_stgtab);
    dbms_stats.drop_stat_table(USER, v_stgtab);
    LOOP
        v_pos := INSTR(v_xml,CHR(10),v_start);
        EXIT WHEN v_pos=0;
        v_piece := SUBSTR(v_xml,v_start,v_pos-v_start);
        v_start := v_pos+1;
        pr('    wr(q''['||rtrim(v_piece)||']'');');
    END LOOP;
    pr('    BEGIN');
    pr('        dbms_stats.drop_stat_table(USER, stgtab);');
    pr('    EXCEPTION WHEN OTHERS THEN NULL;');
    pr('    END;');
    pr('    dbms_stats.create_stat_table(USER, stgtab);');
    pr('    hdr:=dbms_xmlstore.newContext(stgtab);');
    pr('    dbms_output.put_line(dbms_xmlstore.insertXML(hdr,txt)||'' records imported.'');');
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