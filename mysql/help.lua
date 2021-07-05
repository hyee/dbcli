local env=env
local help=env.class(env.helper)
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local helpdict=env.join_path(env.WORK_DIR,'mysql/help.pack')
function help.help_topic(...)
	local args={...}
	if type(args[1])=='table' then table.remove(args,1) end
    local keyword=table.concat(args," "):gsub('%s+',' '):upper():trim()
    if keyword=='' then keyword='HELP_VERSION' end
    local like={keyword:find("%$") and keyword or (keyword.."%")}
    local desc
    env.set.set("feed","off")
    local doc
    if os.exists(helpdict) then
		doc=env.load_data(helpdict,true)
		local category=doc._categories
		doc._categories=nil
		like=like[1]:gsub('%%','.*')
		if keyword=="C" or keyword=="CONTENTS" then
			local rows={}
			for key,list in pairs(category) do
				local keys={}
				for n,_ in pairs(list) do
					if type(n)=='string' then
						keys[#keys+1]=n
					end
				end
				table.sort(keys)
				rows[#rows+1]={list[1],list[2],key,table.concat(keys,', ')}
			end
			table.sort(rows,function(a,b) return a[1]<b[1] end)
			table.insert(rows,1,{"Category#","Parent#","Category","Keywords"})
			grid.print(rows)
		elseif keyword:find("^S%s+") or keyword:find("^F%s+") then
			local f
			f,keyword=keyword:match("^(%w)%s+(.*)$")
			like=(keyword:find("%$") and keyword or ("%"..keyword.."%")):gsub('%%','.-')
			local rows={}
			for key,list in pairs(doc) do
				if key:find(like) or list[3]:find(like) or (f=='F' and not(to) and list[1]:sub(1,512):find(like)) then
					local piece=list[6]
					if f=='F' then
						piece=list[1]:sub(1,512):match('\n('..like..'[^\n\r]+)'):trim()
					end
					rows[#rows+1]={key,list[3],piece}
				end
			end
			table.sort(rows,function(a,b) return a[1]<b[1] end)
			table.insert(rows,1,{"Name","Category",f=='F' and "Piece" or "URL"})
			grid.print(rows)
		else
			local cats={}
			for key,list in pairs(category) do
				if key:upper()==keyword or tostring(list[1])==keyword or tostring(list[2])==keyword then
					cats[#cats+1]=list
				end
			end
			if cats[1] then
				local rows={}
				for _,cat in ipairs(cats) do
					for n,_ in pairs(cat) do
						if type(n)=='string' then
							local key=doc[n]
							rows[#rows+1]={key[4],key[5],n,key[3],key[6]}
						end
					end
				end
				table.sort(rows,function(a,b) return a[3]<b[3] end)
				table.insert(rows,1,{"Category#","Parent#","Name","Category","URL"})
				grid.print(rows)
			else
				local match=doc[keyword]
				if not match then
					for key,list in pairs(doc) do
						if key:find(like) then 
							match=list
							keyword=key
							break
						end
					end
				end
				env.checkerr(match,"No such topic: "..keyword)
				local rows={}
	            rows[1]={'Name:  '..match[3].." / "..keyword}
	            rows[2]={match[1]:gsub("^%s*Syntax:%s*","")}
	            if (match[2] or ""):trim()~="" then
	                rows[2][1]=rows[2][1].."\n$PROMPTCOLOR$Examples: $NOR$\n========= "..(("\n"..match[2]):gsub("\r?\n","\n  "))
	            end
	            if (match[6] or ""):trim()~="" then
	                rows[2][1]=rows[2][1].."\n$PROMPTCOLOR$Refer to: $NOR$\n========= "..(("\n"..match[6]):gsub("\r?\n","\n  "))
	            end
	            grid.print(rows)
			end
		end
		return
	end
    local help_table=" from mysql.help_topic as a right join mysql.help_category as b using(help_category_id) "
    if keyword=="C" or keyword=="CONTENTS" then
        db:query([[select help_category_id as `Category#`,parent_category_id as `Parent#`,b.name as `Category`,
        	              group_concat(distinct coalesce(nullif(substring(a.name,1,instr(a.name,' ')-1),''),a.name) order by a.name) as `Keywords`]]
        	              ..help_table.."group by help_category_id,b.name order by 1")
    elseif keyword:find("^SEARCH%s+") or keyword:find("^S%s+") then
        keyword=keyword:gsub("^[^%s+]%s+","")
        like={keyword:find("%$") and keyword or ("%"..keyword.."%")}
        db:query("select a.name,b.name as category,a.url"..help_table.."where (a.name like :1 or upper(b.name) like :1) order by a.name",like)
    else
        local topic=db:get_value("select 1"..help_table.."where upper(b.name)=:1 or convert(help_category_id,char)=:1",{keyword})
        if topic then
            db:query("select a.name,b.name as category,a.url"..help_table.." where upper(b.name)=:1 or convert(help_category_id,char)=:1 order by a.name",{keyword})
        else
            local topic=db:get_value("select a.name,description,example,b.name as category"..help_table.."where a.name like :1 order by a.name limit 1",like)
            env.checkerr(topic,"No such topic: "..keyword)
            local rows={}
            rows[1]={'Name:  '..topic[4].." / "..topic[1]}
            rows[2]={topic[2]:gsub("^%s*Syntax:%s*","")}
            if (topic[3] or ""):trim()~="" then
                rows[2][1]=rows[2][1].."\n$PROMPTCOLOR$Examples: $NOR$\n========= "..(("\n"..topic[3]):gsub("\r?\n","\n  "))
            end
            grid.print(rows)
        end
    end
end

function help:onload()
	self.prefix=table.concat({"? c           : List all SQL statements grouping by category",
		                      "? s <keyword> : List the SQL statements that match the criteria",
		                      "?  <category> : List the SQL statements belongs to input catetory id or catetory name",
		                      "?   <keyword> : Show help document of the SQL that matches the input keyword"},"\n")
	self.helpdict=helpdict
	set_command(nil,{"?","\\?"},"Synonym for `help`",self.help_topic,false,9)
    env.event.snoop("ON_HELP_NOTFOUND",self.help_topic)
end

return help.new()