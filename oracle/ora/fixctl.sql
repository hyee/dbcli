/*[[
    Query optimizer fixed controls of the specific session. Usage: @@NAME {[keyword] [sid] [inst_id]} [-f"filter"]
    
    Parameters:
        keyword: Used for fussily search BUGNO+DESCRIPTION+SQL_FEATURE+event+OPTIMIZER_FEATURE_ENABLE
        sid    : When not specified then query current sid
        inst_id: When not specified then query local instance

    Sample Output:
    ==============
    ORCL> ora fixctl lateral
    INST_ID SESSION_ID  BUGNO   VALUE          SQL_FEATURE          DESCRIPTION                                                      OPTIMIZER_FEATURE_ENABLE EVENT IS_DEFAULT
    ------- ---------- -------- ----- ----------------------------- ---------------------------------------------------------------- ------------------------ ----- ----------
          1         69  4308414     1 QKSFM_TRANSFORMATION_4308414  outer query must have more than one table unless lateral view    10.1.0.5                 38073          1
          1         69  7345484     1 QKSFM_TRANSFORMATION_7345484  merge outerjoined lateral view with filter on left table         10.2.0.3                     0          1
          1         69  7499258     1 QKSFM_TRANSFORMATION_7499258  enable copy of lateral view for CBQT                             11.2.0.1                     0          1
          1         69  8373261     1 QKSFM_TRANSFORMATION_8373261  Lift restriction on lateral view merge in presence of cursor exp 11.2.0.1                     0          1
          1         69 12348584     1 QKSFM_PLACE_GROUP_BY_12348584 disable GBP for lateral oqb with disjunction                     11.2.0.3                     0          1
          1         69 11727871     1 QKSFM_OUTLINE_11727871        set lateral view start postion to top query block start position 11.2.0.4                     0          1

   --[[
       @CHECK_ACCESS_CTL: gv$session_fix_control={gv$session_fix_control}, default={(select userenv('instance') inst_id, a.* from v$session_fix_control a)}
       &FILTER: default={1=1}, f={}
   --]]
]]*/
select * from &CHECK_ACCESS_CTL
where ((:V1 IS NULL and value=0)
  or   (:V1 IS NOT NULL and lower(BUGNO||DESCRIPTION||SQL_FEATURE||event||OPTIMIZER_FEATURE_ENABLE) like lower(q'[%&V1%]')))
AND    inst_id=nvl(:V3,userenv('instance'))
and    session_id=nvl(:V2,userenv('sid')) 
AND    &filter
order by 1