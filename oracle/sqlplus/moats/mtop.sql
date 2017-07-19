/*[[Run MOATS Top command. 
   Reference: https://github.com/dbsid/moats_rac
]]*/
set arrays 80 lines 2000 trims on head off tab off pages 0 verify off
SELECT /*+ no_monitor */* FROM TABLE(moats.top(5));
