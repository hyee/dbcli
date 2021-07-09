sql @info.view.sql

print Indexes and Constraints:
print ========================
SELECT index_schema `Schema`,
       index_name `Index Name`,
       ELT(non_unique,'No','Yes') `Unique`,
       index_type `Index Type`,
       is_visible 'Visible',
       seq_in_index `#`,
       column_name `Field`,
       nullable    `Null`,
       cardinality `Card`,
       packed      `Packed`,
       expression  `Expr`,
       sub_part    `Sub Part`,
       collation   `Collation`,
	   index_comment `Comment`
FROM   information_schema.statistics
WHERE  table_schema=:object_owner
AND    table_name=:object_name
ORDER  BY 1,2,seq_in_index
;SELECT constraint_schema `Schema`,
        constraint_name `Constraint`,
        constraint_type `Type`
        -- ,enforced        `Enforced`
FROM   information_schema.table_constraints
WHERE  table_schema=:object_owner
AND    table_name=:object_name
ORDER  BY 1,2;

COL "Size(Est)" for KMG2
ENV PIVOT 1 PIVOTSORT OFF 
-- SET HEADSTYLE INITCAP

print Table Info:
print ===========
SELECT A.*,(DATA_LENGTH + INDEX_LENGTH) `Size(Est)`
FROM   information_schema.tables A
WHERE  table_schema=:object_owner
AND    table_name=:object_name
;SELECT concat(partition_method, ' (', partition_expression, ')') `Partition By`,
       COUNT(DISTINCT partition_name) `Partitions`,
       concat(subpartition_method, ' (', subpartition_expression, ')') `Subpartition By`,
       COUNT(DISTINCT subpartition_name) `Subpartitions`
FROM   information_schema.partitions
WHERE  table_schema = :object_owner
AND    table_name = :object_name
AND    partition_name IS NOT NULL
GROUP  BY `Partition By`, `Subpartition By`;