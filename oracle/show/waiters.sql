/*[[Show blocking information, including enqueue and library cache waits.]]*/

set feed off
PRO From DBA_Waiters:
PRO =================
SELECT * FROM dba_waiters;

PRO From DBA_KGLLOCK:
PRO =================
ora liblock