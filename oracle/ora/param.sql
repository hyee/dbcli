/*[[Show db parameters info, pls use 'set instance' to show the specific instance. Usage: @@NAME [<keyword1>[,<keyword2>...]]
   --[[
      @ctn: 12={ISPDB_MODIFIABLE,}, default={}
   --]]
]]*/
set printsize 999
select inst_id,NAME,substr(DISPLAY_VALUE,1,90) value,
       isdefault,
       isses_modifiable,issys_modifiable,&CTN DESCRIPTION
from (select a.*,upper(b.instance_name) sid from gv$parameter a, gv$instance b where a.inst_id=b.inst_id and a.inst_id=nvl(:instance,userenv('instance'))) a
WHERE ((
      :V1 is NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V1||'%')  OR 
      :V2 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V2||'%')  OR
      :V3 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V3||'%')  OR
      :V4 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V4||'%')  OR
      :V5 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V5||'%')) 
  OR (:V1 IS NULL and isdefault='FALSE'))
order by name