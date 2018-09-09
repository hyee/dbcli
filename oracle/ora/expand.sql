/*[[return the result of dbms_utility.expand_sql_text. Usage: @@NAME "sql_text"|<view_name>
   @ver: 12.1={}
]]*/
set feed off
declare
   src VARCHAR2(32767):=regexp_replace(trim(:v1),'[; '||chr(10)||chr(13)||chr(9)||']+$');
   text CLOB;
begin
   if src is null then 
       raise_application_error(-20001,'Please input the sql text, of which EOF syntax is supported!');
   end if;
   if instr(src,' ')=0 then
       src := 'select * from '||src;
   end if;
   dbms_output.enable(null);
   dbms_utility.expand_sql_text(src,text);
   dbms_output.put_line(text);
end;
/