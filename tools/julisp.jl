# 根据传入的参数，执行指定JuLISP脚本 | 启动JuLISP REPL
(@isdefined JuLISP) || include("../src/JuLISP.jl")

if isempty(ARGS)
    # 无参数⇒REPL
    include("REPL.jl")
else
    # 有参数⇒只执行第一个文件，并删除这个参数
    popfirst!(ARGS) |> JuLISP.include_julisp
end
