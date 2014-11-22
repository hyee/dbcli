set arraysize 500
--set define off
set linesize 500
set long 1000000 longchunksize 1000000
set pagesize 990
set serveroutput on
set trim on
set trimspool on

col argument_name format a30
col cluster_name format a30
col col_name format a30
col column_name format a30
col constraint_name format a30
col container_name format a30
col data_type format a30
col db_link format a30
col directory_name format a30
col directory_path format a30
col edition_name format a30
col file_name format a60
col granted_role format a30
col grantee format a30
col host_name format a20
col index_name format a30
col iot_name format a30
col max_lag_time format a12
col name format a30
col object_name format a30
col object_type format a20
col owner format a25
col owner_name format a25
col package_name format a30
col param_name format a25
col partition_name format a30
col pdb format a20
col procedure_name format a30
col queue_table format a30
col role format a30
col schedule_name format a30
col segment_name format a30
col service_name format a30
col subobject_name format a30
col synonym_name format a30
col table_name format a30
col table_type format a30
col triggering_event format a35
col type_name format a30
col type_owner format a30
col type_subname format a30
col username format a30
col value format a30
set feed off
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
set feed on