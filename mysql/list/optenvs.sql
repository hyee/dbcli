/*[[Show main optimization configs]]*/

grid {
    [[/*grid={topic='Instance'}*/
        show variables 
        where Variable_name 
        in('sort_buffer_size',
           'thread_concurrency',
           'thread_cache_size',
           'key_buffer_size', -- index buffer
           'join_buffer_size',
           'read_buffer_size',
           'read_rnd_buffer_size' -- random read
        )
    ]], '|', [[/*grid={topic='Connections'}*/
        show variables 
        where Variable_name 
        in('max_connections',
           'max_connect_errors',
           'connect_timeout',
           'max_user_connections',
           'skip-name-resolve',
           'wait_timeout',
           'back_log'
        )
    ]], '|', [[/*grid={topic='SQL'}*/
        show variables 
        where Variable_name 
        in('query_cache_size',
           'slow_query_log',
           'tidb_enable_slow_log',
           'tidb_slow_log_threshold',
           'slow_query_log_file',
           'tidb_slow_query_file',
           'long_query_time',
           'have_query_cache'
        )
    ]], '-', [[/*grid={topic='Storage Engine'}*/
        show variables 
        where Variable_name 
        in('default_storage_engine',
           'innodb_buffer_pool_size ',
           'binlog_sync',
           'Innodb_flush_method',
           'innodb_log_buffer_size',
           'innodb_log_file_size',
           'innodb_log_files_in_group',
           'innodb_max_dirty_pages_pct',
           'log_bin',
           'max_binlog_cache_size',
           'max_binlog_size',
           'innodb_additional_mem_pool_size'
        )
    ]]
}