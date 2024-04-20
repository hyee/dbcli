/*[[Show index info
    --[[
        @check_access_size: {
            mysql.innodb_index_stats={
            CASE WHEN seq_in_index=1 THEN (
                SELECT stat_value * @@innodb_page_size
                FROM   mysql.innodb_index_stats iis
                WHERE  stat_name = 'size'
                AND    iis.index_name=i.index_name
                AND    iis.table_name = i.table_name
                AND    iis.database_name = i.index_schema) 
            ELSE '' END `Size`,}
            default={}
        }

        @check_access_ck: {
            information_schema.check_constraints={(select constraint_schema,constraint_name,check_clause from information_schema.check_constraints)}
            default={(SELECT '' constraint_schema,'' constraint_name,'' check_clause)}
        }

        &src1: default={index_} t={table_}
        &src2: default={constraint_} t={table_}
        @check_user_tidb: tidb={} default={--}
        @ver: 8={} default={&check_user_tidb}
    }
    --]]
 ]]*/

COL "Size,DATA_LENGTH,DATA_FREE,INDEX_LENGTH" for KMG2

SELECT CASE WHEN seq_in_index=1 THEN table_name ELSE '' END `Table`,
       CASE WHEN seq_in_index=1 THEN index_schema ELSE '' END `Schema`,
       CASE WHEN seq_in_index=1 THEN index_name ELSE '' END `Index`,
       CASE WHEN seq_in_index=1 THEN ELT(2-non_unique,'No','Yes') ELSE '' END `Unique`,
       CASE WHEN seq_in_index=1 THEN index_type ELSE '' END `Index Type`,
       &ver.is_visible 'Visible', 
       &check_access_size
       seq_in_index `#`,
       column_name `Field`,
       nullable    `Null`,
       cardinality `Card`,
       packed      `Packed`,
       &ver.expression  `Expr`,
       sub_part    `Sub Part`,
       collation   `Collation`,
       index_comment `Comment` 
FROM   information_schema.statistics i
WHERE  &src1.schema=:object_owner
AND    &src1.name=:object_name
ORDER  BY lower(table_name),lower(index_name),seq_in_index
;SELECT DISTINCT
        constraint_schema `Schema`,
        constraint_name `Constraint`,
        constraint_type `Type`,
        columns,
        IFNULL(COALESCE(REPLACE(ck.check_clause,'\\''',''''),us.refs),'') `References`,
        IFNULL(rf.unique_constraint_name,'') `Ref Constraint`,
        IFNULL(rf.update_rule,'') 'On Update',
        IFNULL(rf.delete_rule,'') 'On Delete',
        IFNULL(rf.match_option,'') match_option
FROM   information_schema.table_constraints tc
LEFT  OUTER JOIN &check_access_ck ck USING (constraint_schema,constraint_name)
LEFT  OUTER JOIN information_schema.referential_constraints rf USING (constraint_schema,constraint_name,table_name)
LEFT  OUTER JOIN (
    SELECT  constraint_schema,
            constraint_name,
            table_name,
            concat('(',group_concat(column_name ORDER BY ordinal_position SEPARATOR ', '),')') columns,
            concat(max(referenced_table_name),'(',group_concat(referenced_column_name ORDER BY ordinal_position SEPARATOR ', '),')') REFS
    FROM    information_schema.key_column_usage
    GROUP   BY constraint_schema,constraint_name,table_name) us
USING  (constraint_schema,constraint_name,table_name)
WHERE  &src2.schema=:object_owner
AND    &src2.name =:object_name
AND    constraint_name!='PRIMARY'
ORDER  BY 1,2;