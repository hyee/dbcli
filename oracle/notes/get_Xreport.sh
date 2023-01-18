#
# Create cron job for this script to run automatically
# e.g.: run "crontab -e -u oracle" with root to edit the crontab, run this script every 15 minute
# Add:  */15 * * * * /home/oracle/get_xreport.sh
#

#export ORACLE_SID=
#export ORACLE_HOME=
#export ORACLE_BASE=
#export PATH=$ORACLE_HOME/bin:$PATH
. /home/oracle/.bash_profile


begin_time=${1:-`date '+%Y-%m-%d_%H:%M'`}
interval=${2:-900}
min_run_time=${3:-60}
#cur_time=`echo ${begin_time} | sed s/-//g | sed s/_//g | sed s/://`
cur_time=sqlmons

cd `dirname $0`
mkdir $cur_time

sqlplus -s / as sysdba << ! | awk '{if($1!="TOP" && length($0)>0 && $1 != "----") print $1,$2,$3,$4,$5,$6,$7;}' | tee ${cur_time}/sqlmon.tmp
set lines 200
set verify off
set timing off
set pages 50000
set feedback off
set trimspool on
spool ${cur_time}/sqlmon.txt
col sql_text format a50 trunc
select to_char(rownum,'000') top,a.*
from (select sql_id,(LAST_REFRESH_TIME-SQL_EXEC_START)*24*3600,sql_exec_id,to_char(sql_exec_start,'YYYYMMDDHH24MISS') sql_exec_start,sql_plan_hash_value,sql_text
 from Gv\$sql_Monitor 
where (LAST_REFRESH_TIME-SQL_EXEC_START)*24*3600>${min_run_time}
--and sql_plan_hash_value >0
and （status like 'DONE%' or status like 'ERROR%'）
and LAST_REFRESH_TIME>=to_date('${begin_time}','YYYY-MM-DD_HH24:MI') -  $interval/3600/24
and LAST_REFRESH_TIME<=to_date('${begin_time}','YYYY-MM-DD_HH24:MI')
and sql_text is not null
order by elapsed_time desc) a where rownum<=50;
spool off
!

echo "query sql_id for monitor report finished!"

while read num sql_id elap_t sql_exec_id sql_exec_start sql_plan_hash_value sql_text
do
  f1=`echo $sql_exec_start | awk '{print substr($1,1,8)}'`
  f2=`echo $sql_exec_start | awk '{print substr($1,9,6)}'`
  htm_name=${cur_time}/sqlmon_${f1}_${f2}_${sql_id}_${sql_plan_hash_value}_${elap_t}s.html
  echo get monitor report for top $num SQL_ID:$sql_id output:$htm_name
  sqlplus -s / as sysdba << ! >/dev/null
  set echo off
  set linesize 2000
  set heading off
  set pages 0
  set long 20000000
  set longchunksize 20000000
  set timing off
  set feedback off
  set trimspool on
  spool ${htm_name}
    select dbms_sqltune.report_sql_monitor(sql_id=>'${sql_id}', sql_exec_id=>'${sql_exec_id}', sql_exec_start=>to_date('${sql_exec_start}','YYYYMMDDHH24MISS'), type=>'ACTIVE') Monitor_report from dual;
  spool off
!

done < ${cur_time}/sqlmon.tmp

rm ${cur_time}/sqlmon.tmp
rm ${cur_time}/sqlmon.txt

echo "Get all monitor report finished!"

