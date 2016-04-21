local env=env
local json,math,graph,cfg=env.json,env.math,env.class(env.scripter),env.set
local template,cr
--[[
    Please refer to "http://dygraphs.com/options.html" for the graph options that used in .chart files
    Common options from dygraphs:
        ylabel,title,height,rollPeriod,drawPoints,logscale,fillGraph,stackedGraph,stepPlot,strokePattern
    Other options:
        _attrs="<sql_statement>" : Select statement to proceduce the attributes, 
                                   field name matches the attribute name,
                                   and must return only one row, it can also can be used as a variable inside "_sql" option
        _sql  ="<sql_statement>" : The select statement to produce the graph data
                                   1st field : the value of X-Asis, mainly be a time value
                                   _pivot=true:
                                       2nd  field      : as the name of the curve
                                       3rd+ fields     : as the values of Y-Asis, must be number, if >1 fields then split into multiple charts
                                       3rd+ field names: as the y-label
                                   _pivot=false:
                                       2nd+ fields: field name as the curve name and value as the Y-Asis
        _pivot=true|false        : indicate if pivot the >2nd numberic fields  
        _ylabels={"<label1>",...}: Customize the ylabel for each chart, not not define then use the names from "_sql"
        _range="<Time range>"    : Used in sub-title, if not specified then auto-caculate the range                  
]]--

function graph:ctor()
    self.command='graph'
    self.ext_name='chart'
    if not template then
        template=env.load_data(env.WORK_DIR.."lib"..env.PATH_DEL.."dygraphs.html",false)
        env.checkerr(type(template)=="string",'Cannot load file "dygraphs.html" in folder "lib"!')
        cr=[[
        <div id="divNoshow@GRAPH_INDEX" style="display:none">@GRAPH_DATA</div>
        <div id="divShow@GRAPH_INDEX" style="width:100%;"></div>
        <div id="divLabel@GRAPH_INDEX" style="width:90%; margin-left:5%"></div>
        <div style="width: 100%; text-align: center;">
          <input type="checkbox" id="drawPoints@GRAPH_INDEX" onclick="javascript:g@GRAPH_INDEX.updateOptions({drawPoints:this.checked})">Point</button>&nbsp;&nbsp;&nbsp;
          <input type="checkbox" id="logscale@GRAPH_INDEX" onclick="javascript:g@GRAPH_INDEX.updateOptions({logscale:this.checked})">Log Scale</button>&nbsp;&nbsp;&nbsp;
          <input type="checkbox" id="fillGraph@GRAPH_INDEX" onclick="javascript:g@GRAPH_INDEX.updateOptions({fillGraph:this.checked})">Fill Graph</input>&nbsp;&nbsp;&nbsp;
          <input type="checkbox" id="stackedGraph@GRAPH_INDEX" onclick="javascript:g@GRAPH_INDEX.updateOptions({stackedGraph:this.checked})">Stacked Graph</input>&nbsp;&nbsp;&nbsp;
          <input type="checkbox" id="stepPlot@GRAPH_INDEX" onclick="javascript:g@GRAPH_INDEX.updateOptions({stepPlot:this.checked})">Step Plot</input>&nbsp;&nbsp;&nbsp;
          <input type="checkbox" id="strokePattern@GRAPH_INDEX" onclick="javascript:g@GRAPH_INDEX.updateOptions({strokePattern:this.checked?Dygraph.DASHED_LINE:null})">Stroke Pattern</input>
        </div>
        <script type="text/javascript">
        var g@GRAPH_INDEX=new Dygraph(
            document.getElementById("divShow@GRAPH_INDEX"),
            function() {return document.getElementById("divNoshow@GRAPH_INDEX").innerHTML;},
            @GRAPH_ATTRIBUTES
        );
        var ary=['drawPoints','logscale','fillGraph','stackedGraph','strokePattern'];
        for(i=0;i<ary.length;i++) {
            var val=g@GRAPH_INDEX.getOption(ary[i]);
            document.getElementById(ary[i]+"@GRAPH_INDEX").checked=(val==null||val==false)?false:true; 
        }
        
        //gs.push(g@GRAPH_INDEX);
        //if(sync!=null) sync.detach();
        //sync = Dygraph.synchronize(gs);
        </script>
        <hr/><br/><br/>]]
        --template=template:gsub('@GRAPH_FIELDS',cr)
    end
    cfg.init("ChartSeries",12,set_param,"core","Number of top series to be show in graph chart(see command 'chart')",'1-500')
