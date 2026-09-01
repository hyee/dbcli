/*[[Show ash cost for a specific SQL for multiple executions. usage: @@NAME {<sql_id|plan_hash_value|signature> [sql_exec_id|PHV] [YYMMDDHH24MI] [YYMMDDHH24MI]}  [-d|-g] [-o] [-all]

Options:
    -o      : Show top objects (defaults to show top events)
    -d      : Only query dba_hist_active_sess_history (defaults to query both views)
    -sqlset : Use dba_sqlset_plans as the data source instead of dba_hist_sql_plan
    -g      : Only query gv$active_session_history (defaults to query both views)
    -all    : Use hierachy clause to grab the possible missing PX slave records, mainly use for parallel execution
    -pdb    : default to query dba_hist_* views in PDB, when specified this option then use awr_pdb_* views instead
    Format  : defaults not to display the outlines
        *             -s : -outline -rows -parallel
        * -fmt"<format>" : user-defined formats

Outputs:
    Plan Summary :  The summary of all execution plans, grouping by <Plan Hash Value>+<SQL id>+<Plan Hash Full>
    Plan Lines   :  The details of each execution plan, grouping by <Plan Hash Full>
    Wait stats   :  The Wait events of each execution plan, grouping by <Plan Hash Full>

Sample Ouput:
=============
+------------------------+------------------------+-----+-----+--------------+
|  Plan Hash   Full Hash |Execs       Secs DB-Time| CPU%|  PGA| Top Events   |
+------------------------+------------------------+-----+-----+--------------+
|*1656552173  2865921031 |  658 668(97.5%)   05:08|  100|  10M| ON CPU(100%) |
|*0           2865921031 |    4   17(2.5%)   00:09|  100|   9M| ON CPU(100%) |
+------------------------+------------------------+-----+-----+--------------+

==============================================================================================================================================
| Plan Hash Value(Full): 2865921031    Period: [2019/04/04 01:19:57 -- 2019/04/05 20:40:54]
| Plan Hash Value(s)   : 1656552173,0
----------------------------------------------------------------------------------------------------------------------------------------------
| Id  |   Ord |Execs       Secs DB-Time| CPU%|   PGA| Top Events     | Operation                    | Name               | E-Rows | E-Time   |
----------------------------------------------------------------------------------------------------------------------------------------------
|   0 |    12 |    9   36(5.3%)   00:18|  100|   10M| [ 100%] ON CPU | SELECT STATEMENT             |                    |        |          |
|   1 |    11 |                        |     |      |                |  SORT AGGREGATE              |                    |      1 |          |
|   2 |    10 |                        |     |      |                |   NESTED LOOPS               |                    |      1 | 00:00:01 |
|   3 |     8 |    1    1(0.1%)   00:02|  100| 6902K| [ 100%] ON CPU |    NESTED LOOPS              |                    |      1 | 00:00:01 |
|   4 |     6 |                        |     |      |                |     NESTED LOOPS             |                    |      1 | 00:00:01 |
|   5 |     4 |                        |     |      |                |      NESTED LOOPS            |                    |      3 | 00:00:01 |
|*  6 |     1 |   43   43(6.3%)   00:21|  100|   10M| [ 100%] ON CPU |       FIXED TABLE FULL       | X$KSUSD            |      1 |          |
|*  7 |     3 |  503 503(73.4%)   03:52|  100|   10M| [ 100%] ON CPU |       FIXED TABLE FIXED INDEX| X$KSUSESTA (ind:2) |      3 |          |
|   8 |     2 |                        |     |      |                |        FIXED TABLE FULL      | X$KSUSGIF          |      1 |          |
|*  9 |     5 |  102 102(14.9%)   00:46|  100|   10M| [ 100%] ON CPU |      FIXED TABLE FIXED INDEX | X$KSUSE (ind:1)    |      1 |          |
----------------------------------------------------------------------------------------------------------------------------------------------
+--------+-------------------------+-----+----------------------------------------------+-----------------------------+
|Events  |Execs        Secs DB-Time|  PGA| Top Lines                                    | Top Objects                 |
+--------+-------------------------+-----+----------------------------------------------+-----------------------------+
|ON CPU  |  658 685(100.0%)   05:18|  10M| 7(73.4%), 9(14.9%), 6(6.3%), 0(5.3%), 3(.1%) | 10679(81.2%) / 10870(18.8%) |
+--------+-------------------------+-----+----------------------------------------------+-----------------------------+


[|grid:{topic='Output Fields(The fields with no value will be hidden)'}
 |Field Name | Description                                                                                                          |
 |Plan Hash  | SQL Plan Hash value                                                                                                  |
 |SQL  ID    | When input parameter is not SQL ID, then this field will be displayed, otherwise field "Full Hash" is displayed      |
 |Full Hash  | The full hash value introduced since 12c. This field could be a SQL id meaning that the SQL could be a recursive SQL |
 |-          | -                                                                                                                    |
 |AWR-Exes   | The delta executions that retrieved from AWR dictionary                                                              |
 |Avg-Ela    | The average elapsed time that retrieved from AWR dictionary                                                          |
 |-          | -                                                                                                                    |
 |DoP        | The actual DoP of the parallel execution. Can be either <number> format or <min>-<max> format                        |
 |Skew       | The skew ratio of the parallel execution. Value = 100*stddev(<tm_delta_db_time>)/median(<tm_delta_db_time>)          |
 |Execs      | The execution count of the SQL. Value = count(distinct <sql_id>+<sql_exec_id>+<sql_exec_start>)                      |
 |AAS        | The count from ASH, will be hidden when equals to field "Secs"\n  Value = count(1)*decode(sign(<Avg-Ela> - 5secs),1,10,1)|
 |Secs       | Similar to AAS, except that for parallel execution, multiple AAS at the same second will be counted as 1, not n      |
 |DB-Time    | Value = sum(<tm_delta_db_time>)                                                                                      |
 |-          | -                                                                                                                    |
 |CPU%       | Value = 100 * <AAS for ON CPU> / AAS                                                                                 |
 |IO%        | Value = 100 * <AAS for Sytem*User IO Waits> / AAS                                                                    |
 |CL%        | Value = 100 * <AAS for Cluster Waits> / AAS                                                                          |
 |CC%        | Value = 100 * <AAS for Concurrency Waits> / AAS                                                                      |
 |APP%       | Value = 100 * <AAS for Application Waits> / AAS                                                                      |
 |ADM%       | Value = 100 * <AAS for Administrative Waits> / AAS                                                                   |
 |CFG%       | Value = 100 * <AAS for Configuration Waits> / AAS                                                                    |
 |SCH%       | Value = 100 * <AAS for Scheduler Waits> / AAS                                                                        |
 |NET%       | Value = 100 * <AAS for Network Waits> / AAS                                                                          |
 |OTH%       | Value = 100 * <AAS for the Waits that none of above classes> / AAS                                                   |
 |PLSQL      | Value = 100 * <AAS for 'x'> / AAS, of which 'x' is the waits for PL/SQL & Java & recursive calls                     | 
 |Blks       | For table/index scans, return the est blocks; otherwise returns the IO-Cost                                          |
 |Pred       | Search columns, indicating the #columns for the access/filter predicates                                             |
 |-          | -                                                                                                                    |
 |IO-Reqs    | value = sum(<DELTA_READ_IO_REQUESTS>+<DELTA_WRITE_IO_REQUESTS>) / <Execs>                                            |
 |IO-Bytes   | value = sum(<DELTA_INTERCONNECT_IO_BYTES>) / <Execs>                                                                 |
 |PGA        | value = max(<PGA_ALLOCATED>) based on each plan line when <IS_SQLID_CURRENT> = 'Y'                                   |
 |Temp       | value = max(<TEMP_SPACE_ALLOCATED>) based on each plan line when <IS_SQLID_CURRENT> = 'Y'                            |
 |-          | -                                                                                                                    |
 |Top Events | The top (5) events in the group. Format: [<AAS%>]<Event> or <Event>(AAS%)                                            |
 |Top Lines  | The top 5 plan lines of the wait.Format: <#line>(AAS%) [,...]                                                        |
 |Top Objects| The top 5 plan lines of the wait.Format: <object>(AAS%) [/...], of which "object" can be object id/name/etc          |
|]


--[[
    @ARGS: 1
    &V1  : 0={}
    &V2  : 0={}
    &V3  : default={&starttime}
    &V4  : default={&endtime}
    @adaptive : 19={+ADAPTIVE +REPORT -hint_report -QBREGISTRY} 12.1={+ADAPTIVE +REPORT} default={}
    @phf : 12.1={decode('&V1',sql_id,''||sql_full_plan_hash_value,top_level_sql_id,sql_id,''||sql_full_plan_hash_value)} default={decode('&V1',sql_id,''||sql_plan_hash_value,top_level_sql_id,sql_id,''||sql_plan_hash_value)}
    @phf1: 12.1={,''||nullif(sql_full_plan_hash_value,0)} default={}
    @phf2: 12.1={nvl2(other_xml,to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'')} default={null}
    @adp : 12.1={case when instr(other_xml, 'adaptive_plan') > 0 then 'Y' else 'N' end} default={'N'}
    @con : 12.1={,con_dbid} default={}
    @mem : 12.1={DELTA_READ_MEM_BYTES} default={null}
    @cdb2: 12.1={con_dbid} default={1e9}
    @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_} pdb={AWR_PDB_}
    @check_access_aux: default={(26/8/12)-6}
    &dplan: default={&check_access_pdb.sql_plan} sqlset={(select a.*,0+null object#,&dbid dbid from all_sqlset_plans a)}
    &cid  : default={dbid} sqlset={sqlset_id}
    &src1 : default={&check_access_pdb.sql_plan} sqlset={all_sqlset_plans}
    &top1: default={ev}, O={CURR_OBJ#}
    &top2: default={CURR_OBJ#}, O={ev}
    &vw  : default={A} G={G} D={D} sqlset={D}
    &Title: default={Objects}, O={Events}
    &titl2: default={Events}, O={Objects}
    &fmt: default={-outline} fmt={} s={-outline -rows -parallel}
    &simple: default={1} s={0}
    &src_ash:  default={a} all={b}
    &hierachy: {
        default={1 lv,
                nvl(sql_id,top_level_sql_id) sql_id,
                sql_exec_id sql_exec_id_,
                sql_exec_start sql_exec_start_,
                nvl(sql_plan_hash_value,0) phv1,
                sql_plan_line_id,
                sql_plan_operation||' '||sql_plan_options operation,
                &phf plan_hash_full,
                pred_flag} 
           all={level lv,
                connect_by_root(nvl(sql_id,top_level_sql_id)) sql_id,
                connect_by_root(sql_exec_id) sql_exec_id_,
                connect_by_root(sql_exec_start) sql_exec_start_,
                coalesce(case when pred_flag!=2 then nullif(sql_plan_hash_value,0) end,connect_by_root(sql_plan_hash_value),0) phv1,
                coalesce(case when pred_flag!=2 then nullif(case when sql_plan_line_id>65535 then 0 else sql_plan_line_id end,0) end,connect_by_root(sql_plan_line_id),0) sql_plan_line_id,
                coalesce(case when pred_flag!=2 then case when sql_plan_line_id>65535 then null else sql_plan_operation||' '||sql_plan_options end  end,connect_by_root( sql_plan_operation||' '||sql_plan_options)) operation,
                coalesce(case when pred_flag!=2 then nullif(&phf,'0')  end,connect_by_root(&phf),'0') plan_hash_full,
                connect_by_root(pred_flag) pred_flag}
    }

    &gash: {
        default={(select a.*,sql_exec_id sql_exec_id_,sql_exec_start sql_exec_start_ from gash a)},
        all={
            SELECT /*+ordered use_hash(a) no_merge(b) monitor*/*
            FROM   (SELECT service_hash  &con,machine, decode(port,0,session_id*inst_id*10,port) port_,stime,
                           min(sql_exec_id)    KEEP(dense_rank FIRST ORDER BY nvl2(sql_exec_id,1,2),instr(program,'(P')) sql_exec_id_,
                           min(sql_exec_start) KEEP(dense_rank FIRST ORDER BY nvl2(sql_exec_start,1,2),instr(program,'(P')) sql_exec_start_
                    FROM   gash a 
                    GROUP  BY service_hash  &con, machine, decode(port,0,session_id*inst_id*10,port),stime) b
            JOIN (
                SELECT /*+ OPT_ESTIMATE(QUERY_BLOCK ROWS=30000000) use_hash(@GV_ASHV A@GV_ASHV)
                           full(a.a) leading(a.a) use_hash(a.a a.s) swap_join_inputs(a.s)
                           full(A.GV$ACTIVE_SESSION_HISTORY.A)
                           leading(A.GV$ACTIVE_SESSION_HISTORY.A)
                           use_hash(A.GV$ACTIVE_SESSION_HISTORY.A A.GV$ACTIVE_SESSION_HISTORY.S)
                           swap_join_inputs(A.GV$ACTIVE_SESSION_HISTORY.S)
                       */ *
                FROM gv$active_session_history a) a
            USING  (service_hash &con,machine) 
            WHERE  a.sample_time+0=b.stime
            AND    decode(port,0,session_id*inst_id*10,port)=port_
            AND   '&vw' IN('A','G')
        }
    }
    &dash: {
        DEFAULT={(SELECT a.*,sql_exec_id sql_exec_id_,sql_exec_start sql_exec_start_ FROM dash a)},
        ALL={
            SELECT /*+ordered use_hash(a) no_merge(b) PX_JOIN_FILTER(a)*/ *
            FROM   (SELECT dbid, service_hash  &con,machine, decode(port,0,session_id*instance_number*10,port) port_,stime,
                           min(sql_exec_id)    KEEP(dense_rank FIRST ORDER BY nvl2(sql_exec_id,1,2),instr(program,'(P')) sql_exec_id_,
                           min(sql_exec_start) KEEP(dense_rank FIRST ORDER BY nvl2(sql_exec_start,1,2),instr(program,'(P')) sql_exec_start_
                    FROM   dash a 
                    GROUP  BY dbid, service_hash  &con, machine, decode(port,0,session_id*instance_number*10,port),stime) b
            JOIN  (
                SELECT /*+
                        FULL(D.ASH) FULL(D.EVT) swap_join_inputs(D.EVT) PX_JOIN_FILTER(D.ASH)
                        full(D.&check_access_pdb.ACTIVE_SESS_HISTORY.ASH)
                        full(D.&check_access_pdb.ACTIVE_SESS_HISTORY.EVT)
                        swap_join_inputs(D.&check_access_pdb.ACTIVE_SESS_HISTORY.EVT)
                        PX_JOIN_FILTER(D.&check_access_pdb.ACTIVE_SESS_HISTORY.ASH)
                        index_Stats(SYS.WRH$_ACTIVE_SESSION_HISTORY WRH$_ACTIVE_SESSION_HISTORY_PK SET BLOCKS=3000000)
                        table_Stats(SYS.WRH$_ACTIVE_SESSION_HISTORY SET rows=30000000)
                        full(d.AWR_CDB_ACTIVE_SESS_HISTORY.ash) 
                        full(d.AWR_PDB_ACTIVE_SESS_HISTORY.ash)
                       */ *
                FROM &check_access_pdb.active_sess_history d) a
            USING  (dbid,service_hash &con,machine)
            WHERE  to_date(floor(to_char(sample_time,'YYMMDDSSSSS')/10)*10,'YYMMDDSSSSS')=b.stime
            AND    decode(port,0,session_id*instance_number*10,port)=b.port_
            AND    dbid=&dbid
            AND   '&vw' IN('A','D')
        }
    }

    &public: {DEFAULT={ aas_,
                        dbid,
                        instance_number inst_id,
                        nvl(qc_instance_id,instance_number) qc_inst,
                        session_id sid,
                        nvl(qc_session_id,session_id) qc_sid,
                        qc_session_serial#,
                        current_obj#,
                        p1,
                        p2,
                        p3,
                        p1text,
                        p2text,
                        p3text,
                        event,
                        wait_class,
                        mem,
                        tm_delta_time,
                        tm_delta_db_time,
                        delta_time,
                        in_parse,
                        delta_read_io_requests,delta_write_io_requests,delta_interconnect_io_bytes,
                        in_plsql_execution,in_plsql_rpc,in_plsql_compilation,in_java_execution,decode(is_sqlid_current,'Y','N','Y') is_not_current,
                        sample_time,
                        stime,
                        sample_id,
                        px_flags,
                        sql_opname,
                        trim(decode(bitand(time_model,power(2, 3)),0,'','connection_mgmt ') || 
                             decode(bitand(time_model,power(2, 4)),0,'','parse ') || 
                             decode(bitand(time_model,power(2, 7)),0,'','hard_parse ') || 
                             decode(bitand(time_model,power(2,15)),0,'','bind ') || 
                             decode(bitand(time_model,power(2,16)),0,'','cursor_close ') || 
                             decode(bitand(time_model,power(2,17)),0,'','sequence_load ') || 
                             decode(bitand(time_model,power(2,18)),0,'','inmemory_query ') || 
                             decode(bitand(time_model,power(2,19)),0,'','inmemory_populate ') || 
                             decode(bitand(time_model,power(2,20)),0,'','inmemory_prepopulate ') || 
                             decode(bitand(time_model,power(2,21)),0,'','inmemory_repopulate ') || 
                             decode(bitand(time_model,power(2,22)),0,'','inmemory_trepopulate ') || 
                             decode(bitand(time_model,power(2,23)),0,'','tablespace_encryption ')) time_model,
                        decode(is_sqlid_current,'Y',pga_allocated) pga_,
                        decode(is_sqlid_current,'Y',temp_space_allocated) temp_,
                        nvl(trunc(px_flags / 2097152),0) dop_,
                        1 lv,
                        nvl(sql_id,top_level_sql_id) sql_id,
                        sql_exec_id_,
                        sql_exec_start_,
                        nvl(sql_plan_hash_value,0) phv1,
                        sql_plan_line_id,
                        sql_plan_operation||' '||sql_plan_options operation,
                        &phf plan_hash_full,
                        pred_flag}
    }
