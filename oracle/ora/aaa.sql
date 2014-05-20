/*[[
   This is a sample test 
   Script description should be enclosed like this sample
        test indent, the indent is based on the spaces of the 1st none-empty line
        test indent 2
]]*/

select sysdate,dbms_random.value,'welcome,呵呵' from dual connect by rownum<10;