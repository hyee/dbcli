/*****************************************************************************************
   
    EDB360 - Enkitec's Oracle Database 360-degree View
    edb360_copyright (C) 2014  Carlos Sierra

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

*****************************************************************************************/
@@edb360_0a_main.sql
-- esp_requirements is already on main zip. commands below are just to cleanup (remove from file system) the esp files when edb360 is executed on just one database
HOS zip -mT esp_requirements_&&esp_host_name_short..zip res_requirements_&&rr_host_name_short..txt esp_requirements_&&esp_host_name_short..csv cpuinfo_model_name.txt
<<<<<<< HEAD
HOS zip -mT esp_requirements_&&esp_host_name_short..zip res_requirements_stp_&&rr_host_name_short._&&ecr_collection_key..txt esp_requirements_stp_&&esp_host_name_short._&&ecr_collection_key..csv
=======
>>>>>>> origin/master
HOS zip -mT &&edb360_main_filename._&&edb360_file_time. esp_requirements_&&esp_host_name_short..zip
-- list of generated files
HOS unzip -l &&edb360_main_filename._&&edb360_file_time.
PRO "End edb360. Output: &&edb360_main_filename._&&edb360_file_time..zip"