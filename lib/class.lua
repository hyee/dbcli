local rawget,rawset,setmetatable,pairs,ipairs=rawget,rawset,setmetatable,pairs,ipairs

local function newindex(self,k,v)
    if type(v)=="function" then
        if k=="onload" or k=="onunload" or k=="__onload" or k=="__onunload" then
            local super=self.super or self.__super
            local k1='__'..k:match("(%a+)$")
            if  type(super)=="table" and type(super[k1])=="function" then
                local v1=v
                v=function(...) super[k1](...);v1(...) end
            end
        end
    end
    rawset(self,k,v)
end

function class(super,init)
    local this_class=setmetatable(init or {},
        {__newindex=newindex,
        __index=function(self,k)
            if k~='finalize' or rawget(self,'__child') then return rawget(self,k) end
            if not self.onunload then self.onunload=rawget(self,'__onunload') end
            --print(k,'->',rawget(self,'__className'))
            return rawget(self,'__onload')
        end
        })
    super=super and rawget(super,'__class') or super
    local classname=debug.getinfo(2).source:gsub("^@+","",1)
    rawset(this_class,'__className',classname)
    if type(super)=='table' then rawset(super,'__child',classname) end
    this_class.new=function(...)
        local obj={}
        local attrs,super
        rawset(obj,'__class',this_class)
        if this_class.__super then
            super,attrs = this_class.__super.new(...)
            for k,v in pairs(super) do
                if not rawget(this_class,k) and type(v)=="function" then
                    rawset(obj,k,v)
                end
            end
        else
            super,attrs={},{__base=obj}
        end
        rawset(obj,'super',super)

        attrs.__instance=obj

        for k,v in pairs(this_class) do
            if type(v)=="function" then rawset(obj,k,v) end
            rawset(attrs,k,v)
        end

        setmetatable(obj,{
            __index=attrs,
            __newindex=function(self,k,v)
                 if type(v)=="function" then
                    newindex(self,k,v)
                    v=rawget(self,k)
                 end

                 if type(v)~="function" or rawget(attrs,k)==nil then
                    rawset(attrs,k,v)
                 end
            end
        })

        local create=rawget(this_class,'ctor')
        if type(create)=="function" then create(obj,...) end
        for _,k in ipairs({'onload','onunload'}) do
            if not obj[k] then 
                obj[k]=obj['__'..k] 
            end
        end

        return obj,attrs
    end

    if type(super)=="table" and type(super.new)=="function" then
        rawset(this_class,'__super',super)
    end

    return this_class
end

return class