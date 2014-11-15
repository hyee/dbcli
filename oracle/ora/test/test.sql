--test.sql
/*[[
   --[[
       @CHECK_ACCESS: {
           X$KSPPI/X$KSPPCV={X$KSPPCV}, 
           SYS.DBMS_LOGMNR/DBMS_XMLGEN={V$LOGMNR_CONTENT}
        }
   --]]
]]*/

PRO Matched target is '&CHECK_ACCESS'
SELECT * FROM &CHECK_USER WHERE ROWNUM<10;