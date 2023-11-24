/*[[
Show execution plan. Usage: @@NAME [x|<plan_id>|<sql_id>] [<plan_hash>|<child#>|<sql_handle>] [<format>] [-all|-last|-b|-s|-ol|-adv] [-g|-d] 

Options:
    -b    : show binding variables
    -d    : only show the plan from AWR views
    -g    : only show the plan from GV$ views
    -s    : the plan with the simplest 'basic' format
    -ol   : show outline information
    -adv  : the plan with the 'advanced' format
    -all  : the plan with the 'ALLSTATS ALL' format
    -last : the plan with the 'ALLSTATS LAST' format

--[[

    &STAT: default={&DF &adaptive &binds &V3 &V4 &V5 &V6 &V7 &V8 &V9}
    &V1: default={&_SQL_ID} last={X} x={X}
    &V3: none={} ol={outline alias &hint}
    &LAST: last={LAST} all={OUTLINE ALL} allstats={}
    &DF: default={ALLSTATS PARALLEL COST PARTITION REMOTE &LAST -PROJECTION -ALIAS}, basic={BASIC}, adv={advanced}, all={ALLSTATS ALL outline alias}
    &SRC: {
            default={0}, # Both
            d={2},       # Dictionary only
            g={1}        # GV only
          }
    &binds: default={}, b={PEEKED_BINDS}
    @check_access_aux: default={(26/8/12)-6}
    @adaptive: 12.1={+REPORT +ADAPTIVE +METRICS} 11.2={+METRICS} default={}
    @hint    : 19={+HINT_REPORT -QBREGISTRY} DEFAULT={}
    @proj:  {11.2={nullif(regexp_count(projection,'\[[A-Z0-9,]+\](,|$)'),0) proj,nvl2(access_predicates,0+regexp_substr(projection,'#keys=(\d+)',1,1,'i',1),null) keys,0+regexp_substr(projection,'rowset=(\d+)',1,1,'i',1) rowsets},
             default={(select nullif(count(1),0) from dual connect by regexp_substr(projection,'\[[A-Z0-9,]+\](,|$)',1,level) is not null) proj,nullif(0,0) keys,nullif(0,0) rowsets}
             }
    @check_access_ab : dba_hist_sqlbind={1} default={0}
    &check_access_pdb: default={DBA_HIST_} pdb={AWR_PDB_}
    &dop : default={max(nvl2(other_xml,regexp_substr(regexp_substr(to_char(substr(other_xml,1,512)),'<info type="dop" note="y">\d+</info>'),'\d+')/1.1111,1))}
    @check_access_awr: {
           dba_hist_sql_plan={UNION ALL
                  SELECT /*+no_expand*/ id,
                         min(id) over() minid,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         plan_hash_value,
                         2,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         dbid,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         io_cost,position,
                         &proj,
                         access_predicates ap,filter_predicates fp,search_columns sc,
                         &dop over(partition by plan_hash_value) dop,
                         &d_mbrc mbrc
                  FROM   &check_access_pdb.sql_plan a
                  WHERE  a.sql_id = '&v1'
                  AND    &SRC != 1
                  AND    '&v1' not in('X','&_sql_id')
                  AND    a.plan_hash_value = coalesce('&v2'+0,(
                     select --+precompute_subquery index(c.sql(WRH$_SQLSTAT.SQL_ID)) index(c.sn)
                            max(plan_hash_value) keep(dense_rank last order by snap_id)
                     from &check_access_pdb.sqlstat c 
                     where sql_id='&v1' 
                     AND   &SRC != 1
                     AND  dbid=a.dbid
                     AND   '&v1' not in('X','&_sql_id')),(
                     select /*+precompute_subquery*/ 
                            max(plan_hash_value) keep(dense_rank last order by timestamp) 
                     from &check_access_pdb.sql_plan 
                     where sql_id='&v1'
                     AND   &SRC != 1
                     AND    '&v1' not in('X','&_sql_id')
                     AND  dbid=a.dbid))} 
           default={0}
          }
    @check_access_advisor: {
           dba_advisor_sqlplans={
                  UNION ALL
                  SELECT id,
                         min(id) over() minid,
                         parent_id,
                         plan_hash_value,
                         4,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         plan_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         io_cost,position,
                         &proj,
                         access_predicates ap,filter_predicates fp,search_columns sc,
                         &dop over(partition by PLAN_ID) dop,
                         &g_mbrc mbrc
                  FROM   dba_advisor_sqlplans a
                  WHERE  a.sql_id = '&v1'
                  AND    &SRC = 0
                  AND    '&v1' not in('X','&_sql_id')
                  AND    (a.task_id,a.plan_hash_value) = (
                        select /*+precompute_subquery*/ max(task_id),max(plan_hash_value) keep(dense_rank last order by task_id,timestamp) 
                        from   dba_advisor_sqlplans 
                        where  sql_id='&v1'
                        AND    &SRC = 0
                        AND    '&v1' not in('X','&_sql_id')
                        and    plan_hash_value=nvl('&v2'+0,plan_hash_value))}
           default={}
    }

    @check_access_spm: {
           sys.sqlobj$plan={
                  UNION ALL
                  SELECT id,
                         min(id) over() minid,
                         parent_id,
                         null,
                         5,
                         TIMESTAMP,
                         NULL child_number,
                         st.sql_handle,
                         st.signature,
                         plan_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         io_cost,position,
                         &proj,
                         access_predicates ap,filter_predicates fp,search_columns sc,
                         &dop over(partition by PLAN_ID) dop,
                         &g_mbrc mbrc
                  FROM   sys.sql$text st,sys.sqlobj$plan a,(select plan_id p,signature,name from sys.sqlobj$) o
                  WHERE  '&v1' in(st.sql_handle,o.name)
                  AND    &SRC = 0
                  AND    '&v1' not in('X','&_sql_id')
                  AND    a.signature = st.signature
                  AND    a.signature = o.signature
                  AND    a.plan_id   = o.p
                  AND    ('&v1' = o.name or a.plan_id = coalesce('&V2'+0,(
                        select max(plan_id) keep(dense_rank last order by timestamp) 
                        from   sys.sqlobj$plan b 
                        where  b.signature=a.signature
                        AND    &SRC = 0
                        AND   '&v1' not in('X','&_sql_id'))))
           }
           default={}
    }
]]--
]]*/
set PRINTSIZE 9999
set feed off pipequery off verify off


