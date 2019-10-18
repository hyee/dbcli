/*[[
	List cell parameters based on external table EXA$CELLPARAMS. Usage: @@NAME [<keywords>]
	This script relies on external table EXA$CACHED_OBJECTS which is created by shell script "oracle/shell/create_exa_external_tables.sh" with the oracle user
	--[[
      @check_access_obj: EXA$CELLPARAMS_AGG={}
    --]]
]]*/
set printsize 3000
SELECT * 
FROM  EXA$CELLPARAMS_AGG
WHERE lower(name) like lower('%&V1%')
AND   lower(name) like lower('%&V2%')
AND   lower(name) like lower('%&V3%')
AND   lower(name) like lower('%&V4%')
AND   lower(name) like lower('%&V5%')
ORDER BY 1,2,3,4;
