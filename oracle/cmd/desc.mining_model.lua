env.var.define_column("model_name","noprint")
return {
    [[select /*topic="ALL_MINING_MODELS"*/ /*PIVOT*/ * from all_mining_models a where owner=:owner and model_name=:object_name]],
    [[select /*topic="ALL_MINING_MODEL_SETTINGS"*/ * from all_mining_model_settings a where owner=:owner and model_name=:object_name order by setting_name]],
    [[select /*topic="ALL_MINING_MODEL_ATTRIBUTES"*/ * from all_mining_model_attributes a where owner=:owner and model_name=:object_name]],
    [[select /*topic="ALL_MINING_MODEL_XFORMS"*/ * from all_mining_model_xforms where owner=:owner and model_name=:object_name order by attribute_name]],
    [[select /*topic="ALL_MINING_MODEL_TABLES"*/ * from all_mining_model_tables where owner=:owner and model_name=:object_name order by table_name]],
    [[select /*topic="ALL_MINING_MODEL_VIEWS"*/ * from all_mining_model_views where owner=:owner and model_name=:object_name order by view_name]]
}