end


function graph:run_sql(sql,args,cmd,file)

    if type(sql)=="table" then
        for i=1,#sql do self:run_sql(sql[i],args[i],cmd[i],file[i]) end
        return
    end
    local units,rs,rows={}
    
    local context,err=loadstring(('return '..sql):gsub(self.comment,"",1))
    env.checkerr(context,"Error when loading file %s: %s",file,err)
   
    context=context()
    env.checkerr(type(context)=="table" and type(context._sql)=="string","Invalid definition, should be a table with '_sql' property!")
    local default_attrs={
            --legend='always',
            labelsDivStyles= {border='1px solid black',width=80},
            rollPeriod=8,
            showRoller=true,
            height= 400,
            includeZero=true,
            highlightSeriesOpts= {
              strokeWidth= 2,
              strokeBorderWidth=2,
              highlightCircleSize=2,
            },
        }
    if context._attrs then
        rs=self.db:exec(context._attrs,args)
        rows=self.db.resultset:rows(rs,1)
        local title=rows[1]
        local value=rows[2]
        env.checkerr(value,context._error or 'No data found for the given criteria!')
        for k,v in ipairs(title) do
            if not v:find('[a-z]') then v=v:lower() end
            args[v]=value[k]
            --deal with table
            if value[k] and value[k]:sub(1,1)=='{' then value[k]=json.decode(value[k]) end
            default_attrs[v]=value[k]
        end
    end

    local sql,pivot=context._sql,context._pivot
    --Only proceduce top 30 curves to improve the performance in case of there is 'RNK_' field
    if sql:match('RNK%_%W') and not sql:match('RND%_%W') then
        sql='SELECT * FROM (SELECT /*+NO_NOMERGE(A)*/ A.*,dense_rank() over(order by RNK_ desc) RND_ FROM (\n'..sql..'\n) A) WHERE RND_<=30 ORDER BY 1,2'
        --print("Detected field 'RNK_' and re-applying the SQL...")
    end

    rs=self.db:exec(sql,args)
    local title,txt,keys,values,collist,temp=string.char(0x1),{},{},{},{},{}
    
    local function getnum(val)
        if not val then return 0 end
        if type(val)=="number" then return val end
        return tonumber(val:match('[eE%.%-%d]+')) or 0
    end
    local counter,range_begin,range_end=-1
    rows=self.db.resultset:rows(rs,-1)
    while true do
        counter=counter+1
        local row=rows[counter+1]
        if not row then break end
        if counter>0 and row[1]~="" then
            local x=row[1]
            if not range_begin then
                if tonumber(x) then
                    range_begin,range_end=9E9,0
                else
                    range_begin,range_end='ZZZZ','0'
                end
            end
            if type(range_begin)=="number" then x=tonumber(x) end
            range_begin,range_end=range_begin>x and x or range_begin, range_end<x and x or range_end
        end
        --For pivot, col1=x-value, col2=Pivot,col3=y-value
        if pivot then
            local x,p,y=row[1],row[2],{table.unpack(row,3)}
            for i=#y,1,-1 do
               if rows[1][i+2]=="RNK_" or rows[1][i+2]=="RND_" then table.remove(y,i) end 
            end
            if #keys==0 then
                units,keys[1],values[title]=y,title,{x}
                env.checkerr(#units>0,'Pivot mode should have at least 3 columns!')
                print('Start fetching data into HTML file...')
            else
                if not collist[p] then
                    values[title][#values[title]+1],temp[#temp+1]=p,{}
                    collist[p]={#values[title],0,0}
                end
                if not values[x] then
                    values[x]={x,table.unpack(temp)}
                    keys[#keys+1]=x
                end
                values[x][collist[p][1]]=y
                local val=getnum(y[1])
                collist[p][2]=collist[p][2]+val
                if y[1] and y[1]~="" then
                    collist[p][3]=collist[p][3]+1
                    collist[p][4],collist[p][5]=math.min(val,collist[p][4] or val),math.max(val,collist[p][5] or val)
                end
            end
        else
            if not values[title] then values[title]=row end
            for i=2,#row do
                if #txt==0 then
                    collist[row[i]]={i,0,0}
                else
                    local col,val=collist[values[title][i]],getnum(row[i])
                    col[2]=col[2]+val
                    if row[i] and row[i]~="" and val then
                        col[3],col[4],col[5]=col[3]+1,math.min(val,col[4] or val),math.max(val,col[5] or val)
                    end
                    if not row[i] then row[i]=0 end
                end
            end
            txt[#txt+1]=table.concat(row,',')
        end
    end

    env.checkerr(counter>2,"No data found for the given criteria!")
    print(string.format("%d rows processed.",counter))

    --Print summary report
    local sorter={table.unpack(values[title],2)}
    table.sort(sorter,function(a,b)
        if collist[a][2]==collist[b][2] then return a<b end
        return collist[a][2]>collist[b][2]
    end)

    for k,v in pairs(context) do
        default_attrs[k]=v
    end
    local content,ylabels,default_ylabel = template,default_attrs._ylabels or {},default_attrs.ylabel
    local output=env.grid.new()
    output:add{"Item","Total "..(ylabels[1] or default_attrs.ylabel or ""),'|',"Rows","Appear",'%',"Min","Average","Max"}

    for k,v in pairs(collist) do
        if v[2] then
            output:add{ k,math.round(v[2],2),'|',
                        v[3],math.round(v[3]*100/(counter-1),2),'|',
                        v[4],math.round(v[2]/v[3],2),v[5]}
        else
            output:add{k,0,'|',0,0,'|',0,0,0}
        end
    end

    output:add_calc_ratio(2)
    output:sort(2,true)
    output:print(true)
    --Generate graph data
    self.dataindex,self.data=0,{}
    if pivot then
        --Sort the columns by sum(value)
        local max_series=math.min(#sorter,cfg.get('ChartSeries'))
        for idx=1,#units do
            local txt={}
            for k,v in ipairs(keys) do
                local row={values[v][1],table.unpack(temp,1,max_series)}
                for i=1,max_series do
                    local col=values[v][collist[sorter[i]][1]]
                    row[i+1]=k==1 and col or col and col[idx] or 0
                end
                txt[k]=table.concat(row,',')
            end
            self.dataindex=self.dataindex+1
            self.data[self.dataindex]=table.concat(txt,'\n')
        end
    else
        self.dataindex=self.dataindex+1
        self.data[self.dataindex]=table.concat(txt,'\n')
    end

    local replaces={
        ['@GRAPH_TITLE']=default_attrs.title,
        ['@TIME_RANGE']=default_attrs._range or ('(Range:  '..tostring(range_begin)..' ~~ '..tostring(range_end)..')')
    }

    for k,v in pairs(default_attrs) do
        if k:sub(1,1)=='_' then
            default_attrs[k]=nil
        end
    end

    default_attrs.title=nil
    for i=1,self.dataindex do
        replaces['@GRAPH_INDEX']=i
        default_attrs.ylabel=ylabels[i] or default_ylabel or units[i]
        if default_attrs.ylabel then
            default_attrs.title="Unit: "..default_attrs.ylabel
        end
        local attr=json.encode(default_attrs)
        local graph_unit=cr:replace('@GRAPH_ATTRIBUTES',attr,true)
        for k,v in pairs(replaces) do
            graph_unit=graph_unit:replace(k,v,true)
            if i==1 then
                content=content:replace(k,v,true)
            end
        end
        graph_unit=graph_unit:replace('@GRAPH_DATA',self.data[i],true)
        content=content..graph_unit
    end
    content=content.."</body></html>"
    local file=env.write_cache(cmd.."_"..os.date('%Y%m%d%H%M%S')..".html",content)
    print("Result written to "..file)
    os.shell(file)
end

local function set_param(name,value)
    return tonumber(value)
end

function graph:__onload()

end

return graph