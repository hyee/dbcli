
local db,grid=env.getdb(),env.grid
local findobj,cache_obj,loaded={},{}
local stmt=[[
	DECLARE /*INTERNAL_DBCLI_CMD*/
	    schem         VARCHAR2(128);
	    part1         VARCHAR2(128);
	    part2         VARCHAR2(128);
	    part2_temp    VARCHAR2(128);
	    dblink        VARCHAR2(128);
	    part1_type    PLS_INTEGER;
	    object_number PLS_INTEGER;
	    cnt           PLS_INTEGER;
	    flag          BOOLEAN := TRUE;
	    obj_type      VARCHAR2(128);
	    objs          VARCHAR2(2000) := 'dba_objects';
	    stmt          VARCHAR2(4000);
	    target        VARCHAR2(500) := trim(:target);
	    isUpper       BOOLEAN := true;
	BEGIN
	    BEGIN
	        EXECUTE IMMEDIATE 'select 1 from dba_objects where rownum<1';
	    EXCEPTION WHEN OTHERS THEN
	        objs := 'all_objects';
	    END;
	    
	    <<CHECKER>>
	    IF NOT regexp_like(target,'^\d+$') THEN
	        IF regexp_like(target,'^[^"].*" *\. *".+[^"]$') OR NOT isUpper THEN
	            target := '"'||target||'"';
	        END IF;
	        

	        BEGIN 
	            sys.dbms_utility.name_tokenize(target,schem,part1,part2,dblink,part1_type);
	        EXCEPTION WHEN OTHERS THEN
	            IF SQLCODE=-931 THEN --ORA-00931: Missing identifier
	                sys.dbms_utility.name_tokenize('"'||REPLACE(UPPER(target),'.','"."')||'"',schem,part1,part2,dblink,part1_type);
	            END IF;
	        END;
	        target:='"'||REPLACE(trim('.' from schem||'.'||part1||'.'||part2),'.','"."')||'"';
	        
	        schem:=null;
	        FOR i IN 0 .. 9 LOOP
	            BEGIN
	                sys.dbms_utility.name_resolve(NAME          => target,
	                                              CONTEXT       => i,
	                                              SCHEMA        => schem,
	                                              part1         => part1,
	                                              part2         => part2,
	                                              dblink        => dblink,
	                                              part1_type    => part1_type,
	                                              object_number => object_number);
	                IF part2 IS NOT NULL AND part1 IS NULL THEN
	                    part1:=part2;
	                    part2:=null;
	                END IF;
	                EXIT WHEN schem IS NOT NULL;
	            EXCEPTION WHEN OTHERS THEN NULL;
	            END;
	        END LOOP;

	        IF schem IS NULL AND flag AND USER != sys_context('USERENV', 'CURRENT_SCHEMA') AND instr(target,'.')=0 THEN
	            flag   := FALSE;
	            target := sys_context('USERENV', 'CURRENT_SCHEMA') || '.' || target;
	            GOTO CHECKER;
	        END IF;
	    ELSE
	        EXECUTE IMMEDIATE 'select max(to_char(owner)),max(to_char(object_name)),max(to_char(subobject_name)),max(object_id) from '||objs||' where object_id=:1' 
	        INTO schem,part1,part2,object_number
	        USING 0+target;
	    END IF;
	   
	    IF schem IS NULL THEN
	        flag  := FALSE;
	        schem := regexp_substr(target, '[^\."]+', 1, 1);
	        part1 := regexp_substr(target, '[^\."]+', 1, 2);
	        IF part1 IS NULL THEN
	            part1 := trim('"' from target);
	            schem := null;
	            stmt  := objs||' a WHERE nvl(:1,''X'')=''X'' AND object_name =:3)';
	        ELSE
	            part2_temp := schem;
	            BEGIN
	                EXECUTE IMMEDIATE 'SELECT MAX(username) FROM DBA_USERS WHERE upper(username)=:1' INTO schem using upper(schem);
	            EXCEPTION WHEN OTHERS THEN 
	                SELECT MAX(username) INTO schem FROM ALL_USERS WHERE upper(username)=upper(schem);
	            END;

	            IF schem IS NOT NULL THEN
	                stmt  := objs||' a WHERE owner=:1 AND object_name =:2)';
	            ELSE
	                part1      := nvl(part2_temp,trim('"' from target));
	                stmt       := objs||' a WHERE nvl(:1,''Y'')=''Y'' AND object_name=:3)';
	            END IF;            
	        END IF;
	    ELSE
	        flag  := TRUE;
	        stmt  := objs|| ' a WHERE OWNER IN(''SYS'',''PUBLIC'',:1) AND OBJECT_NAME=:3)';
	    END IF;

	    stmt:=q'[SELECT /*+no_expand*/
	           MIN(to_char(OBJECT_TYPE))    keep(dense_rank first order by s_flag,object_id),
	           MIN(to_char(OWNER))          keep(dense_rank first order by s_flag,object_id),
	           MIN(to_char(OBJECT_NAME))    keep(dense_rank first order by s_flag,object_id),
	           MIN(to_char(SUBOBJECT_NAME)) keep(dense_rank first order by s_flag,object_id),
	           MIN(to_number(OBJECT_ID))    keep(dense_rank first order by s_flag)
	    FROM (
	        SELECT /*+INDEX_SS(a) MERGE(A) no_expand*/ a.*,
	               case when owner=:1 then 0 else 100 end +
	               case when :2 like '%"'||OBJECT_NAME||'"'||nvl2(SUBOBJECT_NAME,'."'||SUBOBJECT_NAME||'"%','') then 0 else 10 end +
	               case substr(object_type,1,3) when 'TAB' then 1 when 'CLU' then 2 else 3 end s_flag
	        FROM   ]' || stmt;


	    EXECUTE IMMEDIATE stmt
	        INTO obj_type, schem, part1, part2_temp,object_number USING schem,target,schem, part1;
	    
	    IF part2 IS NULL THEN
	        IF part2_temp IS NULL AND NOT flag THEN
	            part2_temp := regexp_substr(target, '[^\."]+', 1, CASE WHEN part1=regexp_substr(target, '[^\."]+', 1, 1) THEN 2 ELSE 3 END);
	        END IF;
	        part2 := part2_temp;
	    END IF;

	    IF part1 IS NULL AND target IS NOT NULL THEN
	        IF isUpper AND target=upper(target) AND :target!=UPPER(:target) THEN
	            target  := trim(:target);
	            isUpper := false;
	            GOTO CHECKER;
	        ELSIF :ignore IS NULL THEN
	            raise_application_error(-20001,'Cannot find target object '||target||'!');
	        END IF;
	    END IF;
	    
	    :object_owner   := schem;
	    :object_type    := obj_type;
	    :object_name    := part1;
	    :object_subname := part2;
	    :object_id      := object_number;
	END;]]

