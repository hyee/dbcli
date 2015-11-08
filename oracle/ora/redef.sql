/*[[Generate the script for online-redefintion, no DML/DDL will be taken. Usage: redef [owner.]<orig_table_name>[.partition_name] <new_table_name>]]*/
set feed off
ora _find_object &V1
DECLARE
    usr       VARCHAR2(30) := :object_owner;
    org_table VARCHAR2(30) := :object_name;
    part_name VARCHAR2(30) := '';
    new_table VARCHAR2(30) := UPPER('&V2');
    
    v_sql VARCHAR2(32767) := q'{
        DECLARE 
            usr             VARCHAR2(30) := '@user';  --Table owner
            org_table       VARCHAR2(30) := '@org_table'; --Table to be redefined
            new_table       VARCHAR2(30) := '@new_table'; --The interim table
            part_name       VARCHAR2(30) := '@part_name'; --Partition name of org_table
            parallel_degree PLS_INTEGER := 16;
            options_flag    PLS_INTEGER;
            cnt             PLS_INTEGER;
            cols            VARCHAR2(32767):='@cols';--Can be null if all columns are equal
            PROCEDURE pr(p_msg VARCHAR2,p_isshowtime BOOLEAN:=true) IS
            BEGIN --you may use pipelined function instead of dbms_output.put_line
                dbms_output.put_line(CASE WHEN p_isshowtime THEN to_char(systimestamp,'yyyy-mm-dd hh24:mi:ssxff3: ') END||p_msg);
            END;
        BEGIN
            dbms_output.enable(null);
            pr('Removing all constraints from new table...');
            FOR r IN (SELECT constraint_name, constraint_type
                      FROM   all_constraints
                      WHERE  owner = usr
                      AND    table_name = new_table) LOOP
                EXECUTE IMMEDIATE 'alter table ' || usr || '.' || new_table || ' drop constraint "' || r.constraint_name || '"';
            END LOOP;

            pr('Removing all indexes/triggers from new table...');
            FOR r IN (SELECT 'drop index ' typ, owner, index_name
                      FROM   all_indexes
                      WHERE  table_owner = usr
                      AND    table_name = new_table
                      UNION ALL
                      SELECT 'drop trigger ', owner, trigger_name
                      FROM   all_triggers
                      WHERE  table_owner = usr
                      AND    table_name = new_table) LOOP
                EXECUTE IMMEDIATE r.typ || r.owner || '."' || r.index_name || '"';
            END LOOP;

            --Check if can be redef in PK mode
            SELECT COUNT(1)
            INTO   cnt
            FROM   (SELECT index_name, COUNT(DECODE(nullable, 'Y', 1)) cnt
                     FROM   all_ind_columns NATURAL
                     JOIN   all_indexes
                     JOIN   all_tab_cols
                     USING  (table_name, column_name, owner)
                     WHERE  table_owner = usr
                     AND    table_name  = org_table
                     AND    uniqueness  = 'UNIQUE'
                     GROUP  BY index_name)
            WHERE  cnt = 0;

            IF cnt > 0 THEN
                options_flag := sys.dbms_redefinition.cons_use_pk;
                pr('Entering mode: dbms_redefinition.cons_use_pk');
            ELSE
                options_flag := sys.dbms_redefinition.cons_use_rowid;
                pr('Entering mode: dbms_redefinition.cons_use_rowid');
            END IF;
            pr('Verifying the practicability of online redefintion...');
            sys.dbms_redefinition.can_redef_table(usr, org_table, options_flag, part_name);
            pr('Start online redefintion...');
            sys.dbms_redefinition.start_redef_table(uname        => usr,
                                                    orig_table   => org_table,
                                                    int_table    => new_table,
                                                    part_name    => part_name,
                                                    options_flag => options_flag,
                                                    col_mapping  => regexp_replace(cols,'[ '||chr(10)||']'),
                                                    orderby_cols => NULL);
            EXECUTE IMMEDIATE 'alter session force parallel ddl parallel ' || parallel_degree;
            EXECUTE IMMEDIATE 'alter session force parallel dml parallel ' || parallel_degree;
            BEGIN
                sys.dbms_redefinition.copy_table_dependents(usr,org_table,new_table,num_errors => cnt);
                pr('Start sync data...');
                sys.dbms_redefinition.sync_interim_table(usr, org_table, new_table, part_name);
                sys.dbms_redefinition.finish_redef_table(usr, org_table, new_table, part_name);
                pr('Completion of online redefintion.');
            EXCEPTION
                WHEN OTHERS THEN
                    sys.dbms_redefinition.abort_redef_table(usr, org_table, new_table, part_name);
                    RAISE;
            END;
            
            pr('Validating dependencies after online redefintion...');
            FOR r IN (SELECT constraint_name, constraint_type
                      FROM   all_constraints
                      WHERE  owner = usr
                      AND    table_name = org_table
                      AND    validated != 'VALIDATED') LOOP
                BEGIN
                    EXECUTE IMMEDIATE 'alter table '|| usr || '.' || org_table ||' enable validate constraint "' || r.constraint_name || '"';
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END LOOP;
            ---Print dep objects
            pr(RPAD('*',85,'*'),false);
            pr(RPAD('Type',11)||RPAD('Owner',21)||RPAD('Object Name',31)||'Status',false);
            pr(RPAD('-',10,'-')||' '||RPAD('-',20,'-')||' '||RPAD('-',30,'-')||' '||RPAD('-',22,'-'),false);
            FOR r IN(SELECT 'Constraint' TYPE, owner, constraint_name||'('||constraint_type||')' object_name, status || ' ' || validated status
                    FROM   all_constraints
                    WHERE  table_name = org_table
                    AND    owner = usr
                    UNION ALL
                    SELECT 'Index', owner, index_name, status
                    FROM   all_indexes
                    WHERE  table_name = org_table
                    AND    table_owner = usr
                    UNION ALL
                    SELECT 'Trigger', a.owner, trigger_name, b.status||' '||a.status
                    FROM   all_triggers a,all_objects b
                    WHERE  table_name = org_table
                    AND    table_owner = usr
                    AND    a.owner=b.owner
                    AND    a.trigger_name=b.object_name
                    AND    b.object_type='TRIGGER') LOOP
                pr(RPAD(r.type,11)||RPAD(r.Owner,21)||RPAD(r.Object_Name,31)||r.Status,false);    
            END LOOP;
            pr(RPAD('*',85,'*'),false);
            pr('Done.');
        END;}';
    cols  VARCHAR2(32767);
