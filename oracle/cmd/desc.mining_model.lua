env.var.define_column("model_name","noprint")
return {
    [[SELECT /*topic="ALL_MINING_MODELS"*/ /*PIVOT*/ *
      FROM   all_mining_models a
      WHERE  owner = :owner
      AND    model_name = :object_name]],
    [[SELECT /*topic="ALL_MINING_MODEL_SETTINGS"*/ *
      FROM   all_mining_model_settings a
      WHERE  owner = :owner
      AND    model_name = :object_name
      ORDER  BY setting_name]],
    [[SELECT /*topic="ALL_MINING_MODEL_ATTRIBUTES"*/ *
      FROM   all_mining_model_attributes a
      WHERE  owner = :owner
      AND    model_name = :object_name]],
    [[SELECT /*topic="ALL_MINING_MODEL_XFORMS"*/ *
      FROM   all_mining_model_xforms
      WHERE  owner = :owner
      AND    model_name = :object_name
      ORDER  BY attribute_name]],
    [[SELECT /*topic="ALL_MINING_MODEL_TABLES"*/ *
      FROM   all_mining_model_tables
      WHERE  owner = :owner
      AND    model_name = :object_name
      ORDER  BY table_name]],
    [[SELECT /*topic="ALL_MINING_MODEL_VIEWS"*/ *
      FROM   all_mining_model_views
      WHERE  owner = :owner
      AND    model_name = :object_name
      ORDER  BY view_name]]
}
