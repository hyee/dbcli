-- Autostart Command Window script
set termout off
set serveroutput on size 1000000
set trimspool on
set long 5000 longchunksize 1000
set linesize 1000
set colwidth 1000
set pagesize 9999
column plan_plus_exp format a80
define gname=idle
alter session set nls_date_format='YYYY-MM-DD HH24:MI:SS';
alter session set NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SSXFF';
col instance_name format a20
col host_name format a20
col user format a20
set termout on
column instance_name new_value gname
select instance_name,host_name,sysdate,user from v$instance;

