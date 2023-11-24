
/*[[
  Show the channel info whose p1text='channel context'(such as "reliable message"). Usage: @@NAME  [<sid>|<sql_id>|<p1>|<event>] [<inst_id>]
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
        &src1: default={table(gv$(cursor(} d={(((}
        &src2: default={(select userenv('instance') instance_number, a.* from v$active_session_history a)} d={dba_hist_active_sess_history}
    --]]
]]*/
PRO data from ASH
PRO =============
SELECT *
FROM   (SELECT *
        FROM   &src1 --
                SELECT /*+ordered use_nl(b)*/
                       instance_number inst, b.addr "Channel context",
                       b.totpub_ksrcctx, 
                       a.name_ksrcdes, 
                       sql_id, event, 
                       aas,
                       case when bitand(h.flags_ksrchdl,1)=1 then 'PUB ' end ||  
                       case when bitand(h.flags_ksrchdl,2)=2 then 'SUB ' end ||  
                       case when bitand(h.flags_ksrchdl,16)=16 then 'INA ' end flags,
                       a.id_ksrcdes,
                       h.ctxp_ksrchdl,
                       c.program
                FROM   (SELECT  instance_number,sql_id,
                                event,
                                program,
                                TO_CHAR(p1, 'fm0XXXXXXXXXXXXXXX') p1raw,
                                COUNT(1) aas,
                                MAX(sample_time) last_seen
                         FROM   &src2 a
                         WHERE  p1text = 'channel context'
                         AND    sample_time+0 between nvl(to_date(:starttime,'yymmddhh24mi'),sysdate-7) and nvl(to_date(:endtime,'yymmddhh24mi'),sysdate+1)
                         AND    nvl(:v1,'x') in('x',''||a.session_id,a.sql_id,a.event,''||p1)
                         GROUP  BY sql_id, event,program, p1,instance_number) c,
                        sys.X$KSRCCTX b,
                        sys.X$KSRCDES a,
                        sys.x$ksrchdl h
                WHERE  b.name_ksrcctx = a.indx
                AND    h.ctxp_ksrchdl = b.addr
                AND    instance_number = nvl(:V2, instance_number)
                AND    b.addr = p1raw)))
        ORDER  BY aas DESC, inst)
WHERE  ROWNUM <= 50;


PRO data from V$SESSION
PRO ====================
SELECT *
FROM   TABLE(gv$(CURSOR( --
    select case when bitand(c.flags_ksrchdl,1)=1 then 'PUB ' end ||  
           case when bitand(c.flags_ksrchdl,2)=2 then 'SUB ' end ||  
           case when bitand(c.flags_ksrchdl,16)=16 then 'INA ' end flags, 
           s.sid||'@'||userenv('instance') sid, 
           s.program, 
           cd.name_ksrcdes channel_name,  
           cd.id_ksrcdes,  
           to_number(c.ctxp_ksrchdl,'XXXXXXXXXXXXXXXX') p1
    from   sys.x$ksrchdl c ,  
           v$session s,  
           sys.x$ksrcctx ctx,  
           sys.x$ksrcdes cd 
    WHERE nvl(:v1,'x') in('x',''||s.sid,s.sql_id,s.event,''||to_number(c.ctxp_ksrchdl,'XXXXXXXXXXXXXXXX'))
    and s.paddr=c.owner_ksrchdl
    and c.ctxp_ksrchdl=ctx.addr 
    and cd.indx=ctx.name_ksrcctx)))
WHERE p1 in(select p1 from gv$session)
ORDER BY P1,SID; 