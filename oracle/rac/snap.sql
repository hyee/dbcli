/*[[Snap relative gv$ views within specific time and output the delta result. Usage: @@NAME <secs>
    --[[
        &v1: default={5}
        @check_access_sleep: sys.dbms_session={sys.dbms_session.sleep} default={sys.dbms_lock.sleep}
    --]]
]]*/

set feed off verify off autohide col
var c1 refcursor "GC INSTANCE CACHE TRANSFER PER SECOND"
var c2 refcursor "CLUSTER EVENTS PER SECOND"
var c3 refcursor "RAC STATISTICS PER SECOND"
var c4 refcursor "GC CR/CU SERVER PER SECOND"
COL "TIME,AVG,RECV|TIME,CR AVG|IMMED,CR AVG|BUSY,CR AVG|2-HOP,CR AVG|3-HOP,CR AVG|CONGST" for usmhd2
COL "LOST|TIME,LOST|AVG,AVG|TIME,CU AVG|IMMED,CU AVG|BUSY,CU AVG|2-HOP,CU AVG|3-HOP,CU AVG|CONGST" for usmhd2
COL "GC CR|IMMED,CR TIM|IMMED,GC CR|2-HOP,CR TIM|2-HOP,GC CR|3-HOP,CR TIM|3-HOP,GC CR|BUSY,CR TIM|BUSY,GC CR|CONGST,CR TIM|CONGST" FOR PCT
COL "GC CU|IMMED,CU TIM|IMMED,GC CU|2-HOP,CU TIM|2-HOP,GC CU|3-HOP,CU TIM|3-HOP,GC CU|BUSY,CU TIM|BUSY,GC CU|CONGST,CU TIM|CONGST" FOR PCT
COL "1us,2us,4us,8us,16us,32us,64us,128us,256us,512us,1ms,2ms,4ms,8ms,16ms,32ms,65ms,131ms,262ms,524ms,1s,2s,4s,8s,16s,>16s" for pct1
PRO Sampling data for &v1 seconds, please wait ...
declare
    type t_xmls is table of xmltype;
    type t_sqls is table of varchar2(32767);
    type t_curs is table of number;

    sqls t_sqls:=t_sqls();
    curs t_curs:=t_curs();
    rs1  t_xmls:=t_xmls();
    rs2  t_xmls:=t_xmls();
    tim  number;
    tim1 number;
    procedure snap(idx pls_integer) is
    begin
        for i in 1..sqls.count loop
            curs(i):=dbms_xmlgen.newcontext(sqls(i));
        end loop;
        tim := dbms_utility.get_time;
        for i in 1..sqls.count loop
            if idx=1 then
                rs1(i):=dbms_xmlgen.getxmltype(curs(i));
            else
                rs2(i):=dbms_xmlgen.getxmltype(curs(i));
            end if;
            dbms_xmlgen.closecontext(curs(i));
        end loop;
    end;