local default_args={target='v1',ignore='1',object_owner="#VARCHAR",object_type="#VARCHAR",object_name="#VARCHAR",object_subname="#VARCHAR",object_id="#NUMBER"}

function db:check_obj(obj_name,bypass_error,is_set_env)
	if not obj_name then return end
	obj_name=obj_name:gsub('"+','"')
    local obj=obj_name:upper()
    if not loaded then
    	local clock=os.clock()
        --env.printer.write("    Loading object dictionary...")
        local args={"#CLOB"}
        db:dba_query(db.internal_call,[[
	        DECLARE
	            TYPE t IS TABLE OF VARCHAR2(120);
	            t1 t;
	            c  CLOB;
	            c1 VARCHAR2(32767);
	        BEGIN
	            SELECT /*+ordered_predicates*/ 
	                   max(owner || '/' || object_name || '/' || object_type || '/' || object_id || ',')
	            BULK   COLLECT
	            INTO   t1
	            FROM   all_objects
	            WHERE  owner IN ('SYS', 'PUBLIC')
	            AND    regexp_like(object_name, '^(G?V\_?\$|DBA|ALL|USER|CDB|DBMS|UTL)')
	            AND    subobject_name IS NULL
	            AND    object_type not like '% BODY'
	            GROUP  BY object_name;
	            dbms_lob.createtemporary(c, TRUE);
	            FOR i IN 1 .. t1.count LOOP
	                c1 := c1 || t1(i);
	                IF LENGTHB(c1) > 32000 THEN
	                    dbms_lob.writeappend(c, LENGTH(c1), c1);
	                    c1 := NULL;
	                END IF;
	            END LOOP;
	            IF c1 IS NOT NULL THEN
	                dbms_lob.writeappend(c, LENGTH(c1), c1);
	            END IF;
	            :1 := c;
	        END;]],args)
        loaded=0
        for o,n,t,i in args[1]:gmatch("(.-)/(.-)/(.-)/(.-),") do
            loaded=loaded+1
            local item={
                target=o.."."..n,
                owner=o,
                object_owner=o,
                object_type=t,
                object_name=n,
                object_subname="",
                object_id=i}
            item.alias_list={item.target,n}
            cache_obj[item.target],cache_obj[n]=item,item
        end
        --printer.write("done in "..string.format("%.3f",os.clock()-clock).." secs.\n")
    end

    local args
    if obj and cache_obj[obj] then 
    	args=table.clone(cache_obj[obj])
    else
    	args=table.clone(default_args)
	    args.target,args.ignore=obj_name,bypass_error or ""
	    db:exec_cache(stmt,args,'Internal_FindObject')
	    args.owner=args.object_owner
	end

    local found=args and args.object_id and args.object_id~='' and true

    if is_set_env then
    	for k,v in pairs(default_args) do
    		if k:find('^object') then env.var.setInputs(k:upper(),found and args[k] or db.NOT_ASSIGNED) end
    	end
    end
    
    if args.owner=='SYS' then
        local full_name=table.concat({args.owner,args.object_name,args.object_subname},'.')
        local name=args.object_name..(args.object_subname and ('.'..args.object_subname) or '')
        cache_obj[obj],cache_obj[name],cache_obj[full_name]=args,args,args
        args.alias_list={obj,full_name,name}
    end
    return found and args
