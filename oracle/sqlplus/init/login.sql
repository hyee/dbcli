SET ECHO OFF VERIFY OFF SERVEROUTPUT ON SIZE 1000000 TRIMSPOOL ON LONG 8000 LINESIZE 3000 PAGESIZE 9999
set trimout on trimspool on flagger off tab off arraysize 100 sqlbl on
set describe depth all
set termout off
define prompt_name=SQL
define prompt_sql="SELECT initcap(USER)||'@'||case when sys_context('userenv','service_name')!='SYS$USERS' then regexp_substr(sys_context('userenv','service_name'),'[^\-\.]+') else sys_context('userenv','db_name') end service_name FROM dual"
column service_name format a50 new_value prompt_name
column service_name new_value prompt_name
select * from(&prompt_sql); 
set sqlprompt '&prompt_name> '
alter session set nls_date_format='YYYY-MM-DD HH24:MI:SS';
set termout on
col PLAN_TABLE_OUTPUT format a300
----set the format of "SHOW PARAMETERS"
COLUMN name_col_plus_show_param FORMAT a36 HEADING NAME
COLUMN value_col_plus_show_param FORMAT a100 HEADING VALUE
PRO 1