begin
    sqls.extend(5);
    curs.extend(sqls.count);
    rs1.extend(sqls.count);
    rs2.extend(sqls.count); 
    tim1 := dbms_utility.get_time;
    sqls(1):='SELECT * FROM GV$INSTANCE_CACHE_TRANSFER WHERE LOST+CR_BLOCK+CURRENT_BLOCK>0';
    sqls(2):=q'~select /*+no_expand use_hash(a b)*/
                       a.event# n,u,
                       sum(wait_count) v,
                       max(sum(time_waited_micro)) over(partition by a.event#) m,
                       max(sum(total_waits)) over(partition by a.event#) t
                from   gv$system_event B 
                join   (select a.*, least(wait_time_micro,16777217) u from gv$event_histogram_micro a) A 
                using (inst_id,event)
                where  a.wait_count>0 
                and   (b.wait_class='Cluster' or 
                       event like 'gcs%' or event like '%LGWR%' or
                       event in('buffer busy waits',
                                'remote log force - commit',
                                'log file sync',
                                'log file parallel write'))
                group  by a.event#,u~';
    sqls(3):=q'~
            SELECT nvl(i,0) i,n,sum(v) v
            FROM   (select inst_id i,name n,value v from gv$sysstat 
                    union all 
                    select inst_id,name,value from gv$dlm_misc)
            WHERE  n like 'gc%'
            OR     n IN(
                'consistent gets from cache',
                'db block gets from cache',
                'DBWR fusion writes',
                'gcs messages sent',
                'gcs msgs process time(ms)',
                'gcs msgs received',
                'ges messages sent',
                'ges msgs process time(ms)',
                'ges msgs received',
                'global enqueue get time',
                'msgs received queue time (ms)',
                'msgs received queued',
                'msgs sent queue time (ms)',
                'msgs sent queue time on ksxp (ms)',
                'msgs sent queued on ksxp',
                'msgs sent queued',
                'physical reads cache',
                'user commits',
                'user rollbacks')
            GROUP BY n,rollup(i)
            HAVING SUM(v)>0~';
    sqls(4):='SELECT * FROM GV$CR_BLOCK_SERVER';
    sqls(5):='SELECT * FROM GV$CURRENT_BLOCK_SERVER';
    snap(1);
    tim1 := dbms_utility.get_time-tim1;
    dbms_output.put_line('Sampling data took external '|| round(tim1*2/100,2) ||' secs.');
    dbms_output.put_line('*******************************');
    tim1 := greatest(1,:v1-(dbms_utility.get_time-tim)/100);
    &check_access_sleep(tim1);
    snap(2);

    open :c1 for
        WITH delta AS (
            SELECT DIR,CLASS,NAME,(SUM(R2.VALUE)-NVL(SUM(R1.VALUE),0))/tim1 V
            FROM   (
                SELECT A.TARGET|| ' -> '||A.INST_ID dir,A.CLASS,b.name,b.value
                FROM   XMLTABLE('//ROW' PASSING rs2(1)
                       COLUMNS INST_ID INT PATH 'INST_ID',
                               TARGET INT PATH 'INSTANCE',
                               CLASS VARCHAR2(30) PATH 'CLASS',
                               NODE XMLTYPE PATH 'node()') A,
                       XMLTABLE('*[not(name()="INST_ID" or name()="CLASS" or name()="INSTANCE")]' PASSING A.NODE 
                       COLUMNS NAME VARCHAR2(30) PATH 'name()',
                               VALUE INT PATH '.') B) R2
            LEFT JOIN (
                SELECT A.TARGET|| ' -> '||A.INST_ID dir,A.CLASS,b.name,b.value
                FROM   XMLTABLE('//ROW' PASSING rs1(1)
                       COLUMNS INST_ID INT PATH 'INST_ID',
                               TARGET INT PATH 'INSTANCE',
                               CLASS VARCHAR2(30) PATH 'CLASS',
                               NODE XMLTYPE PATH 'node()') A,
                       XMLTABLE('*[not(name()="INST_ID" or name()="CLASS" or name()="INSTANCE")]' PASSING A.NODE 
                       COLUMNS NAME VARCHAR2(30) PATH 'name()',
                               VALUE INT PATH '.') B) R1 
            USING (DIR,CLASS,NAME)
            GROUP BY DIR,CLASS,NAME)
        SELECT DIR,CLASS,
               ROUND(LOST,2) "GC|LOST",LOST_TIME "LOST|TIME",LOST_TIME/NULLIF(LOST,0) "LOST|AVG",
               ROUND(TOTAL,2) "RECV|TOTAL",TOTAL_TIME "RECV|TIME",TOTAL_TIME/nullif(TOTAL,0) "AVG|TIME",
               '$HEADCOLOR$/$NOR$' "/",
               CR_BLOCK "GC CR|IMMED",CR_BLOCK_TIME "CR TIM|IMMED",CR_BLOCK_AVG "CR AVG|IMMED",
               '|' "|",
               CR_2HOP "GC CR|2-HOP",CR_2HOP_TIME "CR TIM|2-HOP",CR_2HOP_AVG "CR AVG|2-HOP",
               '|' "|",
               CR_3HOP "GC CR|3-HOP",CR_3HOP_TIME "CR TIM|3-HOP",CR_3HOP_AVG "CR AVG|3-HOP",
               '|' "|",
               CR_CONGESTED "GC CR|CONGST",CR_CONGESTED_TIME "CR TIM|CONGST",CR_CONGESTED_AVG "CR TIM|CONGST",
               '|' "|",
               CR_BUSY "GC CR|BUSY",CR_BUSY_TIME "CR TIM|BUSY",CR_BUSY_AVG "CR AVG|BUSY",
               '$HEADCOLOR$/$NOR$' "/",
               CU_BLOCK "GC CU|IMMED",CU_BLOCK_TIME "CU TIM|IMMED",CU_BLOCK_AVG "CU AVG|IMMED",
               '|' "|",
               CU_2HOP "GC CU|2-HOP",CU_2HOP_TIME "CU TIM|2-HOP",CU_2HOP_AVG "CU AVG|2-HOP",
               '|' "|",
               CU_3HOP "GC CU|3-HOP",CU_3HOP_TIME "CU TIM|3-HOP",CU_3HOP_AVG "CU AVG|3-HOP",
               '|' "|",
               CU_CONGESTED "GC CU|CONGST",CU_CONGESTED_TIME "CU TIM|CONGST",CU_CONGESTED_AVG "CU TIM|CONGST",
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
                WHERE  a.v1>0
                GROUP  BY r,DIR,CLASS,decode(r,1,name,2,n1,3,n2))
        PIVOT( SUM(V) FOR 
               NAME IN ('LOST' LOST,'LOST_TIME' LOST_TIME,
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
        ORDER BY "RECV|TIME" desc nulls last,1,2;

    OPEN :c2 FOR
        WITH delta AS (
            SELECT n,u,
                   round((r2.v-nvl(r1.v,0))/tim1,2) v,
                   round((r2.m-nvl(r1.m,0))/tim1,2) m,
                   round((r2.t-nvl(r1.t,0))/tim1,2) t
            FROM   XMLTABLE('//ROW' passing rs2(2)
                   COLUMNS n INT PATH 'N',
                           u INT PATH 'U',
                           v INT PATH 'V',
                           m INT PATH 'M',
                           t INT PATH 'T') r2
            JOIN XMLTABLE('//ROW' passing rs1(2)
                   COLUMNS n INT PATH 'N',
                           u INT PATH 'U',
                           v INT PATH 'V',
                           m INT PATH 'M',
                           t INT PATH 'T') r1
            USING(n,u)
            WHERE r2.t-nvl(r1.t,0)>0)
        SELECT * 
        FROM  (select /*+no_merge(a)*/ 
                      b.name,
                      a.m "Time",
                      round(a.m/a.t,2) "Avg",
                      a.t "Count",'|' "|",
                      a.u,
                      nullif(round(a.v/a.t,3),0) v
               from   delta a,v$event_name b 
               where  a.n=b.event#)
        PIVOT(max(v) for u in(
            1 "1us", 2 "2us", 4 "4us", 8 "8us",16 "16us", 32 "32us", 64 "64us", 128 "128us", 256 "256us",  512 "512us", 
            1024 "1ms", 2048 "2ms", 4096 "4ms", 8192 "8ms", 16384 "16ms", 32768 "32ms", 65536 "65ms", 131072 "131ms", 
            262144 "262ms", 524288 "524ms",  1048576 "1s", 2097152 "2s", 4194304 "4s", 8388608 "8s", 16777216 "16s",
            16777217 ">16s"))
        ORDER BY "Time" DESC;

    OPEN :c3 FOR
        WITH delta AS (
            SELECT n,i,
                   ROUND((r2.v-nvl(r1.v,0))/tim1,4) v
            FROM   XMLTABLE('//ROW' passing rs2(3)
                   COLUMNS n VARCHAR2(100) PATH 'N',
                           i INT PATH 'I',
                           v INT PATH 'V') r2
            JOIN  XMLTABLE('//ROW' passing rs1(3)
                   COLUMNS n VARCHAR2(100) PATH 'N',
                           i INT PATH 'I',
                           v INT PATH 'V') r1
            USING(n,i)
            WHERE ROUND((r2.v-nvl(r1.v,0))/tim1,4)>0)
        SELECT /*+no_merge(a)*/ 
               i inst,n,v
        FROM delta a;

    open :c4 for
        WITH delta AS (
            SELECT S SERVER,N NAME,
                   NVL(I,0) I,
                   ROUND((SUM(DECODE(T,2,V))-SUM(DECODE(T,1,V)))/tim1,2) V
            FROM  (SELECT 'CR SERVER' S,2 T,rs2(4) x FROM DUAL
                   UNION ALL
                   SELECT 'CR SERVER' S,1 T,rs1(4) x FROM DUAL
                   UNION ALL
                   SELECT 'CU SERVER' S,2 T,rs2(5) x FROM DUAL
                   UNION ALL
                   SELECT 'CR SERVER' S,1 T,rs1(5) x FROM DUAL
                  ) X,
                  XMLTABLE('//ROW' PASSING X.X
                   COLUMNS I INT PATH 'INST_ID',
                           NODE XMLTYPE PATH 'node()') A,
                  XMLTABLE('*[not(name()="INST_ID")]' PASSING A.NODE 
                   COLUMNS N VARCHAR2(30) PATH 'name()',
                           V INT PATH '.') B
            GROUP BY S,N,ROLLUP(I)) 
        SELECT  A.*,
                decode(name,
                        'CR_REQUESTS','CR blocks served due to remote CR block requests',
                        'CURRENT_REQUESTS','current blocks served due to remote CR block requests',
                        'DATA_REQUESTS','current or CR requests for data blocks',
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
                        'PIN1','Pins taking less than 1 ms',
                        'PIN10','Pins taking 1 to 10 ms',
                        'PIN100','Pins taking 10 to 100 ms',
                        'PIN1000','Pins taking 100 to 1000 ms',
                        'PIN10000','Pins taking 1000 to 10000 ms',
                        'FLUSH1','Flushes taking less than 1 ms',
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
            SELECT * FROM  (SELECT * FROM DELTA WHERE V>0)
            PIVOT (MAX(V) 
                   FOR I IN(0 "Total",1 "#1", 2 "#2",3 "#3", 4 "#4",5 "#5",6 "#6", 7 "#7", 8 "#8",
                            9 "#9", 10 "#10",11 "#11", 12 "#12",13 "#13", 14 "#14",15 "#15", 16 "#16"))) A
        ORDER BY 1,2;
end;
/

print c1
print c2
--print c3
print c4