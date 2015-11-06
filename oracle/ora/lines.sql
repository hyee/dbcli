/*[[Show source text from dba_source with specific line no. Usage: lines [owner.]<object_name> <line#> [rows]
    --[[
        @CHECK_ACCESS_OBJ: dba_source={dba_source), all_source={all_source}
    --]]
]]*/

ora _find_object &V1
set printsize 10000
select type,line,text from &CHECK_ACCESS_OBJ
where owner=:object_owner and name=:object_name and line between trunc(:V2-nvl(:V3,100)/2) and trunc(:V2+nvl(:V3,100)/2)