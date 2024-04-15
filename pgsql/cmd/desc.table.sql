/*[[Show table info
    --[[
        
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