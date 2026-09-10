env.var.define_column('TEXT,TEXT_VC,OWNER,OBJECT_NAME,VIEW_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
local result = obj.redirect('table')
return {
    result[1]:replace('all_tables','(SELECT CAST(NULL AS NUMBER) num_rows, view_name table_name, a.* FROM all_views a)'),
    (result[#result]:gsub('table','view'))
}
