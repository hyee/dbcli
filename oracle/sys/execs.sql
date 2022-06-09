/*[[
    Show object's SQL execution count. Usage: @@NAME [<object_name>|<sql_id>] [<inst_id>]
    
    Sample Output:
    ===============
    INST_ID           OBJECT_NAME           TYPE# OBJECT_TYPE  SQL_EXECUTIONS
    ------- ------------------------------- ----- ------------ --------------
          1 SYS.DBMS_STATS_INTERNAL            11 PACKAGE BODY         447625
          1 SSB_STATS.FLUSH_SQLMON              7 PROCEDURE            247313
          4 SYS.DBMS_RMIN_SYS                  11 PACKAGE BODY         208072
          2 SYS.DBMS_SWRF_INTERNAL             11 PACKAGE BODY         141210
          1 SYS.DBMS_SWRF_INTERNAL             11 PACKAGE BODY         140594
          2 SYS.DBMS_STATS_INTERNAL            11 PACKAGE BODY          86263
          2 SYS.PRVT_HDM                       11 PACKAGE BODY          66396
          1 SYS.PRVT_HDM                       11 PACKAGE BODY          62688
          3 SYS.DBMS_RCVMAN                    11 PACKAGE BODY          61761
          2 SYS.PRVT_ADVISOR                   11 PACKAGE BODY          50572
          3 SYS.PRVT_HDM                       11 PACKAGE BODY          46684
          4 SYS.DBMS_REPORT                    11 PACKAGE BODY          43264
          1 SYS.PRVT_ADVISOR                   11 PACKAGE BODY          43136
          3 ORACLE_OCM.MGMT_DB_LL_METRICS      11 PACKAGE BODY          39684
          3 SYS.DBMS_SWRF_INTERNAL             11 PACKAGE BODY          39102
          2 SYS.WRI$_ADV_HDM_T                 14 TYPE BODY             37694
          3 SYS.V_RANGERECSETIMPL_T            14 TYPE BODY             34892
          3 SYS.DBMS_MANAGEMENT_PACKS          11 PACKAGE BODY          30960
          3 SYS.DBMS_STATS_INTERNAL            11 PACKAGE BODY          28938
    --[[
        &V2: default={&instance}
        @overflow: 12.2={distinct sql_id,',' on overflow truncate} default={decode(seq,1,decode(sign(100-SQL_SEQ),1,CASE WHEN SEQ=1 THEN sql_id END)),','}
    --]]
]]*/
ora _find_object "&V1" 1
SELECT * FROM (
    SELECT /*+ordered use_nl(o)*/ *
    FROM TABLE(GV$(CURSOR(
        SELECT inst_id,object_name,object_type,
               sum(distinct decode(SQL_SEQ,1,execs)) execs,
               sum(decode(SQL_SEQ,1,invalids2,0)+nvl(invalids1,0)) invalids,
               max(kept) kept,max(MARKHOT) MARKHOT,
               count(distinct sql_id) sqls,
               sum(sql_execs) sql_execs,
               decode(flag,2,max(full_hash),listagg(&overflow) within group(order by sql_execs desc nulls last)) sql_ids
        FROM (
            SELECT /*+ ordered use_hash(d) use_hash(c) no_expand*/
                   o.inst_id,
                   o.kglnaown || '.' || o.kglnaobj OBJECT_NAME,
                   regexp_substr(decode(o.kglobtyp, 0, 'NEXT OBJECT', 1, 'INDEX', 2, 'TABLE', 3, 'CLUSTER',
                                  4, 'VIEW', 5, 'SYNONYM', 6, 'SEQUENCE',
                                  7, 'PROCEDURE', 8, 'FUNCTION', 9, 'PACKAGE',
                                  11, 'PACKAGE BODY', 12, 'TRIGGER',
                                  13, 'TYPE', 14, 'TYPE BODY',
                                  19, 'TABLE PARTITION', 20, 'INDEX PARTITION', 21, 'LOB',
                                  22, 'LIBRARY', 23, 'DIRECTORY', 24, 'QUEUE',
                                  28, 'JAVA SOURCE', 29, 'JAVA CLASS', 30, 'JAVA RESOURCE',
                                  32, 'INDEXTYPE', 33, 'OPERATOR',
                                  34, 'TABLE SUBPARTITION', 35, 'INDEX SUBPARTITION',
                                  40, 'LOB PARTITION', 41, 'LOB SUBPARTITION',
                                  42, 'MATERIALIZED ZONEMAP/VIEW',
                                  43, 'DIMENSION',
                                  44, 'CONTEXT', 46, 'RULE SET', 47, 'RESOURCE PLAN',
                                  48, 'CONSUMER GROUP',
                                  51, 'SUBSCRIPTION', 52, 'LOCATION',
                                  55, 'XML SCHEMA', 56, 'JAVA DATA',
                                  57, 'EDITION', 59, 'RULE',
                                  60, 'CAPTURE', 61, 'APPLY',
                                  62, 'EVALUATION CONTEXT',
                                  66, 'JOB', 67, 'PROGRAM', 68, 'JOB CLASS', 69, 'WINDOW',
                                  72, 'SCHEDULER GROUP', 74, 'SCHEDULE', 79, 'CHAIN',
                                  81, 'FILE GROUP', 82, 'MINING MODEL', 87, 'ASSEMBLY',
                                  90, 'CREDENTIAL', 92, 'CUBE DIMENSION', 93, 'CUBE',
                                  94, 'MEASURE FOLDER', 95, 'CUBE BUILD PROCESS',
                                  100, 'FILE WATCHER', 101, 'DESTINATION',
                                  111, 'CONTAINER',
                                  114, 'SQL TRANSLATION PROFILE',
                                  115, 'UNIFIED AUDIT POLICY',
                                  144, 'MINING MODEL PARTITION',
                                  148, 'LOCKDOWN PROFILE',
                                  150, 'HIERARCHY',
                                  151, 'ATTRIBUTE DIMENSION',
                                  152, 'ANALYTIC VIEW',
                                 'UNDEFINED'),'\S+') object_type,
                   o.kglhdexc execs,
                   c.KGLHDIVC invalids1,
                   o.KGLHDIVC invalids2,
                   DECODE(o.KGLHDKMK,0,'NO','YES') KEPT,
                   o.KGLOBPROP||decode(:V1,c.KGLOBT03,'/'||c.KGLOBPROP) MARKHOT,
                   c.KGLOBT03 SQL_ID,
                   c.KGLOBT05 sql_execs,
                   decode(:V1,c.KGLOBT03,2,1) flag,
                   decode(nvl(c.KGLOBT09,0),0,c.KGLNAHSV) full_hash,
                   row_number() over(partition by o.kglnahsh,o.kglhdadr order by c.KGLOBT05 desc nulls last) SQL_SEQ,
                   row_number() over(partition by o.kglnaown,o.kglnaobj,c.KGLOBT03 order by 1) SEQ
            FROM   sys.x$kglob o, 
                   (SELECT DISTINCT kglrfhsh,kglrfhdl,kglhdpar,kglnahsh 
                    FROM   sys.x$kgldp k, sys.x$kglxs a
                    WHERE  k.kglhdadr = a.kglhdadr
                    AND    k.kgldepno = a.kglxsdep) d, 
                    sys.x$kglob c
            WHERE  o.kglobtyp NOT IN(0,55)
            AND    o.kglnahsh = d.kglrfhsh(+)  
            AND    o.kglhdadr = d.kglrfhdl(+)
            AND    d.kglhdpar = c.kglhdpar(+)
            AND    d.kglnahsh = c.kglnahsh(+)
            AND    (o.kglnaown IS NOT NULL OR :V1 IS NOT NULL)
            --AND    o.kglhdexc>0
            AND    c.kglhdnsp(+) = 0
            AND    (c.KGLOBT03 IS NOT NULL OR d.kglrfhsh IS NULL)
            AND    (:object_name IS NULL OR o.kglnaown=:object_owner and o.kglnaobj=:object_name)
            AND    (:object_name IS NOT NULL OR :V1 IS NULL OR :v1 =c.KGLOBT03)
            AND    userenv('instance') = nvl(:V2, userenv('instance'))
        )
    GROUP BY inst_id,object_name,object_type,nvl2(:V1,sql_id,''),flag
    HAVING sum(decode(SQL_SEQ,1,execs))>0 ))) a
    ORDER BY execs desc,OBJECT_NAME,OBJECT_TYPE)
WHERE ROWNUM<=50