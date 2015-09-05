#!/bin/bash
:<<DESC
This is the comment zone that can be identified by DBCLI, should be enclosed by "DESC".
DESC
pwd
echo 1
echo First  parameter is $1
echo Second parameter is `echo $2`
echo Third  parameter is `echo $3`
echo Fourth parameter is `echo $4`