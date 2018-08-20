/*[[Gather and show system statistics. Usage: @@NAME <secs>|<query>]]*/
set feed off
VAR CUR REFCURSOR;
DECLARE
    STATUS     VARCHAR2(20);
    start_time DATE;
    stop_time  DATE;
    PVALUE     INT;
    i          int;
    TYPE t IS RECORD(
        NAME        VARCHAR2(128),
        DESCRIPTION VARCHAR2(1000));
    TYPE t0 IS TABLE OF t;
    t1 t0;
    x  VARCHAR2(5000) := '<ROWSET>';
BEGIN
    DBMS_STATS.GATHER_SYSTEM_STATS(gathering_mode => 'start');
    IF regexp_like(nvl(:V1,'10'),'^\d+$') THEN
        dbms_lock.sleep(nvl(:V1,10));
    ELSE
        execute immediate 'select /*+full(a)*/ count(1) from ('||:V1||') a' into i;
    END IF;
    DBMS_STATS.GATHER_SYSTEM_STATS(gathering_mode => 'stop');
    SELECT DECODE(ROWNUM, 1, 'iotfrspeed', 2, 'ioseektim', 3, 'sreadtim', 4, 'mreadtim', 5, 'cpuspeed', 6, 'cpuspeednw', 7, 'mbrc', 8, 'maxthr', 9,'slavethr') n,
           DECODE(ROWNUM, 1,'I/O transfer speed in bytes for each millisecond', 
                          2,'seek time + latency time + operating system overhead time, in milliseconds', 
                          3,'average time to read single block (random read), in milliseconds', 
                          4,'average time to read an mbrc block at once (sequential read), in milliseconds', 
                          5,'average number of CPU cycles for each second, in millions, captured for the workload',
                          6,'average number of CPU cycles for each second, in millions, captured for the noworkload',
                          7,'average multiblock read count for sequential read, in blocks', 
                          8,'maximum I/O system throughput, in bytes/second', 
                          9,'average slave I/O throughput, in bytes/second') d
    BULK   COLLECT
    INTO   t1
    FROM   dual
    CONNECT BY ROWNUM < 10;

    FOR j IN 1 .. t1.count LOOP
        DBMS_STATS.GET_SYSTEM_STATS(status, start_time, stop_time, t1(j).name, pvalue);
        IF j = 1 THEN
            x := x || '<ROW><NAME>status</NAME><VALUE>' || status || '</VALUE><DESCRIPTION>''WORKLOAD'' mode from '
                   || to_char(start_time,'yyyy-mm-dd hh24:mi:ss') ||' to '|| to_char(stop_time,'yyyy-mm-dd hh24:mi:ss') 
                   ||'</DESCRIPTION></ROW>' || CHR(10);
        END IF;
        x := x || '<ROW><NAME>' || t1(j).name || '</NAME><VALUE>' || pvalue || '</VALUE><DESCRIPTION>' || t1(j).DESCRIPTION || '</DESCRIPTION></ROW>' ||
             CHR(10);
    END LOOP;
    x := x || '</ROWSET>';
    OPEN :CUR FOR
        SELECT extractvalue(b.column_value, '/ROW/NAME') NAME,
               extractvalue(b.column_value, '/ROW/VALUE') VALUE,
               extractvalue(b.column_value, '/ROW/DESCRIPTION') DESCRIPTION
        FROM   TABLE(XMLSEQUENCE(EXTRACT(XMLTYPE(x), '/ROWSET/ROW'))) b;
END;
/