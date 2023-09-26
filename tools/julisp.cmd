@echo off
@REM 把当前目录设置为cmd脚本所在的目录
cd /d %~dp0
@REM 使用「%*」把所有传入的参数注入到Julia脚本中
julia.exe .\julisp.jl %*
