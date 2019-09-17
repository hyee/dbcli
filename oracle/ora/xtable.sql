/*[[Show the v$views and column mappings relative to the specific x$table. Usage: @@NAME <x$ table name>
	--[[
		@ARGS: 1
		@ver: 12.1={dbms_utility} default={sys.dbms_sql2}
		@CHECK_ACCESS_DBA: dba_tab_cols={dba_tab_cols} default={all_tab_cols}
	--]]
]]*/
set feed off
var cur REFCURSOR;
DECLARE
    TYPE t_name IS TABLE OF VARCHAR2(30) INDEX BY VARCHAR2(128);
    names    t_name;
    text     CLOB;
    sub      VARCHAR2(32767);
    sel      VARCHAR2(32767);
    frm      VARCHAR2(32767);
    idx      PLS_INTEGER;
    tab      VARCHAR2(4000);
    alia     VARCHAR2(4000);
    tabsize  PLS_INTEGER := 0;
    colsize  PLS_INTEGER := 0;
    exprsize PLS_INTEGER := 0;
    recs     SYS.ODCICOLINFOLIST2 := SYS.ODCICOLINFOLIST2();
    counter  PLS_INTEGER := 0;
BEGIN
    dbms_output.enable(NULL);
    FOR R IN (SELECT distinct regexp_replace(view_name, '^G?V_?\$', 'V$') n
              FROM   v$fixed_view_definition
              WHERE  ( regexp_like(substr(view_definition, 1, 3999) || ' ', '\W' || REPLACE(:V1, '$', '\$') || '\W', 'i') 
              	    OR upper(:V1) IN(view_name,regexp_replace(view_name, '^G?V_?\$', 'V$')))
              AND    LENGTH(:V1) > 4) LOOP
        BEGIN
        	&ver..expand_sql_text('select * from sys.' || r.n, text);
	        IF instr(text,'"X$')=0 THEN
	        	&ver..expand_sql_text('select * from sys.' || replace(r.n,'V$','V_$'), text);
	        END IF;
	    EXCEPTION WHEN OTHERS THEN
	    	dbms_output.put_line('Unable to access or cannot find X$ table in view '||r.n);
	    	continue;
	    END;
        sub := regexp_replace(text, '.*\(\s*(SELECT.*?X\$.*?)\) ".*', '\1', 1, 1, 'n');
        sel := regexp_replace(sub, '(.*)\s+(FROM\s+.*?)$', '\1');
        frm := SUBSTR(sub, LENGTH(sel) + 1);
        names.delete();
        tabsize := GREATEST(tabsize, LENGTH(r.n));
        idx     := 0;
        LOOP
            idx  := idx + 1;
            tab  := regexp_substr(frm, '"(X\$[^"]+)"\s+"([^"]+)"', 1, idx, 'n', 1);
            alia := regexp_substr(frm, '"(X\$[^"]+)"\s+"([^"]+)"', 1, idx, 'n', 2);
            EXIT WHEN tab IS NULL;
            names(alia) := tab;
            sel := REPLACE(sel, '"' || alia || '"', tab);
        END LOOP;
        sel := regexp_replace(regexp_replace(sel || ',', '"\s+,', '",' || CHR(10)), 'select\s+', '', 1, 1, 'in');
        idx := 0;
        LOOP
            idx  := idx + 1;
            tab  := replace(regexp_replace(regexp_substr(sel, '(.*?)\s+"([^"]+)",', 1, idx, 'i', 1),'\s+',' '),'"');
            alia := regexp_substr(sel, '(.*?)\s+"([^"]+)",', 1, idx, 'i', 2);
            IF idx = 1 THEN
                tab := regexp_replace(tab, 'distinct\s+', '', 1, 1, 'in');
                tab := regexp_replace(tab, '/\*.*\*/\s*', '', 1, 1, 'in');
            END IF;
            colsize  := GREATEST(colsize, LENGTH(alia));
            exprsize := GREATEST(exprsize, LENGTH(tab));
            EXIT WHEN tab IS NULL;
            counter := counter + 1;
                EXIT WHEN counter>1000;
            recs.extend;
            recs(counter) := SYS.ODCICOLINFO(r.n, alia, tab, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
        END LOOP;
    END LOOP;
    OPEN :cur FOR 
    SELECT TableSchema VIEW_NAME,b.column_id "#",TableName COLUMN_NAME,ColName Source 
    FROM TABLE(recs) a,&CHECK_ACCESS_DBA b
    WHERE b.owner='SYS'
    AND   b.table_name=regexp_replace(a.TableSchema,'^(G?V)\$','\1_$')
    AND   b.column_name=a.TableName
    ORDER BY b.column_id;
END;
/
select * from v$fixed_view_definition
where regexp_like(substr(view_definition,1,3999)||' ','\W'||replace(:v1,'$','\$')||'\W','i')
OR upper(:V1) IN(view_name,regexp_replace(view_name, '^G?V_?\$', 'V$'));
