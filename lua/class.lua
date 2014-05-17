local rawget,rawset,setmetatable=rawget,rawset,setmetatable

function class(super)
	local this_class={}
	this_class.new=function(...) 
		local obj={}
		obj.__class=this_class
		obj.super=this_class.__super and this_class.__super.new(...) or {}
		obj=setmetatable(obj,{
			__index=function(self,k) return self.__class[k] or self.super[k] end,
			__newindex=function(self,k,v)
				if self.super[k] and type(self.super[k])~='function' and type(v)~='function' then
					self.super[k]=v
				else
					rawset(self,k,v)
				end
			end
		})
		local create=rawget(this_class,'ctor')
		if create then create(obj,...) end

		return obj
	end

	if type(super)=="table" and type(super.new)=="function" then	
		this_class.__super=super
		this_class=setmetatable(this_class,{__index=super})
	end
	
	return this_class
end

return class