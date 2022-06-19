/*[[
    Snap RAC stats within specific secs and output the delta result. Usage: @@NAME [<secs> | {-awr|-pdb <yymmddhh24mi> [<yymmddhh24mi>]}] 
    <secs>: sample from gv$views default as 30 secs, and 0 is to show global stats instead of snapping
      -awr: analyze dba_hist_*view instead within optional <yymmddhh24mi> [<yymmddhh24mi>] date range parameter
      -pdb: analyze awr_pdb_*view instead within optional <yymmddhh24mi> [<yymmddhh24mi>] date range parameter
    --[[
        &v1: default={30} awr={&starttime} pdb={&starttime}
        &v2: default={&endtime}
        @event:{
            12.1={select /*+merge*/ inst_id,event#,event,wait_time_micro/1024 wait_time_milli,wait_count from gv$event_histogram_micro} 
            default={gv$event_histogram}
        }
        @lms_cpu: 18.1={CPU_USED} default={null}
        @con :12.1={,con_dbid} default={}
        &awr : default={false} awr={true} pdb={true}
        &vw  : default={dba_hist_} pdb={awr_pdb_}
        @check_access_x: {
            sys.x$ksxpif={
                SELECT * FROM TABLE(GV$(CURSOR(
                    SELECT a.* 
                    FROM   sys.x$ksxpif a,v$cluster_interconnects b
                    WHERE  a.IF_NAME=b.NAME
                    AND    a.IP_ADDR=b.IP_ADDRESS)))}
            default={}
)))}}
    --]]
]]*/

set feed off verify off autohide col
var c1 refcursor "INSTANCE CACHE TRANSFER PER SECOND"
var c2 refcursor "EVENT HISTOGRAM PER SECOND"
var c31 refcursor "CR/CU LATERNCY PER SECOND"
var c32 refcursor "MESSAGE LATERNCY PER SECOND (Some algorithms are different from AWR)"
var c4 refcursor "LMS SERVER STATS PER SECOND"
var c5 refcursor "INTER-CONNECT DEVICES STATS PER SECOND"


COL "PING,TIME,AVG,RECV|TIME,CR AVG|IMMED,CR AVG|BUSY,CR AVG|2-HOP,CR AVG|3-HOP,CR AVG|CONGST" for usmhd2
COL "LOST|TIME,LOST|AVG,AVG|TIME,CU AVG|IMMED,CU AVG|BUSY,CU AVG|2-HOP,CU AVG|3-HOP,CU AVG|CONGST" for usmhd2
COL "GC CR|IMMED,CR TIM|IMMED,GC CR|2-HOP,CR TIM|2-HOP,GC CR|3-HOP,CR TIM|3-HOP,GC CR|BUSY,CR TIM|BUSY,GC CR|CONGST,CR TIM|CONGST" FOR PCT
COL "GC CU|IMMED,CU TIM|IMMED,GC CU|2-HOP,CU TIM|2-HOP,GC CU|3-HOP,CU TIM|3-HOP,GC CU|BUSY,CU TIM|BUSY,GC CU|CONGST,CU TIM|CONGST" FOR PCT
COL "1us,2us,4us,8us,16us,32us,64us,128us,256us,512us,1ms,2ms,4ms,8ms,16ms,32ms,65ms,131ms,262ms,524ms,1s,2s,4s,8s,16s,>16s" for pct1
COL "AVG TM|RECEIV,REMOTE|BUILD,REMOTE|FLUSH,BUILD|AVG TM,FLUSH|AVG TM,REMOTE|PIN,PIN|AVG TM,FLUSH|AVG TM" for usmhd2
COL "BUILD|SERVED,FLUSH|SERVED,LGWR|SERVED,PIN|SERVED,QUEU|RECV,FLOW|CTRL,DIREX|SENT,IN-DX|SENT,QUEUE|SENT" for pct
COL "LMS|BUSY,ENQUE|GET,RECV|QUEUE,GCS|PROX,GES|PROX,REMOTE|BUILD%,REMOTE|PIN %,REMOTE|FLUSH%,REMOTE|LGWR %" for pct
COL "LMS|TIME,CR/CU|TIME,CR/ CU|AVG TM,AVG|RECV,AVG|KERNEL,AVG|SENT,AVG|QUEUE,AVG|KSXP,GC|CPU,IPC|CPU" for usmhd2
COL "RECV|BYTE,SENT|BYTE" FOR KMG
COL "RECV|PACK,SENT|PACK" FOR TMB


COL grp noprint
PRO Sampling data, please wait ...
DECLARE
    sleeps INT := :v1;
    awr    BOOLEAN := &awr;
    c      SYS_REFCURSOR;
    TYPE t_xmls IS TABLE OF xmltype;
    TYPE t_sqls IS TABLE OF VARCHAR2(32767);
    TYPE t_curs IS TABLE OF NUMBER;

    sqls t_sqls := t_sqls();
    tmps t_sqls := t_sqls();
    curs t_curs := t_curs();
    rs1  t_xmls := t_xmls();
    rs2  t_xmls := t_xmls();
    tim  NUMBER;
    tim1 NUMBER;
    bid  INT;
    eid  INT;
    did  INT;
    PROCEDURE snap(idx PLS_INTEGER) IS
        ct  CLOB;
        xml XMLTYPE;
        j   INT;
    BEGIN
        FOR i IN 1 .. sqls.count LOOP
            j := i;
            ct:= NULL;
            tmps(i) := replace(replace(trim(sqls(i)),'@dbid',did),'@snap_id', case idx when 1 then bid else eid end);
            IF tmps(i) IS NOT NULL THEN
                curs(i) := dbms_xmlgen.newcontext(tmps(i));
            ELSE
                curs(i) := NULL;
            END IF;
        END LOOP;
        tim := dbms_utility.get_time;
        FOR i IN 1 .. sqls.count LOOP
            j  := i;
            ct := NULL;
            IF curs(i) IS NULL THEN
                xml := xmltype('<ROWSET/>');
            ELSIF NOT AWR THEN 
                xml := dbms_xmlgen.getxmltype(curs(i));
            ELSE
                ct  := nvl(dbms_xmlgen.getxml(curs(i)), '<ROWSET/>');
                ct  := regexp_replace(ct, '<(DBID|CON_DBID|CON_ID|SNAP_ID)>\d+</\1>');
                ct  := REPLACE(ct, 'INSTANCE_NUMBER>', 'INST_ID>');
                xml := xmltype(ct);
            END IF;
            dbms_xmlgen.closecontext(curs(i));
            IF idx = 1 THEN
                rs1(i) := xml;
            ELSE
                rs2(i) := xml;
                IF rs1(i) IS NULL THEN
                    rs1(i) := xmltype('<ROWSET/>');
                END IF;
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Error on SQL# ' || j || ':' || chr(10) || tmps(j));
            IF ct IS NOT NULL THEN
                dbms_output.put_line(ct);
            END IF;
            RAISE;
    END;

    FUNCTION toXML RETURN XMLTYPE IS
        ctx NUMBER;
        xml XMLTYPE;
    BEGIN
        ctx := dbms_xmlgen.newcontext(c);
        xml := dbms_xmlgen.getxmltype(ctx);
        dbms_xmlgen.closecontext(ctx);
        CLOSE c;
        RETURN xml;
    END;

    PROCEDURE sq(idx INT, gsql VARCHAR2, dsql VARCHAR2) IS
    BEGIN
        sqls(idx) := CASE WHEN NOT awr THEN gsql ELSE dsql END;
    END;
