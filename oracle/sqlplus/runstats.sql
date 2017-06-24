set echo on

drop table run_stats;
create global temporary table run_stats 
( seq  NUMBER(3),
  runid varchar2(15), 
  name varchar2(80), 
  value int )
on commit preserve rows;


create or replace view STATS as 
SELECT *
FROM   (SELECT 'STAT...' || a.name NAME, b.value
        FROM   v$statname a, v$mystat b
        WHERE  a.statistic# = b.statistic#
        UNION ALL
        SELECT 'Event..' || event, total_waits
        FROM   v$session_event
        WHERE  sid = userenv('sid')
        UNION ALL
        SELECT 'STAT...Elapsed Time', hsecs
        FROM   v$timer)
WHERE  VALUE > 0
/

CREATE OR REPLACE PACKAGE "RUNSTATS_PKG" IS
    PROCEDURE rs_reset(reset_all BOOLEAN := FALSE);
    PROCEDURE rs_compute(tag VARCHAR2 := NULL);
    PROCEDURE rs_start(tag VARCHAR2 := 'start');
    PROCEDURE rs_middle(tag VARCHAR2 := 'middle');
    PROCEDURE rs_stop(fetch_rows INT := 100);
END;
/
CREATE OR REPLACE PACKAGE BODY "RUNSTATS_PKG" IS
    current_tag run_stats.runid%TYPE;

    PROCEDURE rs_compute(tag VARCHAR2 := NULL) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        IF nvl(tag, current_tag) IS NOT NULL THEN
            INSERT INTO run_stats
                SELECT *
                FROM   (SELECT /*+no_merge(a) no_merge(b) use_hash(a b)*/
                         decode(tag, '<init>', -1, (SELECT MAX(seq) + 1 FROM run_stats)), --
                         nvl(tag, current_tag),
                         NAME,
                         greatest((a.value - nvl(b.value, 0)),
                                  CASE
                                      WHEN NAME LIKE '%Elapsed Time%' THEN
                                       1
                                      ELSE
                                       0
                                  END) ela
                        FROM   stats a
                        LEFT   OUTER JOIN (SELECT NAME, SUM(VALUE) VALUE FROM run_stats WHERE seq <= 0 GROUP BY NAME) b
                        USING  (NAME))
                WHERE  ela > 0;
            current_tag := NULL;
        END IF;
        COMMIT;
    END;

    PROCEDURE rs_reset(reset_all BOOLEAN := FALSE) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        IF reset_all THEN
            DELETE run_stats;
        ELSE
            DELETE run_stats WHERE seq = 0;
        END IF;
        INSERT INTO run_stats
            SELECT 0, NULL, a.* FROM stats a WHERE VALUE > 0;
        COMMIT;
        --warm up
        IF reset_all THEN
            rs_compute('<init>');
            DELETE run_stats WHERE seq = 0;
            INSERT INTO run_stats
                SELECT 0, NULL, a.* FROM stats a WHERE VALUE > 0;
            COMMIT;
        END IF;
    END;

    PROCEDURE rs_start(tag VARCHAR2 := 'start') IS
    BEGIN
        rs_reset(TRUE);
        current_tag := tag;
    END;

    PROCEDURE rs_middle(tag VARCHAR2 := 'middle') IS
    BEGIN
        rs_compute(current_tag);
        rs_reset;
        current_tag := tag;
    END;

    PROCEDURE rs_stop(fetch_rows INT := 100) IS
        tags VARCHAR2(2000);
        head VARCHAR2(2000);
        mgr  VARCHAR2(2000);
        sep  VARCHAR2(2000);
        fmt  VARCHAR2(30) := 'fm999,999,999,999,999';
        len1 PLS_INTEGER;
        len2 PLS_INTEGER;
        cur  SYS_REFCURSOR;
        TYPE t IS TABLE OF VARCHAR2(4000);
        names t;
        vals  t;
        PROCEDURE p(col1 VARCHAR2, col2 VARCHAR2) IS
        BEGIN
            dbms_output.put_line(rpad(col1, len1) || ' ' || col2);
        END;
    BEGIN
        rs_compute(current_tag);
        SELECT MAX(length(TRIM(NAME))), greatest(MAX(length(to_char(VALUE, fmt))), MAX(length(runid))) INTO len1, len2 FROM run_stats;
    
        SELECT listagg(seq, ',') WITHIN GROUP(ORDER BY seq),
               listagg('lpad(nvl("' || seq || '",''0''),' || (len2 + 1) || ')', '||') WITHIN GROUP(ORDER BY seq),
               ' ' || listagg(lpad(tag, len2), ' ') WITHIN GROUP(ORDER BY seq),
               ' ' || listagg(lpad('-', len2, '-'), ' ') WITHIN GROUP(ORDER BY seq)
        INTO   tags, mgr, head, sep
        FROM   (SELECT DISTINCT seq, runid tag FROM run_stats WHERE seq > 0 ORDER BY 1);
    
        dbms_output.enable(NULL);
        p('Name', head);
        p(rpad('-', len1, '-'), sep);
    
        OPEN cur FOR '
            SELECT *
            FROM   (SELECT NAME,' || mgr || ' v
                    FROM   (SELECT seq, NAME, to_char(VALUE, ''' || fmt || ''') VALUE, 
                                   case when name like ''%Elapsed Time%'' then 1e22 else SUM(VALUE) OVER(PARTITION BY NAME) end total
                            FROM   run_stats
                            WHERE  seq > 0)
                    PIVOT(MAX(VALUE) FOR seq IN(' || tags || '))
                    ORDER  BY substr(name,1,4),total DESC)
            WHERE  ROWNUM <= :1'
            USING fetch_rows;
        FETCH cur BULK COLLECT
            INTO names, vals;
        FOR i IN 1 .. names.count LOOP
            p(names(i), vals(i));
        END LOOP;
    END;
END;
/

create or replace public synonym runstats_pkg for runstats_pkg;
grant execute on runstats_pkg to public;