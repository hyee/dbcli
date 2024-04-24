/*[[Show SQL Text. Usage: @@NAME <partial digest>
    --[[
        @ARGS: 1
        @CHECK_ACCESS_TABLE: {
            information_schema.statements_summary={information_schema.statements_summary}
            performance_schema.events_statements_summary_by_digest={performance_schema.events_statements_summary_by_digest}
        }

        @CHECK_ACCESS_PLAN: {
            information_schema.STATEMENTS_SUMMARY={
                SELECT *
                FROM   information_schema.cluster_statements_summary_history
                WHERE  digest=:did
                ORDER  BY summary_end_time DESC 
                LIMIT  1\G
            }

            default={}
        }
    --]]--
]]*/

ENV COLWRAP 150 AUTOHIDE COL FEED OFF

col did new_value did noprint
col "SQL Text with Line Wrap" new_value digest_text noproint

SELECT digest did,digest_text `SQL Text with Line Wrap`
FROM   &CHECK_ACCESS_TABLE
WHERE  digest like concat(:V1,'%')
LIMIT  1;
save digest_text &V1..sql
ENV COLWRAP 4096
col plan new_value plan noprint
col QUERY_SAMPLE_TEXT,DIGEST_TEXT,BINARY_PLAN noprint
&CHECK_ACCESS_PLAN
--PRINTVAR plan
tiplan plan