BEGIN
    sqls.extend(7);
    tmps.extend(sqls.count);
    curs.extend(sqls.count);
    rs1.extend(sqls.count);
    rs2.extend(sqls.count);

    sq(1,
       'SELECT /*+NO_MERGE(A) MERGE(B) USE_HASH(A B)*/ * 
        FROM (
            SELECT inst_id instance,instance inst_id,
                   COUNT_500B+COUNT_8K PING,
                   WAIT_TIME_500B+WAIT_TIME_8K PING_TIME
            FROM gv$instance_ping) B
        JOIN  GV$INSTANCE_CACHE_TRANSFER A USING (inst_id,instance)
        WHERE LOST+CR_BLOCK+CURRENT_BLOCK>0',
       'SELECT /*+NO_MERGE(A) MERGE(B) USE_HASH(A B)*/ * 
        FROM (
             SELECT dbid,snap_id,instance_number instance,TARGET_INSTANCE instance_number,
                    CNT_500B+CNT_8K PING,
                    WAIT_500B+WAIT_8K PING_TIME &con
             FROM   &vw.interconnect_pings
             WHERE DBID=@dbid AND SNAP_ID=@snap_id) B
        JOIN  &vw.inst_cache_transfer USING (dbid, instance_number, instance, snap_id &con)
        WHERE DBID=@dbid AND SNAP_ID=@snap_id');
    sq(2,
       q'~
        SELECT /*+no_expand use_hash(a b) no_or_expand*/
               inst_id i,
               event n,
               u,
               wait_count v,
               time_waited_micro m,
               total_waits t,
               row_number() over(PARTITION BY inst_id, event ORDER BY u) f
        FROM   gv$system_event B
        JOIN   (SELECT a.*, least(round(wait_time_milli * 1024), 16777217) u FROM (&event) a) A
        USING  (inst_id, event)
        WHERE 1 = 1~',
       q'~
        SELECT /*+no_expand use_hash(a b) no_or_expand*/
               instance_number i,
               b.event_name n,
               u,
               wait_count v,
               time_waited_micro m,
               total_waits t,
               row_number() over(PARTITION BY instance_number, event_id ORDER BY u) f
        FROM   &vw.system_event B
        JOIN   (SELECT a.*, least(round(wait_time_milli * 1024), 16777217) u, event_name event FROM &vw.event_histogram a) A
        USING  (dbid, event_id, instance_number, snap_id &con)
        WHERE  dbid = @dbid
        AND    snap_id = @snap_id~');
    sqls(2) := sqls(2) || q'~
        AND   a.wait_count>0
        AND   b.wait_class!='Idle'
        AND   (b.wait_class='Cluster' OR event LIKE  '%LGWR%' OR event LIKE  '%LMS%' or
               event LIKE  'gcs%' OR event LIKE  'ges%' OR 
               event IN('buffer busy waits',
                        'remote log force - commit',
                        'log file sync',
                        'log file parallel write'))~';
    sq(3,
       q'~
        SELECT i, v, n
        FROM   (SELECT inst_id i, NAME n, VALUE v FROM gv$sysstat 
                UNION ALL 
                SELECT inst_id, NAME, VALUE FROM gv$dlm_misc)~',
       q'~
        SELECT i,v,n
        FROM   (select instance_number i,stat_name n,value v FROM &vw.sysstat WHERE dbid=@dbid AND snap_id=@snap_id
                union all 
                SELECT instance_number,name,value FROM &vw.dlm_misc WHERE dbid=@dbid AND snap_id=@snap_id)~');
    sqls(3) := sqls(3) || q'~
        WHERE v > 0
        AND   (n LIKE  'gc %' OR n LIKE  'global%' OR n LIKE  '%undo %' OR
               n IN('cluster wait time',
                    'remote Oradebug requests',
                    'consistent gets FROM cache',
                    'data blocks consistent reads - undo records applied',
                    'db block changes',
                    'db block gets FROM cache',
                    'DBWR fusion writes',
                    'deferred (CURRENT) block cleanout applications',
                    'gcs messages sent',
                    'gcs msgs process time(ms)',
                    'gcs msgs received',
                    'ges messages sent',
                    'ges msgs process time(ms)',
                    'ges msgs received',
                    'IPC CPU used by this session',
                    'ka messages sent',
                    'ka grants received',
                    'msgs received kernel queue time (ns)',
                    'msgs received queue time (ms)',
                    'msgs received queued',
                    'msgs sent queue time (ms)',
                    'msgs sent queue time on ksxp (ms)',
                    'msgs sent queued on ksxp',
                    'msgs sent queued',
                    'messages queue sent actual',
                    'physical reads cache',
                    'messages sent directly',
                    'messages sent indirectly',
                    'messages flow controlled',
                    'user commits',
                    'user rollbacks'))~';
    sq(4,
       'SELECT * FROM GV$CR_BLOCK_SERVER',
       'SELECT * FROM &vw.CR_BLOCK_SERVER WHERE dbid=@dbid AND snap_id=@snap_id');
    sq(5,
       'SELECT * FROM GV$CURRENT_BLOCK_SERVER',
       'SELECT * FROM &vw.CURRENT_BLOCK_SERVER WHERE dbid=@dbid AND snap_id=@snap_id');
    sq(6,
       q'~
        SELECT nvl(inst_id, 0) i, COUNT(DISTINCT sid * 1000 + inst_id) n, SUM(VALUE) v,1 f
        FROM   gv$sess_time_model
        JOIN   gv$session
        USING  (inst_id, sid)
        WHERE  program LIKE  '%(LMS%)%'
        AND    TYPE = 'BACKGROUND'
        AND    stat_name LIKE  'background%time'
        AND    VALUE > 0
        GROUP  BY ROLLUP(inst_id)~',
       q'~
        SELECT nvl(instance_number,0) i, SUM(time_waited_micro) v, SUM(a.value + 0) n, -1 f
        FROM   &vw.parameter a
        JOIN   &vw.system_event
        USING  (dbid, instance_number, snap_id &con)
        WHERE  dbid=@dbid AND snap_id=@snap_id
        AND    parameter_name = 'gcs_server_processes'
        AND    event_name = 'gcs remote message'
        GROUP  BY rollup(instance_number)~');
    sq(7,q'~&check_access_x~',
       q'~
        SELECT *
        FROM   dba_hist_ic_device_stats
        JOIN   (SELECT /*+merge*/ snap_id, dbid, instance_number, NAME if_name, ip_address ip_addr &con 
                FROM   dba_hist_cluster_intercon)
        USING  (snap_id, dbid, instance_number, if_name,ip_addr &con)
        WHERE  dbid=@dbid AND snap_id=@snap_id~');
    IF awr THEN
        SELECT MAX(dbid), MIN(snap_id), MAX(snap_id), 86400 * (MAX(end_interval_time + 0) - MIN(end_interval_time + 0))
        INTO   did, bid, eid, tim1
        FROM   &vw.snapshot
        WHERE dbid = nvl(:dbid, (SELECT dbid FROM v$database))
        AND    end_interval_time BETWEEN
               to_timestamp(coalesce(:V1, to_char(SYSDATE - 7, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') AND
               to_timestamp(coalesce(:V2, to_char(SYSDATE + 1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI');
        IF did IS NULL THEN
            raise_application_error(-20001, 'Cannot find matched AWR snapshots.');
        ELSIF tim1 <= 0 THEN
            raise_application_error(-20001, 'No result in AWR snapshots due to input begin/end times are equal.');
        END IF;
    ELSE
        tim1 := dbms_utility.get_time;
    END IF;

    IF awr THEN
        snap(1);
    ELSIF sleeps > 0 THEN
        snap(1);
        tim1 := dbms_utility.get_time - tim1;
        dbms_output.put_line('Sampling data took external ' || round(tim1 * 2 / 100, 2) || ' secs.');
        dbms_output.put_line('*******************************');
        tim1 := greatest(1, sleeps - (dbms_utility.get_time - tim) / 100);
        tim  := dbms_utility.get_time;
        $IF DBMS_DB_VERSION.VERSION>12 $THEN
            dbms_session.sleep(tim1);
        $ELSE
            sys.dbms_lock.sleep(tim);
        $END
    ELSE
        SELECT greatest(10, round(86400 * AVG(SYSDATE - startup_time) - 60))
        INTO   tim1
        FROM   gv$instance
        WHERE status = 'OPEN';
    END IF;
    snap(2);
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim := dbms_utility.get_time;
    OPEN :c1 FOR
        WITH delta AS
         (SELECT /*+NO_EXPAND_GSET_TO_UNION*/
           nvl(dir, 'ALL') dir, CLASS, NAME, SUM(T * V) / tim1 V
          FROM   (SELECT T, A.TARGET || '->' || A.INST_ID dir, A.CLASS, b.name, V
                  FROM  (SELECT 1 T, rs2(1) X FROM DUAL UNION ALL SELECT -1, rs1(1) FROM DUAL) X,
                         XMLTABLE('//ROW' PASSING X.X 
                         COLUMNS  INST_ID INT          PATH 'INST_ID',
                                  TARGET  INT          PATH 'INSTANCE',
                                  CLASS   VARCHAR2(30) PATH 'CLASS',
                                  NODE    XMLTYPE      PATH 'node()') A,
                         XMLTABLE('*[not(name()="INST_ID" or name()="CLASS" or name()="INSTANCE")]' PASSING A.NODE
                         COLUMNS NAME VARCHAR2(30) PATH 'name()',
                                  V   INT          PATH '.') B) R2
          GROUP  BY ROLLUP(CLASS, DIR), NAME)
        SELECT DIR,
               PING_AVG PING,
               CLASS,
               ROUND(LOST, 2) "GC|LOST",
               LOST_TIME "LOST|TIME",
               LOST_AVG "LOST|AVG",
               ROUND(TOTAL, 2) "RECV|TOTAL",
               TOTAL_TIME "RECV|TIME",
               TOTAL_TIME / nullif(TOTAL, 0) "AVG|TIME",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               CR_BLOCK "GC CR|IMMED",
               CR_BLOCK_TIME "CR TIM|IMMED",
               CR_BLOCK_AVG "CR AVG|IMMED",
               '|' "|",
               CR_2HOP_TIME "CR TIM|2-HOP",
               CR_2HOP_AVG "CR AVG|2-HOP",
               '|' "|",
               CR_3HOP_TIME "CR TIM|3-HOP",
               CR_3HOP_AVG "CR AVG|3-HOP",
               '|' "|",
               CR_CONGESTED_TIME "CR TIM|CONGST",
               CR_CONGESTED_AVG "CR AVG|CONGST",
               '|' "|",
               CR_BUSY_TIME "CR TIM|BUSY",
               CR_BUSY_AVG "CR AVG|BUSY",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               CU_BLOCK "GC CU|IMMED",
               CU_BLOCK_TIME "CU TIM|IMMED",
               CU_BLOCK_AVG "CU AVG|IMMED",
               '|' "|",
               CU_2HOP_TIME "CU TIM|2-HOP",
               CU_2HOP_AVG "CU AVG|2-HOP",
               '|' "|",
               CU_3HOP_TIME "CU TIM|3-HOP",
               CU_3HOP_AVG "CU AVG|3-HOP",
               '|' "|",
               CU_CONGESTED_TIME "CU TIM|CONGST",
               CU_CONGESTED_AVG "CU AVG|CONGST",
               '|' "|",
               CU_BUSY_TIME "CU TIM|BUSY",
               CU_BUSY_AVG "CU AVG|BUSY"
        FROM   (SELECT /*+no_merge(a)*/
                       dir,class,
                       decode(r,1,name,2,n1,3,n2) name,
                       round(decode(r,
                             1,max(v/nullif(v1,0)),
                             2,max(v1),
                             3,max(CASE WHEN NAME LIKE  '%_TIME' THEN v END)/
                               max(CASE WHEN NAME NOT LIKE  '%_TIME' THEN nullif(v,0) END)
                             ),4) v
                FROM   (SELECT a.*,
                               REPLACE(NAME, '_TIME') || '_AVG' n2,
                               regexp_replace(NAME, '^(CR|CURRENT)_[^_]+', 'TOTAL') n1,
                               SUM(CASE WHEN name not LIKE  '%HOP%' THEN v ELSE 0 END) 
                                  OVER(PARTITION BY dir,class,regexp_replace(name,'^(CR|CURRENT)_[^_]+','TOTAL')) v1
                        FROM   delta a
                        WHERE v > 0
                        OR     (NAME LIKE  '%TIME' AND NAME NOT LIKE  '%LOST%' AND NAME NOT LIKE  '%HOP%' AND NAME NOT LIKE  '%CONGESTED%')) a,
                       (SELECT rownum r FROM dual CONNECT BY rownum <= 3)
                GROUP  BY r, DIR, CLASS, decode(r, 1, NAME, 2, n1, 3, n2))
        PIVOT (SUM(V) FOR NAME IN(
                         'LOST' LOST,
                         'LOST_TIME' LOST_TIME,
                         'LOST_AVG' LOST_AVG,
                         'TOTAL' TOTAL,
                         'TOTAL_TIME' TOTAL_TIME,
                         'PING_AVG' PING_AVG,
                         'CR_BLOCK' CR_BLOCK,
                         'CR_BLOCK_TIME' CR_BLOCK_TIME,
                         'CR_BLOCK_AVG' CR_BLOCK_AVG,
                         'CR_2HOP_TIME' CR_2HOP_TIME,
                         'CR_2HOP_AVG' CR_2HOP_AVG,
                         'CR_3HOP_TIME' CR_3HOP_TIME,
                         'CR_3HOP_AVG' CR_3HOP_AVG,
                         'CR_BUSY_TIME' CR_BUSY_TIME,
                         'CR_BUSY_AVG' CR_BUSY_AVG,
                         'CR_CONGESTED_TIME' CR_CONGESTED_TIME,
                         'CR_CONGESTED_AVG' CR_CONGESTED_AVG,
                         'CURRENT_BLOCK' CU_BLOCK,
                         'CURRENT_BLOCK_TIME' CU_BLOCK_TIME,
                         'CURRENT_BLOCK_AVG' CU_BLOCK_AVG,
                         'CURRENT_2HOP_TIME' CU_2HOP_TIME,
                         'CURRENT_2HOP_AVG' CU_2HOP_AVG,
                         'CURRENT_3HOP_TIME' CU_3HOP_TIME,
                         'CURRENT_3HOP_AVG' CU_3HOP_AVG,
                         'CURRENT_BUSY_TIME' CU_BUSY_TIME,
                         'CURRENT_BUSY_AVG' CU_BUSY_AVG,
                         'CURRENT_CONGESTED_TIME' CU_CONGESTED_TIME,
                         'CURRENT_CONGESTED_AVG' CU_CONGESTED_AVG))
        WHERE ROUND(least(TOTAL, TOTAL_TIME), 2) > 0
        ORDER  BY decode(dir, 'ALL', 1, 2), "RECV|TIME" DESC NULLS LAST, 1, 2;

    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim := dbms_utility.get_time;
    OPEN c FOR
        SELECT *
        FROM   (SELECT /*+NO_EXPAND_GSET_TO_UNION*/
                 nvl(i, 0) i,
                 n,
                 u,
                 MIN(F) F,
                 ROUND(SUM(c * V) / tim1, 2) V,
                 MAX(ROUND(SUM(c * decode(f, 1, m)) / tim1, 2)) OVER(PARTITION BY n, i) m,
                 MAX(ROUND(SUM(c * decode(f, 1, t)) / tim1, 2)) OVER(PARTITION BY n, i) t
                FROM   (SELECT 1 c, rs2(2) X FROM DUAL UNION ALL SELECT -1, rs1(2) FROM DUAL) X,
                       XMLTABLE('//ROW' PASSING X.X 
                       COLUMNS  i INT           PATH 'I',
                                n VARCHAR2(128) PATH 'N',
                                u INT           PATH 'U',
                                v INT           PATH 'V',
                                m INT           PATH 'M',
                                t INT           PATH 'T',
                                f INT           PATH 'F') r2
                GROUP  BY n, u, ROLLUP(i)) a
        WHERE t > 0;
    rs2(2) := toXML();

    OPEN :c2 FOR
        WITH delta AS
         (SELECT n NAME, m "Time", round(m / t, 2) "Avg", t "Count", '|' "|", u, nullif(round(v / t, 3), 0) v
          FROM   XMLTABLE('//ROW[I=0]' PASSING rs2(2) 
                 COLUMNS  n VARCHAR2(100) PATH 'N',
                          u INT           PATH 'U',
                          v NUMBER        PATH 'V',
                          m NUMBER        PATH 'M',
                          t NUMBER        PATH 'T') r2)
        SELECT *
        FROM   delta
        PIVOT (MAX(v) FOR u IN(
                          1 "1us",
                          2 "2us",
                          4 "4us",
                          8 "8us",
                          16 "16us",
                          32 "32us",
                          64 "64us",
                          128 "128us",
                          256 "256us",
                          512 "512us",
                          1024 "1ms",
                          2048 "2ms",
                          4096 "4ms",
                          8192 "8ms",
                          16384 "16ms",
                          32768 "32ms",
                          65536 "65ms",
                          131072 "131ms",
                          262144 "262ms",
                          524288 "524ms",
                          1048576 "1s",
                          2097152 "2s",
                          4194304 "4s",
                          8388608 "8s",
                          16777216 "16s",
                          16777217 ">16s"))
        ORDER  BY "Time" DESC;

    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim := dbms_utility.get_time;
    OPEN c FOR
        SELECT *
        FROM   (SELECT S,
                       grp,
                       decode(grouping_id(N), 0, nvl2(grp, '  ' || n, n), grp) n,
                       NVL(I, 0) I,
                       round(SUM(V) / tim1, 2) v
                FROM   (SELECT S,
                               N,
                               CASE WHEN n IN('DATA_REQUESTS','UNDO_REQUESTS','TX_REQUESTS','OTHER_REQUESTS') THEN 'LMS SERVER REQUESTS'
                                    WHEN s='CURRENT' AND regexp_substr(n,'^\D+') in ('FLUSH','PIN','WRITE') THEN regexp_substr(n,'^\D+')
                               END grp,
                               I,
                               T * V V
                        FROM   (SELECT 'CR' S, 1 T, rs2(4) x
                                FROM   DUAL
                                UNION ALL
                                SELECT 'CR' S, -1 T, rs1(4) x
                                FROM   DUAL
                                UNION ALL
                                SELECT 'CURRENT' S, 1 T, rs2(5) x
                                FROM   DUAL
                                UNION ALL
                                SELECT 'CURRENT' S, -1 T, rs1(5) x
                                FROM   DUAL) X,
                               XMLTABLE('//ROW' PASSING X.X COLUMNS I INT PATH 'INST_ID', NODE XMLTYPE PATH 'node()') A,
                               XMLTABLE('*[not(name()="INST_ID")]' PASSING A.NODE 
                               COLUMNS  N VARCHAR2(30) PATH 'name()',
                                        V INT          PATH '.') B)
                GROUP  BY S, grp, CUBE(I, N))
        WHERE V > 0
        AND    n IS NOT NULL;
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim := dbms_utility.get_time;
    rs2(4) := toXML();

    OPEN :c4 FOR
        SELECT A.*,
               decode(TRIM(NAME),
                      'CR_REQUESTS',
                      'CR blocks served due to remote CR block requests',
                      'CURRENT_REQUESTS',
                      'Current blocks served due to remote CR block requests',
                      'DATA_REQUESTS',
                      'Current OR CR requests for data blocks',
                      'UNDO_REQUESTS',
                      'CR requests for undo blocks',
                      'TX_REQUESTS',
                      'CR requests for undo segment header blocks',
                      'OTHER_REQUESTS',
                      'CR requests for other types of blocks',
                      'CURRENT_RESULTS',
                      'requests for which no changes were rolled out of the block returned to the requesting instance',
                      'PRIVATE_RESULTS',
                      'requests for which changes were rolled out of the block returned to the requesting instance, AND only the requesting transaction can use the resulting CR block',
                      'ZERO_RESULTS',
                      'requests for which changes were rolled out of the block returned to the requesting instance. Only zero-XID transactions can use the block.',
                      'DISK_READ_RESULTS',
                      'requests for which the requesting instance had to read the requested block FROM disk',
                      'FAIL_RESULTS',
                      'requests that failed; the requesting transaction must reissue the request',
                      'STALE',
                      'requests for which the disk read of the requested block was stale',
                      'FAIRNESS_DOWN_CONVERTS',
                      'times an instance receiving a request has down-converted an X lock on a block because it was not modifying the block',
                      'FAIRNESS_CLEARS',
                      'times the "fairness counter" was cleared. This counter tracks the times a block was modified after it was served.',
                      'FREE_GC_ELEMENTS',
                      'times a request was received FROM another instance AND the X lock had no buffers',
                      'FLUSHES',
                      'times the log has been flushed by an LMS process',
                      'FLUSHES_QUEUED',
                      'flushes queued by an LMS process',
                      'FLUSH_QUEUE_FULL',
                      'times the flush queue was full',
                      'FLUSH_MAX_TIME',
                      'Maximum time for flush',
                      'LIGHT_WORKS',
                      'times the light-work rule was evoked. This rule prevents the LMS processes FROM going to disk to complete responding to CR requests',
                      'ERRORS',
                      'times an error was signalled by an LMS process',
                      'PIN0',
                      'Pins taking less than 100 us',
                      'PIN1',
                      'Pins taking 100 us to 1 ms',
                      'PIN10',
                      'Pins taking 1 to 10 ms',
                      'PIN100',
                      'Pins taking 10 to 100 ms',
                      'PIN1000',
                      'Pins taking 100 to 1000 ms',
                      'PIN10000',
                      'Pins taking 1000 to 10000 ms',
                      'FLUSH0',
                      'Flushes taking less than 100 us',
                      'FLUSH1',
                      'Flushes taking 100 us to 1 ms',
                      'FLUSH10',
                      'Flushes taking 1 to 10 ms',
                      'FLUSH100',
                      'Flushes taking 10 to 100 ms',
                      'FLUSH1000',
                      'Flushes taking 100 to 1000 ms',
                      'FLUSH10000',
                      'Flushes taking 1000 to 10000 ms',
                      'WRITE1',
                      'Writes taking less than 1 ms',
                      'WRITE10',
                      'Writes taking 1 to 10 ms',
                      'WRITE100',
                      'Writes taking 10 to 100 ms',
                      'WRITE1000',
                      'Writes taking 100 to 1000 ms',
                      'WRITE10000',
                      'Writes taking 1000 to 10000 ms',
                      'CLEANDC',
                      'Reserved for internal use',
                      'RCVDC',
                      'Number of lock down-converts to S (shared) caused by instance recovery',
                      'QUEUEDC',
                      'Number of queued lock down-converts to NULL',
                      'EVICTDC',
                      'Number of lock down-converts to NULL caused by an SGA shrink',
                      'WRITEDC',
                      'Number of dirty blocks in read-mostly objects which were written AND the X lock down-converted to S locks') MEMO
        FROM   (SELECT *
                FROM   XMLTABLE('//ROW' PASSING rs2(4) 
                       COLUMNS  server VARCHAR2(10) PATH 'S',
                                NAME   VARCHAR2(30) PATH 'N',
                                grp    VARCHAR2(30) PATH 'GRP',
                                I      INT          PATH 'I',
                                V      NUMBER       PATH 'V')
                PIVOT(MAX(V) FOR I IN(
                               0 "Total",
                               1 "#1",
                               2 "#2",
                               3 "#3",
                               4 "#4",
                               5 "#5",
                               6 "#6",
                               7 "#7",
                               8 "#8",
                               9 "#9",
                               10 "#10",
                               11 "#11",
                               12 "#12",
                               13 "#13",
                               14 "#14",
                               15 "#15",
                               16 "#16"))) A
        ORDER  BY server, grp, decode(grp, NAME, 1, 2), NAME;

    OPEN c FOR
        SELECT /*+NO_EXPAND_GSET_TO_UNION*/
               nvl(i, 0) i, n, ROUND(SUM(t * v) / tim1, 6) v
        FROM   (SELECT 1 T, rs2(3) x FROM DUAL UNION ALL SELECT -1, rs1(3) x FROM DUAL) X,
               XMLTABLE('//ROW' PASSING x COLUMNS n VARCHAR2(100) PATH 'N', i INT PATH 'I', v INT PATH 'V') r2
        GROUP  BY n, ROLLUP(i)
        HAVING ROUND(SUM(t * v) / tim1, 6) > 0;
    rs2(3) := toXML();
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim := dbms_utility.get_time;
    OPEN :c31 FOR
        WITH delta AS
         (SELECT *
          FROM   (SELECT /*+no_merge*/*
                  FROM   XMLTABLE('//ROW' PASSING rs2(3) 
                         COLUMNS  n VARCHAR2(100) PATH 'N',
                                  i INT           PATH 'I',
                                  v NUMBER        PATH 'V')
                  LEFT   JOIN (SELECT *
                               FROM   XMLTABLE('//ROW' PASSING rs2(4) 
                                      COLUMNS I INT          PATH 'I',
                                              n VARCHAR2(30) PATH 'N',
                                              v NUMBER       PATH 'V')
                              PIVOT(MAX(V) FOR n IN('FLUSHES' gccrfl, 'FLUSH' gccufl, 'PIN' gccupn, 'ERRORS' errs)))
                  USING  (I))
          PIVOT(SUM(v) FOR n IN(
                     'gc cr blocks received' gccrrv,
                     'gc cr block receive time' gccrrt,
                     'gc cr blocks served' gccrsv,
                     'gc cr blocks built' gccrbc,
                     'gc cr block build time' gccrbt,
                     'gc cr blocks flushed' gccrfc,
                     'gc cr block flush time' gccrft,
                     'gc current blocks received' gccurv,
                     'gc current block receive time' gccurt,
                     'gc current blocks served' gccusv,
                     'gc current blocks pinned' gccupc,
                     'gc current block pin time' gccupt,
                     'gc current blocks flushed' gccufc,
                     'gc current block flush time' gccuft,
                     'global enqueue get time' glgt,
                     'global enqueue gets sync' glsg,
                     'global enqueue gets async' glag)))
        SELECT decode(i, 0, '*', '' || i) inst,
               round(errs, 2) "LMS|ERRS",
               round(gccrrv + gccurv, 2) "RECV|BLKS",
               round(gccrsv + gccusv, 2) "SERV|BLKS",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               round(gccrrv, 2) "CR BLKS|RECEIVE",
               round(gccrrt / gccrrv * 10000, 2) "AVG TM|RECEIV",
               round(r_gccrbt / r_gccrsv * 10000, 2) "REMOTE|BUILD",
               round(r_gccrft / r_gccrsv * 10000, 2) "REMOTE|FLUSH",
               '|' "|",
               round(gccrsv, 2) "CR BLKS|SERVED",
               round(gccrbc / gccrsv, 4) "BUILD|SERVED",
               round(gccrfc / gccrsv, 4) "FLUSH|SERVED",
               round(gccrfl / gccrsv, 4) "LGWR|SERVED",
               round(gccrbt / gccrbc * 10000, 2) "BUILD|AVG TM",
               round(gccrft / nvl(gccrfc, gccrfl) * 10000, 2) "FLUSH|AVG TM",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               round(gccurv, 2) "CU BLKS|RECEIVE",
               round(gccurt / gccurv * 10000, 2) "AVG TM|RECEIV",
               round(r_gccupt / r_gccusv * 10000, 2) "REMOTE|PIN",
               round(r_gccuft / r_gccusv * 10000, 2) "REMOTE|FLUSH",
               '|' "|",
               round(gccusv, 2) "CU BLKS|SERVED",
               round(nvl(gccupc, gccupn) / gccusv, 4) "PIN|SERVED",
               round(nvl(gccufc, gccufl) / gccusv, 4) "FLUSH|SERVED",
               round(gccufl / gccusv, 4) "LGWR|SERVED",
               '|' "|",
               round(gccupt / nvl(gccupc, gccupn) * 10000, 2) "PIN|AVG TM",
               round(gccuft / nvl(gccufc, gccufl) * 10000, 2) "FLUSH|AVG TM",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$"
        FROM   (SELECT a.*,
                       MAX(decode(i, 0, gccrsv)) over() - decode(i, 0, 0, gccrsv) r_gccrsv,
                       MAX(decode(i, 0, gccrft)) over() - decode(i, 0, 0, gccrft) r_gccrft,
                       MAX(decode(i, 0, gccrbt)) over() - decode(i, 0, 0, gccrbt) r_gccrbt,
                       MAX(decode(i, 0, gccusv)) over() - decode(i, 0, 0, gccusv) r_gccusv,
                       MAX(decode(i, 0, gccupt)) over() - decode(i, 0, 0, gccupt) r_gccupt,
                       MAX(decode(i, 0, gccuft)) over() - decode(i, 0, 0, gccuft) r_gccuft
                FROM   delta a)
        ORDER  BY inst;
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim := dbms_utility.get_time;
    rs1(6) := rs1(6).deleteXML('//N');
    OPEN :c32 FOR
        WITH delta AS
         (SELECT /*+no_merge*/ *
          FROM   XMLTABLE('//ROW' PASSING rs2(3) COLUMNS n VARCHAR2(100) PATH 'N', i INT PATH 'I', v NUMBER PATH 'V')
          PIVOT(SUM(v) FOR n IN(
                     'gc cr blocks received' gccrrv,
                     'gc cr block receive time' gccrrt,
                     'gc current blocks received' gccurv,
                     'gc current block receive time' gccurt,
                     'gc cr block build time' gccrbt,
                     'gc cr block flush time' gccrft,
                     'gc cr blocks served' gccrsv,
                     'gc current block pin time' gccupt,
                     'gc current block flush time' gccuft,
                     'gc current blocks served' gccusv,
                     'gc blocks lost' gcl,
                     'global enqueue get time' glgt,
                     'global enqueue gets sync' glsg,
                     'global enqueue gets async' glag,
                     'gcs msgs received' gcsmr,
                     'gc status messages received' gssmr,
                     'gcs msgs process time(ms)' gcsmpt,
                     'ges msgs received' gesmr,
                     'ges msgs process time(ms)' gesmpt,
                     'ges messages sent' gems,
                     'gcs messages sent' gcms,
                     'messages queue sent actual' msq,
                     'msgs sent queue time (ms)' msqt,
                     'msgs sent queued on ksxp' msqk,
                     'msgs sent queue time on ksxp (ms)' msqkt,
                     'msgs received kernel queue time (ns)' msqkrt,
                     'ka grants received' kagr,
                     'ka messages sent' kams,
                     'gc status messages sent' gsms,
                     'msgs received queued' mrq,
                     'msgs received queue time (ms)' mrqt,
                     'messages sent directly' msd,
                     'messages sent indirectly' msi,
                     'messages flow controlled' mfl,
                     'gc CPU used by this session' gccpu,
                     'IPC CPU used by this session' ipccpu))),
        LMS AS
         (SELECT i, MAX(n) lms, f * round(SUM(t * v) / tim1) + decode(f, 1, 0, MAX(n) * 1e6) lms_busy
          FROM   (SELECT 1 t, rs2(6) x FROM dual UNION ALL SELECT -1, rs1(6) FROM dual) x,
                 xmltable('//ROW' PASSING x.x COLUMNS v INT PATH 'V', n INT PATH 'N', i INT PATH 'I', f INT PATH 'F')
          GROUP  BY i, f)
        SELECT /*+no_merge(a) no_merge(b) no_merge(c) use_hash(a b c)*/
                 decode(i, 0, '*', '' || i) inst,
                 lms "LMS|NUM",
                 lms_busy "LMS|TIME",
                 gccpu * 1e4 "GC|CPU",
                 round(lms_busy * 1E-6 / lms, 4) "LMS|BUSY",
                 '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
                 round(gcrv, 2) "CR/CU|RECV",
                 round(gcl, 2) "CR/CU|LOST",
                 round(gcf, 2) "CR/CU|RETRY",
                 round(gcrt * 10000, 2) "CR/CU|TIME",
                 '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
                 round(gcrt * 10000 / gcrv, 2) "CR/ CU|AVG TM",
                 round(glgt / gcrt, 4) "ENQUE|GET",
                 nullif(round(r_gccrbt * gccrrv / r_gccrsv / gcrt, 4), 0) "REMOTE|BUILD%",
                 nullif(round(r_gccupt * gccurv / r_gccusv / gcrt, 4), 0) "REMOTE|PIN %",
                 nullif(round((nvl(r_gccrft * gccrrv / r_gccrsv, 0) + nvl(r_gccuft * gccurv / r_gccusv, 0)) / gcrt, 4), 0) "REMOTE|FLUSH%",
                 nullif(round(r_lgwrt*(nvl(gccrrv,0)+nvl(gccurv,0))/nullif(nvl(r_gccrsv,0)+nvl(r_gccusv,0),0)/gcrt/10000,4),0) "REMOTE|LGWR %",
                 '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
                 round(msqk, 2) "QUEU|KSXP",
                 nullif(round(msqkt / msqk * 1000, 2), 0) "AVG|KSXP",
                 nvl(ipccpu * 1e4, 0) "IPC|CPU",
                 '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
                 msgrv "MSGS|RECV",
                 round(mrq / msgrv, 4) "QUEU|RECV",
                 nullif(round((nvl(msqt, 0) + nvl(gesmpt, 0) + nvl(mrqt, 0)) * 1000 / msgrv, 2), 0) "AVG|RECV",
                 nullif(round(mrqt / msgrv / 1000, 2), 0) "AVG|QUEUE",
                 nullif(round(msqkrt / msgrv / 1000, 2), 0) "AVG|KERNEL",
                 '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
                 msgst "MSGS|SENT",
                 nullif(round((nvl(msqt, 0) + nvl(msqkt, 0)) * 1000 / nullif(nvl(msq, 0) + nvl(msqk, 0), 0), 2), 0) "AVG|SENT",
                 nullif(round(msqt * 1000 / nullif(nvl(msq, 0) + nvl(msqk, 0), 0), 2), 0) "AVG|QUEUE",
                 '|' "|",
                 round(msgtt, 2) "TOTAL|SENT",
                 round(mfl / msgtt, 4) "FLOW|CTRL",
                 round(msd / msgtt, 4) "DIREX|SENT",
                 round(msi / msgtt, 4) "IN-DX|SENT",
                 round(msq / msgtt, 4) "QUEUE|SENT"
        FROM   (SELECT a.*,
                       nullif(nvl(gccrrv, 0) + nvl(gccurv, 0), 0) gcrv,
                       nullif(nvl(gccrrt, 0) + nvl(gccurt, 0), 0) gcrt,
                       nullif(round(nvl(gcsmr, 0) + nvl(gssmr, 0) + nvl(kagr, 0) + nvl(gesmr, 0), 2), 0) msgrv,
                       nullif(round(nvl(gcms, 0) + nvl(gsms, 0) + nvl(kams, 0) + nvl(gems, 0), 2), 0) msgst,
                       nullif(round(nvl(mfl, 0) + nvl(msd, 0) + nvl(msi, 0), 2), 0) msgtt,
                       MAX(decode(i, 0, gccrsv)) over() - decode(i, 0, 0, gccrsv) r_gccrsv,
                       MAX(decode(i, 0, gccrft)) over() - decode(i, 0, 0, gccrft) r_gccrft,
                       MAX(decode(i, 0, gccrbt)) over() - decode(i, 0, 0, gccrbt) r_gccrbt,
                       MAX(decode(i, 0, gccusv)) over() - decode(i, 0, 0, gccusv) r_gccusv,
                       MAX(decode(i, 0, gccupt)) over() - decode(i, 0, 0, gccupt) r_gccupt,
                       MAX(decode(i, 0, gccuft)) over() - decode(i, 0, 0, gccuft) r_gccuft
                FROM   delta a) a
        LEFT   JOIN lms b
        USING  (i)
        LEFT   JOIN (SELECT i,
                            nullif(nvl(gccrf, 0) + nvl(gccuf, 0), 0) gcf,
                            MAX(decode(i, 0, lgwrt)) over() - decode(i, 0, 0, lgwrt) r_lgwrt
                     FROM   XMLTABLE('//ROW[F="1"]' PASSING rs2(2) 
                            COLUMNS  i NUMBER        PATH 'I',
                                     v NUMBER        PATH 'T',
                                     n VARCHAR2(100) PATH 'N')
                     PIVOT(MAX(v) FOR n IN(
                                'gcs log flush sync' lgwrt,
                                'gc cr failure' gccrf, --a cr(consistent read) block was requested AND a failure status was received OR some other exceptional event such as a lost block has occurred.
                                'gc current retry' gccuf --Current block was requested AND a failure status was received OR some other exceptional event such as a lost block has occurred.
                                ))) c
        USING  (i)
        ORDER  BY inst;

    OPEN :c5 FOR
        SELECT NVL(''||I,'*') INST,NAME,IP_ADDR,NET_MASK,FLAGS,MTU,
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               ROUND(SUM(BRCV*T)/tim1,2) "RECV|BYTE",
               ROUND(SUM(PRCV*T)/tim1,2) "RECV|PACK",
               NULLIF(ROUND(SUM(DRCV*T)/tim1,2),0) "RECV|DROP",
               NULLIF(ROUND(SUM(ERCV*T)/tim1,2),0) "RECV|ERRS",
               NULLIF(ROUND(SUM(FRCV*T)/tim1,2),0) "RECV|FRAM",
               NULLIF(ROUND(SUM(ORCV*T)/tim1,2),0) "RECV|BUFF",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               ROUND(SUM(BSNT*T)/tim1,2) "SENT|BYTE",
               ROUND(SUM(PSNT*T)/tim1,2) "SENT|PACK",
               NULLIF(ROUND(SUM(DSNT*T)/tim1,2),0) "SENT|DROP",
               NULLIF(ROUND(SUM(ESNT*T)/tim1,2),0) "SENT|ERRS",
               NULLIF(ROUND(SUM(OSNT*T)/tim1,2),0) "SENT|BUFF",
               NULLIF(ROUND(SUM(LSNT*T)/tim1,2),0) "SENT|LOST"
        FROM  (SELECT 1 T, rs2(7) x FROM DUAL UNION ALL SELECT -1, rs1(7) x FROM DUAL) X,
               XMLTABLE('//ROW' PASSING x 
               COLUMNS i        INT           PATH 'INST_ID', 
                       NAME     VARCHAR2(30)  PATH 'IF_NAME', 
                       IP_ADDR  VARCHAR2(30)  PATH 'IP_ADDR', 
                       NET_MASK VARCHAR2(30)  PATH 'NET_MASK',
                       FLAGS    VARCHAR2(30)  PATH 'FLAGS',
                       MTU      VARCHAR2(30)  PATH 'MTU',
                       BRCV     INT           PATH 'BYTES_RECEIVED', 
                       PRCV     INT           PATH 'PACKETS_RECEIVED',
                       ERCV     INT           PATH 'RECEIVE_ERRORS',
                       DRCV     INT           PATH 'RECEIVE_DROPPED',
                       FRCV     INT           PATH 'RECEIVE_FRAME_ERR',
                       ORCV     INT           PATH 'RECEIVE_BUF_OR',
                       BSNT     INT           PATH 'BYTES_SENT',
                       PSNT     INT           PATH 'PACKETS_SENT',
                       ESNT     INT           PATH 'SEND_ERRORS',
                       DSNT     INT           PATH 'SENDS_DROPPED',
                       OSNT     INT           PATH 'SEND_BUF_OR',
                       LSNT     INT           PATH 'SEND_CARRIER_LOST') r2
        GROUP BY ROLLUP((I,NAME,IP_ADDR,NET_MASK,FLAGS,MTU))
        ORDER BY I NULLS FIRST,NAME;
END;
/

set printsize 45
print c2
print c4
print c1
print c31
print c32
print c5