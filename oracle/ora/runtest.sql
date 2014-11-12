/*[[
   This is a sample test 
   Script description should be enclosed like this sample
]]*/
PRO Start testing
/
PRO ====================

VAR OBJS CURSOR
VAR TABLES CURSOR
VAR A VARCHAR
VAR B VARCHAR
VAR C VARCHAR

set printsize 10
BEGIN
	open :OBJS for select * from all_objects;
	open :TABLES for select * from all_tables;
	:A:='XIXI';
	:B:=SYSDATE;
	:C:=dbms_random.value();
END;
/
/*
Test remove comment
*/
exec dbms_output.put_line('hello,IBM!');
pro 2
--comment1
--comment2
PRO sleep for 3 secs
sleep 3
PRO Rotating records...
set pivot 1
alias sf1 select * from v$session where rownum<10;
sf1
--remove alias
alias sf1
select sysdate,dbms_random.value,'welcome呵呵' from dual connect by rownum<10;
