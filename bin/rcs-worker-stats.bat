@echo off

set CWD=%CD%
cd /D C:\RCS\DB

ruby bin\rcs-worker-stats %*

cd /D %CWD%
