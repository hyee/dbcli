/*[[Show object info for the input block in bh. Usage: @@NAME <file#> <block#>
    --[[
        @CHECK_ACCESS_SEG: {
            sys.seg$={select HWMINCR objd,file# from sys.seg$ where :V2 between block# and block#-1+blocks},
            default={select objd,file# from gv$bh where block#=:V2}
        }    
        @CHECK_ACCESS_OBJ: dba_objects={dba_objects}, default={all_objects}
    --]]
]]*/

SELECT b.*
FROM   (&CHECK_ACCESS_SEG) a, &CHECK_ACCESS_OBJ b
WHERE  rownum < 2
AND    file# = :V1
AND    objd = data_object_id
