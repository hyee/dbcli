/*[[Show instance parameters, including hidden parameters. Usage: param [keyword] ]]*/
SELECT ksppinm NAME, ksppity TYPE, substr(ksppstdvl,1,80) DISPLAY_VALUE, ksppstdf ISDEFAULT,
       decode(bitand(ksppiflg / 256, 1), 1, 'TRUE', 'FALSE') ISSES_Mdf,
       decode(bitand(ksppiflg / 65536, 3), 1, 'IMMEDIATE', 2, 'DEFERRED', 3, 'IMMEDIATE', 'FALSE') ISSYS_MDF,
       decode(bitand(ksppiflg, 4),
               4,
               'FALSE',
               decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) ISINST_MDF,
       decode(bitand(ksppstvf, 7), 1, 'MODIFIED', 4, 'SYSTEM_MOD', 'FALSE') ISMODIFIED,
       decode(bitand(ksppstvf, 2), 2, 'TRUE', 'FALSE') ISDEPRECATED,ksppdesc DESCRIPTION
FROM   x$ksppi x, x$ksppcv y
WHERE  (x.indx = y.indx)
AND    x.inst_id=USERENV('Instance')
AND   ((:V1 is not null and (ksppinm LIKE LOWER('%'||:V1||'%') or lower(ksppdesc) LIKE LOWER('%'||:V1||'%'))) or (:V1 is null and ksppstdf='FALSE'))
ORDER BY NAME;