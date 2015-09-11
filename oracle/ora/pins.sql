/*[[Show pinned procedures/packages/functions]]. Usage: ora pins [[owner.]object_name] ]]*/


SELECT --+ opt_param('_optimizer_cartesian_enabled','false') leading(b a) use_hash(b a) no_expand
       a.sid,b.*
FROM   gv$access a, gv$db_object_cache b
WHERE  pins > 0
AND    a.inst_id=b.inst_id
AND    a.owner = b.owner
AND    a.object = b.name
AND    b.owner != 'SYS'
AND    (nvl(instr(:V1,'.'),0)=0 or b.owner=upper(regexp_substr(:V1,'[^\.]+')))
AND    (:V1 is null or instr(:V1,'.')>0 AND b.name=nvl(upper(regexp_substr(:V1,'[^\.]+',1,2)),b.name) or b.name=upper(:V1))
ORDER BY B.OWNER,B.NAME;


/*
WITH r AS
 (SELECT --+materialize
   *
  FROM   dba_ddl_locks
  WHERE  owner NOT LIKE '%SYS%')
SELECT *
FROM   r
WHERE  (owner, NAME) IN (SELECT
                         --+no_merge
                          owner, NAME
                         FROM   gv$db_object_cache
                         WHERE  pins > 0
                         AND    owner NOT LIKE '%SYS%');
*/