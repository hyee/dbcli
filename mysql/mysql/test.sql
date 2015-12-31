
select * from information_schema.tables where table_name like concat('%',@V1,'%');