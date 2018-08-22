/*[[Show blocking infomation, including equeue and library waits]]*/

set feed off
PRO From DBA_Waiters:
PRO =================
select * from dba_waiters;

PRO From DBA_KGLLOCK:
PRO =================
ora liblock