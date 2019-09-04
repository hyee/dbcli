/*[[
	Show mutex sleep info. Usage: @@NAME [<recent minutes>] 
	Refer to Doc ID 1298015.1/1298471.1/1310764.1

  Mainly used to diagnostic below events:
  =======================================
  * cursor: mutex X                  
  * cursor: mutex S                  
  * cursor: pin X                    
  * cursor: pin S                    
  * cursor: pin S wait on X          
  * library cache: mutex X           
  * library cache: bucket mutex X    
  * library cache: dependency mutex X
  * library cache: mutex S           


	Example Output:
	================
    INST_ID        LAST_TIME           HASH    SLEEPS CNT     LOCATION      MUTEX_TYPE   OBJECT
    ------- ----------------------- ---------- ------ --- ---------------- ------------- -------------------
          2 2019-09-03 23:56:10.107 1011610568     25  25 kglhdgn2 106     Library Cache select type#,blocks
          2 2019-09-03 23:56:10.108 1736623433      5   5 kglpndl1  95     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      4   4 kgllkdl1  85     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      3   2 kglpnal1  90     Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      3   2 kglget2   2      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      2   2 kglpin1   4      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      1   1 kglpnal2  91     Library Cache SEG$
          3 2019-09-03 23:27:39.394 1736623433      3   3 kglpndl1  95     Library Cache SEG$
]]*/

set feed off

SELECT *
FROM   TABLE(gv$(CURSOR ( --
          SELECT /*+ordered user_nl(b)*/
                  userenv('instance') inst_id,
                  sid,
                  a.event,
                  decode(trunc(p2 / 4294967296), 0, trunc(P2 / 65536), trunc(P2 / 4294967296)) SID_HOLDING_MUTEX,
                  a.sql_id,
                  b.kglobt03 req_sql_id,
                  substr(TRIM(b.KGLNAOBJ), 1, 100) || CASE
                      WHEN b.KGLNAOBJ LIKE 'table_%' AND
                           regexp_like(regexp_substr(b.KGLNAOBJ, '[^\_]+', 1, 4), '^[0-9A-Fa-f]+$') THEN
                       ' (obj# ' || to_number(regexp_substr(b.KGLNAOBJ, '[^\_]+', 1, 4), 'xxxxxxxxxx') || ')'
                  END SQL_TEXT
          FROM   v$session a, x$kglob b, x$mutex_sleep c
          WHERE  a.p1 = b.kglnahsh
          AND    trunc(a.p3 / 65536) = c.location_id(+)
          AND    a.p1text = 'idn'
          AND    a.p2text = 'value'
          AND    a.p3text = 'where'
          AND    userenv('instance') = nvl(:instance, userenv('instance')))));

SELECT *
FROM   TABLE(gv$(CURSOR(
                  SELECT userenv('instance') inst_id,
                         MAX(SLEEP_TIMESTAMP) LAST_TIME,
                         kglnahsh HASH,
                         SUM(sleeps) sleeps,
                         COUNT(1) CNT,
                         location,
                         mutex_type,
                         substr(kglnaobj, 1, 100) OBJECT
                  FROM   x$kglob, v$mutex_sleep_history
                  WHERE  kglnahsh = mutex_identifier
                  AND    (SLEEP_TIMESTAMP + 0) >= SYSDATE - nvl(:V1, 60) / 1440
                  AND    userenv('instance') = nvl(:instance, userenv('instance'))
                  GROUP  BY kglnaobj, kglnahsh, location, mutex_type
                  ORDER  BY sleeps DESC)))
WHERE  rownum <= 50;
