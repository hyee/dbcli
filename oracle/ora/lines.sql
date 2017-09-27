/*[[Show source text from dba_source with specific line no. Usage: @@NAME {[owner.]<object_name> <line#> [rows] | -t"<keyword>"} [-u] [-f"<filter>"]
    -u           : Based on user_source, default as based on dba_source/all_source
    -t"<keyword>": Search the source contains the <keyword> text
    -f"<filter>" : Custimize the filter predicate
    --[[
        &VW              : default={all_source}, u={user_source}
        &F2              : default={1=1}, f={}
        &OWN             : default={owner=:object_owner and }, u={}
        &F1              : default={name=:object_name and line between trunc(:V2-nvl(:V3,100)/2) and trunc(:V2+nvl(:V3,100)/2)}, t={upper(text) like upper(q'{%&0%}')}
        @CHECK_ACCESS_OBJ: dba_source={dba_source), all_source={&VW}
    --]]
]]*/

ora _find_object &V1
set printsize 10000
select name,type,line,text
from &CHECK_ACCESS_OBJ
where (&F1) AND (&F2)