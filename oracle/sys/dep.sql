/*[[Show cursors that depending on the specific object. Usage: @@NAME {[owner.]<object_name>|-c <sql_id>]} [instance]
    --[[
        &V2: default={&instance}
        &filter: default={g.kglnaobj = :object_name and g.kglnaown = :object_owner AND GREATEST(c.KGLHDLMD,c.KGLHDPMD)>1} c={c.KGLOBT03=:V1 AND c.kglhdnsp = 0}
        &getobj: default={} c={--}
    --]]
]]*/

&getobj findobj "&V1" 0 1

SELECT * FROM TABLE(GV$(CURSOR(
    SELECT /*+ordered*/ userenv('instance') inst_id,
           g.kglnaown,
           g.kglnaobj,
           decode(c.kglhdnsp,
                  0,'CURSOR',
                  1,'TABLE / PROCEDURE',
                  2,'BODY',
                  3,'TRIGGER',
                  4,'INDEX',
                  5,'CLUSTER',
                  6,'OBJECT',
                  13,'JAVA SOURCE',
                  14,'JAVA RESOURCE',
                  15,'REPLICATED TABLE OBJECT',
                  16,'REPLICATION INTERNAL PACKAGE',
                  17,'CONTEXT POLICY',
                  18,'PUB_SUB',
                  19,'SUMMARY',
                  20,'DIMENSION',
                  21,'APP CONTEXT',
                  22,'STORED OUTLINE',
                  23,'RULESET',
                  24,'RSRC PLAN',
                  25,'RSRC CONSUMER GROUP',
                  26,'PENDING RSRC PLAN',
                  27,'PENDING RSRC CONSUMER GROUP',
                  28,'SUBSCRIPTION',
                  29,'LOCATION',
                  30,'REMOTE OBJECT',
                  31,'SNAPSHOT METADATA',
                  32,'JAVA SHARED DATA',
                  33,'SECURITY PROFILE',
                  'INVALID NAMESPACE') AS namespace,
           c.KGLOBTYD AS TYPE,
           decode(bitand(c.kglobflg, 3),
                  0,'NOT LOADED',
                  2,'NON - EXISTENT',
                  3,'INVALID STATUS',
                  decode(c.kglobtyp,
                         0,'CURSOR',
                         1,'INDEX',
                         2,'TABLE',
                         3,'CLUSTER',
                         4,'VIEW',
                         5,'SYNONYM',
                         6,'SEQUENCE',
                         7,'PROCEDURE',
                         8,'FUNCTION',
                         9,'PACKAGE',
                         10,'NON-EXISTENT',
                         11,'PACKAGE BODY',
                         12,'TRIGGER',
                         13,'TYPE',
                         14,'TYPE BODY',
                         15,'OBJECT',
                         16,'USER',
                         17,'DBLINK',
                         18,'PIPE',
                         19,'TABLE PARTITION',
                         20,'INDEX PARTITION',
                         21,'LOB',
                         22,'LIBRARY',
                         23,'DIRECTORY',
                         24,'QUEUE',
                         25,'INDEX-ORGANIZED TABLE',
                         26,'REPLICATION OBJECT GROUP',
                         27,'REPLICATION PROPAGATOR',
                         28,'JAVA SOURCE',
                         29,'JAVA CLASS',
                         30,'JAVA RESOURCE',
                         31,'JAVA JAR',
                         'INVALID TYPE:' || c.KGLOBTYP)) AS ftype,
           c.kglhdldc AS LOADS,
           c.kglhdexc AS EXECS,
           c.kglhdlkc AS LOCKS,
           c.kglobpc0 AS PINS,
           c.kglhdclt AS CHILD_LATCH,
           c.kglhdivc AS INVALIDS,
           DECODE(c.KGLHDLMD, 0, 'NONE', 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'UNKOWN') AS LOCK_MODE,
           DECODE(c.KGLHDPMD, 0, 'NONE', 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'UNKOWN') AS PIN_MODE,
           DECODE(c.KGLOBSTA, 1, 'VALID', 2, 'VALID_AUTH_ERROR', 3, 'VALID_COMPILE_ERROR', 4, 'VALID_UNAUTH', 5, 'INVALID_UNAUTH', 6, 'INVALID', 'UNKOWN') AS STATUS,
           c.kglobt03 sql_id,
           substr(TRIM(regexp_replace(REPLACE(c.kglnaobj, chr(0)), '[' || chr(10) || chr(13) || chr(9) || ' ]+', ' ')), 1, 200) sql_text
    FROM   sys.x$kglob g, sys.x$kgldp k, sys.x$kglxs a, sys.x$kglob c
    WHERE  &filter
    AND    g.kglhdadr = k.kglrfhdl
    AND    k.kglhdadr = a.kglhdadr /* make sure it is not a transitive */
    AND    k.kgldepno = a.kglxsdep /* reference, but a direct one */
    AND    k.kglhdadr = c.kglhdadr
    AND    userenv('instance')+0 = nvl(0+:V2,userenv('instance')+0)
)))
