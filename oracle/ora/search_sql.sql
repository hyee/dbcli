/*[[
    Search SQLs by text. Usage: @@NAME <keyword> [-r] [-d|-g|-awr]
    -r  : the keyword is a Regular Expression, otherwise a LIKE expresssion
    -g  : only search gv$* tables
    -d  : only search dba_* tables
    -awr: only search dba_hist* tables

    --[[
        @ARGS: 1
        &vw     : default={'A'} g={'G'} d={'D'} AWR={'AWR'}
        &filter : default={upper(sql_text_) like upper(q'~%&V1%~') or (sql_id=q'~&v1~')} r={regexp_like(sql_text_||SQL_ID,q'~&V1~','in') or (sql_id=q'~&v1~')}
        @CHECK_ACCESS_GV: {
            GV$SQLSTATS_PLAN_HASH={V$SQLSTATS_PLAN_HASH}
            GV$SQLSTATS={V$SQLSTATS_PLAN_HASH}
            GV$SQLAREA_PLAN_HASH={V$SQLAREA_PLAN_HASH}
            GV$SQLAREA={V$SQLAREA}
            GV$SQL={V$SQL}
        }
        @CHECK_ACCESS_AWR: {
            DBA_HIST_SQLTEXT={
                UNION
                SELECT 'DBA_HIST_SQLTEXT',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_ FROM DBA_HIST_SQLTEXT A)
                WHERE  &vw in('A','D','AWR') AND (&filter)
            }
        }

        @CHECK_ACCESS_SPM: {
            DBA_SQL_PLAN_BASELINES={
                UNION
                SELECT 'DBA_SQL_PLAN_BASELINES',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_,PLAN_NAME SQL_ID FROM DBA_SQL_PLAN_BASELINES A)
                WHERE  &vw in('A','D') AND (&filter)
            }
        }

        @CHECK_ACCESS_SQL_PROFILES: {
            DBA_SQL_PROFILES={
                UNION
                SELECT 'DBA_SQL_PROFILES',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_,NAME SQL_ID FROM DBA_SQL_PROFILES A)
                WHERE  &vw in('A','D') AND (&filter)
            }
        }

        @CHECK_ACCESS_SQL_PATCHES: {
            DBA_SQL_PATCHES={
                UNION
                SELECT 'DBA_SQL_PATCHES',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_,NAME SQL_ID FROM DBA_SQL_PATCHES A)
                WHERE  &vw in('A','D') AND (&filter)
            }
        }

        @CHECK_ACCESS_SQL_MONITOR: {
            GV$SQL_MONITOR={
                UNION
                SELECT * FROM TABLE(gv$(CURSOR(
                    SELECT 'GV$SQL_MONITOR',SQL_ID,SQL_TEXT
                    FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_ FROM V$SQL_MONITOR A)
                    WHERE  &vw in('A','G') AND (&filter)
                )))
            }
        }

        @&CHECK_ACCESS_SQLSET_STATEMENTS: {
            ALL_SQLSET_STATEMENTS={
                UNION
                SELECT 'ALL_SQLSET_STATEMENTS',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_ FROM ALL_SQLSET_STATEMENTS A)
                WHERE  &vw in('A','D') AND (&filter)
            }
        }
    --]]
]]*/
SELECT /*+no_expand PQ_CONCURRENT_UNION OPT_PARAM('_fix_control' '26552730:0')*/
       SOURCE,SQL_ID,
       substr(TRIM(regexp_replace(replace(sql_text,chr(0)), '\s+', ' ')), 1, 300) sql_text
FROM (
    SELECT 'G&CHECK_ACCESS_GV' SOURCE, a.*
    FROM   TABLE(gv$(CURSOR(
        SELECT sql_id,
               substr(sql_text,1,1000) sql_text
        FROM   (SELECT a.*, a.SQL_FULLTEXT sql_text_ FROM &CHECK_ACCESS_GV a)
        WHERE  &vw in('A','G') AND (&filter)))) a
    UNION
    SELECT 'ALL_SQLSET_STATEMENTS',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
    FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_ FROM ALL_SQLSET_STATEMENTS A)
    WHERE  &vw in('A','D') AND (&filter)
    &CHECK_ACCESS_AWR
    &CHECK_ACCESS_SPM
    &CHECK_ACCESS_SQL_PROFILES
    &CHECK_ACCESS_SQL_PATCHES
    &CHECK_ACCESS_SQLSET_STATEMENTS
    &CHECK_ACCESS_SQL_MONITOR
)
WHERE instr(lower(sql_text),'sql_text_')=0
AND   ROWNUM<=100
ORDER BY 1,2
