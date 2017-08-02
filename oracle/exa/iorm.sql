/*[[cellcli list iormplan. Usage: @@NAME [<cell>]]]*/
set printsize 1000
select * from(
    SELECT extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell,
           REPLACE(nvl2(b.catPlan, b.catPlan.getstringval(), NULL), '/><', '/>' || CHR(10) || '<') catPlan,
           REPLACE(nvl2(b.dbPlan, b.dbPlan.getstringval(), NULL), '/><', '/>' || CHR(10) || '<') dbPlan,
           b.objective,
           b.status
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/iormplan' PASSING xmltype(a.confval) COLUMNS --
                    catPlan XMLTYPE path 'catPlan/node()',
                    dbPlan XMLTYPE path 'dbPlan/node()',
                    objective VARCHAR2(300) path 'objective',
                    status VARCHAR2(300) path 'status') b
    WHERE  conftype = 'IORM')
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER BY 1,2,3