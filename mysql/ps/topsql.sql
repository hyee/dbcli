/*[[
    Show top 30 SQLs
    Refer to http://www.markleith.co.uk/2012/07/04/mysql-performance-schema-statement-digests
]]*/
COL time_total,time_max,avg_time FOR USMHD2
COL rows_sent,rows_sent_avg,rows_scanned FOR TMB2
SELECT concat(substr(DIGEST,1,18),' ..') AS digest,
       IF(SUM_NO_GOOD_INDEX_USED > 0 OR SUM_NO_INDEX_USED > 0, 'Full', '') AS scan,
       COUNT_STAR AS execs,
       SUM_ERRORS AS errs,
       SUM_WARNINGS AS warns,
       SUM_TIMER_WAIT / 1e6 time_total,
       MAX_TIMER_WAIT / 1e6 time_max,
       AVG_TIMER_WAIT / 1e6 avg_time,
       SUM_ROWS_SENT AS rows_sent,
       ROUND(SUM_ROWS_SENT / COUNT_STAR) AS rows_sent_avg,
       SUM_ROWS_EXAMINED AS rows_scanned,
       substr(replace(replace(replace(replace(trim(digest_text),'\n',' '),' ','<>'),'><',''),'<>',' '),1,150) sql_text
FROM   performance_schema.events_statements_summary_by_digest
ORDER  BY SUM_TIMER_WAIT DESC LIMIT 30;
