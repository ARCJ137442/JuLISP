# 解决路径问题
rootPath = (
    ispath("src") ? "." : # 始终在JuLISP的根目录下
    ".."
)

# 先进行「自举测试」
# include("../src/JuLISP.jl")
include("test_self_evaluate.jl")

try
    using .JuLISP
catch
end

julisp"""
(call +
    (call sqrt (
        call + 1 3))
    (call + 
        (call * 1 2) 
        2))
"""

include_julisp("$rootPath/test/test.jls", true)

# 「概率论」测试
@show pwd()
data = read("$rootPath/test/probabilities_20230925211635.jl")
s = String(data)
code = Meta.parseall(s)

code.args[1]
ss = code.args


test_code = quote
    1 + 1.0
    println(1)
    @eval "x = x+1"

    "这是一个文档字符串"
    function f(x, y)
        return x + y
    end
end
dump(test_code)
test_code.args[8].args[1].name
test_code.args[8].args[1].mod
test_code.args[8].args[1].binding
eval(test_code)

exl = expr2JuLISP(code)
println(exl)
run_julisp(exl)
