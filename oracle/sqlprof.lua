local db,cfg=env.getdb(),env.set
local sqlprof={}
function sqlprof.extract_profile(sql_id,sql_plan,sql_text)
    local stmt=[[
    DECLARE
        v_SQL CLOB:=:1;
        FUNCTION extract_profile(p_buffer     OUT CLOB,
                                 p_sqlid      VARCHAR2,
                                 p_plan       VARCHAR2 := NULL,
                                 p_dbid       INT := NULL,
                                 p_forcematch BOOLEAN := true) 
        RETURN VARCHAR2 IS
            /*
            To generate the script to fix the execution plan with SQL profile
            Parameters:
              p_sqlid: The target SQL to be fixed, can be SQL_ID/SQL Profile name/SPM plan name
              p_plan:  The exec plan to be used, can be:
                          a.Plan_hash_value of target SQL, when null then use the default plan
                          b.Another optimized SQL's sql id/SQL Profile name/SPM plan name
                       For the "b" option, the 2 SQLs have be of the same text except hints
            Examples:
               1) Extract profile from specifc execution plan:
                  exec extract_profile('dc5n1gqgfq09h',3273999458);
               2) Extract profile from another optimized sql as the replacement of target SQL:
                  exec extract_profile('dc5n1gqgfq09h','dc5n1gqgfq09s');
               3) Extract profile from SPM for target SQL:
                  exec extract_profile('SQL_PLAN_004szdq6gtbrtc3254462');
               4) Extract profile from SPM of another optimized SQL to target sql:
                  exec extract_profile('dc5n1gqgfq09h','SQL_PLAN_004szdq6gtbrtc3254462');
               4) Extract profile from plan_table, make sure there is only one statement in the plan table:
                  exec extract_profile('dc5n1gqgfq09h','plan');
            */
            v_signature   INT;
            v_source      VARCHAR2(128);
            v_flag        PLS_INTEGER := CASE WHEN upper(p_plan) IN('PLAN','PLAN_TABLE') THEN 0 WHEN nullif(p_plan,p_sqlid) IS NULL THEN 1 ELSE 2 END;
            v_plan        INT;
            v_dbid        INT := p_dbid;
            v_sql_id      VARCHAR2(30);
            v_plan_source VARCHAR2(128);
            v_hints       xmltype;
            v_hints2      xmltype;
            v_hint        VARCHAR2(32767);
            v_text        CLOB;
            v_newSQL      CLOB;
            v_pos         PLS_INTEGER;
            v_embed       VARCHAR2(200);
            v_schema      VARCHAR2(60):='<unknown>';
            
            PROCEDURE get_sql(p_sqlid VARCHAR2,pos PLS_INTEGER:=1) IS
                phv INT := nullif(regexp_substr(p_plan,'^\d+$'),0);
            BEGIN
                v_sql_id := p_sqlid;
                SELECT /*+PQ_CONCURRENT_UNION OPT_PARAM('_fix_control' '26552730:0') DYNAMIC_SAMPLING(0)*/ 
                       sql_text, src
                INTO   v_sql, v_source
                FROM   (
                        --awr and sqlset
                        SELECT SQL_TEXT,  v_sql_id src
                        FROM   dba_hist_sqltext a
                        WHERE  sql_id = v_sql_id
                        UNION ALL
                        SELECT SQL_FULLTEXT, v_sql_id
                        FROM   gv$sql a
                        WHERE  sql_id = v_sql_id
                        UNION ALL
                        SELECT SQL_TEXT, v_sql_id
                        FROM   all_sqlset_statements a
                        WHERE  sql_id = v_sql_id
                    $IF DBMS_DB_VERSION.VERSION>11 $THEN
                        UNION ALL
                        SELECT TO_CLOB(SQL_TEXT), v_sql_id
                        FROM   gv$sql_monitor a
                        WHERE  IS_FULL_SQLTEXT='Y'
                        AND    sql_text IS NOT NULL
                        AND    sql_id = v_sql_id 
                        AND    rownum<2
                    $END
                    $IF 1=1 AND DBMS_DB_VERSION.VERSION>10  $THEN
                        UNION ALL
                        SELECT SQL_TEXT,
                               decode(b.obj_type, 1, v_sql_id, 2,  substr(v_sql_id, -26)) src
                        FROM   sys.sqlobj$ b, sys.sql$text a
                        WHERE  v_sql_id in(b.name,a.sql_handle)
                        AND    b.signature = a.signature
                    $ELSE
                        UNION ALL
                        SELECT SQL_TEXT, v_sql_id src
                        FROM   sys.sqlprof$ b, sys.sql$text a
                        WHERE  b.sp_name = v_sql_id
                        AND    b.signature = a.signature
                    $END)
                WHERE  rownum < 2;
                
                IF pos=1 AND v_plan IS NULL THEN
                    SELECT /*+OPT_PARAM('_fix_control' '26552730:0') DYNAMIC_SAMPLING(0)*/ 
                           max(schema_name),
                           max(nullif(p,0)),
                           max(src)
                    INTO v_schema,v_plan,v_plan_source
                    FROM (
                        SELECT * FROM (
                            SELECT PARSING_SCHEMA_NAME schema_name,'SQL' src,plan_hash_value p,last_active_time last_active
                            FROM   GV$SQL
                            WHERE  sql_id=v_sql_id
                            AND    plan_hash_value>0
                            UNION ALL
                            SELECT MAX(PARSING_SCHEMA_NAME) OVER(),'AWR',plan_hash_value,nvl(c.end_interval_time+0,a.timestamp)
                            FROM   DBA_HIST_SQL_PLAN A
                            LEFT   JOIN DBA_HIST_SQLSTAT B USING(DBID,SQL_ID,PLAN_HASH_VALUE)
                            LEFT   JOIN DBA_HIST_SNAPSHOT C USING(DBID,INSTANCE_NUMBER,SNAP_ID) 
                            WHERE  SQL_ID=v_sql_id
                            AND    DBID=v_dbid
                            UNION ALL
                            SELECT PARSING_SCHEMA_NAME,'SQLSET',plan_hash_value,plan_timestamp
                            FROM   all_sqlset_statements
                            WHERE  sql_id=v_sql_id
                            AND    plan_hash_value>0
                        $IF DBMS_DB_VERSION.VERSION>11  $THEN
                            UNION ALL
                            SELECT USERNAME,'MON',sql_plan_hash_value,LAST_REFRESH_TIME
                            FROM   GV$SQL_MONITOR 
                            WHERE  sql_id=v_sql_id
                            AND    sql_plan_hash_value>0
                            AND    username is not null
                        $END
                        ) 
                        ORDER BY DECODE(p,phv,1,2),last_active desc
                    ) WHERE ROWNUM<2;
                    
                    IF v_plan IS NOT NULL AND ''||v_plan=p_plan THEN
                        v_flag := 1;
                    END IF;
                END IF;
            EXCEPTION
                WHEN no_data_found THEN
                    IF pos=1 THEN
                        raise_application_error(-20001, 'Cannot find SQL text of '||v_sql_id);
                    END IF;
            END;

            PROCEDURE get_plan(p_sql_id varchar2) IS
                qid    VARCHAR2(128):=CASE WHEN v_flag=1 THEN v_sql_id ELSE p_sql_id END;
                phv    INT := nvl(regexp_substr(qid, '^\d+$'),v_plan);
            BEGIN
                --dbms_output.put_line(v_flag||','||v_plan||','||phv||','||qid);
                SELECT /*+PQ_CONCURRENT_UNION OPT_PARAM('_fix_control' '26552730:0') DYNAMIC_SAMPLING(0)*/ 
                       xmltype(other_xml), src, p
                INTO   v_hints, v_plan_source, v_plan
                FROM   (SELECT other_xml, 'GV$SQL_PLAN' src, plan_hash_value p
                        FROM   gv$sql_plan a
                        WHERE  v_flag = 1
                        AND    v_plan_source='SQL'
                        AND    sql_id = qid 
                        AND    plan_hash_value=phv
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                        UNION ALL
                        SELECT other_xml, 'GV$SQL_PLAN' src, plan_hash_value phv
                        FROM   gv$sql_plan a
                        WHERE  v_flag = 2
                        AND    qid IN(sql_id,''||plan_hash_value)
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                        UNION ALL
                        SELECT other_xml, 'PLAN_TABLE' src, -1
                        FROM   plan_table a
                        WHERE  (v_flag=0 AND plan_id=(select max(plan_id) keep(dense_rank last order by timestamp) from PLAN_TABLE)
                                  OR 
                                v_flag=2 AND UPPER(qid) IN(''||plan_id,upper(statement_id))) 
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                        UNION ALL
                        SELECT other_xml, 'DBA_HIST_SQL_PLAN' src, plan_hash_value
                        FROM   dba_hist_sql_plan a
                        WHERE  v_flag = 1
                        AND    v_plan_source='AWR'
                        AND    sql_id = qid 
                        AND    plan_hash_value=phv
                        AND    dbid=v_dbid
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                        UNION ALL
                        SELECT other_xml, 'DBA_HIST_SQL_PLAN' src, plan_hash_value
                        FROM   dba_hist_sql_plan a
                        WHERE  v_flag = 2
                        AND    qid IN(sql_id,''||plan_hash_value)
                        AND    dbid=v_dbid
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                        UNION ALL
                        SELECT other_xml, 'ALL_SQLSET_PLANS', plan_hash_value
                        FROM   all_sqlset_plans a
                        WHERE  v_flag = 1
                        AND    v_plan_source='SQLSET'
                        AND    sql_id = qid 
                        AND    plan_hash_value=phv
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                        UNION ALL
                        SELECT other_xml, 'ALL_SQLSET_PLANS', plan_hash_value
                        FROM   all_sqlset_plans a
                        WHERE  v_flag = 2
                        AND    qid IN(sql_id,''||plan_hash_value)
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                    $IF DBMS_DB_VERSION.VERSION>11 $THEN
                        UNION ALL
                        SELECT other_xml, 'GV$SQL_PLAN_MONITOR', SQL_PLAN_HASH_VALUE
                        FROM   gv$sql_plan_monitor a
                        WHERE  v_flag = 1
                        AND    v_plan_source='MON'
                        AND    sql_id = qid 
                        AND    sql_plan_hash_value=phv
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                        UNION ALL
                        SELECT other_xml, 'GV$SQL_PLAN_MONITOR', SQL_PLAN_HASH_VALUE
                        FROM   gv$sql_plan_monitor a
                        WHERE  v_flag = 2
                        AND    qid IN(sql_id,''||sql_plan_hash_value)
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                    $END
                    $IF DBMS_DB_VERSION.VERSION>10 $THEN
                        UNION ALL
                        SELECT other_xml, 'DBA_ADVISOR_SQLPLANS', plan_hash_value
                        FROM   dba_advisor_sqlplans a
                        WHERE  v_flag > 0
                        AND    qid IN(sql_id,''||plan_hash_value)
                        AND    other_xml IS NOT NULL
                        AND    rownum<2
                    $END
                    $IF 1=1 AND DBMS_DB_VERSION.VERSION>11 $THEN
                        UNION ALL
                        SELECT other_xml, 'SPM' src,null
                        FROM   sys.sqlobj$ b, sys.sqlobj$plan a
                        WHERE  v_flag > 0
                        AND    v_plan_source IS NULL
                        AND    b.name = qid
                        AND    b.signature = a.signature
                        AND    other_xml IS NOT NULL
                        AND    rownum < 2
                    $END
                    $IF 1=1 AND DBMS_DB_VERSION.VERSION>10 $THEN
                        UNION ALL
                        SELECT comp_data, decode(b.obj_type, 1, 'SQL Profile', 'SPM') src,null
                        FROM   sys.sqlobj$ b, sys.sqlobj$data a
                        WHERE  v_flag > 0
                        AND    v_plan_source IS NULL
                        AND    b.name = qid
                        AND    b.signature = a.signature
                        AND    comp_data is not null
                        AND    rownum < 2
                    $ELSE
                        UNION ALL
                        SELECT Xmlelement("outline_data", xmlagg(Xmlelement("hint", attr_val) ORDER BY attr#)).getclobval() comp_data,
                               'SQL Profile' src,
                               null
                        FROM   sys.sqlprof$ b, sys.sqlprof$attr a
                        WHERE  v_flag > 0
                        AND    v_plan_source IS NULL
                        AND    b.sp_name = qid
                        AND    b.signature = a.signature
                        AND    rownum < 2
                    $END)
                WHERE  rownum < 2;
            EXCEPTION
                WHEN no_data_found THEN
                    raise_application_error(-20001, 'Cannot find outlines for the execution plan of '||qid);
            END;

            PROCEDURE pr(p_text VARCHAR2, flag BOOLEAN DEFAULT TRUE) IS
            BEGIN
                IF flag THEN
                    dbms_lob.writeappend(v_text, length(p_text) + 1, p_text || chr(10));
                ELSE
                    dbms_lob.writeappend(v_text, length(p_text), p_text);
                END IF;
            END;

            PROCEDURE writeSQL(p_SQL CLOB,p_name VARCHAR2) IS
                v_begin VARCHAR2(10):='q''[';
                v_end   VARCHAR2(10):=']''';
                v_size  PLS_INTEGER := length(p_SQL);
            BEGIN
                IF instr(p_SQL,'~')=0 THEN
                    v_begin := 'q''~';
                    v_end   := '~''';
                ELSIF instr(p_SQL,'!')=0 THEN
                    v_begin := 'q''!';
                    v_end   := '!''';
                ELSIF instr(p_SQL,']')>0 THEN
                    v_begin := 'q''{';
                    v_end   := '}''';
                END IF;
                IF (v_size <= 1200 OR dbms_lob.instr(p_SQL, CHR(10)) > 0 OR p_name != 'sql_txt') AND v_size<=24000 THEN
                    pr('        '||p_name||' := '||v_begin, FALSE);
                    dbms_lob.append(v_text, replace(p_SQL,chr(0),'@chr(0)@'));
                    pr(v_end||';');
                ELSE
                    pr('        dbms_lob.createtemporary(sql_txt, TRUE);');
                    v_pos := 0;
                    WHILE TRUE LOOP
                        pr('        wr('||v_begin|| replace(dbms_lob.substr(p_SQL, 1000, v_pos * 1000 + 1),chr(0),'@chr(0)@') || v_end||');');
                        v_pos  := v_pos + 1;
                        v_size := v_size - 1000;
                        EXIT WHEN v_size < 1;
                    END LOOP;
                END IF;
                
                IF p_name = 'sql_txt' THEN
                    pr(q'[        sql_txt := replace(sql_txt,'@chr(0)@',chr(0));]');
                END IF;
            END;
        BEGIN
            dbms_output.enable(NULL);

            IF v_dbid IS NULL THEN
                SELECT dbid
                INTO   v_dbid
                FROM   v$database;
            END IF;
            get_sql(p_sqlid);
            
            dbms_lob.createtemporary(v_text, TRUE);
            pr('Set define off sqlbl on serveroutput on'||chr(10));
            pr('DECLARE --Better for this script to have the access on gv$sqlarea');
            pr('    sql_txt   CLOB;');
            pr('    sql_txt1  CLOB;');
            pr('    sql_prof  SYS.SQLPROF_ATTR;');
            pr('    signature NUMBER;');
            pr('    sq_id     VARCHAR2(30):='''||v_sql_id||''';');
            pr('    prof_name VARCHAR2(30);');
            pr('    procedure wr(x varchar2) is begin dbms_lob.writeappend(sql_txt, length(x), x);end;');
            pr('BEGIN');
           
            pr('    BEGIN execute immediate ''select * from (SELECT SQL_FULLTEXT FROM gv$sqlarea WHERE SQL_ID=:1 union all SELECT SQL_TEXT FROM dba_hist_sqltext WHERE SQL_ID=:1 union all SELECT SQL_TEXT FROM dba_sqlset_statements WHERE SQL_ID=:1) where rownum<2'' INTO sql_txt USING sq_id,sq_id,sq_id;');
            pr('    EXCEPTION WHEN OTHERS THEN NULL;END;');
            pr('    IF sql_txt IS NULL THEN');
            writeSQL(v_sql,'sql_txt');
            pr('    END IF;');
            pr('    ');

            get_plan(nullif(p_plan,v_sql_id));

            v_signature := dbms_sqltune.SQLTEXT_TO_SIGNATURE(v_sql, TRUE);
            
            pr('    sql_prof := SYS.SQLPROF_ATTR(');
            pr('        q''[BEGIN_OUTLINE_DATA]'',');
            FOR i IN (SELECT /*+ opt_param('parallel_execution_enabled', 'false') */
                             SUBSTR(EXTRACTVALUE(VALUE(d), '/hint'), 1, 4000) hint
                      FROM   TABLE(XMLSEQUENCE(EXTRACT(v_hints, '//outline_data/hint'))) d) LOOP
                v_hint := REGEXP_REPLACE(i.hint,'^((NO_)?INDEX[A-Z_]*)_[ADE]+SC\(','\1(');
                IF v_hint LIKE '%IGNORE_OPTIM_EMBEDDED_HINTS%' THEN
                    v_embed := '        q''{' || v_hint || '}'','; 
                ELSIF v_hint NOT LIKE '%OUTLINE_DATA' THEN
                    --v_hint := regexp_replace(v_hint,'"([0-9A-Z$#_]+)"','\1');
                    WHILE NVL(LENGTH(v_hint), 0) > 0 LOOP
                        IF LENGTH(v_hint) <= 500 THEN
                            pr('        q''{' || v_hint || '}'',');
                            v_hint := NULL;
                        ELSE
                            v_pos := INSTR(SUBSTR(v_hint, 1, 500), ' ', -1);
                            pr('        q''{' || SUBSTR(v_hint, 1, v_pos) || '}'',');
                            v_hint := '   ' || SUBSTR(v_hint, v_pos);
                        END IF;
                    END LOOP;
                END IF;
            END LOOP;
            
            v_source := substr('PROF_'||nvl(regexp_replace(v_source,'^PROF_'),to_char(v_signature,'fm'||rpad('X',length(v_signature),'X'))),1,30);
            
            IF v_embed IS NOT NULL THEN
                pr(v_embed);
            END IF;
            pr('        q''[END_OUTLINE_DATA]'');');
            pr('    signature := DBMS_SQLTUNE.SQLTEXT_TO_SIGNATURE(sql_txt,TRUE);');
            pr('    prof_name := ''' ||replace(v_source,v_sql_id,'''||sq_id||''')||''';');
            pr('    BEGIN DBMS_SQLTUNE.DROP_SQL_PROFILE(prof_name);EXCEPTION WHEN OTHERS THEN NULL;END;');
            pr('    DBMS_SQLTUNE.IMPORT_SQL_PROFILE (');
            pr('        sql_text    => sql_txt,');
            pr('        profile     => sql_prof,');
            pr('        name        => prof_name,');
            pr('        description => prof_name || ''_'||ltrim(v_plan||'_','_')||'''||signature,');
            pr('        category    => ''DEFAULT'',');
            pr('        replace     => TRUE,');
            pr('        force_match => ' || CASE WHEN p_forcematch THEN 'TRUE' ELSE 'FALSE' END || ');');
            pr(q'[    dbms_output.put_line('SQL Profile created, to drop this profile, execute: DBMS_SQLTUNE.DROP_SQL_PROFILE('''||prof_name||''')');]');
            pr('END;');
            pr('/');
            
            p_buffer := v_text;
            RETURN trim('/' FROM v_plan_source||'/'||v_plan);
        END;
    BEGIN
        :2 := extract_profile(:3,:4,:5,:6, TRUE);
    END;]]
    env.checkhelp(sql_id)
    if (sql_plan or ''):find('[^%w_%$.#"]') then
        return sqlprof.generate_profile_from_outlines(sql_id,sql_plan)
    end
    if not db:check_access('sys.sql$text',1) and not db:check_access('sys.sqlobj$',1) then
        stmt=stmt:gsub("%$IF 1=1.-%$END","")
    end
    local args={sql_text or "",'#VARCHAR','#CLOB',sql_id or "",sql_plan or "",env.set.get("dbid") or ""}
    db:internal_call(stmt,args)

    if args[1] and args[1]:sub(1,1)=="#" then
        env.raise(args[1]:sub(2))
    end

    sql_id=((sql_id or ''):gsub('^PROF_','') or "plan_table");

    if args[2] then
        local src,phv=args[2]:match('^(.*)/(%d+)$')
        if phv then
            print('SQL Profile for plan #'..phv..' is extraced from '..src)
            sql_id = sql_id .. '_'..phv
        else
            print('SQL Profile is extraced from '..args[2])
        end
    end
    print("Result written to file "..env.write_cache('prof_'..sql_id..".sql",args[3]))
end

local profile_template=[[Set define off sqlbl on
DECLARE --Better for this script to have the access on gv$sqlarea
    sql_txt   CLOB;
    sql_prof  SYS.SQLPROF_ATTR;
    signature NUMBER;
    sq_id     VARCHAR2(30):='@sql_id@';
BEGIN
    BEGIN
        EXECUTE IMMEDIATE q'[SELECT /*+PQ_CONCURRENT_UNION OPT_PARAM('_fix_control' '26552730:0')*/ * FROM (
                                 SELECT SQL_FULLTEXT FROM gv$sqlarea
                                 WHERE SQL_ID=:1 AND ROWNUM<2
                                 UNION ALL
                                 SELECT SQL_TEXT FROM dba_hist_sqltext
                                 WHERE SQL_ID=:1 
                                 AND ROWNUM<2
                                 UNION ALL
                                 SELECT SQL_TEXT FROM all_sqlset_statements
                                 WHERE SQL_ID=:1 AND ROWNUM<2
                                 UNION ALL
                                 SELECT to_clob(SQL_TEXT) FROM gv$sql_monitor 
                                 WHERE SQL_ID=:1 AND IS_FULL_SQLTEXT='Y'
                                 AND   SQL_TEXT IS NOT NULL AND ROWNUM<2
                             ) WHERE ROWNUM<2]' 
        INTO sql_txt USING sq_id,sq_id,sq_id,sq_id;
    EXCEPTION WHEN OTHERS THEN NULL;END;
    IF sql_txt IS NULL THEN
        raise_application_error(-20001, 'Cannot find the SQL text for sql_id: ' || sq_id);
    END IF;
    
    sql_prof := SYS.SQLPROF_ATTR(
        @sql_profile
    );
    signature := DBMS_SQLTUNE.SQLTEXT_TO_SIGNATURE(sql_txt,TRUE);
    BEGIN DBMS_SQLTUNE.DROP_SQL_PROFILE('PROF_'||sq_id||'');EXCEPTION WHEN OTHERS THEN NULL;END;
    DBMS_SQLTUNE.IMPORT_SQL_PROFILE (
        sql_text    => sql_txt,
        profile     => sql_prof,
        name        => 'PROF_'||sq_id||'',
        description => 'PROF_'||sq_id||'_'||signature,
        category    => 'DEFAULT',
        replace     => TRUE,
        force_match => TRUE);
END;
/
PRO SQL Profile created, to drop this profile, execute: DBMS_SQLTUNE.DROP_SQL_PROFILE('PROF_@sql_id@')]]

function sqlprof.generate_profile_from_outlines(sql_id,outlines)
    outlines=outlines:trim()
    local hints={}
    if outlines:find('<hint>',1,true) then
        outlines:gsub('<hint>(.-)</hint>',function(s)
            if s:find('<![CDATA',1,true) then
                s=s:match('<!%[CDATA%[(.*)%]%]>')
            end
            hints[#hints+1]=s:trim() 
        end)
    else
        for v in outlines:gsplit('\n') do
            v=v:trim()
            if v:find('^%a') then hints[#hints+1]=v end
        end
    end
    
    for i=#hints,1,-1 do
        local hint=hints[i]
        if hint:upper():find('_OUTLINE_DATA',1,true) then
            table.remove(hints,i)
        else
            local q,st,ed='','',''
            if hint:find("'",1,true) then
                q='q'
                if hint:find('[',1,true) then
                    st,ed='{','}'
                elseif hint:find('{',1,true) then
                    st,ed='[',']'
                else
                    st,ed='~','~'
                end
            end
            hints[i]=q.."'"..st..hint..ed.."'"
        end
    end
    
    outlines=table.concat(hints,',\n        ')
    local profile=profile_template:gsub('@sql_id@',sql_id):gsub('@sql_profile',outlines)
    print("Result written to file "..env.write_cache('prof_'..sql_id..".sql",profile))
end

function sqlprof.onload()
    local help=[[
    Extract sql profile. Usage: @@NAME {<sql_id|sql_prof_name|spm_plan_name|spm_sql> [<plan_hash_value|new_sql_id|sql_prof_name|spm_plan_name|statement_id>|plan]}
    The command will not make any changes on the database, but to create a SQL file that used to fix the execution plan by SQL Profile.
    Examples:
        1). Generate the profile for the last plan of target SQL ID: @@NAME gjm43un5cy843
        2). Generate the profile of the specifc SQL ID + plan hash value: @@NAME gjm43un5cy843 1106594730
        3). Generate the profile for a SQL id with the plan of another SQL: @@NAME gjm43un5cy843 53c2k4c43zcfx
        4). Extract an existing SQL profile or baseline: @@NAME PROF_gjm43un5cy843
        5). Generate the profile for a SQL id with the profile/baseline of another sql: @@NAME gjm43un5cy843  PROF_53c2k4c43zcfx
        6). Generate the profile from plan table:
                xplan select * from dual;
                @@NAME gjm43un5cy843 plan;
        7). Generate the profile from outlines: @NAME <sql_id> <outlines_text>|<xml>
    ]]
    env.set_command(nil,"sqlprof",help,sqlprof.extract_profile,false,3)
end
return sqlprof