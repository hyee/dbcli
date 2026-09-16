/*[[
    Summarize the global resources
    ==============================
    Group the GES resources(gv$ges_resource) by master node and resource type, and show the count
    and the percentage of each group, top 50. Usage: @@NAME

    Notes:
    ------
    - the resource type is taken as the 2 characters following the 3rd '[' of resource_name
    - gv$ges_resource only holds the resources that exist at the moment, so an idle database
      returns no row at all
    - gv$ges_resource(and v$ges_resource) only exists on 12c or above, on 11.2 the query fails
      with ORA-00942
]]*/
SELECT *
FROM   (SELECT master#,
               type,
               sum(cnt) cnt,
               round(100 * ratio_to_report(sum(cnt)) OVER(), 4) pct
        FROM   TABLE(gv$(CURSOR(
                          SELECT substr(resource_name, instr(resource_name, '[', 1, 3) + 1, 2) type,
                                 master_node master#,
                                 count(*) cnt
                          FROM   v$ges_resource
                          GROUP  BY substr(resource_name, instr(resource_name, '[', 1, 3) + 1, 2), master_node)))
        GROUP  BY master#,
               type
        ORDER  BY pct DESC)
WHERE  ROWNUM <= 50