end

function db:check_access(obj_name,bypass_error,is_set_env)
    local obj=self:check_obj(obj_name,bypass_error,is_set_env)
    if not obj or not obj.object_id then return false end
    local o=obj.target
    if cache_obj[o] and cache_obj[o].accessible then return cache_obj[o].accessible==1 and true or false end
    obj.count='#NUMBER'
    self:exec_cache([[
        DECLARE /*INTERNAL_DBCLI_CMD*/
            x   PLS_INTEGER := 0;
            e   VARCHAR2(500);
            obj VARCHAR2(61) := :owner||'.'||:object_name;
        BEGIN
            IF instr(obj,'PUBLIC.')=1 THEN
                obj := :object_name;
            END IF;
            BEGIN
                EXECUTE IMMEDIATE 'select count(1) from ' || obj || ' where rownum<1';
                x := 1;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            IF x = 0 THEN
                BEGIN
                    EXECUTE IMMEDIATE 'begin ' || obj || '."_test_access"; end;';
                    x := 1;
                EXCEPTION
                    WHEN OTHERS THEN
                        e := SQLERRM;
                        IF INSTR(e,'PLS-00225')>0 OR INSTR(e,'PLS-00302')>0 THEN
                            x := 1;
                        END IF;
                END;
            END IF;
            :count := x;
        END;
    ]],obj,'Internal_CheckAccessRight')

    if cache_obj[o] then
        local value=obj.count==1 and 1 or 0
        for k,v in ipairs(cache_obj[o].alias_list) do cache_obj[v].accessible=value end
    end
    return obj.count==1 and true or false;
end

function findobj.onload()
	env.set_command(db,"FINDOBJ",nil,db.check_obj,false,4)
	env.event.snoop("AFTER_ORACLE_CONNECT",findobj.onreset)
end

function findobj.onreset()
    cache_obj,loaded={}
end


return findobj