/*[[Show PGA stats]]*/
set feed off
pro PGA Stats:
pro ================
select * from GV$PGASTAT order by 1,2;

pro PGA Advise:
pro ================
select * from GV$PGA_TARGET_ADVICE order by 1,2;

pro PGA Parameters:
pro ================
ora param pga