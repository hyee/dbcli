/*[[
    --[[
        @CHECK_USER_GUASS: gaussdb={1} default={0}
    ]]--
]]*/
VAR C VARCHAR2
DO
$$
DECLARE
    in_schema_name VARCHAR(64) := '&object_owner';
    in_table_name VARCHAR(64)  := '&object_name';
    v_table_ddl text; -- the ddl we're building
    v_table_oid int;  -- data about the target table
    v_column_record record; -- records for looping
    v_constraint_record record;
    v_index_record record;
BEGIN
   
    SELECT c.oid
    INTO   v_table_oid
    FROM   pg_catalog.pg_class c
    LEFT   JOIN pg_catalog.pg_namespace n
    ON     n.oid = c.relnamespace
    WHERE  c.relkind = 'r'
    AND    c.relname = in_table_name 
    AND    n.nspname = in_schema_name;

    -- throw an error if table was not found
    IF (v_table_oid IS NULL) THEN
        RAISE EXCEPTION 'table does not exist';
    END IF;

    IF &CHECK_USER_GUASS=1 THEN
        execute 'select pg_get_tabledef('||v_table_oid||')' INTO v_table_ddl;

    ELSE
        -- start the create definition
        v_table_ddl := 'CREATE TABLE ' || in_schema_name || '.' || in_table_name || ' (' || E'\n';

        -- define all of the columns in the table; https://stackoverflow.com/a/8153081/3068233
        FOR v_column_record IN (SELECT c.column_name, c.data_type, c.character_maximum_length, c.is_nullable, c.column_default
                                FROM   information_schema.columns c
                                WHERE  (table_schema, table_name) = (in_schema_name, in_table_name)
                                ORDER  BY ordinal_position) LOOP
            v_table_ddl := v_table_ddl || '  ' -- note: two char spacer to start, to indent the column
                        || v_column_record.column_name || ' ' || v_column_record.data_type || CASE
                            WHEN v_column_record.character_maximum_length IS NOT NULL THEN
                                ('(' || v_column_record.character_maximum_length || ')')
                            ELSE
                                ''
                        END || ' ' || CASE
                            WHEN v_column_record.is_nullable = 'NO' THEN
                                'NOT NULL'
                            ELSE
                                'NULL'
                        END || CASE
                            WHEN v_column_record.column_default IS NOT NULL THEN
                                (' DEFAULT ' || v_column_record.column_default)
                            ELSE
                                ''
                        END || ',' || E'\n';
        END LOOP;

        FOR v_constraint_record IN (SELECT con.conname AS constraint_name,
                                        con.contype AS constraint_type,
                                        CASE
                                            WHEN con.contype = 'p' THEN
                                                1 -- primary key constraint
                                            WHEN con.contype = 'u' THEN
                                                2 -- unique constraint
                                            WHEN con.contype = 'f' THEN
                                                3 -- foreign key constraint
                                            WHEN con.contype = 'c' THEN
                                                4
                                            ELSE
                                                5
                                        END AS type_rank,
                                        pg_get_constraintdef(con.oid) AS constraint_definition
                                    FROM   pg_catalog.pg_constraint con
                                    JOIN   pg_catalog.pg_class rel
                                    ON     rel.oid = con.conrelid
                                    JOIN   pg_catalog.pg_namespace nsp
                                    ON     nsp.oid = connamespace
                                    WHERE  nsp.nspname = in_schema_name
                                    AND    rel.relname = in_table_name
                                    ORDER  BY type_rank) LOOP
            v_table_ddl := v_table_ddl || '  ' || 'CONSTRAINT' || ' ' || v_constraint_record.constraint_name || --
                        ' ' || v_constraint_record.constraint_definition || ',' || E'\n';
        END LOOP;

        -- drop the last comma before ending the create statement
        v_table_ddl = substr(v_table_ddl, 0, length(v_table_ddl) - 1) || E'\n';

        -- end the create definition
        v_table_ddl := v_table_ddl || ');' || E'\n';

        -- suffix create statement with all of the indexes on the table
        FOR v_index_record IN SELECT indexdef FROM pg_indexes WHERE(schemaname, tablename) = (in_schema_name, in_table_name) LOOP
            v_table_ddl := v_table_ddl || v_index_record.indexdef || ';' || E'\n';
        END LOOP;
    END IF;
    -- return the ddl
    RAISE NOTICE '%',v_table_ddl;
END;
$$;
