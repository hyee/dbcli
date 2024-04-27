col sequence_schema,sequence_name noprint
select '&object_fullname'::regclass oid, a.* 
from   information_schema.sequences a
where sequence_schema=:object_owner
and   sequence_name=:object_name\G 