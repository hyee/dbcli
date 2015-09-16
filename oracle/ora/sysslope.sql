/*[[Show change slope based on GV$SYSMETRIC_HISTORY. Usage: sysslope [metric_name] [inst_id] ]]*/
set feed off
var cur refcursor
BEGIN
    IF :V1 IS NULL THEN
        OPEN :cur FOR
            WITH mtx AS
             (SELECT /*+MATERIALIZE*/
               METRIC_ID,METRIC_NAME, 86400 * (SYSDATE - END_TIME) DAYS_AGO, AVG(val) VAL,END_TIME,
               AVG(val) / MEDIAN(AVG(val)) OVER(PARTITION BY METRIC_NAME) med
              FROM   (SELECT /*+merge no_expand*/
                         METRIC_ID,REPLACE(REPLACE(METRIC_NAME, ' Bytes', ' MB'), ' Per ', ' / ') METRIC_NAME, end_time,
                         VALUE / CASE WHEN LOWER(' '||METRIC_UNIT||' ') LIKE '% bytes %' THEN 1024 * 1024 ELSE 1 END val
                       FROM   GV$SYSMETRIC_HISTORY
                       WHERE  (:V2 IS NULL OR INST_ID=:V2))
              GROUP  BY METRIC_ID,METRIC_NAME, END_TIME
              HAVING AVG(val) > 0)
            SELECT METRIC_ID,METRIC_NAME,
                   CASE
                       WHEN REGR_SLOPE(t.med, t.days_ago) > 0 THEN
                        'IMPROVING'
                       ELSE
                        'REGRESSING'
                   END change, ROUND(REGR_SLOPE(t.med, t.days_ago), 6) "SLOPE", round(MEDIAN(val), 3) "Median",
                   round(STDDEV(val), 3) "Std Dev", round(AVG(val), 3) "Avg", round(MIN(val), 3) "Min",
                   round(MAX(val), 3) "Max", round(MIN(val) KEEP(dense_rank FIRST ORDER BY DAYS_AGO), 3) "First",
                   round(MIN(val) KEEP(dense_rank LAST ORDER BY DAYS_AGO), 3) "Last",
                   MIN(END_TIME) "First_Time",
                   MAX(END_TIME) "Last_Time"
            FROM   mtx t
            GROUP  BY METRIC_ID,METRIC_NAME
            ORDER  BY ABS(REGR_SLOPE(t.med, t.days_ago)) DESC NULLS LAST;
    ELSE
        OPEN :cur FOR
            SELECT /*+merge no_expand*/A.*
               FROM   GV$SYSMETRIC_HISTORY A
               WHERE  (:V2 IS NULL OR INST_ID=:V2)
               AND    ( upper(METRIC_NAME) like UPPER('%&V1%')) /* changed from metric_id to metric_name as name is more intuitive*/
               ORDER  BY END_TIME,INST_ID;
    END IF;
END;
/