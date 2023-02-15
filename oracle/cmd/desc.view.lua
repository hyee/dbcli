env.var.define_column('TEXT,TEXT_VC,OWNER,OBJECT_NAME,VIEW_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
local result=obj.redirect('table')
return {
    result[1],
    (result[#result]:gsub('TABLE','VIEW'))
}