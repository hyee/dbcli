/*[[return the result of dbms_utility.expand_sql_text. Usage: @@NAME "sql_text"|<view_name>|<sql_id>

Examples:
    @@NAME gv$active_session_history
    @@NAME "select * from gv$active_session_history where sample_time>sysdate-21"
   --[[
        @ver: 12.1={dbms_utility} default={sys.dbms_sql2}
        @VER2: 12.1={,con_dbid} default={}
        @ARGS: 1
   --]]
]]*/
set feed off
var c refcursor;
declare
   src  CLOB:=regexp_replace(trim(:v1),'[; '||chr(10)||chr(13)||chr(9)||']+$');
   schem1 VARCHAR2(128):=SYS_CONTEXT('USERENV','CURRENT_SCHEMA');
   schem2 VARCHAR2(128);
   text CLOB;
begin
   if src is null then 
       raise_application_error(-20001,'Please input the sql text, of which EOF syntax is supported!');
   end if;
   if instr(src,' ')=0 then
       BEGIN
           select *
           into   src,schem2
           from (
               SELECT sql_text,parsing_schema_name
               FROM   dba_hist_sqltext join dba_hist_sqlstat
               USING  (dbid &ver2,sql_id)
               WHERE  sql_id = to_char(src)
               AND    ROWNUM<2
               union all
               select sql_fulltext,parsing_schema_name
               from    gv$sqlarea
               where  sql_id=to_char(src)
               and     rownum<2
           ) where rownum<2;  
       EXCEPTION WHEN OTHERS THEN
           src := 'select * from '||src;
       END;
       
   end if;
   IF schem1!=schem2 THEN
       execute immediate 'alter session set current_schema='||schem2;
   END IF;
   &ver..expand_sql_text(src,text);
   open :c for select text from dual;
   IF schem1!=schem2 THEN
       execute immediate 'alter session set current_schema='||schem1;
   END IF;
end;
/
