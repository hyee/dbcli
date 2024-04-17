
db.C.sql:run_script('@'..file:gsub('table.lua$','view.sql'))
local index=obj.redirect("index")
index=index:gsub('isp.nspname=','/*TOPIC=Indexes*/ nsp.nspname='):gsub('idx.relname=','tbl.relname=')

db.C.sql:run_script("bloats",obj.object_fullname)

return {index,[[
    SELECT /*TOPIC=Constraints*/ conname "constraint_name",pg_get_constraintdef(c.oid) AS constraint_def
    FROM pg_constraint c
    WHERE conrelid = :object_fullname::regclass]],
[[SELECT /*TOPIC=Table Attributes*//*PIVOT*/ * FROM information_schema.tables WHERE table_schema=:object_owner and table_name=:object_name]]}