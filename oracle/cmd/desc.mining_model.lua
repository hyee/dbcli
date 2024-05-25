env.var.define_column("model_name","noprint")
return {
    [[select /*topic="all_mining_model_settings"*/ * from all_mining_model_settings a where owner=:owner and model_name=:object_name order by setting_name]],
    [[select /*topic="all_mining_model_attributes"*/ * from all_mining_model_attributes a where owner=:owner and model_name=:object_name]],
    [[select /*topic="all_mining_model_xforms"*/ * from all_mining_model_xforms where owner=:owner and model_name=:object_name order by attribute_name]],
    [[select /*topic="dba_mining_model_tables"*/ * from dba_mining_model_tables where owner=:owner and model_name=:object_name order by table_name]],
    [[select /*topic="dba_mining_model_views"*/ * from dba_mining_model_views where owner=:owner and model_name=:object_name order by view_name]]
}