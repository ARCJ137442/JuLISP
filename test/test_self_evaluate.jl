"""
自举测试：
    1. 把自身源码转换成JuLISP
    2. 再反向解析并执行JuLISP
    3. 结果：二者的运行效果应该一致
"""

# 尝试引入测试集 #
try # 如果能，就引入作为「真正的`@test`」
    using Test
catch # 否则使用`@assert`代替`@test`
    eval(Expr(:(=), Symbol("@test"), Symbol("@assert")))
end

# 解决路径问题
rootPath = (
    ispath("src") ? "." : # 始终在JuLISP的根目录下
    ".."
)

# 自身源码⇒JuLISP⇒等价Julia模块 #

# 无JuLISP⇒导入JuLISP
(@isdefined JuLISP) || begin
    # include("../src/JuLISP.jl")
    push!(LOAD_PATH, "$rootPath/src")
    import JuLISP as JLS
end


# 把源码转换成JuLISP
JuLISP_julia_text::String = read("$rootPath/src/JuLISP.jl") |> String
jls::String = JuLISP_julia_text |> Meta.parseall |> JLS.expr2JuLISP
# 保存
write("$rootPath/test/JuLISP.jls", jls)

# 加载JuLISP数据
jls_code::Expr = read("$rootPath/test/JuLISP.jls") |> String |> JLS.parse
@test jls_code == JLS.parse(jls) # 两次解析使用同一代码文本，理应相同

# 解析用JuLISP表示的JuLISP解释器
@show eval(jls_code)
@test (@isdefined JuLISP) # 此时已经定义了JuLISP
const JLS_by_jls = JuLISP
@show JuLISP.run(jls) # 再用「编译成Julia AST」后的JuLISP代码覆盖一次

# 比对这三个模块：应该彼此不同
@test JLS !== JuLISP
@test JLS !== JLS_by_jls
@test JuLISP !== JLS_by_jls


# 用「从JuLISP解析出来的JuLISP解析器」再回解释JuLISP代码 #

# 三个模块的解析器理应解释出相同的Julia AST，并且与一开始「直接读取源码文件，并使用Meta.parse解析出的Julia AST」相同
@test jls_code == JLS.parse(jls) == JLS_by_jls.parse(jls) == JuLISP.parse(jls)

# 三个模块应该能把相同的AST转换成相同的JuLISP文本，并且与「直接把Julia代码转换成的JuLISP文本」相同
let julisp_texts = [JLS.julia2julisp(JuLISP_julia_text)]
    push!(
        julisp_texts,
        (
            m.expr2JuLISP(jls_code)
            for m in [JLS, JLS_by_jls, JuLISP]
        )...
    )
    @show julisp_texts .|> length
    for t1 in julisp_texts, t2 in julisp_texts
        @test t1 === t2 # 两两相等，即便长度不恒定
    end
end

println("It's done.")
