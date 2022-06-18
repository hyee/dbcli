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
    --]]
]]*/

set feed off verify off autohide col
var c1 refcursor "INSTANCE CACHE TRANSFER PER SECOND"
var c2 refcursor "EVENT HISTOGRAM PER SECOND"
var c31 refcursor "CR/CU LATERNCY PER SECOND"
var c32 refcursor "MESSAGE LATERNCY PER SECOND"
var c4 refcursor "LMS SERVER STATS PER SECOND"
COL "TIME,AVG,RECV|TIME,CR AVG|IMMED,CR AVG|BUSY,CR AVG|2-HOP,CR AVG|3-HOP,CR AVG|CONGST" for usmhd2
COL "LOST|TIME,LOST|AVG,AVG|TIME,CU AVG|IMMED,CU AVG|BUSY,CU AVG|2-HOP,CU AVG|3-HOP,CU AVG|CONGST" for usmhd2
COL "GC CR|IMMED,CR TIM|IMMED,GC CR|2-HOP,CR TIM|2-HOP,GC CR|3-HOP,CR TIM|3-HOP,GC CR|BUSY,CR TIM|BUSY,GC CR|CONGST,CR TIM|CONGST" FOR PCT
COL "GC CU|IMMED,CU TIM|IMMED,GC CU|2-HOP,CU TIM|2-HOP,GC CU|3-HOP,CU TIM|3-HOP,GC CU|BUSY,CU TIM|BUSY,GC CU|CONGST,CU TIM|CONGST" FOR PCT
COL "1us,2us,4us,8us,16us,32us,64us,128us,256us,512us,1ms,2ms,4ms,8ms,16ms,32ms,65ms,131ms,262ms,524ms,1s,2s,4s,8s,16s,>16s" for pct1
COL "AVG TM|RECEIV,REMOTE|BUILD,REMOTE|FLUSH,BUILD|AVG TM,FLUSH|AVG TM,REMOTE|PIN,PIN|AVG TM,FLUSH|AVG TM" for usmhd2
COL "BUILD|SERVED,FLUSH|SERVED,LGWR|SERVED,PIN|SERVED,QUEU|RECV" for pct
COL "LMS|BUSY,ENQUE|GET,RECV|QUEUE,GCS|PROX,GES|PROX,REMOTE|BUILD%,REMOTE|PIN %,REMOTE|FLUSH%,REMOTE|LGWR %" for pct
COL "LMS|TIME,CR CU|TIME,CR CU|AVG TM,AVG|RECV,AVG|KERNEL,AVG|SENT,AVG|QUEUE,AVG|KSXP,GC|CPU,IPC|CPU" for usmhd2

COL grp noprint
PRO Sampling data, please wait ...
declare
    sleeps int := :v1;
    awr    BOOLEAN := &awr;
    c    sys_refcursor;
    type t_xmls is table of xmltype;
    type t_sqls is table of varchar2(32767);
    type t_curs is table of number;

    sqls t_sqls:=t_sqls();
    tmps t_sqls:=t_sqls();
    curs t_curs:=t_curs();
    rs1  t_xmls:=t_xmls();
    rs2  t_xmls:=t_xmls();
    tim  number;
    tim1 number;
    bid  int;
    eid  int;
    did  int;
    procedure snap(idx pls_integer) is
        ct  CLOB;
        xml XMLTYPE;
        j   int;
    begin
        for i in 1..sqls.count loop
            j  := i;
            tmps(i) := replace(replace(sqls(i),'@dbid',did),'@snap_id', case idx when 1 then bid else eid end);
            curs(i):=dbms_xmlgen.newcontext(tmps(i));
        end loop;
        tim := dbms_utility.get_time;
        for i in 1..sqls.count loop
            j := i;
            IF NOT AWR THEN
                xml := dbms_xmlgen.getxmltype(curs(i));
            ELSE
                ct  := nvl(dbms_xmlgen.getxml(curs(i)),'<ROWSET/>');
                ct  := regexp_replace(ct,'<(DBID|CON_DBID|CON_ID|SNAP_ID)>\d+</\1>');
                ct  := replace(ct,'INSTANCE_NUMBER>','INST_ID>');
                xml := xmltype(ct);
            END IF;
            dbms_xmlgen.closecontext(curs(i));
            if idx=1 then
                rs1(i):=xml;
            else
                rs2(i):=xml;
                if rs1(i) is null then
                    rs1(i):=xmltype('<ROWSET/>');
                end if;
            end if;
        end loop;
    exception when others then
        dbms_output.put_line('Error on SQL# '||j||':'||chr(10)||tmps(j));
        if ct IS NOT NULL THEN
            dbms_output.put_line(ct);
        end if;
        raise;
    end;

    function toXML return XMLTYPE is
        ctx NUMBER;
        xml XMLTYPE;
    BEGIN
        ctx := dbms_xmlgen.newcontext(c);
        xml := dbms_xmlgen.getxmltype(ctx);
        dbms_xmlgen.closecontext(ctx);
        close c;
        return xml;
    END;

    PROCEDURE sq(idx int, gsql VARCHAR2,dsql VARCHAR2) IS
    BEGIN   
        sqls(idx) := CASE WHEN NOT awr THEN gsql ELSE dsql END; 
    END;
