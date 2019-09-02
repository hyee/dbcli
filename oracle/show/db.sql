/*[[Show gv$database in pivot mode]]*/
set pivot 10 feed off
select * from gv$database order by inst_id;

select * from database_properties order by 1;