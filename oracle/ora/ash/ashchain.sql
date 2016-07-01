/*[[
Show ash wait chains. Usage: @@NAME {[<sql_id>|[-f<"filter">]] [YYMMDDHH24MI] [YYMMDDHH24MI]}|{-snap [secs]} [-dash]
This script references Tanel Poder's script
    --[[
        &V8    : ash={gv$active_session_history},dash={Dba_Hist_Active_Sess_History}
        &Filter: default={sql_id='&V1'} -f={}
        &snap  : default={--}, snap={}
        &group : default={}, g={,&0} 
        @CHECK_ACCESS_OBJ  : dba_objects={dba_objects}, default={all_objects}
    --]]
]]*/

WITH
bclass AS (SELECT class, ROWNUM r from v$waitstat),
ash AS (SELECT /*+ QB_NAME(ash) LEADING(a) USE_HASH(u) SWAP_JOIN_INPUTS(u) */
            coalesce(sql_id,p3text,p2text,p1text) sql_id_or_e,
            SESSION_ID||',@'||INST_ID SID,
            nullif(blocking_session||',@'|| BLOCKING_INST_ID,',@') b_sid
          , u.username
          , CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
              REGEXP_REPLACE(SUBSTR(a.program,INSTR(a.program,'(')), '\d', 'n')
            ELSE
                '('||REGEXP_REPLACE(REGEXP_REPLACE(a.program, '(.*)@(.*)(\(.*\))', '\1'), '\d', 'n')||')'
            END || ' ' program2
          , NVL(a.event||CASE WHEN p3text='class#'
                              THEN ' ['||(SELECT class FROM bclass WHERE r = a.p3)||']' ELSE null END,'ON CPU')
                       || ' ' event2
          , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p1 ELSE null END, '0XXXXXXXXXXXXXXX') p1hex
          , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p2 ELSE null END, '0XXXXXXXXXXXXXXX') p2hex
          , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p3 ELSE null END, '0XXXXXXXXXXXXXXX') p3hex
          , a.*
        FROM
            &V8 a
          , dba_users u
        WHERE a.user_id = u.user_id (+)
        AND sample_time BETWEEN NVL(TO_DATE(NVL(:V2,:STARTTIME),'YYMMDDHH24MI'),SYSDATE-1) AND NVL(TO_DATE(NVL(:V3,:ENDTIME),'YYMMDDHH24MI'),SYSDATE)
  &snap AND sample_time>=sysdate - nvl(:V1,60)/86400  
    ),
ash_samples AS (SELECT DISTINCT sample_id FROM ash),
ash_data AS (SELECT /*+ MATERIALIZE */ * FROM ash),
chains AS (
    SELECT /*+NO_EXPAND*/
        level lvl
      --, sql_id
      , sid w_sid
      , REPLACE(SYS_CONNECT_BY_PATH(sql_id_or_e, '->'), '->', ' -> ') sql_ids
      , REPLACE(SYS_CONNECT_BY_PATH(program2||event2, '->'), '->', ' -> ') path -- there's a reason why I'm doing this (ORA-30004 :)
     -- , CASE WHEN CONNECT_BY_ISLEAF = 1 THEN d.session_id ELSE NULL END sids
      , CONNECT_BY_ISLEAF isleaf
      , CONNECT_BY_ISCYCLE iscycle
      , d.*
    FROM
        ash_samples s
      , ash_data d
    WHERE
        s.sample_id = d.sample_id
    CONNECT BY NOCYCLE
        (    PRIOR d.b_sid = d.sid
        -- AND PRIOR d.blocking_inst_id = d.inst_id
         AND PRIOR s.sample_id = d.sample_id
        )
     START WITH (regexp_substr(:V1,'[a-zA-Z]') is null and b_sid is not null or &filter)
)
SELECT * FROM (
    SELECT
        LPAD(ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100)||'%',5,' ') "%This"
      , COUNT(*) seconds
    &snap , w_sid, b_sid
      , (SELECT nvl(max(object_name),''||current_obj#) FROM &CHECK_ACCESS_OBJ WHERE object_id=current_obj#) obj#
      &group
      , sql_ids 
      , path wait_chain
    FROM
        chains
    WHERE
        isleaf = 1
    GROUP BY
        current_obj# &group
      , path,sql_ids
    &snap , w_sid, b_sid 
    ORDER BY
        COUNT(*) DESC
    )
WHERE
    ROWNUM <= 50