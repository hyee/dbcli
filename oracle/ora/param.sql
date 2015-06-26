/*[[Show db parameters info: ora param [<name>]]]*/

select NAME,substr(DISPLAY_VALUE,1,90) value,isdefault,isses_modifiable,issys_modifiable,DESCRIPTION 
from v$parameter WHERE (:V1 is not null and NAME LIKE LOWER('%'||:V1||'%')) or (:V1 is null and isdefault='FALSE')
order by 1