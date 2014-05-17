/*[[Get resource usage from SQL monitor. Usage: sqlm <sql_id> [A|A1|B [,<sid>]]  ]]*/
select DBMS_SQLTUNE.REPORT_SQL_MONITOR(
   report_level=>decode(upper(:V2),'A1','ALL','A','ALL-SESSIONS','BASIC+PLAN'),type => 'TEXT',sql_id=>:V1, session_id=>:V3) as report
FROM dual