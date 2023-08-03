env.var.define_column('TEXT,TEXT_VC,OWNER,OBJECT_NAME,VIEW_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')
local result=obj.redirect('table')
return {
    result[1]:replace('all_tables','(select cast(null as number) num_rows,view_name table_name,a.* from all_views a)'),
    (result[#result]:gsub('TABLE','VIEW'))
}