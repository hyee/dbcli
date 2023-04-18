/*[[
    Show ash wait chains. Usage: @@NAME {[<sql_id>|<sid>|<event>|<plan_hash_value>|-f"<filter>"] [YYMMDDHH24MI] [YYMMDDHH24MI]}|{-snap [secs]} [-sid] [-dash] [-flat] [-t"<ash_dump_table>"]
    
    Options:
        -dash        : source from dba_hist_active_session_history instead of gv$active_session_history
        -snap <secs> : show wait chain within recent n secs
        -sid         : grouping by sid instead of sql_id
        -phase       : show top phase instead of top object
        -op          : show top op name instead of top object
        -p           : show progam + event + p1/2/3 instead of event + top object
        -flat        : show ashchain in flat style instead of tree style
        -t           : source table is <ash_dump_table>
    
    The script could trigger error 'ORA-12850'(Bug 26424079) in some env, try to use 'ALTER SESSION SET "_with_subquery"=INLINE' to fix the issue.

    Sample Output:
    ==============
                       Leaf
      Pct    AAS EXECS  AAS    IO      TOP_CURR_OBJ#     WAIT_CHAIN      EVENT_CHAIN                              FULL_EVENT_CHAIN
    -------- --- ----- ---- --------- --------------- ----------------- ----------------------------------------- ---------------------------------------------------------------------------------------
    37.5%      3     1    0 408.00 KB  (3) x$kglst#2   adzjh275fvvx4     library cache load lock                  library cache load lock
    | 12.50%   1     1    1 320.00 KB  (1) 11613       |  cvn54b7yz0s8u  |  db file sequential read               library cache load lock > db file sequential read
    | 12.50%   1     1    1 320.00 KB  (1) 11613       |  cvn54b7yz0s8u  |  ON CPU [file# block# blocks]          library cache load lock > ON CPU [file# block# blocks]
    | 12.50%   1     1    1 296.00 KB  (1) 11613       |  3ktacv9r56b51  |  ON CPU [file# block# blocks]          library cache load lock > ON CPU [file# block# blocks]
    25.%       2     2    0   1.02 MB  (2) 122         0b0wj2ykgnnzg     enq: TM - contention                     enq: TM - contention
    | 25.00%   2     2    2 108.68 MB  (1) 4           |  1b28hzmjun5t0  |  db file sequential read               enq: TM - contention > db file sequential read
    12.5%      1     1    0      0  B  (1) 12442       (Mnnn)            (Mnnn) library cache pin                 (Mnnn) library cache pin
    | 12.50%   1     1    0   8.00 KB  (1) 5944        |  (CJQn)         |  (CJQn) rdbms ipc reply                (Mnnn) library cache pin > (CJQn) rdbms ipc reply
    | 12.50%   1     1    1  72.00 KB  (1) -1          |    (DBRM)       |    (DBRM) resmgr:internal state change (Mnnn) library cache pin > (CJQn) rdbms ipc reply > (DBRM) resmgr:internal state change
    12.5%      1     1    0  96.00 KB  (1) data block  32hbap2vtmf53     read by other session [data block]       read by other session [data block]
    | 12.50%   1     1    1 120.00 KB  (1) 162         |  32hbap2vtmf53  |  db file sequential read               read by other session [data block] > db file sequential read
    12.5%      1     1    1 944.00 KB  (1) -1          92b382ka0qgdt     rdbms ipc reply > (Remote)               rdbms ipc reply > (Remote)

    This script references Tanel Poder's script
    --[[
        @con : 12.1={AND prior nvl(con_id,0)=nvl(con_id,0)} default={}
        &tree  : default={1} flat={0}
        &ash   : default={&8} t={&0}
        &v2    : default={&starttime}
        &v3    : default={&endtime}
        &hint  : ash={inline} dash={materialize}
        &AWR_VIEW        : default={dba_hist_} pdb={AWR_PDB_}
        @check_access_pdb: pdb/awr_pdb_snapshot={&AWR_VIEW.} default={DBA_HIST_}
        @did : 12.2={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
        &V8: ash={gv$active_session_history}, dash={(select * from &check_access_pdb.Active_Sess_History where dbid=nvl(0+'&dbid',&did) )}
        &Filter: default={:V1 in(p1text,''||session_id,''||sql_plan_hash_value,sql_id,&top_sql SESSION_ID||'@'||&INST1,event,''||current_obj#)} f={}
        &filter1: default={0} f={1}
        &range : default={sample_time BETWEEN NVL(TO_DATE(:V2,'YYMMDDHH24MI'),SYSDATE-7) AND NVL(TO_DATE(:V3,'YYMMDDHH24MI'),SYSDATE+1)}, snap={sample_time>=sysdate - nvl(:V1,60)/86400}, f1={}
        &snap:   default={--} snap={}
        &pname : default={decode(session_type,'BACKGROUND',program2)} p={program2}
        &group : default={curr_obj#}, p={p123}, phase={phase} , op={sql_opname}
        &grp1  : default={sql_ids}, sid={sids}
        &grp2  : default={sql_id}, sid={sid}, none={sample_id}
        &unit  : default={1}, dash={10}
        &INST1 : default={inst_id}, dash={instance_number}
        &OBJ   : default={dba_objects}, dash={(select obj# object_id,object_name from &check_access_pdb.seg_stat_obj)}
        @tmodel: 11.2={time_model} default={to_number(null)}
        @opname: 11.2={SQL_OPname,TOP_LEVEL_CALL_NAME} default={null}
        @top_sql: 11.1={top_level_sql_id,} default={}
        @CHECK_ACCESS_OBJ  : dba_objects={&obj}, default={all_objects}
        @INST: 11.2={'@'|| a.BLOCKING_INST_ID}, default={'@'||a.&inst1}
        @secs: 11.2={round(sum(least(delta_time,nvl(tm_delta_db_time,delta_time)))*1e-6,2) db_time,} default={&unit,}
        @io  : 11.2={DELTA_INTERCONNECT_IO_BYTES} default={null}
        @exec_id:  11.2={CONNECT_BY_ROOT sql_id||nvl(sql_exec_id||to_char(sql_exec_start,'yymmddhh24miss'),session_id||','||&inst1||','||seq#) } default={null}
    --]]
]]*/

