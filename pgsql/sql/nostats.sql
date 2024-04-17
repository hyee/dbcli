/*[[Find columns that have no statistics. Usage: @@NAME [-k"<keyword>"]|[-f"<filter>"]
Ref: https://github.com/pgexperts/pgx_scripts/blob/master/vacuum/no_stats_table_check.sql
--[[
    &filter: dft={table_schema NOT IN ('pg_catalog', 'information_schema')} k={lower(concat(table_schema,'.',table_name,'.',column_name)) LIKE lower('%&0%')} f={}
--]]
]]*/
SELECT table_schema, table_name,
    ( pg_class.relpages = 0 ) AS is_empty,
    coalesce(psut.last_analyze,psut.last_autoanalyze) last_analyzed,
    array_agg(column_name::TEXT) as no_stats_columns
FROM information_schema.columns
    JOIN pg_class ON columns.table_name = pg_class.relname
        AND pg_class.relkind = 'r'
    JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
        AND nspname = table_schema
    LEFT OUTER JOIN pg_stats
    ON table_schema = pg_stats.schemaname
        AND table_name = pg_stats.tablename
        AND column_name = pg_stats.attname
    LEFT OUTER JOIN pg_stat_user_tables AS psut
        ON table_schema = psut.schemaname
        AND table_name = psut.relname
WHERE pg_stats.attname IS NULL
AND   (&filter)
GROUP BY table_schema, table_name, relpages, psut.relname, last_analyze, last_autoanalyze
ORDER BY table_schema, table_name
;