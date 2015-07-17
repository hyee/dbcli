select partition_name,c.* from user_tab_partitions ,contexts c where table_name=upper(:V1) and PARTITION_POSITION=:V2
and substr(partition_name,2) in(pk_ws,pk_rd,pk_rd_ws)