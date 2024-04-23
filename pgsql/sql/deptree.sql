/*[[
    Show dependency tree of the input object: Usage: @@NAME [<owner>.]<name> [<max_depth>] [-d]
    
    <max_depth>: default 10
    -d         : find its depending objects instead of the objects depending on it

    Example:
    =========
    SQL> pg deptree emailaddress
    depth  oid  tree                                                                                      deptype
    ----- ----- ----------------------------------------------------------------------------------------- --------
        0 16497 table "person"."emailaddress"
        1 18014   constraint FK_EmailAddress_Person_BusinessEntityID on table person.emailaddress         AUTO
        1 17494   constraint PK_EmailAddress_BusinessEntityID_EmailAddressID on table person.emailaddress AUTO
        2 17493     index person."PK_EmailAddress_BusinessEntityID_EmailAddressID"                        INTERNAL
        1 18989   constraint uk_emailaddress on table person.emailaddress                                 AUTO
        2 18988     index person.uk_emailaddress                                                          INTERNAL
        1 16501   default for table person.emailaddress column rowguid                                    AUTO
        1 18990   index person.ux_emailaddress                                                            AUTO
        1 16495   sequence person.emailaddress_emailaddressid_seq                                         AUTO
        2 19015     default for table person.emailaddress1 column emailaddressid                          NORMAL
        2 16496     type person.emailaddress_emailaddressid_seq                                           INTERNAL
        1 16499   type person.emailaddress                                                                INTERNAL
        2 16498     type person.emailaddress[]                                                            INTERNAL

    --[[
        @ARGS: 1
        &p1: c={ref} d={}
        &p2: c={} d={ref}
    --]]
]]*/

findobj "&1" 0 1

WITH RECURSIVE tree AS
 (SELECT lower('&object_type')||' &object_fullname' AS tree,
         0 AS depth,
         '&object_class'::regclass AS classid,
         &object_id::integer AS oid,
         0 AS objsubid,
         ' ' ::"char" AS deptype,
         ''::text as "chain"
   UNION ALL
 SELECT DISTINCT * FROM (
    SELECT LPAD(' ',2*(depth+1))|| rtrim(pg_describe_object(d.classid, d.objid, d.objsubid)) tree,
            depth + 1 depth,
            d.&p2.classid::regclass classid,
            d.&p2.objid::integer oid,
            d.&p2.objsubid objsubid,
            d.deptype deptype,
            "chain"||'->'||rtrim(pg_describe_object(d.classid, d.objid, d.objsubid))
    FROM   tree
    JOIN   pg_depend d
    ON     tree.classid = d.&p1.classid
    AND    tree.oid = d.&p1.objid
    AND    tree.objsubid IN (d.&p1.objsubid, 0)
    WHERE  depth<coalesce(nullif('&V2',''),'10')::integer
    AND    pg_describe_object(d.&p2.classid, d.&p2.objid, d.&p2.objsubid) NOT LIKE 'rule _RETURN%') s
  WHERE tree NOT LIKE 'rule _RETURN%' AND (ltrim(tree) not like 'trigger %' or deptype != 'i')
 )
SELECT depth,
       oid,
       tree.tree, 
       case tree.deptype when 'n' then 'NORMAL' when 'a' then 'AUTO' when 'p' then 'PIN' when 'i' then 'INTERNAL' end deptype
       --,chain 
FROM tree
ORDER  by "chain";
