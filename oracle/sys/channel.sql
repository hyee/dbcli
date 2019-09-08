
/*[[
  Show the channel info whose p1text='channel context'(such as "reliable message"). Usage: @@NAME  [<sid>|<sql_id>|<event>] [<inst_id>]
  Refer to Doc ID 69088.1

  Mainly used to diagnostic below events:
  =======================================
  * reliable message  
  * wait for unread message on broadcast channel          
  * wait for unread message on multiple broadcast channels
                                    
  Example Output:
  ================
    SQL> sys channel . 4
    INST Channel context  TOTPUB_KSRCCTX  NAME_KSRCDES                                             SQL_ID          EVENT        AAS
    ---- ---------------- -------------- ------------------------------------------------------ ------------- ---------------- -----
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    fktb4trc8zb16                  17211
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    27331pta0jn12                  16107
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    4ksfp9juvtdkg                  13233
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    47uwdv1ffx4fx                    310
       4 0000002B293879D0         945636 RBR channel                                                          reliable message   124
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    fktb4trc8zb16 reliable message    37
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    27331pta0jn12 reliable message    28
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    4ksfp9juvtdkg reliable message    25
       4 0000002B29383F50        4962868 CKPT ksbxic channel                                    47uwdv1ffx4fx reliable message    17
       4 0000002B2938F650        5107983 kxfp control signal channel                            aca366jx8bh0f reliable message    14
       4 0000002B2938F650        5107983 kxfp control signal channel                            7v8dacmx3t3td reliable message    12
       4 0000002B2938F650        5107983 kxfp control signal channel                            d3ddjhh624zy9 reliable message     8
       4 0000002B2938F650        5107983 kxfp control signal channel                            ard6ysp2ufm1n reliable message     8
       4 0000002B2938F650        5107983 kxfp control signal channel                            a8zxxqa1hcc7f reliable message     8
       4 0000002B29394D50              0 kfioSr channel                                                                            3
       4 0000002B293879D0         945636 RBR channel                                                                               3
       4 0000002B29387B50         490044 obj broadcast channel                                  2vzap93xpn8gq reliable message     2
       4 0000002B29387B50         490044 obj broadcast channel                                  bqb09swgjaf30 reliable message     1
    --[[
        &V2: default={&instance}
    --]]
]]*/

SELECT *
FROM   (SELECT *
        FROM   TABLE(gv$(CURSOR( --
                SELECT /*+ordered use_nl(b)*/
                       a.inst_id inst, b.addr "Channel context", b.totpub_ksrcctx, a.name_ksrcdes, sql_id, event, aas
                FROM   (SELECT  sql_id,
                                event,
                                TO_CHAR(p1, 'fm0XXXXXXXXXXXXXXX') p1raw,
                                COUNT(1) aas,
                                MAX(sample_time) last_seen
                         FROM   v$active_session_history a
                         WHERE  p1text = 'channel context'
                         AND    nvl(:v1,'x') in('x',''||a.session_id,a.sql_id,a.event)
                         GROUP  BY sql_id, event, p1) c,
                        X$KSRCCTX b,
                        X$KSRCDES a
                WHERE  b.name_ksrcctx = a.indx
                AND    userenv('instance') = nvl(:V2, userenv('instance'))
                AND    b.addr = p1raw)))
        ORDER  BY aas DESC, inst)
WHERE  ROWNUM <= 50;

