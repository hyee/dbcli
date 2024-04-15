/*[[Show available roles/users.
    --[[
        @ALIAS: users
        @CHECK_USER_GAUSS: {
            gaussdb={
                    CASE
                        WHEN rolcatupdate THEN
                         'CAT-UPDATE,'
                    END,
                    CASE
                        WHEN rolauditadmin THEN
                         'AUDITADMIN,'
                    END,
                    CASE
                        WHEN roluseft THEN
                         'USE-FT,'
                    END,
                    CASE
                        WHEN rolmonitoradmin THEN
                         'MONADMIN,'
                    END,
                    CASE
                        WHEN rolsystemadmin THEN
                         'SYSADMIN,'
                    END,
                    CASE
                        WHEN roloperatoradmin THEN
                         'OPRADMIN,'
                    END,
                    CASE
                        WHEN rolpolicyadmin THEN
                         'POLADMIN,'
                    END,
            }
            default={}
        }
    --]]

]]*/

SELECT r.rolname AS role_name,
       RTRIM(CONCAT(CASE
                        WHEN rolcanlogin THEN
                         'LOGIN,'
                    END,
                    CASE
                        WHEN rolsuper THEN
                         'SUPER,'
                    END,
                    CASE
                        WHEN not rolinherit THEN
                         'DISINHERIT,'
                    END,
                    CASE
                        WHEN rolcreaterole THEN
                         'CREATEROLE,'
                    END,
                    CASE
                        WHEN rolcreatedb THEN
                         'CREATEDB,'
                    END,
                    CASE
                        WHEN rolreplication THEN
                         'REPLI,'
                    END,
                    &CHECK_USER_GAUSS
                    ''),
             ',') attrs,
       r.rolconnlimit AS max_connections,
       r.rolvaliduntil AS expiration_date,
       ARRAY (SELECT b.rolname FROM pg_auth_members m JOIN pg_roles b ON (m.member = b.oid) WHERE m.roleid = r.oid) AS member_of,
       ARRAY (SELECT b.rolname FROM pg_auth_members m JOIN pg_roles b ON (m.roleid = b.oid) WHERE m.member = r.oid) AS has_members,
       pg_catalog.shobj_description(r.oid, 'pg_authid') AS description
FROM   pg_roles r
ORDER  BY rolcanlogin, r.rolname