col db_time format smhd2
col io format KMG

SET verify off feed off
var target VARCHAR2
var chose varchar2
var filter2 number;

declare
    target varchar2(4000) := q'[
        select a.*,nvl(&tmodel,0) tmodel,&INST1 inst,SESSION_ID||'@'||&INST1 SID,
                SUBSTR(a.program,-6) PRO_,
                nvl(a.blocking_session,
                    case 
                        when p1text='idn' then 
                            nullif(decode(trunc(p2 / 4294967296), 0, trunc(P2 / 65536), trunc(P2 / 4294967296)), 0) 
                    end)|| &INST b_sid_,
                floor(to_char(sample_time,'yymmddhh24miss')/&unit)*&unit stime 
        from &ash a where ]'||:range;
    chose varchar2(2000) := '1';
BEGIN
    :filter2 := 1;
    IF (:V1 IS NOT NULL AND :snap IS NOT NULL) OR :filter1=1 THEN
        :filter2 := 0;
        target := replace(replace(q'[select /*+no_merge(a) use_hash(b) OPT_ESTIMATE(table,a,rows=30000) OPT_ESTIMATE(table,b,rows=3000000)*/ * from (select distinct stime from (@target and (@filter))) a join (@target) b using(stime)]','@filter',:filter),'@target',target);
        chose := 'CASE WHEN ' ||:filter|| ' THEN 1 ELSE 0 END';
    END IF;
    :target := '('||target||')';
    :chose:= chose;
END;
/

