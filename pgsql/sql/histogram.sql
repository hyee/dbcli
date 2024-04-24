/*[[
    Show table column histogram stats. Usage: @@NAME [schema.]<table> <column>
    Refer to https://www.postgresql.org/docs/current/view-pg-stats.html
    --[[
        @ARGS: 2
    --]]
]]*/
findobj "&V1" 0 1
env feed off
col nulls,ndv,rows for tmb2
col nulls%,ndv%,common_freq,elem_freqs,correlation for pct3

SELECT row_number() over() "#",
       h.*
FROM   pg_stats s, 
       rows FROM   
           (unnest(most_common_vals::text::text[]), 
            unnest(most_common_freqs), 
            unnest(histogram_bounds::text::text[]),
            unnest(most_common_elems ::text::text[]), 
            unnest(most_common_elem_freqs), 
            unnest(elem_count_histogram)) h(common_val, common_freq,"histogram",common_elems,elem_freqs,elem_histogram)
WHERE  s.attname = :v2
AND    s.schemaname=:object_owner
AND    s.tablename =:object_name;

SELECT row_number() over() "#",
       h.*
FROM   pg_stats s, 
       rows FROM   
           (unnest(most_common_vals::text::text[]), 
            unnest(most_common_freqs), 
            unnest(histogram_bounds::text::text[]),
            unnest(most_common_elems ::text::text[]), 
            unnest(most_common_elem_freqs), 
            unnest(elem_count_histogram)) h(common_val, common_freq,"histogram",common_elems,elem_freqs,elem_histogram)
WHERE  s.attname = :v2
AND    s.schemaname=:object_owner
AND    s.tablename =:object_name;

SELECT s.avg_width, 
       t.reltuples "rows",
       s.null_frac "nulls", 
       s.null_frac/nullif(t.reltuples,0) "nulls%",
       case when n_distinct<0 then t.reltuples*abs(n_distinct) else n_distinct end NDV,
       case when n_distinct<0 then abs(n_distinct) else n_distinct/nullif(t.reltuples,0) end "NDV%",
       s.correlation
FROM   pg_class t,
       pg_stats s
WHERE  s.attname = :v2
AND    s.schemaname=:object_owner
AND    s.tablename =:object_name
AND    t.oid='&object_fullname'::regclass;