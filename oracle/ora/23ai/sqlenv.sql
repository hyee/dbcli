
/*[[
    List SQL optimizer environment variables. Usage: @@NAME <sql_id> [<hash1>] [<hash2>] [-g|-d] [-diff|-f"<filter>"]
    -g     : only query gv$ views
    -d     : only query dba_hist views
    -diff  : only list the non-default parameters
    <hash> : optionaly specify one or two <optimizer_env_hash_value>/<sql_plan_hash_value>
    --[[
        @ARGS: 1
        @VER: 23={dba_hist_optimizer_env_details} default={(select 0 dbid,0 optimizer_env_hash_value,' ' name,' ' value from dual)}
        &opt: default={A} g={G} d={D}
        &diff: default={1=1} diff={b.isdefault='N' or nvl(lower(a.value),' ')!=nvl(lower(b.value),' ')} 
        @check_access_Sys: {
            sys.X$QKSCESYS={SELECT DISTINCT PNAME_QKSCESYROW NAME,X$QKSCESYS.PVALUE_QKSCESYROW VALUE,FID_QKSCESYROW SQL_FEATURE,DECODE(BITAND(X$QKSCESYS.FLAGS_QKSCESYROW,2),0,'NO','YES') ISDEFAULT FROM SYS.X$QKSCESYS}
            default={SELECT DISTINCT NAME,VALUE,SQL_FEATURE,ISDEFAULT FROM v$sys_optimizer_env}
        }
        &filter: default={1=1} f={}
    --]]
]]*/

col name break
set printsize 10000
WITH lst AS(
    SELECT a.*,
           COUNT(distinct plan_hash) OVER(PARTITION BY name,nvl(trim(lower(value)),' ')) occurs,
           COUNT(distinct plan_hash) OVER(PARTITION BY name) phvs
    FROM (
        SELECT *
        FROM   TABLE(gv$(CURSOR(
            SELECT s.plan_hash_value plan_hash,o.hash_value opt_env_hash, o.name, o.value
            FROM   v$sql s
            JOIN   v$sql_optimizer_env o
            USING  (sql_id, child_number)
            WHERE  sql_id = :v1
            AND    :opt in ('A','G')
            AND    (:v3 IS NULL AND nvl(:v2+0,o.hash_value) IN (s.plan_hash_value,o.hash_value) 
                OR  :v3 IS NOT NULL AND s.plan_hash_value IN(:v2+0,:v3+0) OR o.hash_value IN(:v2+0,:v3+0))
            )))
        UNION
        SELECT /*+ outline_leaf no_merge(s) leading(s)*/
               s.plan_hash_value,optimizer_env_hash_value, d.name, d.value
        FROM   dba_hist_sqlstat s
        JOIN   &VER d
        USING  (dbid, optimizer_env_hash_value)
        WHERE  sql_id = :v1
        AND    dbid=:dbid
        AND    :opt in ('A','D')
        AND    (:v3 IS NULL AND nvl(:v2+0,optimizer_env_hash_value) IN (s.plan_hash_value,optimizer_env_hash_value)
             OR :v3 IS NOT NULL AND s.plan_hash_value IN(:v2+0,:v3+0) OR optimizer_env_hash_value IN(:v2+0,:v3+0))
    ) a
)
SELECT /*+OPT_PARAM('_fix_control' '26552730:0') opt_param('_no_or_expansion' 'true') opt_param('_optimizer_cbqt_or_expansion' 'off')*/* 
FROM (
    SELECT a.*,'|' "|",b.value sys_value,b.isdefault,b.SQL_FEATURE
    FROM (
        SELECT decode(phvs,1,''||opt_env_hash,'<SAME>') opt_env_hash,null plan_hash,name,value,occurs,phvs all_plans
        FROM lst 
        WHERE occurs=phvs AND phvs>1
        UNION
        SELECT ''||opt_env_hash,plan_hash,name,value,phvs,occurs
        FROM lst 
        WHERE occurs!=phvs OR phvs=1
    ) a
    LEFT JOIN (&check_access_Sys) b
    ON    (a.name=b.name)
    WHERE (b.isdefault IS NULL OR &diff))
WHERE   (&filter)
ORDER BY decode(opt_env_hash,'<SAME>',1,2),lower(name),plan_hash