set verify on
var cur refcursor
BEGIN
    IF &tree=0 THEN
        open :cur for
            WITH bclass   AS (SELECT /*+inline*/ class, ROWNUM r from v$waitstat),
                 ash_base AS (select /*+materialize*/ a.*,nullif(b_sid_,'@') b_sid from &target a),
                 ash_data AS (
                SELECT /*+&hint ordered swap_join_inputs(b) swap_join_inputs(c) swap_join_inputs(u)  use_hash(a b u c)  no_expand*/
                        a.*, 
                        nvl2(b.chose,0,1) is_root,
                        u.username,
                        nvl(trim(case 
                            when current_obj# < -1 then
                                'Temp I/O'
                            when current_obj# > 0 then 
                                 ''||current_obj#
                            when p2text='id1' then
                                 ''||p2
                            when p3text like '%namespace' and p3>power(16,8)*4294950912 then
                                'Undo'
                            when p3text like '%namespace' and p3>power(16,8) then 
                                 ''||trunc(p3/power(16,8))
                            when p3text like '%namespace' then 
                                'X$KGLST#'||trunc(mod(p3,power(16,8))/power(16,4))
                            when p1text like 'cache id' then 
                                (select parameter from v$rowcache where cache#=p1 and rownum<2)
                            when event like 'latch%' and p2text='number' then 
                                (select name from v$latchname where latch#=p2 and rownum<2)
                            when c.class is not null then c.class
                            when p1text ='file#' and p2text='block#' then 
                                'file#'||p1||' block#'||p2
                            when p3text in('block#','block') then 
                                'file#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(p3)||' block#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_BLOCK(p3)    
                            when current_obj# = 0 then 'Undo'
                            --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                            --when c.class is not null then c.class
                        end),''||current_obj#) curr_obj#,
                        CASE WHEN PRO_ LIKE '(%)' AND upper(substr(PRO_,2,1))=substr(PRO_,2,1) THEN
                            CASE WHEN PRO_ LIKE '(%)' AND substr(PRO_,2,1) IN('P','W','J') THEN
                                '('||substr(PRO_,2,1)||'nnn)'
                            ELSE regexp_replace(PRO_,'[0-9a-z]','n') END
                        WHEN instr(program,'@')>1 THEN
                            nullif(substr(program,1,instr(program,'@')-1),'oracle')
                        END program2,
                        CASE WHEN a.session_state = 'WAITING' THEN a.event 
                             WHEN bitand(tmodel, power(2,18)) > 0 THEN 'CPU: IM Query'
                             WHEN bitand(tmodel, power(2,19)) > 0 THEN 'CPU: IM Populate'
                             WHEN bitand(tmodel, power(2,20)) > 0 THEN 'CPU: IM Prepopulate'
                             WHEN bitand(tmodel, power(2,21)) > 0 THEN 'CPU: IM Repopulate'
                             WHEN bitand(tmodel, power(2,22)) > 0 THEN 'CPU: IM Trickle Repop'
                        ELSE 'ON CPU' END ||
                        CASE WHEN c.class IS NOT NULL THEN ' ['||c.class||']'
                             WHEN a.event IS NULL AND tmodel<power(2,18) THEN nvl2(a.p1text,' ['||trim(p1text||' '||p2text||' '||p3text)||']','')
                        END || ' ' event2,
                        replace(nvl2(p1text,p1text||' #'||case when p1>power(2,32) then to_char(p1,'fm0XXXXXXXXXXXXXXX') else ''||p1 end,'')
                            ||nvl2(p2text,'/'||p2text||' #'||case when p2>power(2,32) then to_char(p2,'fm0XXXXXXXXXXXXXXX') else ''||p2 end,'')
                            ||nvl2(p3text,'/'||p3text||' #'
                                || case when p3>power(2,32) then to_char(p3,'fm0XXXXXXXXXXXXXXX') 
                                        when c.class is not null then c.class
                                        else ''||p3 end,''),'# #',' #') p123,
                        coalesce(trim(decode(bitand(tmodel,power(2, 3)),0,'','in_connection_mgmt ') || 
                            decode(bitand(tmodel,power(2, 4)),0,'','in_parse ') || 
                            decode(bitand(tmodel,power(2, 7)),0,'','in_hard_parse ') || 
                            decode(bitand(tmodel,power(2,10)),0,'','in_sql_execution ') || 
                            decode(bitand(tmodel,power(2,11)),0,'','in_plsql_execution ') || 
                            decode(bitand(tmodel,power(2,12)),0,'','in_plsql_rpc ') || 
                            decode(bitand(tmodel,power(2,13)),0,'','in_plsql_compilation ') || 
                            decode(bitand(tmodel,power(2,14)),0,'','in_java_execution ') || 
                            decode(bitand(tmodel,power(2,15)),0,'','in_bind ') || 
                            decode(bitand(tmodel,power(2,16)),0,'','in_cursor_close ') || 
                            decode(bitand(tmodel,power(2,17)),0,'','in_sequence_load ') || 
                            decode(bitand(tmodel,power(2,18)),0,'','in_inmemory_query ') || 
                            decode(bitand(tmodel,power(2,19)),0,'','in_inmemory_populate ') || 
                            decode(bitand(tmodel,power(2,20)),0,'','in_inmemory_prepopulate ') || 
                            decode(bitand(tmodel,power(2,21)),0,'','in_inmemory_repopulate ') || 
                            decode(bitand(tmodel,power(2,22)),0,'','in_inmemory_trepopulate ') || 
                            decode(bitand(tmodel,power(2,23)),0,'','in_tablespace_encryption ')),&opname) phase
              FROM   ash_base a
              LEFT   JOIN (SELECT DISTINCT b_sid, stime, 0 chose FROM ash_base WHERE b_sid IS NOT NULL) b
              ON     (a.sid = b.b_sid AND a.stime = b.stime)
              LEFT JOIN dba_users  u 
              ON    (a.user_id = u.user_id)
              LEFT JOIN bclass c
              ON    (a.p3text='class#' and a.p3=c.r)
              WHERE  b.chose IS NOT NULL
              OR     a.b_sid IS NOT NULL),
            chains AS (
                SELECT /*+NO_EXPAND opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('optimizer_dynamic_sampling' 11)*/
                      level lvl,
                      sid w_sid,
                      SYS_CONNECT_BY_PATH(case when :filter2 = 1 then 1 when &filter then 1 else 0 end ,',') is_found,
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(coalesce(sql_id,&top_sql program2), '>')||decode(connect_by_isleaf,1,nvl2(b_sid,'>(Idle)','')),'(>.+?)\1+','\1 +',2)), '>', ' > ') sql_ids,
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(&pname ||event2, '>')||decode(connect_by_isleaf,1,nvl2(b_sid,'>(Idle)','')),'(>.+?)\1+','\1 +',2)), '>', ' > ') path, -- there's a reason why I'm doing this (ORA-30004 :)
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(sid,'>')||decode(connect_by_isleaf,1,nullif('>'||b_sid,'>')),'(>.+?)\1+','\1 +')), '>', ' > ') sids,
                      &exec_id sql_exec,
                      CONNECT_BY_ROOT &group root_&group,
                      CONNECT_BY_ISLEAF isleaf,
                      CONNECT_BY_ISCYCLE iscycle,
                      d.*
                FROM  ash_data d
                CONNECT BY NOCYCLE (PRIOR d.b_sid = d.sid AND PRIOR stime = stime &con)
                START WITH is_root=1
            )
            SELECT * FROM (
                SELECT to_char(RATIO_TO_REPORT(COUNT(*)) OVER () * 100,'990.00')||'%' "%This",
                       SUM(&UNIT) AAS,count(distinct sql_exec) execs, &secs sum(&io) io,
                       &snap w_sid, b_sid,
                       root_&group, &grp1, path wait_chain
                FROM   chains c
                WHERE  isleaf = 1 and is_found like '%1%'
                GROUP BY root_&group, path,&grp1 &snap , w_sid, b_sid
                ORDER BY AAS DESC
                )
            WHERE ROWNUM <= 50;
    ELSE
        OPEN :cur FOR
            WITH bclass AS (SELECT class, ROWNUM r from v$waitstat),
            ash_base as (select /*+materialize */ a.*,nullif(b_sid_,'@') b_sid from &target a),
            ash_data AS (
                SELECT /*+&hint opt_param('optimizer_dynamic_sampling' 11) ordered swap_join_inputs(b) swap_join_inputs(c) swap_join_inputs(u)  use_hash(a b u c)  no_expand*/
                        a.*, 
                        nvl2(b.chose,0,1) is_root,
                        u.username,
                        nvl(trim(case 
                            when current_obj# < -1 then
                                'Temp I/O'
                            when current_obj# > 0 then 
                                 ''||current_obj#
                            when p3text like '%namespace' and p3>power(16,8)*4294950912 then
                                'Undo'
                            when p3text like '%namespace' and p3>power(16,8) then 
                                 ''||trunc(p3/power(16,8))
                            when p3text like '%namespace' then 
                                'X$KGLST#'||trunc(mod(p3,power(16,8))/power(16,4))
                            when p1text like 'cache id' then 
                                (select parameter from v$rowcache where cache#=p1 and rownum<2)
                            when event like 'latch%' and p2text='number' then 
                                (select name from v$latchname where latch#=p2 and rownum<2)
                            when c.class is not null then c.class
                            when p1text ='file#' and p2text='block#' then 
                                'file#'||p1||' block#'||p2
                            when p3text in('block#','block') then 
                                'file#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(p3)||' block#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_BLOCK(p3)    
                            when current_obj# = 0 then 'Undo'
                            --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                            --when c.class is not null then c.class
                        end),''||current_obj#) curr_obj#,
                        CASE WHEN PRO_ LIKE '(%)' AND upper(substr(PRO_,2,1))=substr(PRO_,2,1) THEN
                            CASE WHEN PRO_ LIKE '(%)' AND substr(PRO_,2,1) IN('P','W','J') THEN
                                '('||substr(PRO_,2,1)||'nnn)'
                            ELSE regexp_replace(PRO_,'[0-9a-z]','n') END
                        WHEN instr(program,'@')>1 THEN
                            nullif(substr(program,1,instr(program,'@')-1),'oracle')
                        END program2,
                        CASE WHEN a.session_state = 'WAITING' THEN a.event 
                             WHEN bitand(tmodel, power(2,18)) > 0 THEN 'CPU: IM Query'
                             WHEN bitand(tmodel, power(2,19)) > 0 THEN 'CPU: IM Populate'
                             WHEN bitand(tmodel, power(2,20)) > 0 THEN 'CPU: IM Prepopulate'
                             WHEN bitand(tmodel, power(2,21)) > 0 THEN 'CPU: IM Repopulate'
                             WHEN bitand(tmodel, power(2,22)) > 0 THEN 'CPU: IM Trickle Repop'
                        ELSE 'ON CPU' END ||
                        CASE WHEN c.class IS NOT NULL THEN ' ['||c.class||']'
                             WHEN a.event IS NULL AND tmodel<power(2,18) THEN nvl2(a.p1text,' ['||trim(p1text||' '||p2text||' '||p3text)||']','')
                        END || ' ' event2,
                        replace(nvl2(p1text,p1text||' #'||case when p1>power(2,32) then to_char(p1,'0XXXXXXXXXXXXXXX') else ''||p1 end,'')
                            ||nvl2(p2text,'/'||p2text||' #'||case when p2>power(2,32) then to_char(p2,'0XXXXXXXXXXXXXXX') else ''||p2 end,'')
                            ||nvl2(p3text,'/'||p3text||' #'
                                || case when p3>power(2,32) then to_char(p3,'0XXXXXXXXXXXXXXX') 
                                        when c.class is not null then c.class
                                        else ''||p3 end,''),'# #',' #') p123,
                        coalesce(trim(decode(bitand(tmodel,power(2, 3)),0,'','in_connection_mgmt ') || 
                            decode(bitand(tmodel,power(2, 4)),0,'','in_parse ') || 
                            decode(bitand(tmodel,power(2, 7)),0,'','in_hard_parse ') || 
                            decode(bitand(tmodel,power(2,10)),0,'','in_sql_execution ') || 
                            decode(bitand(tmodel,power(2,11)),0,'','in_plsql_execution ') || 
                            decode(bitand(tmodel,power(2,12)),0,'','in_plsql_rpc ') || 
                            decode(bitand(tmodel,power(2,13)),0,'','in_plsql_compilation ') || 
                            decode(bitand(tmodel,power(2,14)),0,'','in_java_execution ') || 
                            decode(bitand(tmodel,power(2,15)),0,'','in_bind ') || 
                            decode(bitand(tmodel,power(2,16)),0,'','in_cursor_close ') || 
                            decode(bitand(tmodel,power(2,17)),0,'','in_sequence_load ') || 
                            decode(bitand(tmodel,power(2,18)),0,'','in_inmemory_query ') || 
                            decode(bitand(tmodel,power(2,19)),0,'','in_inmemory_populate ') || 
                            decode(bitand(tmodel,power(2,20)),0,'','in_inmemory_prepopulate ') || 
                            decode(bitand(tmodel,power(2,21)),0,'','in_inmemory_repopulate ') || 
                            decode(bitand(tmodel,power(2,22)),0,'','in_inmemory_trepopulate ') || 
                            decode(bitand(tmodel,power(2,23)),0,'','in_tablespace_encryption ')),&opname) phase
              FROM   ash_base a
              LEFT   JOIN (SELECT DISTINCT b_sid, stime, 0 chose FROM ash_base WHERE b_sid IS NOT NULL) b
              ON     (a.sid = b.b_sid AND a.stime = b.stime)
              LEFT JOIN dba_users  u 
              ON    (a.user_id = u.user_id)
              LEFT JOIN bclass c
              ON    (a.p3text='class#' and a.p3=c.r)
              WHERE  b.chose IS NOT NULL
              OR     a.b_sid IS NOT NULL),
            chains AS (
                SELECT /*+NO_EXPAND CONNECT_BY_COMBINE_SW*/
                       sid w_sid,b_sid,
                       rownum-level r,
                       inst,
                       case when :filter2 = 1 then 1 when &filter then 1 else 0 end is_found,
                       TRIM('>' FROM regexp_replace(SYS_CONNECT_BY_PATH(trim(decode('&grp2','sample_id','x','sql_id',nvl(sql_id, program2),&grp2)),'>'),'(>.+?)\1+','\1(+)',2)) sql_ids,
                       TRIM('>' FROM regexp_replace(SYS_CONNECT_BY_PATH(trim(&pname || event2), '>'), '(>.+?)\1+', '\1(+)',2)) p, 
                       &exec_id sql_exec,
                       connect_by_isleaf isleaf,
                       CONNECT_BY_ISCYCLE iscycle,
                       CONNECT_BY_ROOT decode('&grp2','sample_id',trim(&pname || event2),'sql_id',nvl(sql_id, program2),&grp2) root_sql,
                       trim(decode('&grp2','sample_id',' ','sql_id',nvl(sql_id, program2),&grp2))  sq_id,
                       trim(&pname || event2) env,
                       &group,
                       &io io
                FROM  ash_data d
                CONNECT BY NOCYCLE (PRIOR d.b_sid = d.sid AND PRIOR stime = stime  &con)
                START WITH is_root=1),
            calc AS (
               SELECT /*+materialize*/ * 
               FROM (SELECT a.*,
                            100*aas/nullif(sum(aas*decode(lvl,0,1,0)) over(),0) pct,
                            dense_rank() over(order by rnk desc) rnk_ 
                 FROM (
                  SELECT /*+leading(b a)*/
                         sum(count(1)) over(partition by root_sql) rnk,
                         max(nvl2(&group,' ('||grp_count||') '||&group,'')) keep(dense_Rank last order by grp_count) &group,
                         root_sql,
                         sql_ids,
                         trim(p)||idle p,
                         SUM(&UNIT*isleaf) delta,
                         max(nullif(sq_id||plus1,'(+)')) sq_id,
                         max(env||plus2||replace(idle,'>',' > ')) env,
                         COUNT(DISTINCT sql_exec) execs,
                         SUM(&UNIT) aas,
                         sum(io) io,
                         lvl
                  FROM (
                      SELECT A.*,
                             b.is_found,
                             b.rnk,
                             greatest(length(sql_ids)-length(replace(sql_ids,'>')),length(p)-length(replace(p,'>'))) lvl,
                             case when iscycle=0 and isleaf=1 and b_sid is not null then
                                       case when b_sid like '%@'||inst then '>(Unknown)' else '>(Remote)' end
                             end idle,
                             case when sql_ids like '%(+)' then '(+)' end plus1,
                             case when p like '%(+)' then '(+)' end|| decode(iscycle,1,'(C)') plus2,
                             sum(&UNIT) over(partition by sql_ids,p,&group,case when  iscycle=0 and isleaf=1 and b_sid is not null then 1 else 0 end) grp_count
                      FROM   chains a,
                             (SELECT b.*, dense_rank() OVER(ORDER BY leaves DESC,paths) rnk
                              FROM   (SELECT r, MAX(sql_ids) || MAX(p) paths,max(is_found) is_found,COUNT(1) OVER(PARTITION BY MAX(sql_ids) || MAX(p)) leaves 
                                      FROM CHAINS c 
                                      GROUP BY r) b
                              WHERE is_found=1) b
                      WHERE  a.r = b.r
                      AND    b.rnk <= 100) --exclude the chains whose rank >
                  GROUP  BY root_sql, sql_ids, p,idle,lvl) A)
               WHERE rnk_<=10)
            SELECT DECODE(LEVEL, 1, to_char(pct,'fm990.99'), '|'||to_char(least(pct,99.99),'90.00'))||'%' "Pct",
                   AAS,
                   EXECS,
                   DELTA "Leaf|AAS",
                   IO,
                   &group top_&group,
                   DECODE(LEVEL, 1, '', ' |') || LPAD(' ', (LEVEL - 1) * 2 - 1, ' ') || ' ' || SQ_ID WAIT_CHAIN,
                   DECODE(LEVEL, 1, '', ' |') || LPAD(' ', (LEVEL - 1) * 2 - 1, ' ') || ' ' || ENV EVENT_CHAIN,
                   replace(p,'>',' > ') FULL_EVENT_CHAIN
            FROM   calc
            START  WITH LVL = 0
            CONNECT BY NOCYCLE SQL_IDS LIKE PRIOR SQL_IDS || '%'
                AND    P LIKE PRIOR P || '%'
                AND    LVL = PRIOR LVL + 1
            ORDER SIBLINGS BY AAS DESC;
    END IF;
END;
/