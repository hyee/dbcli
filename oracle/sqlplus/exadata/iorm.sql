SET PAGES 999 ARRAYSIZE 50 long 500
col catplan for a30
col dbplan for a80
select * from(
    SELECT cast(extractvalue(xmltype(a.confval), '/cli-output/context/@cell') as varchar2(20)) cell,
           to_clob(REPLACE(nvl2(b.catPlan, b.catPlan.getstringval(), NULL), '/><', '/>' || CHR(10) || '<')) catPlan,
           to_clob(REPLACE(nvl2(b.dbPlan, b.dbPlan.getstringval(), NULL), '/><', '/>' || CHR(10) || '<')) dbPlan,
           b.objective,
           b.status
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/iormplan' PASSING xmltype(a.confval) COLUMNS --
                    catPlan XMLTYPE path 'catPlan/node()',
                    dbPlan XMLTYPE path 'dbPlan/node()',
                    objective VARCHAR2(30) path 'objective',
                    status VARCHAR2(15) path 'status') b
    WHERE  conftype = 'IORM')
ORDER BY 1;