--]]
]]*/
set feed off printsize 10000 pipequery off
WITH gash AS(
    SELECT /*+inline merge(a) OPT_ESTIMATE(QUERY_BLOCK ROWS=1000000)*/
            a.*,sample_time+0 stime
    FROM   gv$active_session_history a
    WHERE  userenv('instance')=nvl(:instance,userenv('instance'))
    AND    sample_time+0 BETWEEN nvl(to_date('&V3','YYMMDDHH24MISS'),sysdate-7) AND nvl(to_date('&V4','YYMMDDHH24MISS'),sysdate)
    AND    '&V1' IN(sql_id,top_level_sql_id,''||force_matching_signature,''||sql_plan_hash_value &phf1)
    AND    nvl(0+regexp_substr('&V2','^\d+$'),0) IN(0,sql_exec_id,nullif(sql_plan_hash_value,0) &phf1)
    AND   '&vw' IN('A','G')),
dash AS(
    SELECT d.*,
           to_date(floor(to_char(sample_time,'YYMMDDSSSSS')/10)*10,'YYMMDDSSSSS') stime
    FROM   &check_access_pdb.active_sess_history d
    WHERE  '&vw' IN('A','D')
    AND    dbid=&dbid
    AND    '&V1' IN(sql_id,top_level_sql_id,''||force_matching_signature,''||sql_plan_hash_value &phf1)
    AND    nvl(0+regexp_substr('&V2','^\d+$'),0) IN(0,sql_exec_id,nullif(sql_plan_hash_value,0) &phf1)
    AND    sample_time BETWEEN nvl(to_date('&V3','YYMMDDHH24MISS'),sysdate-7) AND nvl(to_date('&V4','YYMMDDHH24MISS'),sysdate+1)),