BEGIN
    FOR r IN (SELECT NVL2(b.column_name, b.column_name, 'NULL ' || upper(a.column_name)) col,a.column_id idx
              FROM   all_tab_columns a, all_tab_cols b
              WHERE  a.owner = usr
              AND    b.owner(+) = usr
              AND    a.table_name = new_table
              AND    b.table_name(+) = org_table
              AND    upper(a.column_name) = upper(b.column_name(+))
              ORDER  BY a.column_id) LOOP
        cols := cols || CASE WHEN UPPER(r.col)=r.col THEN r.col ELSE '"'||r.col||'"' END||',';
        IF mod(r.idx,10)=0 THEN
            cols := cols||chr(10)||RPAD(' ', 8);
        END IF;
    END LOOP;

    IF cols IS NULL THEN
        raise_application_error(-20001, 'Cannot find object ' || usr || '.' || new_table || '!');
    ELSE
        cols := trim(',' from trim(cols));
    END IF;

    dbms_output.enable(NULL);
    v_sql := regexp_replace(v_sql, CHR(10) || RPAD(' ', 8), CHR(10));
    v_sql := REPLACE(v_sql, '@user', usr);
    v_sql := REPLACE(v_sql, '@org_table', org_table);
    v_sql := REPLACE(v_sql, '@new_table', new_table);
    v_sql := REPLACE(v_sql, '@part_name', part_name);
    v_sql := REPLACE(v_sql, '@cols', cols);
    dbms_output.put_line(v_sql);
END;
/