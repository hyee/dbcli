/*[[Show asm disk groups]]*/
set feed off verify on
select * from v$asm_diskgroup;

var x refcursor;
declare
   c sys_refcursor;
   grps VARCHAR2(4000);
BEGIN
   $IF DBMS_DB_VERSION.VERSION>10 $THEN
   select LISTAGG('''#'||GROUP_NUMBER||'''',',') within group(order by GROUP_NUMBER) into grps from v$asm_diskgroup;
   OPEN C for '
        SELECT *
        FROM  (SELECT NAME, READ_ONLY,VALUE, ''#'' || group_number grp FROM V$ASM_ATTRIBUTE WHERE NAME NOT LIKE ''template%'')
        PIVOT (MAX(VALUE) FOR grp IN('||grps||'))
        ORDER BY name';
   $END
   :x := c;
END;
/