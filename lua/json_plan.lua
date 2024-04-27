local env=env
local plan={leaf='LEAF TIME'}
--[[--
    JSON structure:
    {
        <$root>:{
            <root attributes>
            <$child>: [
                {
                    <child attributes>,
                    <$child>: [...]
                },
                ...
            ]
        }
    }
--]]--
function plan.parse_json_plan(json,options)
    if not json or not options then return end
    local fields={__={}}
    
    json=env.json.decode(json)
    json=#json>0 and json[1] or json
    local processor=options.processor or function(name,value,row,node) return value end
    local pcts={}
    for _,v in ipairs(options.percents or {}) do
        pcts[v:upper()]={val=0,width=0};
    end

    --parse JSON data
    local n,id,rows,ord,counter=0,1,{},0,0
    local maps,projection={},{{'Id','Projection'}}
    local proj=(options.projection or ""):upper()
    local leaf_based=type(options.leaf_time_based)=='table' and options.leaf_time_based or {options.leaf_time_based}
    local last_end_time
    local parse_tree=function(parse,tree,depth)
        local row={__=depth,__childs={sig=''}}
        local child={}
        local function push_field(name,org_name,value)
            if value~='' and value and (tonumber(value) or 1) >0 then
                if not fields[name] then
                    n=n+1
                    fields[name],fields.__[n]=n,org_name
                elseif name==proj then
                    value=value:trim()
                    projection[#projection+1]={id,value:match('^%b[]$') and value:sub(2,-2) or value}
                end 
            end
            row[name]=value
            if pcts[name] then
                pcts[name].val=pcts[name].val+(tonumber(value) or 0)
            end
        end
        processor(nil,nil,nil,tree)
        counter=0
        local branch_end_time
        for name,value in pairs(tree) do
            if name~=options.child then
                local org_name=name
                name=name:upper()
                value=processor(org_name,value,row,tree)
                if type(value)=="table" and #value>0 then
                    push_field(name,org_name,'['..table.concat(value,',')..']')
                elseif type(value)=="table" then
                    for k,v in pairs(value) do
                        v=processor(org_name..'.'..k,v,row,tree)
                        push_field(name..'.'..k:upper(),org_name..'.'..k,v)
                    end
                else
                    push_field(name,org_name,value)
                end
                --caculate leaf time
                value=tonumber(value)
                if name==(leaf_based[#leaf_based] or ''):upper() and value and value>0 then
                    local end_=value
                    if not tree[options.child] or #tree[options.child]==0 then
                        --last_end_time is the last time of neighbor branch
                        if last_end_time and end_>=last_end_time then
                            end_=end_ - last_end_time
                        elseif #leaf_based>1 then
                            local start_=tonumber(tree[leaf_based[1]])
                            if start_ then
                                end_=end_ - start_
                            end
                        end
                    end
                    branch_end_time=value
                    push_field(plan.leaf,plan.leaf,end_)
                    for d=depth-1,1,-1 do
                        if maps[d] then
                            local pleaf=maps[d][plan.leaf] or 0
                            if pcts[plan.leaf] then
                                pcts[plan.leaf].val=pcts[plan.leaf].val-math.min(value,pleaf)
                            end
                            if pleaf>value then
                                maps[d][plan.leaf]=pleaf-value
                                break
                            else
                                maps[d][plan.leaf]=0
                                value=value-pleaf
                            end
                        else
                            break
                        end
                    end
                end
                counter=1
            else
                child=value
            end
        end
        
        rows[id],maps[depth]=row,row

        for i=#maps,depth+1,-1 do maps[i]=nil end
        if maps[depth-1] then
            table.insert(maps[depth-1].__childs,id)
        end

        for _,node in ipairs(child) do
            id=id+counter
            parse(parse,node,depth+counter)
        end
        if branch_end_time and branch_end_time>(last_end_time or 0) then
            last_end_time=branch_end_time 
        end
        ord=ord+counter
        row._=ord
    end
    
    --generate plan summary
    local summary={{"Name","Information"}}
    for item,info in pairs(json) do
        if item==options.root then
            parse_tree(parse_tree,json[options.root],1)
        else
            info=processor(item,info)
            if type(info)=="table" and #info>1 then
                summary[1+#summary]={item,'['..table.concat(info,',')..']'}
            elseif type(info)=='table' then
                for k,v in pairs(info) do
                    v=processor(item..' / '..k,v)
                    if v and v~='' and (tonumber(v) or 1)>0 then
                        summary[1+#summary]={item..' / '..k,v}
                    end
                end
            elseif info and info~='' and (tonumber(info) or 1)>0 then
                summary[1+#summary]={item,info}
            end
        end
    end
    env.checkerr(#rows>0,"Cannot find root node from the JSON data: "..options.root)

    --build plan line indents
    maps={''}
    local space,width=' ',tonumber(options.indent_width) or 2
    local colors={_=0,'$HIB$','$HIM$','$HIY$','$HIC$','$HIR$'}
    local lines={_=3,'!','|',':'}
    local color_fmt='%s%s%s$NOR$'
    local function get_seq(obj)
        obj._=obj._+1
        return obj[(obj._%#obj)+1]
    end
    if options.keep_indent~=true then
        for id,row in ipairs(rows) do
            local depth,childs=row.__,row.__childs
            for i=#maps,depth+1,-1 do maps[i]=nil end
            local color=get_seq(colors)
            childs.color=color
            if #childs<2 or childs[#childs]-childs[1]<#childs+1 then
                maps[depth+1]=space:rep(width)
            else
                childs.has_child=true
                local line=get_seq(lines)
                maps[depth+1]=color_fmt:format(color,line,space:rep(width-1))
                for seq,child_id in ipairs(childs) do
                    local node=rows[child_id].__childs
                    node.sig=color_fmt:format(color,line..'=',space:rep(width-2))
                    if seq==#childs then node.last=true end
                end
            end
            if childs.last then
                maps[depth]=space:rep(width)
            end
            childs.indent=table.concat(maps,'',1,depth - (childs.sig=='' and 0 or 1))..childs.sig
        end
    end

    --calculate the execution orders
    local header={'|','Id','|','Ord','|'}
    local sorts,caches=type(options.sorts)=='table' and options.sorts or {options.sorts},{}
    if options.sorts==false then
        header,sorts={'|','Id','|'},{}
    end
    for i=#sorts,1,-1 do
        local col=sorts[i]:upper()
        if not fields[col] then 
            table.remove(sorts,i)
        else
            sorts[i]=col
        end
    end

    --build other info
    local ids = #header
    local col_seq = ids
    local seq,col,title,indexes=1,nil,nil,{}
    local sep_pattern='^%W+$'
    local miss=table.clone(fields)
    miss.__,miss[proj]=nil
    for _,n in ipairs(options.excludes or {}) do
        miss[n:upper()]=nil
    end

    --build column list
    local sig_color_fmt='%s%s$NOR$ %s'
    local nor_color_fmt='%s%s$NOR$'
    while seq <= #options.columns do
        col=options.columns[seq]
        if type(col)~='table' then
            title=tostring(col)
            local idx=fields[title:upper()]
            miss[title:upper()]=nil
            if not idx then
                if title:match(sep_pattern) then
                    col_seq=col_seq+1
                    header[col_seq]=title
                    indexes[col_seq]=title
                end
            else
                col_seq=col_seq+1
                header[col_seq]=title
                indexes[col_seq]={title:upper()}
            end
        else
            title=col[#col]
            if type(title)=='table' then
                title=table.concat(title,' ')
            end
            col_seq=col_seq+1
            header[col_seq]=title
            local func
            for _,n in ipairs(type(col[1])=='table' and col[1] or {col[1]}) do
                n=n:upper()
                local idx=fields[n]
                miss[n]=nil
                if idx then
                    if indexes[col_seq] then
                        indexes[col_seq][1+#indexes[col_seq]]=n
                    else
                        indexes[col_seq]={n}
                    end
                    if pcts[n] and col.format then
                        func=env.var.format_function(col.format)
                        pcts[n].func=func
                        env.var.define_column(title,'JUSTIFY','RIGHT')
                    end
                end
            end
            if not indexes[col_seq] then
                header[col_seq],col_seq=nil,col_seq-1
            elseif col.format and not func then
                env.var.define_column(title,'FOR',col.format)
            end
        end
        seq=seq+1
    end
    for col=#header,ids+1,-1 do
        if header[col]:match(sep_pattern) and header[col-1]:match(sep_pattern) then
            table.remove(header,col)
            table.remove(indexes,col)
            col_seq=col_seq-1
        end
    end
    --build grid results bases on column list and sorts
    local result,additions={header},{}
    local id_fmt='%s %'..#tostring(#rows)..'d'
    for seq,org in ipairs(rows) do
        local row=options.sorts==false and {'|',seq,'|'} or {'|',seq,'|',org._,'|'}
        --caculate the value of sort columns
        if #sorts>0 then
            local cache={seq=seq+1,val=0}
            local c=#sorts
            for i=1,c do
                cache.val=cache.val+math.pow(10000,c-i)*(tonumber(org[sorts[i]]) or 0)
            end
            caches[seq]=cache;
        end

        --find additional info
        local found,info=false,{}
        for n,_ in pairs(miss) do
            local val=org[n]
            if val~=nil and val~='' and (tonumber(val) or 1)>0 then
                found,info[#info+1]=true,{n=fields.__[fields[n]],v=tostring(val)}
            end
        end
        additions[seq]=found and info or ''
        row[2]=id_fmt:format(found and '*' or ' ',seq)

        --calculate the pct columns
        for n,v in pairs(pcts) do
            local val=tonumber(org[n])
            if val and val>0 and v.val>0 then
                local pct=math.round(val/v.val*100,3)
                local pct=pct<0.03 and '     ' or (tostring(pct):sub(1,4):lpad(4,' ')..'%')
                if v.func then val=v.func(val) end
                val=tostring(val):trim():gsub('%.0+(%D)','%1')..' | '..pct
                v.width=math.max(v.width,#val)
                org[n]=val
            elseif v.val>0 then
                org[n]='|      '
            end
        end
        for i=#row+1,col_seq do
            local index=indexes[i]
            if type(index)=='table' then
                local col={}
                for c,n in ipairs(index) do
                    if type(org[n])=='boolean' then
                        col[c]=org[n] and fields.__[fields[n]] or ''
                    else
                        col[c]=org[n] or ''
                    end
                    if not pcts[n] and (tonumber(col[c])==0 or col[c]==false) then
                        col[c]=''
                    end
                end
                row[i]=table.concat(col,' ')
                
                if type(row[i])=='string' and not pcts[index[1]] then
                    if options.keep_indent~=true then row[i]=row[i]:trim():gsub('%s+',' ') end
                    row[i]=tonumber(row[i]) or row[i]
                end
            else
                row[i]=index or ''
            end
            
            if i==ids+1 and options.keep_indent~=true then
                local sig,text=tostring(row[i]):match('^(%S) (.*)$')
                local indent,color=org.__childs.indent,org.__childs.color
                if sig then
                    row[i]=indent..sig_color_fmt:format(color or "$HIR$",sig,text)
                elseif color and org.__childs.has_child then
                    row[i]=indent..nor_color_fmt:format(color,row[i])
                else
                    row[i]=indent..row[i]
                end
            else
                row[i]=tonumber(row[i]) or row[i] or ''
            end
            
        end
        result[seq+1]=row
    end

    --set ord field
    if #sorts>0 then
        table.sort(caches,function(a,b)
            if a.val ~= b.val then
                return a.val<b.val
            else
                return a.seq>b.seq
            end
        end)
        for i,cache in ipairs(caches) do
            result[cache.seq][4]=i
        end
    end

    if #summary > 1 then
        print("===========")
        print("| Summary |")
        print("===========")
        env.grid.print(summary,true,'|','-')
        print('')
    end
    local colwidth=env.set.get("COLWRAP")
    env.set.set("COLWRAP",'default')
    result[#result+1]={'-'}
    local title='| '..(options.title or "Plan Tree")..' |'
    print(string.rep("=",#title))
    print(title)
    print(string.rep("=",#title))
    env.grid.print(result,true)
    print('')

    table.clear(result)
    result[1]={'Id','Name','Information'}
    
    for seq,info in ipairs(additions) do
        if type(info)=='table' then
            for i,r in ipairs(info) do
                if type(r.v)~='string' or not r.v:match('^%W.*%W$') then
                    r.v=' '..tostring(r.v)
                end
                result[#result+1] = {i==1 and seq or '',r.n,r.v}
            end
        end
    end

    env.set.set("COLWRAP",180)
    if #result>1 then
        print("=====================")
        print("| Other Information |")
        print("=====================")
        env.grid.print(result,true)
        print('')
    end

    if #projection>1 then
        env.set.set("COLWRAP",200)
        print("=====================")
        print("|    Projections    |")
        print("=====================")
        env.grid.print(projection,true)
        print('')
    end
    env.set.set("COLWRAP",colwidth)
end

return plan