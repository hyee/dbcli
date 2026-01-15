
/*[[List SQL optimizer environment variables. Usage: @@NAME <sql_id> [<optimizer_env_hash_value>] [-g|-d] [-diff]
    -g   : only query gv$ views
    -d   : only query dba_hist views
    -diff: only list the non-default parameters
    --[[
        @ARGS: 1
        @VER: 23={dba_hist_optimizer_env_details} default={(select 0 dbid,0 optimizer_env_hash_value,' ' name,' ' value from dual)}
        &opt: default={A} g={G} d={D}
        &diff: default={1=1} diff={b.isdefault='N' or nvl(a.value,' ')!=nvl(b.value,' ')} 
        @check_access_Sys: {
            sys.X$QKSCESYS={SELECT DISTINCT PNAME_QKSCESYROW NAME,X$QKSCESYS.PVALUE_QKSCESYROW VALUE,FID_QKSCESYROW SQL_FEATURE,DECODE(BITAND(X$QKSCESYS.FLAGS_QKSCESYROW,2),0,'NO','YES') ISDEFAULT FROM SYS.X$QKSCESYS}
            default={SELECT DISTINCT NAME,VALUE,SQL_FEATURE,ISDEFAULT FROM v$sys_optimizer_env}
        }
    --]]
]]*/
WITH lst AS(
    SELECT /*+OPT_PARAM('_fix_control' '26552730:0') opt_param('_or_expand_nvl_predicate' 'false')*/
           a.*,
           COUNT(1) OVER(PARTITION BY name,value) occurs,
           COUNT(DISTINCT plan_hash_value) OVER() phvs
    FROM (
        SELECT *
        FROM   TABLE(gv$(CURSOR(
            SELECT s.plan_hash_value,o.hash_value opt_env_hash, o.name, o.value
            FROM   v$sql s
            JOIN   v$sql_optimizer_env o
            USING  (sql_id, child_number)
            WHERE  sql_id = :v1
            AND    :opt in ('A','G')
            AND    nvl(:v2,o.hash_value)=o.hash_value )))
        UNION
        SELECT /*+no_expand outline_leaf no_merge(s) leading(s)*/
               s.plan_hash_value,optimizer_env_hash_value, d.name, d.value
        FROM   dba_hist_sqlstat s
        JOIN   &VER d
        USING  (dbid, optimizer_env_hash_value)
        WHERE  sql_id = :v1
        AND    dbid=:dbid
        AND    :opt in ('A','D')
        AND    nvl(:v2,optimizer_env_hash_value)=optimizer_env_hash_value) a
)
SELECT a.*,b.isdefault,b.SQL_FEATURE
FROM (
    SELECT decode(phvs,1,''||opt_env_hash,'PUBLIC') opt_env_hash,null plan_hash_value,name,value,phvs plan_hashs,occurs
    FROM LST 
    WHERE occurs=phvs
    UNION ALL
    SELECT ''||opt_env_hash,plan_hash_value,name,value,phvs,occurs
    FROM LST 
    WHERE occurs<phvs
) a
LEFT JOIN (&check_access_Sys) b 
ON (a.name=b.name)
WHERE (occurs<plan_hashs OR plan_hashs=1 OR nvl(b.isdefault,'Y')='N')
AND  (b.isdefault IS NULL OR &diff) 
ORDER BY decode(opt_env_hash,'PUBLIC',1,2),a.name,plan_hash_value