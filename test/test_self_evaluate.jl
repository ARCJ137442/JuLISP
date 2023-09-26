# 导入
include("../src/JuLISP.jl")
using .JuLISP

#= # 把源码转换成JuLISP
jls = read("src/JuLISP.jl") |> String |> Meta.parseall |> JuLISP.expr2JuLISP
# 保存
write("test/JuLISP.jls", jls) =#

# 加载JuLISP数据
ex::Expr = read("test/JuLISP.jls") |> String |> JuLISP.parse
@show ex
eval(ex)
