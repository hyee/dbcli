/*[[
    show flashcache based on EXA$FLASHCACHE. Usage: @@NAME [<cell>]
    To run this script, please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
  --[[
      @check_access_obj: EXA$FLASHCACHE={}
  --]]
]]*/
col size,effectiveCacheSize for kmg
SELECT CELLNODE,"status","size","effectiveCacheSize","degradedCelldisks",name,"id","cellDisk","creationTime"
FROM   EXA$FLASHCACHE
WHERE  NVL(:V1,' ') IN (' ',cellnode)
ORDER BY 1,2;
