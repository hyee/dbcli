/*[[Show PGA stats]]*/
set feed off

pro PGA Advise:
pro ================
select * from GV$PGA_TARGET_ADVICE order by 1,2;

pro PGA Stats:
pro ================
select inst_id,name,decode(UNIT,'bytes', round(value/1024/1024,2),value) value,decode(UNIT,'bytes','MB',unit) unit from GV$PGASTAT order by 1,2;


pro PGA Parameters:
pro ================
ora param pga workarea