env.var.define_column('QUERY,MVIEW_NAME','NOPRINT')
local result=obj.redirect('table')
result[#result]=result[#result]:gsub('TABLE','MVIEW')
env.table.insert(result,1,[[
    SELECT QUERY TEXT FROM ALL_MVIEWS
    WHERE OWNER=:owner AND MVIEW_NAME=:object_name     
]])
env.table.insert(result,#result,[[SELECT * FROM ALL_MVIEW_DETAIL_RELATIONS WHERE OWNER=:owner AND MVIEW_NAME=:object_name]])
return result