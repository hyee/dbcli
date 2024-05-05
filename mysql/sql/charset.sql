/*[[Show db character sets & collations. Usage: @@NAME [<keyword>]
]]*/


ECHO 
ECHO COLLATIONS:
ECHO ===========
select a.*,case when b.collation_name is null then 'no' else 'yes' end `Applicable`
from   information_schema.collations as a
left outer join information_schema.collation_character_set_applicability as b
on     a.collation_name=b.collation_name and a.character_set_name=b.character_set_name
where  lower(a.collation_name) like lower('%&v1%') 
ORDER  BY 1 limit 100;


ECHO 
ECHO CHARACTER_SETS:
ECHO ===============
SELECT * 
FROM information_schema.character_sets 
where lower(character_set_name) like lower('%&v1%') 
ORDER  BY 1 limit 100;