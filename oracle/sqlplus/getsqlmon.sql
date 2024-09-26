set termout off long 500000000 longchunksize 500000000 pages 0 timing off echo off verify off lines 3000 trimspool on
spool sqlmon_&&sqlid..html
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(sql_id       => '&&sqlid.',
                                       --sql_exec_id  => '&&sql_exe_id.',
                                       TYPE         => 'active',
                                       report_level => 'ALL') AS report
FROM   dual;
spool off