begin
    sqls.extend(6);
    tmps.extend(sqls.count);
    curs.extend(sqls.count);
    rs1.extend(sqls.count);
    rs2.extend(sqls.count); 

    sq(1,'SELECT * FROM GV$INSTANCE_CACHE_TRANSFER WHERE LOST+CR_BLOCK+CURRENT_BLOCK>0'
        ,'SELECT * FROM &vw.inst_cache_transfer WHERE DBID=@dbid AND SNAP_ID=@snap_id');
    sq(2,q'~
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
        WHERE  1 = 1~',q'~
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
    sqls(2):=sqls(2)||q'~
        and   a.wait_count>0
        and   b.wait_class!='Idle'
        and   (b.wait_class='Cluster' or event like '%LGWR%' or event like '%LMS%' or
               event like 'gcs%' or event like 'ges%' or 
               event in('buffer busy waits',
                        'remote log force - commit',
                        'log file sync',
                        'log file parallel write'))~';
    sq(3,q'~
        SELECT i, v, n
        FROM   (SELECT inst_id i, NAME n, VALUE v FROM gv$sysstat 
                UNION ALL 
                SELECT inst_id, NAME, VALUE FROM gv$dlm_misc)~',q'~
        SELECT i,v,n
        FROM   (select instance_number i,stat_name n,value v FROM &vw.sysstat WHERE dbid=@dbid AND snap_id=@snap_id
                union all 
                select instance_number,name,value FROM &vw.dlm_misc WHERE dbid=@dbid AND snap_id=@snap_id)~'
    );
    sqls(3):=sqls(3)||q'~
        WHERE  v > 0
        AND   (n like 'gc %' or n like 'global%' or n like '%undo %' OR
               n IN(
                'cluster wait time',
                'remote Oradebug requests',
                'consistent gets from cache',
                'data blocks consistent reads - undo records applied',
                'db block changes',
                'db block gets from cache',
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
                'physical reads cache',
                'messages sent directly',
                'messages sent indirectly',
                'messages flow controlled',
                'user commits',
                'user rollbacks'))~';
    sq(4,'SELECT * FROM GV$CR_BLOCK_SERVER','SELECT * FROM &vw.CR_BLOCK_SERVER WHERE dbid=@dbid AND snap_id=@snap_id');
    sq(5,'SELECT * FROM GV$CURRENT_BLOCK_SERVER','SELECT * FROM &vw.CURRENT_BLOCK_SERVER WHERE dbid=@dbid AND snap_id=@snap_id');
    sq(6,q'~SELECT nvl(inst_id, 0) i, COUNT(DISTINCT sid * 1000 + inst_id) n, SUM(VALUE) v,1 f
            FROM   gv$sess_time_model
            JOIN   gv$session
            USING  (inst_id, sid)
            WHERE  program LIKE '%(LMS%)%'
            AND    TYPE = 'BACKGROUND'
            AND    stat_name LIKE 'background%time'
            AND    VALUE > 0
            GROUP  BY ROLLUP(inst_id)~',q'~
            SELECT nvl(instance_number,0) i, SUM(time_waited_micro) v, SUM(a.value + 0) n, -1 f
            FROM   dba_hist_parameter a
            JOIN   dba_hist_system_event
            USING  (dbid, instance_number, snap_id &con)
            WHERE  dbid=@dbid and snap_id=@snap_id
            AND    parameter_name = 'gcs_server_processes'
            AND    event_name = 'gcs remote message'
            GROUP  BY rollup(instance_number)~');

    IF awr THEN
        select max(dbid),min(snap_id),max(snap_id),86400*(max(end_interval_time+0)-min(end_interval_time+0))
        into   did,bid,eid,tim1
        from   &vw.snapshot
        where   dbid=nvl(:dbid,(select dbid from v$database))
        and     end_interval_time 
        between to_timestamp(coalesce(:V1, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')
            and to_timestamp(coalesce(:V2, to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI');
        IF did IS NULL THEN
            raise_application_error(-20001,'Cannot find matched AWR snapshots.');
        ELSIF tim1<=0 THEN
            raise_application_error(-20001,'No result in AWR snapshots due to input begin/end times are equal.');
        END IF;
    ELSE
        tim1 := dbms_utility.get_time;
    END IF;

    IF awr then
        snap(1);
    ELSIF sleeps > 0 THEN
        snap(1);
        tim1 := dbms_utility.get_time-tim1;
        dbms_output.put_line('Sampling data took external '|| round(tim1*2/100,2) ||' secs.');
        dbms_output.put_line('*******************************');
        tim1 := greatest(1,sleeps-(dbms_utility.get_time-tim)/100);
        tim:= dbms_utility.get_time;
        $IF DBMS_DB_VERSION.VERSION>12 $THEN
            dbms_session.sleep(tim1);
        $ELSE
            sys.dbms_lock.sleep(tim);
        $END
    ELSE
        SELECT 86400*(sysdate-startup_time) into tim1
        FROM   v$instance;
    END IF;
    snap(2);
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim:= dbms_utility.get_time;
    open :c1 for
        WITH delta AS (
            SELECT nvl(dir,'ALL') dir,CLASS,NAME,SUM(T*V)/tim1 V
            FROM   (
                SELECT T,A.TARGET|| '->'||A.INST_ID dir,A.CLASS,b.name,V
                FROM  (SELECT 1 T,rs2(1) X FROM DUAL 
                       UNION ALL 
                       SELECT -1,rs1(1) FROM DUAL) X,
                       XMLTABLE('//ROW' PASSING X.X
                       COLUMNS INST_ID INT PATH 'INST_ID',
                               TARGET INT PATH 'INSTANCE',
                               CLASS VARCHAR2(30) PATH 'CLASS',
                               NODE XMLTYPE PATH 'node()') A,
                       XMLTABLE('*[not(name()="INST_ID" or name()="CLASS" or name()="INSTANCE")]' PASSING A.NODE 
                       COLUMNS NAME VARCHAR2(30) PATH 'name()',
                               V INT PATH '.') B) R2
            GROUP BY ROLLUP((DIR,CLASS)),NAME)
        SELECT DIR,CLASS,
               ROUND(LOST,2) "GC|LOST",LOST_TIME "LOST|TIME",LOST_AVG "LOST|AVG",
               ROUND(TOTAL,2) "RECV|TOTAL",TOTAL_TIME "RECV|TIME",TOTAL_TIME/nullif(TOTAL,0) "AVG|TIME",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               CR_BLOCK "GC CR|IMMED",CR_BLOCK_TIME "CR TIM|IMMED",CR_BLOCK_AVG "CR AVG|IMMED",
               '|' "|",
               CR_2HOP "GC CR|2-HOP",CR_2HOP_TIME "CR TIM|2-HOP",CR_2HOP_AVG "CR AVG|2-HOP",
               '|' "|",
               CR_3HOP "GC CR|3-HOP",CR_3HOP_TIME "CR TIM|3-HOP",CR_3HOP_AVG "CR AVG|3-HOP",
               '|' "|",
               CR_CONGESTED "GC CR|CONGST",CR_CONGESTED_TIME "CR TIM|CONGST",CR_CONGESTED_AVG "CR AVG|CONGST",
               '|' "|",
               CR_BUSY "GC CR|BUSY",CR_BUSY_TIME "CR TIM|BUSY",CR_BUSY_AVG "CR AVG|BUSY",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               CU_BLOCK "GC CU|IMMED",CU_BLOCK_TIME "CU TIM|IMMED",CU_BLOCK_AVG "CU AVG|IMMED",
               '|' "|",
               CU_2HOP "GC CU|2-HOP",CU_2HOP_TIME "CU TIM|2-HOP",CU_2HOP_AVG "CU AVG|2-HOP",
               '|' "|",
               CU_3HOP "GC CU|3-HOP",CU_3HOP_TIME "CU TIM|3-HOP",CU_3HOP_AVG "CU AVG|3-HOP",
               '|' "|",
               CU_CONGESTED "GC CU|CONGST",CU_CONGESTED_TIME "CU TIM|CONGST",CU_CONGESTED_AVG "CU AVG|CONGST",
               '|' "|",
                CU_BUSY "GC CU|BUSY",CU_BUSY_TIME "CU TIM|BUSY",CU_BUSY_AVG "CU AVG|BUSY"
        FROM   (SELECT /*+no_merge a*/ 
                       dir,class,
                       decode(r,1,name,2,n1,3,n2) name,
                       round(decode(r,
                             1,max(v/nullif(v1,0)),
                             2,max(v1),
                             3,max(CASE WHEN NAME LIKE '%_TIME' THEN v END)/
                               max(CASE WHEN NAME NOT LIKE '%_TIME' THEN nullif(v,0) END)
                             ),4) v
                FROM   (select a.*,
                              replace(name,'_TIME')||'_AVG' n2,
                              regexp_replace(name,'^(CR|CURRENT)_[^_]+','TOTAL') n1,
                              SUM(CASE WHEN name not LIKE '%HOP%' THEN v ELSE 0 END) 
                                OVER(PARTITION BY dir,class,regexp_replace(name,'^(CR|CURRENT)_[^_]+','TOTAL')) v1
                        FROM  delta a
                        WHERE v>0 OR (name not like '%TIME' and name not like '%HOP%' and name not like '%CONGESTED%')
                        ) a,
                       (select rownum r from dual connect by rownum<=3)
                GROUP  BY r,DIR,CLASS,decode(r,1,name,2,n1,3,n2))

        PIVOT( SUM(V) FOR 
               NAME IN ('LOST' LOST,'LOST_TIME' LOST_TIME,'LOST_AVG' LOST_AVG,
                        'TOTAL' TOTAL,'TOTAL_TIME' TOTAL_TIME,
                        'CR_BLOCK' CR_BLOCK,'CR_BLOCK_TIME' CR_BLOCK_TIME,'CR_BLOCK_AVG' CR_BLOCK_AVG,
                        'CR_2HOP' CR_2HOP,'CR_2HOP_TIME' CR_2HOP_TIME,'CR_2HOP_AVG' CR_2HOP_AVG,
                        'CR_3HOP' CR_3HOP,'CR_3HOP_TIME' CR_3HOP_TIME,'CR_3HOP_AVG' CR_3HOP_AVG,
                        'CR_BUSY' CR_BUSY,'CR_BUSY_TIME' CR_BUSY_TIME,'CR_BUSY_AVG' CR_BUSY_AVG,
                        'CR_CONGESTED' CR_CONGESTED,'CR_CONGESTED_TIME' CR_CONGESTED_TIME,'CR_CONGESTED_AVG' CR_CONGESTED_AVG,
                        'CURRENT_BLOCK' CU_BLOCK,'CURRENT_BLOCK_TIME' CU_BLOCK_TIME,'CURRENT_BLOCK_AVG' CU_BLOCK_AVG,
                        'CURRENT_2HOP' CU_2HOP,'CURRENT_2HOP_TIME' CU_2HOP_TIME,'CURRENT_2HOP_AVG' CU_2HOP_AVG,
                        'CURRENT_3HOP' CU_3HOP,'CURRENT_3HOP_TIME' CU_3HOP_TIME,'CURRENT_3HOP_AVG' CU_3HOP_AVG,
                        'CURRENT_BUSY' CU_BUSY,'CURRENT_BUSY_TIME' CU_BUSY_TIME,'CURRENT_BUSY_AVG' CU_BUSY_AVG,
                        'CURRENT_CONGESTED' CU_CONGESTED,'CURRENT_CONGESTED_TIME' CU_CONGESTED_TIME,'CURRENT_CONGESTED_AVG' CU_CONGESTED_AVG)
        )
        WHERE ROUND(least(TOTAL,TOTAL_TIME),2)>0
        ORDER BY "RECV|TIME" desc nulls last,1,2;

    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim:=dbms_utility.get_time;
    OPEN c FOR
        SELECT *
        FROM  (SELECT /*+no_merge*/ 
                      nvl(i,0) i,n,u, 
                      MIN(F) F,
                      ROUND(SUM(c*V)/tim1,2) V,
                      MAX(ROUND(SUM(c*decode(f,1,m))/tim1,2)) OVER(PARTITION BY n,i) m,
                      MAX(ROUND(SUM(c*decode(f,1,t))/tim1,2)) OVER(PARTITION BY n,i) t
               FROM  (SELECT 1 c,rs2(2) X FROM DUAL 
                      UNION ALL 
                      SELECT -1,rs1(2) FROM DUAL) X,
                      XMLTABLE('//ROW' passing X.X
                      COLUMNS i INT PATH 'I',
                              n VARCHAR2(128) PATH 'N',
                              u INT PATH 'U',
                              v INT PATH 'V',
                              m INT PATH 'M',
                              t INT PATH 'T',
                              f INT PATH 'F') r2
               GROUP BY n,u,rollup(i)) a
        WHERE t>0;
    rs2(2) := toXML();

    OPEN :c2 FOR
        WITH delta AS (
            SELECT n name,
                      m "Time",
                      round(m/t,2) "Avg",
                      t "Count",'|' "|",
                      u,
                      nullif(round(v/t,3),0) v
            FROM   XMLTABLE('//ROW[I=0]' PASSING rs2(2)
                   COLUMNS n VARCHAR2(100) PATH 'N',
                           u INT PATH 'U',
                           v NUMBER PATH 'V',
                           m NUMBER PATH 'M',
                           t NUMBER PATH 'T') r2
        )
        SELECT * 
        FROM  delta
        PIVOT(max(v) for u in(
            1 "1us", 2 "2us", 4 "4us", 8 "8us",16 "16us", 32 "32us", 64 "64us", 128 "128us", 256 "256us",  512 "512us", 
            1024 "1ms", 2048 "2ms", 4096 "4ms", 8192 "8ms", 16384 "16ms", 32768 "32ms", 65536 "65ms", 131072 "131ms", 
            262144 "262ms", 524288 "524ms",  1048576 "1s", 2097152 "2s", 4194304 "4s", 8388608 "8s", 16777216 "16s",
            16777217 ">16s"))
        ORDER BY "Time" DESC;

    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim:=dbms_utility.get_time;
    OPEN c FOR
        SELECT * FROM (
            SELECT S,
                   grp,
                   decode(grouping_id(N),0,nvl2(grp,'  '||n,n),grp) n,
                   NVL(I,0) I,
                   round(SUM(V)/tim1,2) v
            FROM (
                SELECT S,
                       N,
                       CASE WHEN n IN('DATA_REQUESTS','UNDO_REQUESTS','TX_REQUESTS','OTHER_REQUESTS') THEN 'LMS SERVER REQUESTS'
                            WHEN s='CURRENT' AND regexp_substr(n,'^\D+') in ('FLUSH','PIN','WRITE') THEN regexp_substr(n,'^\D+')
                       END grp,
                       I,
                       T*V V
                FROM  (SELECT 'CR' S,1 T,rs2(4) x FROM DUAL
                       UNION ALL
                       SELECT 'CR' S,-1 T,rs1(4) x FROM DUAL
                       UNION ALL
                       SELECT 'CURRENT' S,1 T,rs2(5) x FROM DUAL
                       UNION ALL
                       SELECT 'CURRENT' S,-1 T,rs1(5) x FROM DUAL
                      ) X,
                      XMLTABLE('//ROW' PASSING X.X
                       COLUMNS I INT PATH 'INST_ID',
                               NODE XMLTYPE PATH 'node()') A,
                      XMLTABLE('*[not(name()="INST_ID")]' PASSING A.NODE 
                       COLUMNS N VARCHAR2(30) PATH 'name()',
                               V INT PATH '.') B
            ) GROUP BY S,grp,CUBE(I,N))
        WHERE V>0 AND n IS NOT NULL;
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim:=dbms_utility.get_time;
    rs2(4) := toXML();

    open :c4 for
        SELECT  A.*,
                decode(trim(name),
                        'CR_REQUESTS','CR blocks served due to remote CR block requests',
                        'CURRENT_REQUESTS','Current blocks served due to remote CR block requests',
                        'DATA_REQUESTS','Current or CR requests for data blocks',
                        'UNDO_REQUESTS','CR requests for undo blocks',
                        'TX_REQUESTS','CR requests for undo segment header blocks',
                        'OTHER_REQUESTS','CR requests for other types of blocks',
                        'CURRENT_RESULTS','requests for which no changes were rolled out of the block returned to the requesting instance',
                        'PRIVATE_RESULTS','requests for which changes were rolled out of the block returned to the requesting instance, and only the requesting transaction can use the resulting CR block',
                        'ZERO_RESULTS','requests for which changes were rolled out of the block returned to the requesting instance. Only zero-XID transactions can use the block.',
                        'DISK_READ_RESULTS','requests for which the requesting instance had to read the requested block from disk',
                        'FAIL_RESULTS','requests that failed; the requesting transaction must reissue the request',
                        'STALE','requests for which the disk read of the requested block was stale',
                        'FAIRNESS_DOWN_CONVERTS','times an instance receiving a request has down-converted an X lock on a block because it was not modifying the block',
                        'FAIRNESS_CLEARS','times the "fairness counter" was cleared. This counter tracks the times a block was modified after it was served.',
                        'FREE_GC_ELEMENTS','times a request was received from another instance and the X lock had no buffers',
                        'FLUSHES','times the log has been flushed by an LMS process',
                        'FLUSHES_QUEUED','flushes queued by an LMS process',
                        'FLUSH_QUEUE_FULL','times the flush queue was full',
                        'FLUSH_MAX_TIME','Maximum time for flush',
                        'LIGHT_WORKS','times the light-work rule was evoked. This rule prevents the LMS processes from going to disk to complete responding to CR requests',
                        'ERRORS','times an error was signalled by an LMS process',
                        'PIN0','Pins taking less than 100 us',
                        'PIN1','Pins taking 100 us to 1 ms',
                        'PIN10','Pins taking 1 to 10 ms',
                        'PIN100','Pins taking 10 to 100 ms',
                        'PIN1000','Pins taking 100 to 1000 ms',
                        'PIN10000','Pins taking 1000 to 10000 ms',
                        'FLUSH0','Flushes taking less than 100 us',
                        'FLUSH1','Flushes taking 100 us to 1 ms',
                        'FLUSH10','Flushes taking 1 to 10 ms',
                        'FLUSH100','Flushes taking 10 to 100 ms',
                        'FLUSH1000','Flushes taking 100 to 1000 ms',
                        'FLUSH10000','Flushes taking 1000 to 10000 ms',
                        'WRITE1','Writes taking less than 1 ms',
                        'WRITE10','Writes taking 1 to 10 ms',
                        'WRITE100','Writes taking 10 to 100 ms',
                        'WRITE1000','Writes taking 100 to 1000 ms',
                        'WRITE10000','Writes taking 1000 to 10000 ms',
                        'CLEANDC','Reserved for internal use',
                        'RCVDC','Number of lock down-converts to S (shared) caused by instance recovery',
                        'QUEUEDC','Number of queued lock down-converts to NULL',
                        'EVICTDC','Number of lock down-converts to NULL caused by an SGA shrink',
                        'WRITEDC','Number of dirty blocks in read-mostly objects which were written and the X lock down-converted to S locks'
                ) MEMO
        FROM (
            SELECT * 
            FROM XMLTABLE('//ROW' PASSING rs2(4)
                 COLUMNS server VARCHAR2(10) PATH 'S',
                         name   VARCHAR2(30) PATH 'N',
                         grp    VARCHAR2(30) PATH 'GRP',
                         I      INT PATH 'I',
                         V      NUMBER PATH 'V')
            PIVOT (MAX(V) 
                   FOR I IN(0 "Total",1 "#1", 2 "#2",3 "#3", 4 "#4",5 "#5",6 "#6", 7 "#7", 8 "#8",
                            9 "#9", 10 "#10",11 "#11", 12 "#12",13 "#13", 14 "#14",15 "#15", 16 "#16"))) A
        ORDER BY server,grp,decode(grp,name,1,2),name;

    OPEN c FOR
        SELECT nvl(i,0) i, n,
               ROUND(SUM(t*v)/tim1,6) v
        FROM   (SELECT 1 T,rs2(3) x FROM DUAL
                UNION ALL
                SELECT -1 ,rs1(3) x FROM DUAL) X,
               XMLTABLE('//ROW' passing x
               COLUMNS n VARCHAR2(100) PATH 'N',
                       i INT PATH 'I',
                       v INT PATH 'V') r2
        GROUP BY n,rollup(i)
        HAVING ROUND(SUM(t*v)/tim1,6)>0;
    rs2(3) := toXML();
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim:=dbms_utility.get_time;
    OPEN :c31 FOR
        WITH delta AS(
            SELECT * FROM (
                SELECT /*+no_merge*/ *
                FROM XMLTABLE('//ROW' PASSING rs2(3)
                       COLUMNS n VARCHAR2(100) PATH 'N',
                               i INT PATH 'I',
                               v NUMBER PATH 'V')
                LEFT JOIN  (
                       SELECT * 
                       FROM XMLTABLE('//ROW' PASSING rs2(4)
                            COLUMNS I INT PATH 'I',
                                    n  VARCHAR2(30) PATH 'N',
                                    v  NUMBER PATH 'V')
                       PIVOT (MAX(V) FOR N IN('FLUSHES' gccrfl,'FLUSH' gccufl,'PIN' gccupn,'ERRORS' errs)))
                USING (I))
            pivot (sum(v) for n in (
                 'gc cr blocks received'         gccrrv
               , 'gc cr block receive time'      gccrrt
               , 'gc cr blocks served'           gccrsv
               , 'gc cr blocks built'            gccrbc
               , 'gc cr block build time'        gccrbt
               , 'gc cr blocks flushed'          gccrfc
               , 'gc cr block flush time'        gccrft
               , 'gc current blocks received'    gccurv
               , 'gc current block receive time' gccurt
               , 'gc current blocks served'      gccusv
               , 'gc current blocks pinned'      gccupc
               , 'gc current block pin time'     gccupt
               , 'gc current blocks flushed'     gccufc
               , 'gc current block flush time'   gccuft
               , 'global enqueue get time'       glgt
               , 'global enqueue gets sync'      glsg
               , 'global enqueue gets async'     glag))
        )
        SELECT decode(i,0,'*',''||i) inst
             , round(errs,2) "LMS|ERRS"
             , round(gccrrv+gccurv,2) "RECV|BLKS"
             , round(gccrsv+gccusv,2) "SERV|BLKS"
             , '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$"
             , round(gccrrv,2) "CR BLKS|RECEIVE"
             , round(gccrrt/gccrrv*10000,2)         "AVG TM|RECEIV"
             , round(r_gccrbt/r_gccrsv*10000,2) "REMOTE|BUILD"
             , round(r_gccrft/r_gccrsv*10000,2) "REMOTE|FLUSH"
             , '|' "|"
             , round(gccrsv,2)               "CR BLKS|SERVED"
             , round(gccrbc/gccrsv,4)               "BUILD|SERVED"
             , round(gccrfc/gccrsv,4)               "FLUSH|SERVED"
             , round(gccrfl/gccrsv,4)               "LGWR|SERVED"
             , round(gccrbt/gccrbc*10000,2)         "BUILD|AVG TM"
             , round(gccrft/nvl(gccrfc,gccrfl)*10000,2)         "FLUSH|AVG TM"
             , '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$"
             , round(gccurv,2) "CU BLKS|RECEIVE"
             , round(gccurt/gccurv*10000,2)         "AVG TM|RECEIV"
             , round(r_gccupt/r_gccusv*10000,2)         "REMOTE|PIN"
             , round(r_gccuft/r_gccusv*10000,2)         "REMOTE|FLUSH"
             , '|' "|"
             , round(gccusv,2) "CU BLKS|SERVED"
             , round(nvl(gccupc,gccupn)/gccusv,4)   "PIN|SERVED"
             , round(nvl(gccufc,gccufl)/gccusv,4)   "FLUSH|SERVED"
             , round(gccufl/gccusv,4)               "LGWR|SERVED"
             , '|' "|"
             , round(gccupt/nvl(gccupc,gccupn)*10000,2)         "PIN|AVG TM"
             , round(gccuft/nvl(gccufc,gccufl)*10000,2)         "FLUSH|AVG TM"
             , '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$"
             --, round(glgt/nullif(nvl(glag,0)+nvl(glsg,0),0)*10000,4)  "GC ENQ|GET TIME"
        FROM  (select a.*,
                      max(decode(i,0,gccrsv)) over()-decode(i,0,0,gccrsv) r_gccrsv,
                      max(decode(i,0,gccrft)) over()-decode(i,0,0,gccrft) r_gccrft,
                      max(decode(i,0,gccrbt)) over()-decode(i,0,0,gccrbt) r_gccrbt,
                      max(decode(i,0,gccusv)) over()-decode(i,0,0,gccusv) r_gccusv,
                      max(decode(i,0,gccupt)) over()-decode(i,0,0,gccupt) r_gccupt,
                      max(decode(i,0,gccuft)) over()-decode(i,0,0,gccuft) r_gccuft
               from   delta a)
        ORDER BY inst;
    --dbms_output.put_line(dbms_utility.get_time-tim);
    tim:=dbms_utility.get_time;
    rs1(6):=rs1(6).deleteXML('//N');
    OPEN :c32 FOR
        WITH delta AS(
            SELECT /*+no_merge*/ *
            FROM XMLTABLE('//ROW' PASSING rs2(3)
                   COLUMNS n VARCHAR2(100) PATH 'N',
                           i INT PATH 'I',
                           v NUMBER PATH 'V')
            pivot (sum(v) for n in (
                 'gc cr blocks received'         gccrrv
               , 'gc cr block receive time'      gccrrt
               , 'gc current blocks received'    gccurv
               , 'gc current block receive time' gccurt
               , 'gc cr block build time'        gccrbt
               , 'gc cr block flush time'        gccrft
               , 'gc cr blocks served'           gccrsv
               , 'gc current block pin time'     gccupt
               , 'gc current block flush time'   gccuft
               , 'gc current blocks served'      gccusv
               , 'gc blocks lost' gcl
               , 'global enqueue get time'       glgt
               , 'global enqueue gets sync'      glsg
               , 'global enqueue gets async'     glag
               , 'gcs msgs received'             gcsmr
               , 'gc status messages received'   gssmr
               , 'gcs msgs process time(ms)'     gcsmpt
               , 'ges msgs received'             gesmr 
               , 'ges msgs process time(ms)'     gesmpt
               , 'ges messages sent'             gems
               , 'gcs messages sent'             gcms
               , 'msgs sent queued'              msq
               , 'msgs sent queue time (ms)'     msqt
               , 'msgs sent queued on ksxp'      msqk
               , 'msgs sent queue time on ksxp (ms)' msqkt
               , 'msgs received kernel queue time (ns)' msqkrt
               , 'ka grants received'                kagr
               , 'ka messages sent'                  kams
               , 'gc status messages sent'           gsms
               , 'msgs received queued'             mrq
               , 'msgs received queue time (ms)'    mrqt
               , 'messages sent directly'   msd
               , 'messages sent indirectly' msi
               , 'messages flow controlled' mfl
               , 'gc CPU used by this session' gccpu
               , 'IPC CPU used by this session'  ipccpu))
        ),
        LMS AS(
            select i,max(n) lms,
                   f*round(sum(t*v)/tim1)+decode(f,1,0,max(n)*1e6) lms_busy
            from  (select 1 t,rs2(6) x from dual union all select -1,rs1(6) from dual) x,
                    xmltable('//ROW' PASSING x.x
                       COLUMNS v INT PATH 'V',
                               n INT PATH 'N',
                               i INT PATH 'I',
                               f INT PATH 'F')
            group by i,f
            )
        SELECT /*+no_merge(a) no_merge(b) no_merge(c) use_hash(a b c)*/
               decode(i,0,'*',''||i) inst,
               lms "LMS|NUM",
               lms_busy "LMS|TIME",
               gccpu*1e4 "GC|CPU",
               round(lms_busy*1E-6/lms,4) "LMS|BUSY",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               round(gcrv,2) "CR CU|RECV",
               round(gcl,2)  "CR CU|LOST",
               round(gcf,2)  "GC CU|FAILS",
               round(gcrt*10000,2) "CR CU|TIME",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               round(gcrt*10000/gcrv,2) "CR CU|AVG TM",
               round(glgt/gcrt,4)  "ENQUE|GET",
               nullif(round(r_gccrbt*gccrrv/r_gccrsv/gcrt,4),0) "REMOTE|BUILD%",
               nullif(round(r_gccupt*gccurv/r_gccusv/gcrt,4),0) "REMOTE|PIN %",
               nullif(round((nvl(r_gccrft*gccrrv/r_gccrsv,0)+nvl(r_gccuft*gccurv/r_gccusv,0))/gcrt,4),0) "REMOTE|FLUSH%",
               nullif(round(r_lgwrt*(nvl(gccrrv,0)+nvl(gccurv,0))/nullif(nvl(r_gccrsv,0)+nvl(r_gccusv,0),0)/gcrt/10000,4),0) "REMOTE|LGWR %",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               round(msqk,2) "QUEU|KSXP",
               nullif(round(msqkt/msqk*1000,2),0) "AVG|KSXP",
               nvl(ipccpu*1e4,0) "IPC|CPU",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               msgrv "MSGS|RECV",
               round(mrq/msgrv,4) "QUEU|RECV",
               nullif(round((nvl(msqt,0)+nvl(gesmpt,0)+nvl(mrqt,0))*1000/msgrv,2),0) "AVG|RECV",
               nullif(round(mrqt/msgrv/1000,2),0) "AVG|QUEUE",
               nullif(round(msqkrt/msgrv/1000,2),0) "AVG|KERNEL",
               '$PROMPTCOLOR$||$NOR$' "$PROMPTCOLOR$||$NOR$",
               msgst "MSGS|SENT",
               nullif(round((nvl(msqt,0)+nvl(msqkt,0))*1000/msgst,2),0) "AVG|SENT",
               '|' "|",
               round(msd,2) "DIRX|SENT",
               round(msi,2) "NO-DX|SENT",
               round(msq,2) "QUEU|SENT",
               nullif(round(msqt/msq*1000,2),0) "AVG|QUEUE"
        FROM (select a.*,
                     nullif(nvl(gccrrv,0)+nvl(gccurv,0),0) gcrv,
                     nullif(nvl(gccrrt,0)+nvl(gccurt,0),0) gcrt,
                     nullif(round(nvl(gcsmr,0)+nvl(gssmr,0)+nvl(kagr,0)+nvl(gesmr,0),2),0) msgrv,
                     nullif(round(nvl(gcms,0)+nvl(gsms,0)+nvl(kams,0)+nvl(gems,0),2),0) msgst,
                     max(decode(i,0,gccrsv)) over()-decode(i,0,0,gccrsv) r_gccrsv,
                     max(decode(i,0,gccrft)) over()-decode(i,0,0,gccrft) r_gccrft,
                     max(decode(i,0,gccrbt)) over()-decode(i,0,0,gccrbt) r_gccrbt,
                     max(decode(i,0,gccusv)) over()-decode(i,0,0,gccusv) r_gccusv,
                     max(decode(i,0,gccupt)) over()-decode(i,0,0,gccupt) r_gccupt,
                     max(decode(i,0,gccuft)) over()-decode(i,0,0,gccuft) r_gccuft
              from delta a) a
        LEFT JOIN lms b USING(i)
        LEFT JOIN (

              select i,nullif(nvl(gccrf,0)+nvl(gccuf,0),0) gcf,max(decode(i,0,lgwrt)) over()-decode(i,0,0,lgwrt) r_lgwrt
              from xmltable('//ROW[F="1"]' PASSING rs2(2)
                       COLUMNS v NUMBER PATH 'M',
                               n VARCHAR2(100) PATH 'N',
                               i NUMBER PATH 'I')
              pivot(max(v) for n in('gcs log flush sync' lgwrt,
                                   'gc cr failure' gccrf, --a cr(consistent read) block was requested and a failure status was received or some other exceptional event such as a lost block has occurred.
                                   'gc current retry' gccuf --Current block was requested and a failure status was received or some other exceptional event such as a lost block has occurred.
                                   ))) c
        USING(i)
        ORDER BY inst;
end;
/
print c4
print c1
print c2
print c31
print c32
