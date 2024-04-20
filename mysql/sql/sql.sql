/*[[Show SQL Text. Usage: @@NAME <partial digest>
    --[[
        @ARGS: 1
        @CHECK_ACCESS_TABLE: {
            information_schema.cluster_statements_summary_history={information_schema.cluster_statements_summary_history}
            performance_schema.events_statements_summary_by_digest={performance_schema.events_statements_summary_by_digest}
        }

        @CHECK_ACCESS_PLAN: {
            information_schema.cluster_statements_summary_history={
                SELECT PLAN
                FROM   information_schema.cluster_statements_summary_history
                WHERE  digest=:did
                ORDER  BY summary_end_time DESC LIMIT  1
            }

            default={}
        }
    --]]--
]]*/

ENV COLWRAP 150 FEED OFF

col did new_value did noprint
col "SQL Text with Line Wrap" new_value digest_text noproint

SELECT digest did,digest_text `SQL Text with Line Wrap`
FROM   &CHECK_ACCESS_TABLE
WHERE  digest like concat(:V1,'%')
LIMIT  1;
save digest_text &V1..sql

--col plan new_value plan noprint
&CHECK_ACCESS_PLAN;
--tiplan plan