/*[[Show asm disk groups]]*/
set feed off verify on
select * from v$asm_diskgroup;

var x refcursor;
declare
   c sys_refcursor;
   grps VARCHAR2(4000);
BEGIN
   
   select LISTAGG('''#'||GROUP_NUMBER||'''',',') within group(order by GROUP_NUMBER) into grps from v$asm_diskgroup;
   OPEN C for '
        SELECT *
        FROM  (SELECT NAME, READ_ONLY,VALUE, ''#'' || group_number grp FROM V$ASM_ATTRIBUTE WHERE NAME NOT LIKE ''template%'')
        PIVOT (MAX(VALUE) FOR grp IN('||grps||'))
        ORDER BY name';
   
   :x := c;
END;
/