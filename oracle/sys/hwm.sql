/*[[Show high water mark, refer to Doc ID 1020006.6

The script lists the highwater marks for the following parameters:
- HIGH_DML_LOCKS
- MAX_DML_LOCKS
- HIGH_TRANS
- MAX_DML_LOCKS
- HIGH_ENQUEUE
- MAX_ENQUEUE
- HIGH_ENQ_RES
- MAX_ENQ_RES
- HIGH_SESSIONS
- MAX_SESSIONS
- HIGH_PROCESSES
- MAX_PROCESSES
]]*/
SELECT * FROM 
TABLE(GV$(CURSOR(
        SELECT userenv('instance') inst_id,'HIGH_DML_LOCKS' NAME, COUNT(*) VALUE
        FROM   sys.x$ktadm
        WHERE  ksqlkses != hextoraw('00')
        AND    ksqlkres != hextoraw('00')
        UNION ALL
        SELECT userenv('instance') inst_id,'MAX_DML_LOCKS', COUNT(*) MAX_DML_LOCKS
        FROM   sys.x$ktadm
        UNION ALL
        SELECT userenv('instance') inst_id,'HIGH_TRANS', COUNT(*) HIGH_TRANS
        FROM   sys.x$ktcxb
        WHERE  ksqlkses != hextoraw('00')
        AND    ksqlkres != hextoraw('00')
        UNION ALL
        SELECT userenv('instance') inst_id,'MAX_DML_LOCKS', COUNT(*) MAX_DML_LOCKS
        FROM   sys.x$ktadm
        UNION ALL
        SELECT userenv('instance') inst_id,'HIGH_ENQUEUE', COUNT(*) HIGH_ENQUEUE
        FROM   sys.x$ksqeq
        WHERE  ksqlkses != hextoraw('00')
        AND    ksqlkres != hextoraw('00')
        UNION ALL
        SELECT userenv('instance') inst_id,'MAX_ENQUEUE', COUNT(*) MAX_ENQUEUE
        FROM   sys.x$ksqeq
        UNION ALL
        SELECT userenv('instance') inst_id,'HIGH_ENQ_RES', COUNT(*) HIGH_ENQ_RES
        FROM   sys.x$ksqrs
        WHERE  ksqrsidt != chr(0) || chr(0)
        UNION ALL
        SELECT userenv('instance') inst_id,'MAX_ENQ_RES', COUNT(*) MAX_ENQ_RES
        FROM   sys.x$ksqrs
        UNION ALL
        SELECT userenv('instance') inst_id,'HIGH_SESSIONS', COUNT(*) HIGH_SESSIONS
        FROM   sys.x$ksuse
        WHERE  ksuudnam IS NOT NULL
        UNION ALL
        SELECT userenv('instance') inst_id,'MAX_SESSIONS', COUNT(*) MAX_SESSIONS
        FROM   sys.x$ksuse
        UNION ALL
        SELECT userenv('instance') inst_id,'HIGH_PROCESSES', COUNT(*) HIGH_PROCESSES
        FROM   sys.x$ksupr
        WHERE  ksuprunm IS NOT NULL
        UNION ALL
        SELECT userenv('instance') inst_id,'MAX_PROCESSES', COUNT(*) MAX_PROCESSES
        FROM   sys.x$ksupr)))
PIVOT (MAX(VALUE) FOR INST_ID IN(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16))
ORDER BY regexp_substr(name,'_.*'), 1