ash_raw AS (
    SELECT /*+MATERIALIZE qb_name(ash_raw) NO_DATA_SECURITY_REWRITE opt_estimate(query_block rows=3000000)*/ h.*,
            nvl(event,'ON CPU')||decode(in_parse,'Y',' [PARSE]') ev,
            nvl(wait_class,'ON CPU') wl,
            nvl(nullif(plan_hash_full,'0'),''||phv1) phf,
            max(CASE WHEN pred_flag!=2 OR is_px_slave=1 THEN dop_ END)  OVER(PARTITION BY dbid,phv1,sql_exec,pid) dop,
            sum(CASE WHEN p3text='block cnt' THEN temp_ END) OVER(PARTITION BY dbid,phv1,sql_exec,pid,stime) temp,
            sum(pga_)  OVER(PARTITION BY dbid,phv1,sql_exec,pid,stime) pga
    FROM   (SELECT a.*, --seq: if ASH and DASH have the same record, then use ASH as the standard
                   row_number() OVER(PARTITION BY dbid,stime,inst_id,sid ORDER BY aas_,lv DESC) seq,
                   --sec_seq: multiple PX processes at the same second will be treated as on second 
                   row_number() OVER(PARTITION BY dbid,phv1,sql_plan_line_id,operation,stime,qc_inst,qc_sid ORDER BY aas_,lv DESC,tm_delta_db_time DESC) sec_seq,
                   nvl(CASE WHEN sql_plan_line_id>65535 THEN 0 ELSE sql_plan_line_id END,0) pid,
                   nvl(''||sql_exec_id_,'@'||qc_inst||','||qc_sid||','||qc_session_serial#)||','||to_char(sql_exec_start_,'yyyymmddhh24miss') sql_exec,
                   CASE WHEN (qc_sid!=sid OR qc_inst!=inst_id) THEN 1 ELSE 0 END is_px_slave,
                   CASE WHEN 'Y' IN(decode(pred_flag,2,'Y','N'),is_not_current,in_plsql_execution,in_plsql_rpc,in_plsql_compilation,in_java_execution) THEN 1 END in_plsql       
            FROM   (
                SELECT  &public
                FROM    (
                    SELECT 
                            a.*,inst_id instance_number,&dbid dbid,1 aas_,&mem mem,
                            0 snap_id,decode('&V1',nvl(sql_id,top_level_sql_id),1,top_level_sql_id,2,3) pred_flag
                    FROM  (&gash) a
                    ) a
                WHERE 1=1 
                UNION ALL
                SELECT  &public
                FROM    (SELECT a.*, 10 aas_,NULL mem,decode('&V1',sql_id,1,top_level_sql_id,2,3) pred_flag
                         FROM   (&dash) a
                         ) a
                WHERE 1=1
                )a) h
    WHERE  seq = 1),
sql_list AS(SELECT /*+MATERIALIZE*/ DISTINCT sql_id,phv1 plan_hash_value,dbid,count(1) OVER(PARTITION BY dbid,phv1,sql_id) cnt FROM ash_raw WHERE sql_id IS NOT NULL AND (phv1>0 OR sql_opname='INSERT')),
all_plans AS(
    SELECT  /*+MATERIALIZE OPT_PARAM('_fix_control' '26552730:0') opt_estimate(query_block rows=100000) no_parallel*/
            h.dbid,
            extractvalue(column_value,'//ID')+0 id,
            extractvalue(column_value,'//PARENT_ID')+0 parent_id,
            extractvalue(column_value,'//INST_ID')+0 inst_id,
            extractvalue(column_value,'//HA')+0 ha,
            extractvalue(column_value,'//FLAG')+0 flag,
            extractvalue(column_value,'//CHILD_NUMBER')+0 child_number,
            extractvalue(column_value,'//SQL_ID') sql_id,
            extractvalue(column_value,'//PHV')+0 phv,
            extractvalue(column_value,'//OBJ')+0 object#,
            extractvalue(column_value,'//POS')+0 pos,
            nullif(extractvalue(column_value,'//SC'),'0')  ac,
            extractvalue(column_value,'//AP') ap,
            extractvalue(column_value,'//FP') fp,
            extractvalue(column_value,'//IO_COST')+0 io_cost,
            extractvalue(column_value,'//DF_DOP')+0 df_dop,
            extractvalue(column_value,'//MBRC')+0 mbrc,
            extractvalue(column_value,'//OBJECT_NAME') object_name,
            replace(extractvalue(column_value,'//OBJECT_ALIAS'),'"') alias,
            extractvalue(column_value,'//TM') tm,
            extractvalue(column_value,'//OPERATION') operation,
            extractvalue(column_value,'//PLAN_HASH_FULL') plan_hash_full,
            extractvalue(column_value,'//IS_ADAPTIVE_')+0 is_adaptive_,
            extractvalue(column_value,'//CID')+0 cid
    FROM    (SELECT a.*,row_number() OVER(PARTITION BY plan_hash_value,dbid ORDER BY cnt DESC) plan_seq
             FROM   sql_list a) h,
            TABLE(xmlsequence(extract(dbms_xmlgen.getxmltype(q'!
                SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/ * 
                FROM (SELECT a.*,dense_rank() OVER(ORDER BY flag,inst_id) seq
                FROM (
                    SELECT id,
                           decode(parent_id,-1,id-1,parent_id) parent_id,
                           child_number    ha,
                           1               flag,
                           to_char(TIMESTAMP,'YYYY-MM-DD HH24:MI:SS') tm,
                           child_number,
                           sql_id,
                           nvl(plan_hash_value,0) phv,
                           inst_id,
                           object# obj,
                           object_name,
                           object_alias,
                           position pos,
                           object_node tq,operation||' '||options operation,
                           &phf2 plan_hash_full,
                           instr(other_xml,'adaptive_plan') is_adaptive_,
                           io_cost,access_predicates ap,filter_predicates fp,search_columns sc,
                           max(nvl2(other_xml,round(regexp_substr(regexp_substr(to_char(substr(other_xml,1,512)),'<info type="dop" note="y">\d+</info>'),'\d+')/1.1111,4),1)) OVER(PARTITION BY inst_id,child_number) df_dop,
                           &g_mbrc mbrc,
                           1e9 cid,
                           &dbid dbid 
                    FROM   gv$sql_plan a 
                    WHERE '&vw' IN('A','G')
                    AND    a.sql_id='!'|| h.sql_id ||'''
                    AND    a.plan_hash_value='||h.plan_hash_value||q'!
                    UNION ALL
                    SELECT  id,
                            decode(parent_id,-1,id-1,parent_id) parent_id,
                            plan_hash_value ha,
                            2 flag,
                            to_char(TIMESTAMP,'YYYY-MM-DD HH24:MI:SS') tm,
                            NULL child_number,
                            sql_id,
                            nvl(plan_hash_value,0) phv,
                            &cid inst_id,
                            object# obj,
                            object_name,
                            object_alias,
                            position pos,
                            object_node tq,operation||' '||options operation,
                            &phf2 plan_hash_full,
                            instr(other_xml,'adaptive_plan') is_adaptive_,
                            io_cost,access_predicates ap,filter_predicates fp,search_columns sc,
                            max(nvl2(other_xml,regexp_substr(regexp_substr(to_char(substr(other_xml,1,512)),'<info type="dop" note="y">\d+</info>'),'\d+')/1.1111,1)) OVER(PARTITION BY plan_hash_value) df_dop,
                            &d_mbrc mbrc,
                            &cdb2 cid,
                            dbid
                    FROM    &dplan a
                    WHERE  '&vw' IN('A','D')
                    AND    a.sql_id='!'|| h.sql_id ||'''
                    AND    a.plan_hash_value='||h.plan_hash_value||'
                    AND    a.dbid='||h.dbid||') a
                ) WHERE SEQ=1 ORDER BY ID'), '//ROW'))) b
    WHERE plan_seq<=10),
sql_plan_data AS
 (SELECT * FROM
     (SELECT a.*,
             nvl(max(plan_hash_full) OVER(PARTITION BY phv),phv) phf,
             nvl(max(sign(is_adaptive_)) OVER(PARTITION BY phv),0) is_adaptive,
             dense_rank() OVER(PARTITION BY phv ORDER BY flag, tm DESC, child_number DESC NULLS FIRST, inst_id DESC,dbid,sql_id) seq
      FROM   all_plans a
      WHERE  id IS NOT NULL)
  WHERE  seq = 1),
sqlstats AS(
    SELECT /*+MATERIALIZE qb_name(sqlstats)*/ 
            dbid,sql_id,
            nvl(plan_hash_value,-1) phv,
            sum(executions_delta) exec_,
            round(sum(elapsed_time_delta) * 1e-6, 2) ela,
            round(sum(elapsed_time_delta) * 1e-3 /
                    decode(sum(executions_delta),
                            0,
                            nullif(floor(sum(parse_calls_delta) / greatest(1, sum(px_servers_execs_delta))), 0),
                            sum(executions_delta)),
                    3) avg_
    FROM   sql_list 
    JOIN   &check_access_pdb.sqlstat USING (sql_id,plan_hash_value,dbid)
    JOIN   &check_access_pdb.snapshot USING(dbid,snap_id,instance_number)
    WHERE  elapsed_time_delta>0
    AND    dbid=nvl(0+'&dbid',dbid)
    AND    end_interval_time+0 BETWEEN nvl(to_date('&V3','YYMMDDHH24MISS'),sysdate-7) AND nvl(to_date('&V4','YYMMDDHH24MISS'),sysdate+1)
    GROUP  BY dbid,sql_id, ROLLUP(plan_hash_value)
),
ash_aas  AS(
    SELECT /*+MATERIALIZE qb_name(ASH_AAS)*/ a.*,decode(sec_seq,1,aas) cost
    FROM (
    SELECT a.*,
           decode(aas_,1,1,decode((
                SELECT sign(max(avg_) KEEP(dense_rank LAST ORDER BY phv1)- 5e3) flag 
                FROM   sqlstats b 
                WHERE  a.sql_id=b.sql_id 
                AND    b.phv IN(a.phv1,-1)
            ),1,10,1)) aas
    FROM   ash_raw a) a),
ash_phvs AS(SELECT /*+qb_name(ash_phvs) MATERIALIZE use_hash_aggregation*/phv1 phv,max(phf) phf,sum(cost) cost,sum(aas) aas FROM ash_aas GROUP BY phv1),
ash_phv_agg AS(
    SELECT  /*+MATERIALIZE qb_name(ash_phv_agg)*/ a.* 
    FROM (
        SELECT  phv phv1,
                is_adaptive,
                nvl(b.phf,a.phf) phfv,
                100*sum(cost) OVER(PARTITION BY nvl(b.phf,a.phf))/sum(cost) OVER() phf_rate,
                100*ratio_to_report(cost) OVER() phv_rate,
                first_value(phv) OVER(PARTITION BY nvl(b.phf,a.phf) ORDER BY nvl2(b.phf,0,1),cost DESC,aas DESC) phv,
                listagg(phv,',') WITHIN GROUP(ORDER BY cost DESC,aas DESC) OVER(PARTITION BY nvl(b.phf,a.phf)) phvs,
                count(1) OVER(PARTITION BY nvl(b.phf,a.phf)) phv_cnt,
                max(nvl2(b.phf,1,0)) OVER(PARTITION BY  nvl(b.phf,a.phf)) plan_exists
        FROM ash_phvs a 
        LEFT JOIN (SELECT DISTINCT phv,phf,is_adaptive FROM sql_plan_data) b USING(phv)) a
    WHERE phv_rate>=0.1),
hr AS((SELECT /*+MATERIALIZE qb_name(hr) opt_estimate(query_block rows=100000)*/ 
              DISTINCT id, parent_id pid, phv,operation,alias,io_cost,pos,ac,ap,fp,df_dop,mbrc,
              max(id) OVER(PARTITION BY phv) AS maxid 
       FROM sql_plan_data 
       WHERE phv IN(SELECT phv FROM ash_phv_agg WHERE plan_exists=1))),
hierarchy_data AS
 (SELECT /*+CONNECT_BY_COMBINE_SW*/ hr.*,ROWNUM rn
  FROM   hr
  START  WITH id = 0
  CONNECT BY PRIOR id = pid AND phv=PRIOR phv 
  ORDER  siblings BY pos DESC,id DESC),
ordered_hierarchy_data AS
 (SELECT /*+materialize*/ a.*,
         CASE 
             WHEN nvl(ap,ac) IS NOT NULL THEN 'A'
         END||CASE 
             WHEN ac IS NOT NULL THEN ac
             WHEN ap IS NOT NULL THEN 
               (SELECT ''||count(DISTINCT regexp_substr(replace(ap,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,LEVEL,'i',2))
                FROM   dual
               CONNECT BY regexp_substr(replace(ap,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,LEVEL) IS NOT NULL)
         END||CASE 
             WHEN fp IS NOT NULL THEN
             (SELECT 'F'||count(DISTINCT regexp_substr(replace(fp,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,LEVEL,'i',2))
              FROM dual
              CONNECT BY regexp_substr(replace(fp,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,LEVEL) IS NOT NULL) 
         END sc
  FROM  (SELECT a.*,
                '"'||regexp_substr(nvl(alias,first_value(alias IGNORE NULLS) OVER(PARTITION BY phv ORDER BY rn ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)),'[^@]+')||'".' al,
                row_number() OVER(PARTITION BY phv ORDER BY rn DESC) AS oid
         FROM   hierarchy_data a) a),
qry AS
 ( SELECT DISTINCT sql_id sq,
         flag flag,
         'ADVANCED IOSTATS METRICS -PEEKED_BINDS -cost -bytes -alias -projection &adaptive &fmt' format,
         phv phv,
         coalesce(child_number, 0) child_number,
         inst_id,
         dbid,
         cid
  FROM   sql_plan_data
  WHERE  phv IN(SELECT phv FROM ash_phv_agg WHERE plan_exists=1)),
xplan AS
 (  SELECT phv,ROWNUM r,a.*
    FROM   qry, TABLE(dbms_xplan.display('&src1',NULL,format,'&cid='||inst_id||' and &cdb2='||cid||' and plan_hash_value=' || phv || ' and sql_id=''' || sq ||'''')) a
    WHERE  flag = 2
    UNION ALL
    SELECT phv,ROWNUM,a.*
    FROM   qry, TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'inst_id='|| inst_id||' and plan_hash_value=' || phv || ' and sql_id=''' || sq ||''' and child_number='||child_number)) a
    WHERE  flag = 1),
ash_agg AS(
    SELECT /*+MATERIALIZE qb_name(ash_agg)*/ 
           a.*, 
           nvl2(costs,trim(dbms_xplan.format_number(costs))||'('||to_char(ratio,CASE WHEN ratio=10 THEN '990' ELSE 'fm990.0' END)||'%)','') cost_rate,
           trim(dbms_xplan.format_number(costs)) cost_text,
           trim(dbms_xplan.format_number(aas)) aas_text,
           trim(dbms_xplan.format_number(io_reqs_/execs)) io_reqs,
           trim(dbms_xplan.format_size(io_bytes_/execs)) io_bytes,
           trim(dbms_xplan.format_size(buf_/execs)) buf,
           trim(dbms_xplan.format_size(pga_)) pga,
           trim(dbms_xplan.format_size(temp_)) temp,
           CASE 
                WHEN nvl(secs_,0) <= 0 THEN ' '
                WHEN secs_<  1     THEN round(secs_*1e3)||'ms'
                WHEN secs_<100     THEN round(secs_,2)||'s'
                WHEN secs_<500     THEN round(secs_,1)||'s'
                WHEN secs_<6e3     THEN round(secs_/60,2)||'m'
                WHEN secs_<6e3*5   THEN round(secs_/60,1)||'m'
                WHEN secs_<72*3600 THEN round(secs_/3600,2)||'h'
                ELSE round(secs_/86400,2)||'d'
           END secs
    FROM (
        SELECT a.*, first_value('['||lpad(round(100*aas/aas1,1),4)||'%] '||grp) 
                   OVER(PARTITION BY phv,subtype,sub ORDER BY decode(grp,'-1',1,NULL,2,0),aas DESC,decode(grp,'ON CPU','Z',grp)) top_grp, 
               listagg(CASE WHEN seq<=5 AND sub IS NOT NULL THEN sub||'('||round(100*aas/aas0,1)||'%)' END,' / ') 
                   WITHIN GROUP(ORDER BY seq) OVER(PARTITION BY phv,grp,subtype)  top_list,
               round(100*ratio_to_report(costs) OVER(PARTITION BY decode(g,8,NULL,phv),gid,g,subtype),1) ratio,
               decode(g,8,phv_rate,round(100*ratio_to_report(aas) OVER(PARTITION BY phv,gid,g,subtype),1)) aas_rate
        FROM (
            SELECT a.*,
                max(aas) OVER(PARTITION BY phv,grp) aas0,
                max(aas) OVER(PARTITION BY phv,sub,subtype) aas1,
                row_number() OVER(PARTITION BY phv,gid,grp,subtype ORDER BY aas DESC,sub) seq
            FROM(
                SELECT --+NO_EXPAND_GSET_TO_UNION NO_USE_DAGG_UNION_ALL_GSETS
                    grouping_id(phv1,id,top2) gid,
                    CASE
                        WHEN grouping_id(phv1,top1) =1 THEN 8
                        WHEN grouping_id(id,top1) =1 THEN 4
                        WHEN grouping_id(top1,id) =1 THEN 2   
                        WHEN grouping_id(top1,top2) =1 THEN 1
                    END g,
                    grouping_id(phv1,top1) g1,
                    grouping_id(id,top1) g2,
                    grouping_id(top1,top2) g3,
                    decode(grouping_id(phv1, id,top2),3,sql_id||','||phv1,5,top1,top1) grp,
                    decode(grouping_id(phv1, id,top2),3,top1,5,''||id,top2) sub,
                    decode(grouping_id(phv1, id,top2),3,'E',5,'P','O') subtype,
                    phv,phv1,phvs,phfv,plan_exists, top1, top2,id,sql_id,
                    max(phf_rate) phf_rate,max(phv_rate) phv_rate,max(pred_flag) pred_flag,
                    max(dop) max_dop,min(nullif(dop,0)) min_dop,decode(sign(max(dop)),1,max(skew)) skew,
                    count(DISTINCT sql_exec) execs,
                    sum(secs) secs_,
                    sum(aas) aas,
                    sum(cost) costs,
                    round(sum(decode(wl, 'ON CPU', aas, 0))*100/ sum(aas), 1) "CPU",
                    round(sum(CASE WHEN wl IN ('User I/O','System I/O') THEN aas ELSE 0 END) * 100 / sum(aas), 1) "IO",
                    round(sum(decode(wl, 'Cluster', aas, 0)) * 100 / sum(aas), 1) "CL",
                    round(sum(decode(wl, 'Concurrency', aas, 0)) * 100 / sum(aas), 1) "CC",
                    round(sum(decode(wl, 'Application', aas, 0)) * 100 / sum(aas), 1) "APP",
                    round(sum(decode(wl, 'Scheduler', aas, 0)) * 100 / sum(aas), 1) "SCH",
                    round(sum(decode(wl, 'Administrative', aas, 0)) * 100 / sum(aas), 1) "ADM",
                    round(sum(decode(wl, 'Configuration', aas, 0)) * 100 / sum(aas), 1) "CFG",
                    round(sum(decode(wl, 'Network', aas, 0)) * 100 / sum(aas), 1) "NET",
                    round(sum(CASE WHEN wl IN ('Idle','Commit','Other','Queueing') THEN aas ELSE 0 END) * 100 / sum(aas), 1) oth,
                    round(sum(in_plsql*aas)* 100 / sum(aas), 1) plsql,
                    sum(delta_read_io_requests+delta_write_io_requests) io_reqs_,
                    sum(delta_interconnect_io_bytes) io_bytes_,
                    sum(mem) buf_,
                    max(pga) pga_,
                    max(temp) temp_,
                    min(sample_time) begin_time,
                    max(sample_time) end_time
                FROM (SELECT a.*, nvl(''||&top1,' ') top1,nvl(''||&top2,' ') top2,
                            decode(is_adaptive,1,nvl((SELECT min(id) FROM ordered_hierarchy_data b WHERE a.phv=b.phv AND b.id>=a.pid AND a.operation=b.operation),a.pid),a.pid) id,
                            nullif(round(100*stddev(dbtime) OVER(PARTITION BY px_flags,dbid,phv1,sql_exec,pid,qc_sid,qc_inst,qc_session_serial#)
                                    /greatest(avg(dbtime) OVER(PARTITION BY px_flags,dbid,phv1,sql_exec,pid,qc_sid,qc_inst,qc_session_serial#),5e6),2),0) skew
                    FROM (SELECT /*+ordered use_hash(b)*/ * 
                          FROM ash_phv_agg NATURAL JOIN (
                            SELECT  /*+use_hash(b c)*/ b.*,
                                   nvl(trim(CASE 
                                    WHEN current_obj# < -1 THEN
                                        'Temp I/O'
                                    WHEN current_obj# > 0 THEN 
                                        nvl(c.object_name,''||current_obj#) 
                                    WHEN p2text='id1' THEN
                                         ''||p2
                                    WHEN p3text IN('(identifier<<32)+(namespace<<16)+mode','100*mode+namespace') THEN 
                                         ''||trunc(p3/power(16,8))
                                    WHEN p3text LIKE '%namespace' AND p3>power(16,8)*4294950912 THEN
                                        'Undo'
                                    WHEN p3text LIKE '%namespace' AND p3>power(16,8) THEN 
                                        nvl(c.object_name,''||trunc(p3/power(16,8))) 
                                    WHEN p3text LIKE '%namespace' THEN 
                                        'X$KGLST#'||trunc(mod(p3,power(16,8))/power(16,4))
                                    WHEN p1text LIKE 'cache id' THEN 
                                        (SELECT parameter FROM v$rowcache WHERE cache#=p1 AND ROWNUM<2)
                                    WHEN event LIKE 'latch%' AND p2text='number' THEN 
                                        (SELECT name FROM v$latchname WHERE latch#=p2 AND ROWNUM<2)
                                    WHEN p3text='class#' THEN
                                        (SELECT class FROM (SELECT class, ROWNUM r FROM v$waitstat) WHERE r=p3 AND ROWNUM<2)
                                    WHEN p1text ='file#' AND p2text='block#' THEN 
                                        'file#'||p1||' block#'||p2
                                    WHEN p3text IN('block#','block') THEN 
                                        'file#'||dbms_utility.data_block_address_file(p3)||' block#'||dbms_utility.data_block_address_block(p3)    
                                    WHEN px_flags > 65536 THEN
                                        decode(trunc(mod(px_flags/65536, 32)),
                                               1,'[PX]Executing-Parent-DFO',     
                                               2,'[PX]Executing-Child-DFO',
                                               3,'[PX]Sampling-Child-DFO',
                                               4,'[PX]Joining-Group',      
                                               5,'[QC]Scheduling-Child-DFO',
                                               6,'[QC]Scheduling-Parent-DFO',
                                               7,'[QC]Initializing-Objects', 
                                               8,'[QC]Flushing-Objects',    
                                               9,'[QC]Allocating-Slaves', 
                                              10,'[QC]Initializing-Granules', 
                                              11,'[PX]Parsing-Cursor',   
                                              12,'[PX]Executing-Cursor',    
                                              13,'[PX]Preparing-Transaction',    
                                              14,'[PX]Joining-Transaction',  
                                              15,'[PX]Load-Commit', 
                                              16,'[PX]Aborting-Transaction',
                                              17,'[QC]Executing-Child-DFO',
                                              18,'[QC]Executing-Parent-DFO')
                                    WHEN current_obj#=0 THEN 'Undo'
                                    WHEN time_model IS NOT NULL THEN
                                        '['||time_model||']'
                                    --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                                    --when c.class is not null then c.class
                                END),''||current_obj#) curr_obj#,
                                decode(sec_seq,1,least(coalesce(tm_delta_db_time,delta_time,aas*1e6),coalesce(tm_delta_time,delta_time,aas*1e6),aas*2e6) * 1e-6) secs,
                                sum(CASE WHEN is_px_slave=1 AND px_flags>65536 THEN least(tm_delta_db_time,aas*2e6) END) OVER(PARTITION BY px_flags,dbid,phv1,sql_exec,pid,qc_sid,qc_inst,qc_session_serial#,sid,inst_id) dbtime
                            FROM ash_aas b,
                                 (SELECT /*+no_merge*/ DISTINCT object#,object_name FROM all_plans) c
                            WHERE c.object#(+)=decode(sign(current_obj#),1,current_obj#,trunc(p3/power(16,8))))) a
                    )
                GROUP BY phv,phvs,phfv,plan_exists,GROUPING SETS((phv1,sql_id),(phv1,sql_id,top1),id,(id,top1),top1,(top1,top2))) a) a
    ) a WHERE g IS NOT NULL
),
plan_agg AS(
    SELECT decode(plan_exists,1,'*',' ')||phv1 phv2,
           row_number() OVER(ORDER BY phf_rate DESC,costs DESC,aas DESC) r,
           row_number() OVER(PARTITION BY phv1 ORDER BY phf_rate DESC,costs DESC,aas DESC) r1,
           trim(dbms_xplan.format_number(b.exec_)) awr_exec,
           CASE 
                WHEN nvl(b.avg_,0) <= 0 THEN NULL
                WHEN b.avg_<  1   THEN b.avg_*1e3||'us'
                WHEN b.avg_<1e3   THEN round(b.avg_,1)||'ms'
                WHEN b.avg_<180e3 THEN round(b.avg_/1e3,2)||'s'
                WHEN b.avg_<6e6   THEN round(b.avg_/1e3/60,2)||'m'
                ELSE round(b.avg_/1e3/3600,2)||'h'
           END awr_ela,
           a.* 
    FROM   ash_agg a LEFT JOIN sqlstats b ON(a.sql_id=b.sql_id AND a.phv1=b.phv) 
    WHERE  g=8
),
plan_wait_agg AS(
    SELECT ROWNUM r,a.* 
    FROM (
        SELECT * FROM ash_agg NATURAL JOIN (SELECT phv,top1,replace(top_list,' / ',', ') top_lines FROM ash_agg WHERE subtype='P' AND seq=1) 
        WHERE gid=7 AND g=2 AND plan_exists=1
        ORDER BY phv,nvl(ratio,aas_rate) DESC,aas DESC,top1) a
),
plan_line_agg AS(
    SELECT /*+materialize no_expand no_merge(a) no_merge(b) qb_name(plan_line_agg)*/*
    FROM   ordered_hierarchy_data a
    LEFT   JOIN (SELECT a.* FROM ash_agg a WHERE g=4 AND plan_exists=1) b
    USING(phv,id)),
plan_line_xplan AS
 (SELECT /*+no_merge(x) use_hash(x o)  qb_name(plan_line_xplan)*/
       r,
       max(CASE WHEN nvl(x.id,-2)<0 THEN regexp_instr(x.plan_table_output,'\| *E\-Time *\|') END) OVER(PARTITION BY x.phv) etime,
       x.phv phv,
       x.plan_table_output AS plan_output,
       x.id,x.prefix,
       nvl(''||o.pid,' ') pid,nvl(''||o.oid,' ') oid,o.maxid,
       nvl(o.alias,' ') alias,
       sc,
       cpu,io,cc,cl,app,oth,adm,cfg,sch,net,plsql,cost_text,aas_text,execs,
       nvl(cost_rate,' ') cost_rate,
       secs,o.min_dop,o.max_dop,o.skew,o.buf,o.io_reqs,o.io_bytes,o.pga,o.temp,
       nvl(top_grp,' ') top_grp,
       nvl(trim(dbms_xplan.format_number(CASE 
               WHEN regexp_like(x.plan_table_output,'(TABLE ACCESS [^|]*(FULL|SAMPLE)|INDEX .*FAST FULL)') THEN
                   greatest(1,floor(io_cost*nvl(df_dop,1)/nvl(mbrc,0.271)))
               ELSE
                   io_cost
           END)),' ') blks,
       '| Plan Hash Value(Full): '||max(phfv) OVER(PARTITION BY x.phv)
       ||decode(min(min_dop) OVER(PARTITION BY x.phv),
               NULL,'',
               max(max_dop) OVER(PARTITION BY x.phv),'    DoP: '||max(max_dop) OVER(PARTITION BY x.phv),
               '    DoP: '||min(min_dop) OVER(PARTITION BY x.phv)||'-'||max(max_dop) OVER(PARTITION BY x.phv))
       ||'    Period: ['||to_char(min(begin_time) OVER(PARTITION BY x.phv),'yyyy/mm/dd hh24:mi:ss') ||' -- '
            ||to_char(max(end_time) OVER(PARTITION BY x.phv),'yyyy/mm/dd hh24:mi:ss')||']' time_range,
       '| Plan Hash Value(s)   : '||max(phvs) OVER(PARTITION BY x.phv) phvs
  FROM  (SELECT x.*,
                nvl(regexp_substr(prefix,'\d+')+0,least(-1,r-min(nvl2(regexp_substr(prefix,'\d+'),r,NULL)) OVER(PARTITION BY phv))) id
         FROM   (SELECT x.*,regexp_substr(x.plan_table_output, '^\|[-\* ]*([0-9]+|Id) +\|') prefix FROM xplan x) x) x
  LEFT OUTER JOIN plan_line_agg o
  ON   x.phv = o.phv AND x.id = o.id),
agg_data AS(
  SELECT 'line' flag,phv,r,id,''||oid oid,alias,blks,sc,'' full_hash,
         ''||secs secs,''||cost_rate cost_rate,aas_text aas,cost_text costs,''||execs execs,decode(min_dop,NULL,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,skew,
         ''||cpu cpu,''||io io,''||cl cl,''||cc cc,''||app app,''||adm adm,''||cfg cfg,''||sch sch,''||net net,''||oth oth,''||plsql  plsql,buf,io_reqs ioreqs,io_bytes iobytes,pga,temp,
         decode(&simple,1,top_grp) top_list,'' top_list2,NULL pred_flag,NULL awr_exec,NULL awr_ela
  FROM plan_line_xplan
  UNION ALL
  SELECT 'phv' flag,-1,r,rid,''||phv2 oid,'' alias,'' blks,NULL sc,decode(pred_flag,3,sql_id,2,sql_id,''||phfv),
         ''||secs secs,''|| cost_rate,aas_text aas,cost_text costs,''||execs execs,decode(min_dop,NULL,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,skew,
         ''||cpu cpu,''||io io,''||cl cl,''||cc cc,''||app app,''||adm adm,''||cfg cfg,''||sch sch,''||net net,''||oth oth,''||plsql  plsql,buf,io_reqs,io_bytes,pga,temp,
         ''||top_list,'',pred_flag,awr_exec,awr_ela
  FROM  plan_agg a,(SELECT ROWNUM-3 rid FROM dual CONNECT BY ROWNUM<=3)
  UNION ALL
  SELECT 'wait' flag,phv,r,rid,''||top1 oid,'' alias,'' blks,NULL sc,'' phfv,
         ''||secs secs,''|| cost_rate,aas_text aas,cost_text costs,''||execs execs,decode(min_dop,NULL,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,skew,
         '' cpu,'' io,'' cl,'' cc,'' app,'' adm,'' cfg,'' sch,'' net,'' oth,''  plsql,buf,io_reqs,io_bytes,pga,temp,
         ''||top_list,''||top_lines,NULL pred_flag,NULL awr_exec,NULL awr_ela
  FROM  plan_wait_agg a,(SELECT ROWNUM-3 rid FROM dual CONNECT BY ROWNUM<=3)
),

plan_line_widths AS(
    SELECT a.*,swait+swait2+sdop + sskew + csize + rate_size + ssec + sexe + saas + scpu + sio + scl + scc + sapp + ssch +scfg + sadm + snet + soth + splsql + sbuf + sioreqs + siobytes +spga +stemp+sawrela+sawrexec+ 6 widths
    FROM( 
       SELECT  flag,phv,
               nvl(greatest(max(length(oid)) + 1, 5),0) AS csize,
               nvl(greatest(max(length(alias)) + 1, 6),0) AS calias,
               nvl(greatest(max(length(sc)) + 1, 5),0) AS csc,
               nvl(greatest(max(length(blks)) + 1, 6),0) AS cblks,
               nvl(greatest(max(length(trim(nullif(full_hash,oid)))), 11),0) AS shash,
               nvl(greatest(max(length(trim(secs)))+1, 8),0)*&simple AS ssec,
               nvl(greatest(max(length(trim(cost_rate))) + 1, 7),0) AS rate_size,
               nvl(greatest(max(length(nullif(aas,costs)))+1,7),0) AS saas,
               nvl(greatest(max(length(nullif(execs,'0'))) + 1, 5),0) AS sexe,
               nvl(greatest(max(length(nullif(dop,'0'))) + 2, 5),0) AS sdop,
               nvl(greatest(max(length(nullif(skew,0))) + 2, 6),0) AS sskew,
               nvl(greatest(max(length(nullif(cpu,'0'))) + 1, 5),0) AS scpu,
               nvl(greatest(max(length(nullif(io,'0'))) + 1, 5),0) AS sio,
               nvl(greatest(max(length(nullif(cl,'0'))) + 1, 5),0) AS scl,
               nvl(greatest(max(length(nullif(cc,'0'))) + 1, 5),0) AS scc,
               nvl(greatest(max(length(nullif(app,'0'))) + 1, 5),0) AS sapp,
               nvl(greatest(max(length(nullif(adm,'0'))) + 1, 5),0) AS sadm,
               nvl(greatest(max(length(nullif(cfg,'0'))) + 1, 5),0) AS scfg,
               nvl(greatest(max(length(nullif(sch,'0'))) + 1, 5),0) AS ssch,
               nvl(greatest(max(length(nullif(net,'0'))) + 1, 5),0) AS snet,
               nvl(greatest(max(length(nullif(oth,'0'))) + 1, 5),0) AS soth,
               nvl(greatest(max(length(nullif(plsql,'0'))) + 2, 6),0) AS splsql,
               nvl(greatest(max(length(nullif(buf,'0'))) + 1, 7),0)*&simple AS sbuf,
               nvl(greatest(max(length(nullif(ioreqs,'0'))) + 1, 8),0)*&simple AS sioreqs,
               nvl(greatest(max(length(nullif(iobytes,'0'))) + 1, 9),0)*&simple AS siobytes,
               nvl(greatest(max(length(nullif(pga,'0'))) + 1, 5),0)*&simple AS spga,
               nvl(greatest(max(length(nullif(temp,'0'))) + 2, 6),0)*&simple AS stemp,
               nvl(greatest(max(length(trim(top_list))) + 2, 10),0) AS swait,
               nvl(greatest(max(length(trim(top_list2))) + 2, 10),0) AS swait2,
               nvl(greatest(max(length(nullif(awr_exec,'0'))) + 1, 8),0) AS sawrexec,
               nvl(greatest(max(length(nullif(awr_ela,'0'))) + 1, 8),0) AS sawrela
         FROM  agg_data
         GROUP BY flag,phv) a),
format_info AS (
    SELECT flag,phv,r,widths,id,calias,csc,cblks,
       decode(id,
            -2,decode(flag,'line',lpad('Ord', csize),'phv','|'||lpad('Plan Hash ',csize),'|'||rpad('&titl2',csize)) || lpad(nvl2(regexp_substr('&V1','^\d+$'),'SQL Id  ','Full Hash'), shash) || ' |'
                ||decode(sawrexec+sawrela,0,'',lpad('AWR-Exes',sawrexec)||lpad('Avg-Ela',sawrela)||'|')
                ||lpad('DoP  ', sdop)|| lpad('Skew  ', sskew)|| lpad('Execs', sexe) || lpad('Secs', rate_size) || lpad('AAS', saas) || lpad('DB-Time', ssec) 
                ||nullif('|'||lpad('CPU%', scpu)  || lpad('IO%', sio) || lpad('CL%', scl) || lpad('CC%', scc) || lpad('APP%', sapp)
                            ||lpad('Sch%', ssch)  || lpad('Cfg%', scfg) || lpad('Adm%', sadm)|| lpad('Net%', snet)
                            ||lpad('OTH%', soth)  || lpad('PLSQL', splsql),'|')
                ||nullif('|'||lpad('Buffer',sbuf)||lpad('IO-Reqs',sioreqs)||lpad('IO-Bytes',siobytes)||lpad('PGA',spga)||lpad(' Temp',stemp),'|')
                ||nullif('|'||rpad(' Top Lines', swait2),'|') || nullif('|'||rpad(' Top '||decode(flag,'wait','&Title','&titl2'), swait),'|')||'|',
            -1, '+'||lpad('-',csize+shash+1,'-')||'+'
                ||decode(sawrexec+sawrela,0,'',lpad('-',sawrexec+sawrela,'-')||'+')
                ||lpad('-',sdop+sskew+sexe+rate_size+saas+ssec,'-')
                ||nullif('+'||lpad('-',scpu+sio+scl+scc+sapp+ssch+scfg+sadm+snet+soth+splsql,'-'),'+')
                ||nullif('+'||lpad('-',sbuf+sioreqs+siobytes+spga+stemp,'-'),'+')
                ||nullif('+'||rpad('-', swait2,'-'),'+') ||nullif('+'||lpad('-',swait,'-'),'+')||'+', 
           decode(flag,'line',lpad(oid, csize),'|'||rpad(oid,csize)) || lpad(nvl(full_hash,' '), shash) || ' |'
                ||decode(sawrexec+sawrela,0,'',lpad(nvl(awr_exec,' '),sawrexec)||lpad(nvl(awr_ela,' '),sawrela)||'|')
                ||lpad(dop||'  ', sdop)||lpad(skew||nvl2(nullif(skew,0),'%','')||' ', sskew)||lpad(nvl(execs,' '), sexe) || lpad(nvl(cost_rate,' '), rate_size) || lpad(nvl(aas,' '), saas) || lpad(nvl(secs,' '), ssec) 
                ||nullif('|'||lpad(nvl(cpu,' '), scpu) || lpad(nvl(io,' '), sio) || lpad(nvl(cl,' '), scl) || lpad(nvl(cc,' '), scc) || lpad(nvl(app,' '), sapp)
                            ||lpad(nvl(sch,' '), ssch) || lpad(nvl(cfg,' '), scfg) || lpad(nvl(adm,' '), sadm)|| lpad(nvl(net,' '), snet)
                            ||lpad(nvl(oth,' '), soth)  || lpad(nvl(plsql,' '), splsql),'|')
                ||nullif('|'||lpad(buf||' ',sbuf)||lpad(ioreqs||' ',sioreqs)||lpad(iobytes||' ',siobytes)||lpad(nvl(pga,' '),spga)||lpad(nvl(temp,' '),stemp),'|')
                ||nullif('|'||rpad(' '||top_list2, swait2),'|')||nullif('|'||rpad(' ' || top_list, swait),'|')||'|'
            ) fmt
    FROM   plan_line_widths JOIN agg_data USING (flag,phv)
    --WHERE  instr(cost_rate,'(0.0%)')=0
),

plan_output AS (
    SELECT /*+ordered use_hash(b)*/
           phv,
           r,
           b.id,
           prefix,
           prefix || 
           CASE
               WHEN plan_output LIKE '---------%' THEN
                   rpad('-', widths, '-')
               WHEN b.id = -2 THEN
                   fmt
               WHEN b.id > -1 THEN
                   fmt
               WHEN b.id = -4 THEN
                   phvs
               WHEN b.id = -5 THEN
                   time_range
           END || 
           CASE WHEN b.id NOT IN(-4,-5) THEN CASE
               WHEN b.id =-2 AND etime>0 THEN
                   --substr(plan_output, nvl(LENGTH(prefix), 0) + 1)
                   substr(regexp_replace(plan_output,'[^\|]+',lpad(' Blks',cblks-1),etime,1), nvl(length(prefix), 0) + 1)
               WHEN b.id >-1 AND etime>0  THEN
                   substr(regexp_replace(plan_output,'[^\|]+',lpad(nvl(blks,' '),cblks-1),etime,1), nvl(length(prefix), 0) + 1)
               ELSE
                   substr(plan_output, nvl(length(prefix), 0) + 1)
           END END ||
           CASE WHEN &simple=1 THEN CASE
               WHEN plan_output LIKE '---------%' THEN rpad('-',calias,'-')
               WHEN b.id = -2 THEN decode(csc,0,'',lpad('Pred',csc-1)||'|')||rpad(' Alias',calias-1)||'|'
               WHEN b.id > -1 THEN decode(csc,0,'',lpad(nvl(sc,' '),csc-1)||'|')||rpad(alias,calias-1)||'|'
           END END plan_line
    FROM   (SELECT * FROM format_info WHERE flag='line') a
    JOIN   plan_line_xplan b USING  (phv,r)
    WHERE  b.id>=-5 AND (b.id!=-1 OR b.id=-1 AND trim(plan_output) IS NOT NULL)
    ORDER  BY phv, r),
titles AS(SELECT DISTINCT phv,fmt,id,flag FROM format_info WHERE id<0),
final_output AS(
    SELECT 0 id,-1 phv,fmt,0 r,0 seq FROM titles WHERE id=-1 AND flag='phv'
    UNION ALL
    SELECT 1,-1,fmt,0,0 FROM titles WHERE id=-2 AND flag='phv'
    UNION ALL
    SELECT 2,-1,fmt,0,0 FROM titles WHERE id=-1 AND flag='phv'
    UNION ALL
    SELECT 3,-1,fmt,r,0 seq FROM format_info WHERE flag='phv' AND id=0 AND instr(fmt,'(0.0%)')=0
    UNION ALL
    SELECT 4,-1,fmt,0,0 FROM titles WHERE id=-1 AND flag='phv'
    UNION ALL
    SELECT 5,b.phv,b.plan_output,r,seq
    FROM   (SELECT r,phv1 phv FROM plan_agg WHERE r1=1) a,
        (SELECT /*+NO_PQ_CONCURRENT_UNION*/ b.*,r_*1e8+seq_ seq 
            FROM (
                SELECT 1 r_,ROWNUM seq_,phv,NULL plan_output FROM (SELECT DISTINCT phv FROM plan_output)
                UNION ALL
                SELECT 2,ROWNUM seq,phv,plan_output FROM (SELECT phv,rpad('=',max(length(rtrim(plan_line))),'=') plan_output FROM plan_output GROUP BY phv)
                UNION ALL
                SELECT 3,r seq,phv,rtrim(plan_line) FROM plan_output
                UNION ALL
                SELECT 4,ROWNUM seq,phv,fmt FROM titles WHERE id=-1 AND flag='wait'
                UNION ALL
                SELECT 5,ROWNUM seq,phv,fmt FROM titles WHERE id=-2 AND flag='wait'
                UNION ALL
                SELECT 6,ROWNUM seq,phv,fmt FROM titles WHERE id=-1 AND flag='wait'
                UNION ALL
                SELECT 7,r,phv,fmt FROM format_info WHERE flag='wait' AND id=0
                UNION ALL
                SELECT 8,ROWNUM seq,phv,fmt FROM titles WHERE id=-1 AND flag='wait'
            ) b) b
    WHERE a.phv=b.phv)
SELECT fmt ash_plan_output FROM final_output ORDER BY id,r,seq;