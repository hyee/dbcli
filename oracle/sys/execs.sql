/*[[
	Show object's SQL execution count. Usage: @@NAME [<object_name>] [<inst_id>]
	
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
    --]]
]]*/
ora _find_object "&V1" 1
SELECT * FROM (
	SELECT /*+ordered use_nl(o)*/ *
	FROM TABLE(GV$(CURSOR(
		SELECT inst_id,object_name,regexp_substr(object_type,'\S+') object_type,
			   sum(sql_execs) sql_execs,sum(invalids) invalids,max(kept) kept,max(MARKHOT) MARKHOT,
			   count(distinct sql_id) sqls,
			   regexp_replace(listagg(decode(sign(100-sql_seq),1,sql_id),',') within group(order by sql_id),'([^,]{13,})(,\1)+','\1') sql_ids
		FROM (
			SELECT /*+ ordered use_hash(d) use_hash(c) no_expand*/
				   distinct
			       o.inst_id,
			       o.kglnaown || '.' || o.kglnaobj OBJECT_NAME,
			       o.kglobtyp type#,
			       decode(o.kglobtyp, 0, 'NEXT OBJECT', 1, 'INDEX', 2, 'TABLE', 3, 'CLUSTER',
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
		                         'UNDEFINED') object_type,
			       o.kglhdexc sql_execs,
			       o.KGLHDIVC invalids,
			       DECODE(o.KGLHDKMK,0,'NO','YES') KEPT,
			       o.KGLOBPROP MARKHOT,
			       c.KGLOBT03 SQL_ID,
			       dense_rank() over(partition by o.kglnaown,o.kglnaobj order by c.KGLOBT03 nulls last) SQL_SEQ
			FROM   sys.x$kglob o, sys.x$kgldp d, sys.x$kglcursor c
			WHERE  o.kglobtyp NOT IN(0,55)
			AND    o.kglnahsh = d.kglrfhsh(+)  
			AND    o.kglhdadr = d.kglrfhdl(+)
			AND    d.kglhdpar = c.kglhdpar(+)
			AND    d.kglnahsh = c.kglnahsh(+)
			AND    o.kglnaown IS NOT NULL
			AND    (:object_name IS NULL OR o.kglnaown=:object_owner and o.kglnaobj=:object_name)
			AND    userenv('instance') = nvl(:V2, userenv('instance'))
		)
	GROUP BY inst_id,object_name,regexp_substr(object_type,'\S+') ))) a
	ORDER BY sql_execs desc,OBJECT_NAME,OBJECT_TYPE)
WHERE ROWNUM<=50