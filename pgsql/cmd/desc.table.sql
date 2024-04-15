/*[[Show table info
    --[[
        @CHECK_USER_TIDB: tidb={LEFT JOIN information_schema.table_storage_stats USING(table_schema,table_name)} default={}
    --]]
]]*/

sql @desc.view.sql

echo Indexes and Constraints:
echo ========================
sql @desc.index.sql

ENV PIVOT 1 PIVOTSORT OFF

echo Table and Partition Info:
echo =========================
SELECT * FROM information_schema.tables WHERE table_schema=:object_owner and table_name=:object_name