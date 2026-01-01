/*[[
    Query optimizer fixed controls of the specific session. Usage: @@NAME {[keyword] [sid] [inst_id]} [-f"filter"]
    
    Parameters:
        keyword: Used for fussily search BUGNO+DESCRIPTION+SQL_FEATURE+event+OPTIMIZER_FEATURE_ENABLE
        sid    : When not specified then query current sid
        inst_id: When not specified then query local instance
        -f     : Customized filter. i.e. -f"value=6"

    Sample Output:
    ==============
    SQL> ora fixctl lateral
    SYS_VALUE INST_ID SESSION_ID  BUGNO   VALUE          SQL_FEATURE          DESCRIPTION                                                      OPTIMIZER_FEATURE_ENABLE EVENT IS_DEFAULT CON_ID
    --------- ------- ---------- -------- ----- ----------------------------- ---------------------------------------------------------------- ------------------------ ----- ---------- ------
            1       4       2216  4308414     1 QKSFM_TRANSFORMATION_4308414  outer query must have more than one table unless lateral view    10.1.0.5                 38073          1      0
            1       4       2216  7345484     1 QKSFM_TRANSFORMATION_7345484  merge outerjoined lateral view with filter on left table         10.2.0.3                     0          1      0
            1       4       2216  7499258     1 QKSFM_TRANSFORMATION_7499258  enable copy of lateral view for CBQT                             11.2.0.1                     0          1      0
            1       4       2216  8373261     1 QKSFM_TRANSFORMATION_8373261  Lift restriction on lateral view merge in presence of cursor exp 11.2.0.1                     0          1      0
            1       4       2216 12348584     1 QKSFM_PLACE_GROUP_BY_12348584 disable GBP for lateral oqb with disjunction                     11.2.0.4                     0          1      0
            1       4       2216 22212124     1 QKSFM_TRANSFORMATION_22212124 Enable lateral view decorrelation in UPDATE, DELETE and MERGE    18.1.0                       0          1      0
            1       4       2216 18558952     1 QKSFM_CVM_18558952            Allow CVM for lateral view if valid join cond                    12.2.0.1                     0          1      0
            1       4       2216 22077191     1 QKSFM_TRANSFORMATION_22077191 Enable lateral view decorrelation in CTAS and IAS                12.2.0.1                     0          1      0
            1       4       2216 21979983     1 QKSFM_CURSOR_SHARING_21979983 unpeek binds that disables lateral view merging                  12.2.0.1                     0          1      0
            1       4       2216 23223113     1 QKSFM_SVM_23223113            relax restriction on LATERAL view merge                          12.2.0.1                     0          1      0
            1       4       2216 22258300     1 QKSFM_ACCESS_PATH_22258300    allow sort merge join for outer joined lateral view              12.2.0.1                     0          1      0
            1       4       2216 11727871     1 QKSFM_OUTLINE_11727871        set lateral view start postion to top query block start position 11.2.0.4                     0          1      0

   --[[
       @CHECK_ACCESS_CTL: gv$session_fix_control={gv$session_fix_control}, default={(select userenv('instance') inst_id, a.* from v$session_fix_control a)}
       &FILTER: default={1=1}, f={}
       &V3    : default={&instance}
   --]]
]]*/

SELECT * 
FROM TABLE(GV$(CURSOR(
    SELECT /*+outline_leaf leading(a) use_nl(b)*/ * 
    FROM (SELECT userenv('instance') inst,bugno,value sys_value
          FROM   v$system_fix_control
          WHERE ((:V1 IS NULL AND (:FILTER != '1=1' OR VALUE = 0)) OR
                 (:V1 IS NOT NULL AND lower(BUGNO || DESCRIPTION || SQL_FEATURE || event || OPTIMIZER_FEATURE_ENABLE) LIKE lower(q'[%&V1%]')))
          AND    userenv('instance') = nvl(:V3, userenv('instance'))
          AND    (&filter)) a
    JOIN  v$session_fix_control b USING(bugno)
    WHERE b.session_id=0+nvl(:v2,userenv('sid'))
    AND   userenv('instance') = nvl(:V3, userenv('instance'))
)))
ORDER  BY regexp_substr(OPTIMIZER_FEATURE_ENABLE,'\d+\.\d+')+0 nulls first,bugno;