VAR C REFCURSOR Binding Variables
VAR msg VARCHAR2
DECLARE/*INTERNAL_DBCLI_CMD*/
    msg       VARCHAR2(100);
    BINDS     XMLTYPE := XMLTYPE('<BINDS/>');
    ELEM      XMLTYPE;
    BIND_VAL  SYS.ANYDATA;
    BIND_TYPE VARCHAR2(128);
    DTYPE     VARCHAR2(128);
    STR_VAL   VARCHAR2(32767);
BEGIN
    IF :binds = 'PEEKED_BINDS' THEN
        FOR r IN (WITH qry AS
                       (SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/ 
                               a.*, dense_rank() over(ORDER BY decode('&V2',c,0,1),captured, r DESC) seq
                       FROM   (SELECT a.*, decode(MAX(was_captured) over(PARTITION BY r), 'YES', 0, 1) captured
                               FROM   (SELECT MAX(LAST_CAPTURED) OVER(PARTITION BY child_number,inst_id) || child_number || ':' || INST_ID r,
                                              ''||child_number c,
                                              was_captured,
                                              position,
                                              NAME,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              inst_id,
                                              last_captured,
                                              'GV$SQL_BIND_CAPTURE' SRC
                                       FROM   gv$sql_bind_capture a
                                       WHERE  sql_id = '&v1'
                                       AND    &SRC!=2
                                       $IF &check_access_ab=1 $THEN
                                       UNION ALL
                                       SELECT MAX(LAST_CAPTURED) OVER(PARTITION BY DBID,SNAP_ID,INSTANCE_NUMBER)||DBID||':'|| SNAP_ID || ':' || INSTANCE_NUMBER,
                                              ''||SNAP_ID c,
                                              was_captured,
                                              position,
                                              NAME,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              instance_number,
                                              last_captured,
                                              'DBA_HIST_SQLBIND' SRC
                                       FROM   &check_access_pdb.sqlbind a
                                       WHERE  sql_id = '&v1'
                                       AND    &SRC!=1
                                       AND    dbid=&dbid
                                       $END
                                       ) a) a)
                      SELECT inst_id inst,
                             position pos#,
                             qry.NAME,
                             datatype,
                             datatype_string,
                             value_string,
                             value_anydata,
                             to_char(qry.last_captured) last_captured,
                             src
                      FROM   qry
                      WHERE  seq = 1
                      ORDER  BY position) LOOP
            DTYPE    := r.datatype_string;
            BIND_VAL := r.value_anydata;
            IF BIND_VAL IS NOT NULL THEN
                CASE ANYDATA.GETTYPENAME(BIND_VAL)
                    WHEN ('SYS.NUMBER') THEN
                        STR_VAL := TO_CHAR(ANYDATA.ACCESSNUMBER(BIND_VAL));
                    WHEN ('SYS.VARCHAR2') THEN
                        STR_VAL := ANYDATA.ACCESSVARCHAR2(BIND_VAL);
                    WHEN ('SYS.DATE') THEN
                        STR_VAL := TO_CHAR(ANYDATA.ACCESSDATE(BIND_VAL));
                    WHEN ('SYS.RAW') THEN
                        STR_VAL := RAWTOHEX((ANYDATA.ACCESSRAW(BIND_VAL)));
                    WHEN ('SYS.CHAR') THEN
                        STR_VAL := ANYDATA.ACCESSCHAR(BIND_VAL);
                    WHEN ('SYS.NCHAR') THEN
                        STR_VAL := ANYDATA.ACCESSNCHAR(BIND_VAL);
                    WHEN ('SYS.NVARCHAR2') THEN
                        STR_VAL := ANYDATA.ACCESSNVARCHAR2(BIND_VAL);
                    WHEN ('SYS.UROWID') THEN
                        STR_VAL := ANYDATA.ACCESSUROWID(BIND_VAL);
                    WHEN ('SYS.TIMESTAMP') THEN
                        STR_VAL := TRIM('0' FROM ANYDATA.ACCESSTIMESTAMP(BIND_VAL));
                    ELSE
                        STR_VAL := NVL(r.value_string,'NOT AVAILABLE');
                END CASE;
            ELSE
                str_val := '<NOT CAPTURE>';
            END IF;
        
            SELECT XMLELEMENT("BIND",
                              XMLELEMENT("inst", r.inst),
                              XMLELEMENT("pos", r.pos#),
                              XMLELEMENT("name", r.name),
                              XMLELEMENT("value", nvl(str_val,r.value_string)),
                              XMLELEMENT("dtype", dtype),
                              XMLELEMENT("last_captured", r.last_captured),
                              XMLELEMENT("src", r.src))
            INTO   ELEM
            FROM   DUAL;
            BINDS := BINDS.APPENDCHILDXML('/*', ELEM);
        END LOOP;
        OPEN :C FOR
            SELECT EXTRACTVALUE(COLUMN_VALUE, '//inst') + 0 inst,
                   EXTRACTVALUE(COLUMN_VALUE, '//pos') + 0 pos#,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//name') AS VARCHAR2(128)) NAME,
                   EXTRACTVALUE(COLUMN_VALUE, '//value') VALUE,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//dtype') AS VARCHAR2(30)) data_type,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//last_captured') AS VARCHAR2(20)) last_captured,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//src') AS VARCHAR2(30)) SOURCE
            FROM   TABLE(XMLSEQUENCE(EXTRACT(BINDS, '/BINDS/BIND')));
    END IF;
    
    IF '&v1' = '&_SQL_ID' THEN
        msg  := 'Displaying execution plan for last SQL: &_SQL_ID';
        :msg := 'PRO ' || msg || chr(10) || 'PRO ' || rpad('=', length(msg), '=');
    END IF;
END;
/

&msg

print c
WITH /*INTERNAL_DBCLI_CMD*/ sql_plan_data AS
 (SELECT /*+materialize opt_param('optimizer_dynamic_sampling' 5) OPT_PARAM('_fix_control' '26552730:0')*/ *
  FROM   (SELECT /*+no_merge(a) NO_PQ_CONCURRENT_UNION*/ distinct a.*,
                 dense_rank() OVER(ORDER BY flag, tm DESC, child_number DESC, plan_hash_value DESC,inst_id) seq
          FROM   (SELECT /*+no_expand*/ id,
                         min(id) over() minid,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         child_number    ha,
                         1               flag,
                         TIMESTAMP       tm,
                         child_number,
                         sql_id,
                         plan_hash_value,
                         inst_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         io_cost,position,
                         &proj,
                         access_predicates ap,filter_predicates fp,search_columns sc,
                         &dop over(partition by inst_id,child_number) dop,
                         &g_mbrc mbrc
                  FROM   gv$sql_plan_statistics_all a
                  WHERE  a.sql_id = '&v1'
                  AND   ('&v1' != '&_sql_id' or inst_id=userenv('instance'))
                  AND    '&v1' !='X'
                  AND    &SRC != 2
                  AND    nvl('&V2'+0,-1) in(plan_hash_value,child_number,-1)
                  UNION ALL
                  SELECT /*+no_expand*/ id,
                         min(id) over() minid,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         plan_hash_value,
                         3,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         sqlset_id plan_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         io_cost,position,
                         &proj,
                         access_predicates ap,filter_predicates fp,search_columns sc,
                         &dop over(partition by SQLSET_ID,plan_hash_value) dop,
                         &g_mbrc mbrc
                  FROM   all_sqlset_plans a
                  WHERE  a.sql_id = '&v1'
                  AND    &SRC = 0
                  AND    '&v1' not in('X','&_sql_id')
                  AND    (sqlset_id,a.plan_hash_value) = (
                        select /*+precompute_subquery*/ 
                               max(sqlset_id),
                               max(plan_hash_value) keep(dense_rank last order by sqlset_id,timestamp) 
                        from   all_sqlset_plans 
                        where  sql_id='&V1'
                        AND    &SRC = 0
                        AND    '&v1' not in('X','&_sql_id')
                        and    plan_hash_value=nvl('&V2'+0,plan_hash_value))
                  &check_access_awr
                  &check_access_advisor
                  &check_access_spm
                  UNION  ALL
                  SELECT /*+noparallel*/
                         id,
                         min(id) over()  minid,
                         parent_id,
                         NULL            ha,
                         9               flag,
                         NULL            tm,
                         NULL,
                         ''||plan_id,
                         max(decode(id, 1, regexp_substr(regexp_substr(to_char(substr(other_xml,1,2000)), 'plan_hash_full.*?(\d+)', 1, 1, 'i'),'\d+'))) over()+0 plan_hash_value,
                         NULL,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         io_cost,position,
                         &proj,
                         access_predicates ap,filter_predicates fp,search_columns sc,
                         &dop over(partition by plan_id) dop,
                         &g_mbrc mbrc
                  FROM   plan_table a
                  WHERE  '&v1' not in('&_sql_id')
                  AND    &SRC = 0
                  AND    (plan_id,timestamp)=(
                      select /*+precompute_subquery*/ 
                             max(plan_id) keep(dense_rank last order by timestamp),
                             max(timestamp)
                      from   plan_table
                      where  nvl(upper('&V1'),'X') in(statement_id,''||plan_id,'X')
                      AND    &SRC = 0
                      AND    '&v1' not in('&_sql_id'))) a
         )
  WHERE  seq = 1),
hierarchy_data AS
 (SELECT /*+CONNECT_BY_COMBINE_SW NO_CONNECT_BY_FILTERING*/
         id, parent_id pid,qb,alias,plan_hash_value phv,minid,io_cost,rownum r_,
         ap,fp,dop,mbrc,nvl(nullif(sc,0),keys) sc,nvl2(rowsets,'R'||rowsets||nvl2(proj,'/P'||proj,''),proj) proj
  FROM   sql_plan_data
  START  WITH id = minid
  CONNECT BY PRIOR id = parent_id
  ORDER  SIBLINGS BY position desc,id DESC),
ordered_hierarchy_data AS
(SELECT /*+materialize*/ A.*,
        CASE 
            WHEN nvl(ap,sc) IS NOT NULL THEN 'A'
        END||CASE 
            WHEN sc IS NOT NULL THEN sc
            WHEN ap IS NOT NULL THEN 
              (SELECT count(distinct regexp_substr(regexp_substr(replace(ap,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level),'".*"'))
               FROM   dual
               connect by regexp_substr(replace(ap,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level) IS NOT NULL)
        END||CASE 
            WHEN fp IS NOT NULL THEN
            (SELECT 'F'||count(distinct regexp_substr(regexp_substr(replace(fp,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level),'".*"'))
             FROM dual
             connect by regexp_substr(replace(fp,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level) IS NOT NULL) 
        END pred
 FROM(SELECT a.*,
             '"'||regexp_substr(NVL(ALIAS,FIRST_VALUE(ALIAS IGNORE NULLs) OVER(ORDER BY r_ ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)),'[^@]+')||'".' al,
             row_number() over(PARTITION BY phv ORDER BY r_ DESC) AS OID,
             MAX(id) over(PARTITION BY phv) AS maxid
      FROM   hierarchy_data a) a),
qry AS
 (SELECT DISTINCT sql_id sq,
                  flag flag,
                  '&STAT' format,
                  NVL(child_number, plan_hash_value) plan_hash,
                  inst_id
  FROM   sql_plan_data
  WHERE  rownum<2),
xplan AS
 (SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display( '&check_access_pdb.sql_plan',NULL,format,'dbid='||inst_id||' and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 2
  UNION ALL
  SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display( 'all_sqlset_plans',NULL,format,'sqlset_id='||inst_id||' and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 3
  UNION ALL
  SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display( 'dba_advisor_sqlplans',NULL,format,'plan_id='||inst_id||' and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 4
  UNION ALL
  SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display( 'sys.sqlobj$plan',NULL,format,'plan_id='||inst_id||' and signature=' || plan_hash)) a
  WHERE  flag = 5
  UNION ALL
  SELECT a.*
  FROM   qry,TABLE(dbms_xplan.display('plan_table',NULL,format,'plan_id=' || sq)) a
  WHERE  flag = 9
  UNION  ALL
  SELECT a.*
  FROM   qry,TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'child_number=' || plan_hash || ' and sql_id=''' || sq ||''' and inst_id=' || inst_id)) a
  WHERE  flag = 1),
xplan_data AS
 (SELECT /*+use_hash(o x) no_merge(o)*/
           x.plan_table_output AS plan_table_output,
           nvl(o.id,x.oid) id,
           o.pid,
           o.pred,o.qb,o.alias,o.proj,
           o.oid,
           o.maxid,
           r,
           max(o.minid) over() as minid,
           COUNT(*) over() AS rc,
           nvl(trim(dbms_xplan.format_number(CASE 
               WHEN REGEXP_LIKE(x.plan_table_output,'(TABLE ACCESS [^|]*(FULL|SAMPLE)|INDEX .*FAST FULL)') THEN
                   greatest(1,floor(io_cost*nvl(dop*1.009,1)/mbrc))
               ELSE
                   io_cost
           END)),' ') blks
  FROM   (select rownum r, 
                 CASE WHEN regexp_like(plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(plan_table_output, '[0-9]+')) END oid,
                 x.* 
         from   xplan x) x
  LEFT   OUTER JOIN ordered_hierarchy_data o
  ON     (o.id = x.oid)
  ORDER  BY x.oid)
SELECT plan_table_output
FROM   xplan_data --
model  dimension by (r)
measures(plan_table_output,id,maxid,pred,oid,minid,qb,alias,nullif(proj,null) proj,blks,
         greatest(max(length(maxid)) over () + 3, 5) as csize,
         nvl(greatest(max(length(pred)) over () + 3, 7),0) as psize,
         nvl(greatest(max(length(qb)) over () + 3, 6),0) as qsize,
         nvl(greatest(max(length(alias)) over () + 3, 8),0) as asize,
         nvl(greatest(max(length(proj)) over () + 3, 7),0) as jsize,
         greatest(max(length(blks)) over () + 2,7) bsize,
         cast(null as varchar2(128)) as inject,
         rc)
rules sequential order (
        inject[r] = case
              when plan_table_output[cv()] like '------%' then 
                   rpad('-', csize[cv()]+psize[cv()]+jsize[cv()]+qsize[cv()]+asize[cv()]+bsize[cv()]+1, '-') || '{PLAN}'  
              when id[cv()+2] = 0 then
                   '|' || lpad('Ord ', csize[cv()]) || '{PLAN}' 
                       || rpad(' Blks',bsize[cv()]-1)||'|'
                       || decode(psize[cv()],0,'',rpad(' Pred', psize[cv()]-1)||'|')
                       || lpad('Proj |', jsize[cv()]) 
                       || decode(qsize[cv()],0,'',rpad(' Q.B', qsize[cv()]-1)||'|')
                       || decode(asize[cv()],0,'',rpad(' Alias', asize[cv()]-1)||'|')
              when id[cv()] is not null then
                   '|' || lpad(oid[cv()]||' ', csize[cv()]) || '{PLAN}'
                       || lpad(blks[cv()],bsize[cv()]-1)||'|'
                       || decode(psize[cv()],0,'',rpad(' '||pred[cv()], psize[cv()]-1)||'|')
                       || lpad(proj[cv()] || ' |', jsize[cv()]) 
                       || decode(qsize[cv()],0,'',rpad(' '||qb[cv()], qsize[cv()]-1)||'|')
                       || decode(asize[cv()],0,'',rpad(' '||alias[cv()] , asize[cv()]-1)||'|')
          end,
        plan_table_output[r] = case
             when inject[cv()] is not null then
                  replace(inject[cv()], '{PLAN}',plan_table_output[cv()])
             else plan_table_output[cv()]
         end)
order  by r;
