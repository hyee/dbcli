env.var.define_column("Size","for","KMG2")
db.C.sql:run_script('@'..file:gsub('table.lua$','view.sql'))

if obj.object_type=='PARTITIONED TABLE' then
    env.print('Partition Info:\n===============')
    db:query([[
        select pg_get_partkeydef(:object_id::bigint) partition_by,
               count(1) "partitions", 
               sum(pg_relation_size(('"&object_owner"."'||relid||'"')::regclass)) "size"
         from  pg_partition_tree(:object_id::bigint) 
         where level>0
    ]],obj)
elseif obj.object_type=='TABLE' then
    local rows=db.resultset:rows(db:internal_call([[
        SELECT COUNT(1) inherited_tables,
               sum(pg_relation_size(inhrelid)) "size"
        FROM   pg_inherits
        WHERE  inhparent=:object_id::bigint
        HAVING count(1)>0]]))
    if #rows>1 then
        env.grid.print(rows,true,nil,nil,nil,'Inherit Info:\n============','\n')
    elseif db.props.gaussdb then
        local rows=db.resultset:rows(db:internal_call([[
        select CASE  p.partstrategy 
                WHEN 'r' THEN 'RANGE'
                WHEN 'v' THEN 'NUMERIC'
                WHEN 'i' THEN 'INTERVAL'
                WHEN 'l' THEN 'LIST'
                WHEN 'h' THEN 'HASH'
                WHEN 'n' THEN 'INVALID'
            END partition_type,
            count(distinct p.relname) "partitions",
            sum(pg_partition_size(:object_id::bigint,p.oid)) "size",
            CASE s.partstrategy
                WHEN 'r' THEN 'RANGE'
                WHEN 'v' THEN 'NUMERIC'
                WHEN 'i' THEN 'INTERVAL'
                WHEN 'l' THEN 'LIST'
                WHEN 'h' THEN 'HASH'
                WHEN 'n' THEN 'INVALID'
            END subpartition_type,
            nullif(count(distinct s.relname),0) "subpartitions"
        from pg_partition p
        LEFT JOIN pg_partition s
        ON  s.parentid=p.oid 
        AND s.parttype='s'
        WHERE p.parentid=:object_id::bigint
        AND   p.parttype='p'
        group by  partition_type,subpartition_type
        having count(1)>0]],obj))
        if #rows>1 then
            env.grid.print(rows,true,nil,nil,nil,'Partition Info:\n===============','\n')
        end
    end 
end

local index=obj.redirect("index")
index=index:gsub('isp.nspname=','/*TOPIC=Indexes*/ nsp.nspname='):gsub('idx.relname=','tbl.relname=')

db.C.sql:run_script("bloats",obj.object_fullname,'-table')

return {index,
[[SELECT /*TOPIC=Constraints*/ conname "constraint_name",pg_get_constraintdef(c.oid) AS constraint_def
  FROM pg_constraint c
  WHERE conrelid = :object_fullname::regclass]],
[[SELECT /*TOPIC=Table Attributes*//*PIVOT*/ * 
  FROM information_schema.tables 
  WHERE table_schema=:object_owner 
  and table_name=:object_name]]}