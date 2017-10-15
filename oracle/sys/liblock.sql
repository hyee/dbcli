/*[[Library cache lock/pin holders/waiters. Usage: @@NAME [sid|object_name] ]]*/
WITH ho AS
 (SELECT *
  FROM   TABLE(gv$(CURSOR (SELECT /*+leading(h h1 ho) use_hash*/ DISTINCT hl.*,
                                    ho.kglnaown || '.' || ho.kglnaobj object_name,
                                    h.sid || ',' || h.serial# || ',@' || ho.inst_id holder,
                                    h.sql_id holder_sql_id,
                                    h.event holder_event
                    FROM   (SELECT kgllkuse, kgllkhdl, kgllkmod, kgllkreq, 'Lock' kgllktype
                            FROM   x$kgllk
                            UNION ALL
                            SELECT kglpnuse, kglpnhdl, kglpnmod, kglpnreq, 'Pin' kgllktype
                            FROM   x$kglpn) hl,
                           x$kglob ho,
                           v$session h
                    WHERE  hl.KGLLKMOD > 1
                    AND    hl.KGLLKHDL = ho.kglhdadr
                    AND    hl.KGLLKUSE = h.saddr
                    AND    NVL(ho.kglnaown, 'SYS') != 'SYS')))),
wo AS
 (SELECT *
  FROM   TABLE(gv$(CURSOR (SELECT /*+leading(w) use_hash(wo)*/ 
                                    distinct wo.kglnaown || '.' || wo.kglnaobj object_name,
                                    nvl2(w.sid, w.sid || ',' || w.serial# || ',@' || wo.inst_id, NULL) waiter,
                                    w.sql_id waiter_sql_id,
                                    w.event waiter_event
                    FROM   x$kglob wo, v$session w
                    WHERE  wo.kglhdadr = w.p1raw
                    AND    w.event LIKE '%library%'))))
SELECT /*+no_expand use_hash(ho wo)*/ distinct * 
FROM   ho LEFT JOIN wo USING (object_name)
WHERE  (:V1 IS NULL AND wo.waiter IS NOT NULL) 
OR     (:V1 IS NOT NULL AND (upper(object_name) like UPPER('%'||:V1||'%') OR regexp_substr(holder,'\d+')=:V1 OR  regexp_substr(waiter,'\d+')=:V1))