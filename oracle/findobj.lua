
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
	    object_number NUMBER;
	    cnt           PLS_INTEGER;  
	    did           PLS_INTEGER;
	    flag          BOOLEAN := TRUE;
	    obj_type      VARCHAR2(128);
	    objs          VARCHAR2(2000) := 'dba_objects';
	    stmt          VARCHAR2(4000);
	    target        VARCHAR2(500) := trim(:target);
	    isUpper       BOOLEAN := true;
	    xTableID      NUMBER := 0;
	BEGIN
		IF upper(target) like 'X$%' THEN
			BEGIN
				execute immediate 'select object_id from v$fixed_table where name=upper(:1)'
				into xTableID using upper(target);
				schem := 'SYS';
				obj_type :='TABLE';
				part1 := upper(upper(target));
				object_number := xTableID;
			EXCEPTION WHEN OTHERS THEN NULL;
			END;
		END IF;

	    BEGIN
	        EXECUTE IMMEDIATE 'select 1 from dba_objects where rownum<1';
	    EXCEPTION WHEN OTHERS THEN
	        objs := 'all_objects';
	    END;
	    
	    <<CHECKER>>
	    IF xTableID=0 THEN
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
		           MIN(OBJECT_TYPE)    keep(dense_rank first order by s_flag,object_id),
		           MIN(OWNER)          keep(dense_rank first order by s_flag,object_id),
		           MIN(OBJECT_NAME)    keep(dense_rank first order by s_flag,object_id),
		           MIN(SUBOBJECT_NAME) keep(dense_rank first order by s_flag,object_id),
		           MIN(OBJECT_ID)      keep(dense_rank first order by s_flag),
		           MIN(DATA_OBJECT_ID) keep(dense_rank first order by s_flag,object_id)
		    FROM (
		        SELECT /*+INDEX_SS(a) MERGE(A) no_expand*/ a.*,
		               case when owner=:1 then 0 else 100 end +
		               case when :2 like '%"'||OBJECT_NAME||'"'||nvl2(SUBOBJECT_NAME,'."'||SUBOBJECT_NAME||'"%','') then 0 else 10 end +
		               case substr(object_type,1,3) when 'TAB' then 1 when 'CLU' then 2 else 3 end s_flag
		        FROM   ]' || stmt;


		    EXECUTE IMMEDIATE stmt
		        INTO obj_type, schem, part1, part2_temp,object_number,did USING schem,target,schem, part1;
		    
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
		        ELSIF nvl(:ignore,'0') = '0' THEN
		            raise_application_error(-20001,'Cannot find target object '||target||'!');
		        END IF;
		    END IF;
	    END IF;

	    :object_owner   := schem;
	    :object_type    := obj_type;
	    :object_name    := part1;
	    :object_subname := part2;
	    :object_id      := object_number;
	    :object_data_id := did;
	END;]]

local default_args={target='v1',ignore='1',object_owner="#VARCHAR",object_type="#VARCHAR",object_name="#VARCHAR",object_subname="#VARCHAR",object_id="#NUMBER",object_data_id="#NUMBER"}

function db:check_obj(obj_name,bypass_error,is_set_env)
	if not obj_name then
		return env.checkerr((bypass_error or '0')~='0',"Please input the object name/id!");
	end
	obj_name=obj_name:gsub('"+','"')
    local obj=obj_name:trim():upper()
    env.checkerr(bypass_error=='1' or obj~="","Please input the object name/id!")

    if not loaded then
    	local clock=os.clock()
        --env.printer.write("    Loading object dictionary...")
        local args={"#CLOB"}
        local sql=[[
	        DECLARE
	            TYPE t IS TABLE OF VARCHAR2(300);
	            t1 t;
	            c  CLOB;
				c1 VARCHAR2(32767);
				@lz_compress@
	        BEGIN
	        	SELECT /*+ordered_predicates use_hash(o d) swap_join_inputs(d)*/
				       MAX(owner || '/' || object_name || '/' || object_type || '/' || object_id || '/' || nullif(n1,object_name)|| ',' ) 
				       keep(dense_rank FIRST ORDER BY decode(object_type, 'SYNONYM', 'ZZZZ', object_type)) n
				BULK   COLLECT INTO t1
				FROM   all_objects o
				LEFT   JOIN (SELECT /*+use_hash(o p) no_merge*/
				                    object_name n1, referenced_object_id object_id
				             FROM   all_objects o
				             JOIN   PUBLIC_DEPENDENCY p
				             ON     (p.object_id = o.object_id)
				             WHERE  o.owner IN ('PUBLIC')
				             AND    o.object_type = 'SYNONYM'
				             AND    p.object_id != referenced_object_id) d
				USING  (object_id)
				WHERE  (owner IN ('SYS', 'PUBLIC') OR owner LIKE 'C##')
				AND    object_type != 'SYNONYM'
				AND    regexp_like(object_name, '^(G?V\_?\$|DBA|ALL|USER|CDB|DBMS|UTL|AWR_)')
				AND    subobject_name IS NULL
				AND    object_type NOT LIKE '% BODY'
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
				base64encode(c);
	            :1 := c;
			END;]]
		local success,res=pcall(db.internal_call,self,sql:gsub('all_objects','dba_objects'),args)
		if not success then res=self:internal_call(sql,args) end
		loaded=0
		args[1]=loader:Base64ZlibToText(args[1]:split('\n'));
		for o,n,t,i,s in args[1]:gmatch("(.-)/(.-)/(.-)/(.-)/(.-),") do
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
            if s and s~='' then
            	item.synonym=s
            	cache_obj[s],cache_obj['PUBLIC.'..s]=item,item 
            end
        end
        --printer.write("done in "..string.format("%.3f",os.clock()-clock).." secs.\n")
    end

    local args
    if cache_obj[obj] then
    	args=table.clone(cache_obj[obj])
    elseif obj~="" then
    	args=table.clone(default_args)
	    args.target,args.ignore=obj_name,bypass_error and (''..bypass_error) or "0"
	    db:exec_cache(stmt,args,'Internal_FindObject')
	    args.owner=args.object_owner
	else
		args={}
	end

    local found=args and args.object_id and args.object_id~='' and true

    if is_set_env then
    	for k,v in pairs(default_args) do
    		if k:find('^object') then env.var.setInputs(k:upper(),found and args[k] or db.NOT_ASSIGNED) end
    	end
    end
    
    if args.owner and (args.owner=='SYS' or args.owner:find('^C##')) then
        local full_name=table.concat({args.owner,args.object_name,args.object_subname},'.')
        local name=args.object_name..(args.object_subname and ('.'..args.object_subname) or '')
        cache_obj[obj],cache_obj[name],cache_obj[full_name]=args,args,args
        args.alias_list={obj,full_name,name}
    end
    return found and args
