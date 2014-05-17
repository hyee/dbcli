local string,table=string,table

local java=java


function string.initcap(v)
	return (' '..v):lower():gsub("([^%w])(%w)",function(a,b) return a..b:upper() end):sub(2)
end

--Continus sep would return empty element
function string.split (s, sep, plain)
	local r={}
	for v in s:gsplit(sep,plain) do
		r[#r+1]=v
	end
	return r
end


function string.gsplit(s, sep, plain)
	local start = 1
	local done = false
	local function pass(i, j, ...)
		if i then
			local seg = s:sub(start, i - 1)
			start = j + 1
			return seg, ...
		else
			done = true
			return s:sub(start)
		end
	end
	return function()
		if done then return end
		if sep == '' then done = true return s end
		return pass(s:find(sep, start, plain))
	end
end

function string.trim(s,sep)
	if sep==' ' then sep=' \t\n\v\f\r' end
	local p=p2[sep]
	if not p then
		local space = lpeg.S(sep)
 		local nospace = 1 - space
 		p = space^0 * lpeg.C((space^0 * nospace^1)^0)
 		p2[sep]=p
	end
	return p:match(s)
end

local str=java.require("java.lang.String")
--this function only support %s
function string.fmt(base,...)
    local args = {...}
    for k,v in ipairs(args) do
      if type(v)~="string" then
        args[k]=tostring(v)
      end
    end
    return str:format(base,table.unpack(args))
end

function table.unpack(tab)
	return unpack(tab)
end

function string.from(v)
	local path=_G.WORK_DIR
  	path=path and #path or 0
	if type(v) == "function" then
      	local d=debug.getinfo(v)
      	local src=d.short_src:sub(path+1)
      	if src and src~='' then
      		return 'function('..src:gsub('%.lua$','#'..d.linedefined)..')'
      	end
    elseif type(v) == "string" then
    	return ("%q"):format(v:gsub("\t","    "))
    end
    return tostring(v)
end

local weekmeta={__mode='k'}
local globalweek=setmetatable({},weekmeta)
function table.weak(reuse)
	return reuse and globalweek or setmetatable({},weekmeta)
end

function table.append(tab,...)
	for i=1,select('#',...) do
		tab[#tab+1]=select(i,...)
	end
end

local function compare(a,b)
	local t1,t2=type(a[1]),type(b[1])
	if t1==t2 and t1~='table' and t1~='function' and t1~='userdata' then return a[1]<b[1] end
	if t1=="number" then return true end
	if t2=="number" then return false end
	return tostring(a[1])<tostring(b[1])
end

function math.round(num,digits)  
  return math.floor(10^digits*num+0.5)/(10^digits)
end

function table.dump(tbl,indent,maxdep,tabs)  	
  	maxdep=tonumber(maxdep) or 9
  	if maxdep<=1 then
  		return tostring(tbl)
  	end

  	if tabs==nil then
  		tabs={}
  	end

  	if not indent then indent = '' end
  	
  	indent=string.rep(' ',type(indent)=="number" and indent or #indent)
  	
  	local ind = 0
  	local pad=indent..'  '
  	local maxlen=0
  	local keys={}

    local fmtfun=string.format
  	for k,_ in pairs(tbl) do
      local k1=k
      if type(k)=="string" and not k:match("^[%w_]+$") then k1=string.format("[%q]",k) end
  		keys[#keys+1]={k,k1}
  		if maxlen<#tostring(k1) then maxlen=#tostring(k1) end
  		if maxlen>99 then 
	  		 fmtfun=string.fmt
	  	end
  	end

  	table.sort(keys,compare)
  	local rs=""
  	for _, k in ipairs(keys) do
  		v,k=tbl[k[1]],k[2]
      local fmt =(ind==0 and "{ " or pad)  .. fmtfun('%-'..maxlen..'s%s' ,tostring(k),'= ')
      local margin=(ind==0 and indent or '')..fmt
    	rs=rs..fmt
    	if type(v) == "table" then
    		if tabs then 
    			if not tabs[v] then
		    		local c=tabs.__current_key or ''
		    		local c1=c..(c=='' and '' or '.')..tostring(k)
		    		tabs[v],tabs.__current_key=c1,c1
		      		rs=rs..table.dump(v,margin,maxdep-1,tabs)
		      		tabs.__current_key=c
		      	else
		      		rs=rs..'<<Refer to '..tabs[v]..'>>'
		      	end
		    else
		    	rs=rs..table.dump(v,margin,maxdep-1,tabs)
	      	end
      	elseif type(v) == "function" then
      		rs=rs..'<'..string.from(v)..'>'
      	elseif type(v) == "userdata" then
      		rs=rs..'<userdata('..tostring(v)..')>'
      	elseif type(v) == "string" then
      		rs=rs..string.format("%q",v:gsub("\n","\n"..string.rep(" ",#margin)))
    	else
      		rs=rs..tostring(v)  
    	end
    	rs=rs..',\n'
    	ind=ind+1
  	end
  	if ind==0 then return  '{}' end
  	rs=rs:sub(1,-3)..'\n'
  	if ind<2 then return rs:sub(1,-2)..' }' end
  	return rs..indent..'}'
end

return {}