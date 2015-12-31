/*[[Show object info for the input block in bh. Usage: @@NAME <file#> <block#>]]*/

SELECT b.*
FROM   gv$bh a, all_objects b
WHERE  rownum < 2
AND    file# = :V1
AND    block# = :V2
AND    objd IN (object_id, data_object_id)