end

local privs={}
function db:check_access(obj_name,bypass_error,is_set_env,is_cache)
	local obj=cache_obj[obj_name] or privs[obj_name]
	if obj~=nil then 
		if type(obj)=="table" and obj.accessible then 
			return obj.accessible==1
		elseif type(obj)=="number" then
			return obj==1
		end
	end

	obj=self:check_obj(obj_name,bypass_error,is_set_env)
	
	if not obj or not obj.object_id then
		if is_cache==true then privs[obj_name]=0 end
		return false 
	end

    local o=obj.target
    if cache_obj[o] and cache_obj[o].accessible then return cache_obj[o].accessible==1 end
    obj.count='#NUMBER'

    self:exec_cache([[
        DECLARE /*INTERNAL_DBCLI_CMD*/
            x   PLS_INTEGER := 0;
            e   VARCHAR2(500);
            obj VARCHAR2(61) := :owner||'.'||:object_name;
        BEGIN
        	select count(1) into x
            from   table_privileges
            where  owner=case when regexp_like(:object_name,'^(G?V)\$') then 'SYS' else :owner end
            AND    table_name=regexp_replace(:object_name,'^(G?V)\$','\1_$')
            AND    SELECT_PRIV!='G'
            AND    rownum<2;

            IF x=0 THEN
	            IF instr(obj,'PUBLIC.')=1 THEN
	                obj := :object_name;
	            END IF;
	            BEGIN
	                EXECUTE IMMEDIATE 'select count(1) from ' || obj || ' where rownum<1';
	                x := 1;
	            EXCEPTION WHEN OTHERS THEN NULL;
	            END;
	        END IF;
	        
            :count := x;
        END;
	]],obj,'Internal_CheckAccessRight')
	local value=obj.count==1 and 1 or 0
	if cache_obj[o] then
		for k,v in ipairs(cache_obj[o].alias_list) do cache_obj[v].accessible=value end
	elseif is_cache==true then
		privs[obj_name]=value
    end
    return value==1 and true or false;
end

local re=env.re
local P=re.compile([[
        pattern <- {pt} {owner* obj} {suffix}
        suffix  <- [%s,;)]
        pt      <- [%s,(]
        owner   <- ('SYS.'/ 'PUBLIC.'/'"SYS".'/'"PUBLIC".')
        obj     <- full/name
        full    <- '"' name '"'
        name    <- {prefix %a%a [%w$#__]+}
        prefix  <- "DBA_"/"ALL_"/"CDB_"
    ]],nil,true)

local function rep(prefix,full,obj,suffix)
	local o=obj:upper()
	local p,s=o:sub(1,3),o:sub(4)
	local t=full:replace(obj,(p=='ALL' and 'DBA' or p)..s)
	if db:check_access(t,'1',nil,true) then
		return prefix..t..suffix
	else
		if p=='CDB' then
			t=full:replace(obj,'DBA'..s)
			if db:check_access(t,'1',nil,true) then return prefix..t..suffix end
		end
		if p=='ALL' then return prefix..full..suffix end
		return prefix..full:replace(obj,'ALL'..s)..suffix
	end
end

function oracle:dba_query(func,sql,args)
	sql=re.gsub(sql..' ',P,rep)
    local res=func(self,sql,args)
    return res,args
end

function findobj.onload()
	env.set_command(db,"FINDOBJ",nil,db.check_obj,false,4)
	env.event.snoop("AFTER_ORACLE_CONNECT",findobj.onreset)
end

function findobj.onreset()
    cache_obj,privs,loaded={},{}
end


return findobj