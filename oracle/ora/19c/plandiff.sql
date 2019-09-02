/*[[
	Comparing Execution plan that available since 19c. Usage: @@NAME <plan_hash_value1> <plan_hash_value2>

	Sample Output:
	===============
    ---------------------------------------------------------------------------------------------
      Current user           : SYS
      Total number of plans  : 2
      Number of findings     : 1
    ---------------------------------------------------------------------------------------------

    COMPARISON DETAILS
    ---------------------------------------------------------------------------------------------
     Plan Number            : 1 (Reference Plan)
     Plan Found             : Yes
     Plan Source            : Cursor Cache
     SQL ID                 : 9qq6ps32900bg

    Plan
    -----------------------------
     Plan Hash Value  : 2662980928
    -------------------------------------------------------------------------------------------------
    | Id  | Operation                 | Name                       | Rows | Bytes | Cost | Time     |
    -------------------------------------------------------------------------------------------------
    |   0 | SELECT STATEMENT          |                            |      |       |    1 |          |
    | * 1 |   COUNT STOPKEY           |                            |      |       |      |          |
    |   2 |    PARTITION RANGE SINGLE |                            |    2 |    22 |    1 | 00:00:01 |
    | * 3 |     INDEX FULL SCAN       | WRH$_INTERCONNECT_PINGS_PK |    2 |    22 |    1 | 00:00:01 |
    -------------------------------------------------------------------------------------------------
    Predicate Information (identified by operation id):
    ------------------------------------------
    * 1 - filter(ROWNUM<2)
    * 3 - filter((("SNAP_ID">=1486 AND "DBID"=1544102455) OR "DBID">1544102455))

    ---------------------------------------------------------------------------------------------
     Plan Number            : 2
     Plan Found             : Yes
     Plan Source            : Cursor Cache
     SQL ID                 : 8yqz7gms7n0c4

    Plan
    -----------------------------
     Plan Hash Value  : 2833100446
    ----------------------------------------------------------------------------------------------------------------
    | Id  | Operation                                | Name                       | Rows | Bytes | Cost | Time     |
    ----------------------------------------------------------------------------------------------------------------
    |   0 | SELECT STATEMENT                         |                            |      |       |    2 |          |
    | * 1 |   COUNT STOPKEY                          |                            |      |       |      |          |
    |   2 |    PARTITION RANGE SINGLE                |                            |    3 |    33 |    2 | 00:00:01 |
    | * 3 |     INDEX STORAGE FAST FULL SCAN FIRST R | WRH$_SERVICE_WAIT_CLASS_PK |    3 |    33 |    2 | 00:00:01 |
    ----------------------------------------------------------------------------------------------------------------
    Predicate Information (identified by operation id):
    ------------------------------------------
    * 1 - filter(ROWNUM<2)
    * 3 - storage((("SNAP_ID">=1486 AND "DBID"=1544102455) OR "DBID">1544102455))
    * 3 - filter((("SNAP_ID">=1486 AND "DBID"=1544102455) OR "DBID">1544102455))

    Comparison Results (1):
    -----------------------------
     1. Query block SEL$1: Tables are different (0 tables of 1 match).

	--[[
		@ARGS: 2
		@VER : 19={}
	--]]
]]*/

set feed off verify off
var res clob
var txt clob;
var filename VARCHAR2(60)

DECLARE
    phv1    INT := regexp_substr(:V1, '\d+');
    phv2    INT := regexp_substr(:V2, '\d+');
    sql_id1 VARCHAR2(30);
    sql_id2 VARCHAR2(30);
    src     sys.generic_plan_object;
    target  sys.plan_object_list;
    xml     XMLTYPE;
    c       CLOB;
BEGIN
    IF phv1 IS NULL OR phv2 IS NULL THEN
        raise_application_error(-20001, 'Please input the plan hash values in number format!');
    END IF;

    FOR r IN (SELECT 1 flag, sql_id, plan_hash_value phv, SYS.CURSOR_CACHE_OBJECT(sql_id, child_number) obj
              FROM   gv$sql_plan
              WHERE  plan_hash_value IN (phv1, phv2)
              AND    id = 1
              UNION ALL
              SELECT 2, sql_id, plan_hash_value, SYS.AWR_OBJECT(sql_id, dbid,con_dbid, plan_hash_value) obj
              FROM   dba_hist_sql_plan
              WHERE  plan_hash_value IN (phv1, phv2)
              AND    id = 1
              UNION ALL
              SELECT 3, sql_id, plan_hash_value, SYS.SQLSET_OBJECT(sqlset_owner, sqlset_name, sql_id, plan_hash_value) obj
              FROM   dba_sqlset_plans
              WHERE  plan_hash_value IN (phv1, phv2)
              AND    id = 1
              UNION ALL
              SELECT 4, sql_id, plan_hash_value, SYS.SQLSET_OBJECT(task_name, execution_name, sql_id, plan_id) obj
              FROM   dba_advisor_sqlplans
              WHERE  plan_hash_value IN (phv1, phv2)
              AND    id = 1) LOOP
        IF r.phv = phv1 AND src IS NULL THEN
            src := r.obj;
        ELSIF r.phv = phv2 AND target IS NULL THEN
            target := sys.plan_object_list(r.obj);
        END IF;
    
        EXIT WHEN src IS NOT NULL AND target IS NOT NULL;
    END LOOP;

    IF src IS NULL THEN
        raise_application_error(-20001, 'Cannot find execution plan for ' || phv1);
    ELSIF target IS NULL THEN
        raise_application_error(-20001, 'Cannot find execution plan for ' || phv2);
    END IF;
    xml       := XMLTYPE(dbms_xplan.compare_plans(src, target,'XML','TYPICAL','ALL'));
    :res      := dbms_report.format_report(xml,'html');
    :filename := 'plandiff_'||phv1||'_'||phv2||'.html';
    c         := dbms_report.format_report(xml.deleteXML('//sql_text'),'text');
    c         := regexp_replace(c,'(COMPARE PLANS REPORT|COMPARISON DETAILS|Comparison Results.*)','$USAGECOLOR$\1$NOR$');
    c         := regexp_replace(c,chr(10)||rpad('-',93,'-')||chr(10),chr(10)||'$USAGECOLOR$'||rpad('=',100,'=')||'$NOR$'||chr(10));
    :txt      := c;
END;
/
print txt
save res filename