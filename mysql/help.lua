local env=env
local help=env.class(env.helper)
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local helpdict=env.join_path(env.WORK_DIR,'mysql/help.pack')
function help.help_offline(...)
    help.help_topic('\1',...)
end
function help.help_topic(...)
    local args={...}
    local offline,f
    while args[1]=='\1' do offline=table.remove(args,1) and os.exists(helpdict) end
    if type(args[1])=='table' then table.remove(args,1) end
    if args[1] and args[1]:match('^[sfSF]$') then f=table.remove(args,1):upper() end
    local keyword=table.concat(args," "):upper():trim()
    if keyword=='' then keyword='HELP_VERSION' end
    local like={keyword:find("%",1,true) and keyword or ('%'..keyword.."%")}
    local desc
    env.set.set("feed","off")
    local doc
    local help_table=" from mysql.help_topic as a right join mysql.help_category as b using(help_category_id) "
    local done=not offline and db:is_connect() and pcall(db.internal_call,db,'select 1'..help_table..' limit 1',{})
    if done then
        if keyword=="C" or keyword=="CONTENTS" then
            db:query([[select help_category_id as `Category#`,parent_category_id as `Parent#`,b.name as `Category`,
                              group_concat(distinct coalesce(nullif(substring(a.name,1,instr(a.name,' ')-1),''),a.name) order by a.name) as `Keywords`]]
                    ..help_table.."group by help_category_id,b.name order by 1")
        elseif f then
            db:query("select a.name,b.name as category,a.url"..help_table.."where (upper(a.name) like :1 or upper(b.name) like :1 or upper(a.description) like :1) order by a.name",like)
        else
            local topic=db:get_value("select 1"..help_table.."where upper(b.name)=:1 or convert(help_category_id,char)=:1",{keyword})
            if topic then
                db:query("select a.name,help_category_id as `Category#`,parent_category_id as `Parent#`,b.name as category,a.url"..help_table.." where upper(b.name)=:1 or convert(help_category_id,char)=:1 order by a.name",{keyword})
            else
                local topic=db:get_value("select a.name,description,example,b.name as category"..help_table.."where upper(a.name) like :1 order by nullif(instr(upper(a.name),trim('%' from :1)),0),a.name limit 1",like)
                env.checkerr(topic,"No such topic: "..keyword)
                local rows={}
                rows[1]={'Name:  '..topic[4].." / "..topic[1]}
                rows[2]={topic[2]:gsub("^%s*Syntax:%s*",""):trim()}
                if (topic[3] or ""):trim()~="" then
                    rows[2][1]=rows[2][1].."\n$PROMPTCOLOR$Examples: $NOR$\n========= "..(("\n"..topic[3]):gsub("\r?\n","\n  "))
                end
                grid.print(rows)
            end
        end
    else
        doc=env.load_data(helpdict,true)
        local category=doc._categories
        doc._categories=nil
        like=like[1]:gsub('%%','.-')
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
        elseif f then
            local rows={}
            for key,list in pairs(doc) do
                local piece=f=='S' and list[1]:sub(1,512):upper():match('\n('..like..'[^\n\r]+)')
                if piece or key:find(like) or list[3]:upper():find(like) then
                    local piece=list[6]
                    rows[#rows+1]={key,list[3],piece and piece:trim() or list[6]}
                end
            end
            table.sort(rows,function(a,b) return a[1]<b[1] end)
            table.insert(rows,1,{"Name","Category",f=='S' and "Piece" or "URL"})
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
                if not match then return help.help_topic('\1','F',keyword) end
                env.checkerr(match,"No such topic: "..keyword)
                local rows={}
                rows[1]={'Name:  '..match[3].." / "..keyword}
                rows[2]={match[1]:gsub("^%s*Syntax:%s*",""):trim()}
                if (match[2] or ""):trim()~="" then
                    rows[2][1]=rows[2][1].."\n\n$PROMPTCOLOR$Examples: $NOR$\n========= "..(("\n"..match[2]):gsub("\r?\n","\n  "))
                end
                if (match[6] or ""):trim()~="" then
                    rows[2][1]=rows[2][1].."\n\n$PROMPTCOLOR$Refer to$NOR$: "..match[6]
                end
                grid.print(rows)
            end
        end
    end
end

function help:onload()
    self.prefix=table.concat({"? c           : List all SQL statements grouping by category",
                              "? s <keyword> : List the SQL statements that match the criteria",
                              "?  <category> : List the SQL statements belongs to input catetory id or catetory name",
                              "?   <keyword> : Show help document of the SQL that matches the input keyword",
                              "help ...      : Query offline help documents"},"\n")
    self.helpdict=helpdict
    set_command(nil,{"?","\\?"},"#Synonym for `help`",self.help_topic,false,9)
    env.event.snoop("ON_HELP_NOTFOUND",function(...) self.help_offline('\1',...) end)
end

return help.new()