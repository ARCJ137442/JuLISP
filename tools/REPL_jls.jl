# 现场解释执行REPL，不需要Julia源码
(@isdefined JuLISP) || include("../src/JuLISP.jl")
JuLISP.include_julisp("REPL.jls")
