/*[[Show db parameters info: ora param [<keyword1>[,<keyword2>...]]]]*/

select NAME,substr(DISPLAY_VALUE,1,90) value,isdefault,isses_modifiable,issys_modifiable,DESCRIPTION
from v$parameter 
WHERE (
      :V1 is NOT NULL and (NAME LIKE LOWER('%'||:V1||'%') OR lower(DESCRIPTION) LIKE LOWER('%'||:V1||'%'))  OR 
      :V2 IS NOT NULL and (NAME LIKE LOWER('%'||:V2||'%') OR lower(DESCRIPTION) LIKE LOWER('%'||:V2||'%'))  OR
      :V3 IS NOT NULL and (NAME LIKE LOWER('%'||:V3||'%') OR lower(DESCRIPTION) LIKE LOWER('%'||:V3||'%'))  OR
      :V4 IS NOT NULL and (NAME LIKE LOWER('%'||:V4||'%') OR lower(DESCRIPTION) LIKE LOWER('%'||:V4||'%'))  OR
      :V5 IS NOT NULL and (NAME LIKE LOWER('%'||:V5||'%') OR lower(DESCRIPTION) LIKE LOWER('%'||:V5||'%'))) 
OR   (:V1 IS NULL and isdefault='FALSE')
order by 1