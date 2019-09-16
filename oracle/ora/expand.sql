/*[[return the result of dbms_utility.expand_sql_text. Usage: @@NAME "sql_text"|<view_name>|<sql_id>

Examples:
    @@NAME gv$active_session_history
    @@NAME "select * from gv$active_session_history where sample_time>sysdate-21"
   --[[
        @ver: 12.1={dbms_utility} default={sys.dbms_sql2}
        @ARGS: 1
   --]]
]]*/
set feed off
var c refcursor;
declare
   src  CLOB:=regexp_replace(trim(:v1),'[; '||chr(10)||chr(13)||chr(9)||']+$');
   text CLOB;
begin
   if src is null then 
       raise_application_error(-20001,'Please input the sql text, of which EOF syntax is supported!');
   end if;
   if instr(src,' ')=0 then
       BEGIN
           select sql_text
           into   src
           from (
               select sql_text
               from   dba_hist_sqltext
               where  sql_id=to_char(src)
               union all
               select sql_fulltext
               from    gv$sqlarea
               where  sql_id=to_char(src)
               and     rownum<2
           ) where rownum<2;  
       EXCEPTION WHEN OTHERS THEN
           src := 'select * from '||src;
       END;
       
   end if;
   
   &ver..expand_sql_text(src,text);
   open :c for select text from dual;
end;
/
