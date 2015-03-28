-- edb360 configuration file. for those cases where you must change edb360 functionality

/*************************** ok to modify (if really needed) ****************************/

-- history days (default 31)
DEF edb360_conf_days = '31';

-- range of dates below superceed history days when values are other than YYYY-MM-DD
DEF edb360_conf_date_from = 'YYYY-MM-DD';
DEF edb360_conf_date_to = 'YYYY-MM-DD';
--DEF edb360_conf_date_from = '2015-03-01';
--DEF edb360_conf_date_to = '2015-03-10';

-- working hours are defined between these two HH24MM values (i.e. 7:30AM and 7:30PM)
DEF edb360_conf_work_hours_from = '0730';
DEF edb360_conf_work_hours_to = '1930';

/**************************** not recommended to modify *********************************/

-- excluding report types reduce usability while providing marginal performance gain
DEF edb360_conf_incl_html = 'Y';
DEF edb360_conf_incl_text = 'Y';
DEF edb360_conf_incl_csv = 'Y';
DEF edb360_conf_incl_line = 'Y';
DEF edb360_conf_incl_pie = 'Y';

-- excluding awr reports substantially reduces usability with minimal performance gain
DEF edb360_conf_incl_awr_rpt = 'Y';
DEF edb360_conf_incl_addm_rpt = 'Y';
DEF edb360_conf_incl_ash_rpt = 'Y';
DEF edb360_conf_incl_tkprof = 'Y';

-- top sql to execute further diagnostics (range 0-128)
DEF edb360_conf_top_sql = '32';
DEF edb360_conf_planx_top = '32';
DEF edb360_conf_sqlmon_top = '24';
DEF edb360_conf_sqlash_top = '0';
DEF edb360_conf_sqlhc_top = '0';
DEF edb360_conf_sqld360_top = '8';
