include("../src/JuLISP.jl")

try
    using .JuLISP
catch
end;

julisp"""
(call println (
    call + 1 3
))
(call + (
    call * 1 2
) 2)
"""

include_julisp("test.jls", true)
include_julisp("./JuLISP/test/test.jls", true)

@show pwd()
data = read("./gll_20230925211635.jl")
s = String(data)
code = Meta.parseall(s)

code.args[1]
ss = code.args


fc = filterExpr(code)
eval(fc)


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

ls = expr2LISP(test_code)
println(ls)

:(@eval x) |> filterExpr
:(@eval x).head
:(@eval x).args[1]
:(@eval x).args[2]
:(@eval x).args[3] |> filterExpr
e = :(@eval x)
ve = filter!(x -> !(x isa LineNumberNode), e.args)
map!(filterExpr, e.args, e.args)
e.args
Expr(e.head, ve...,)
Expr(e.head, e.args...)

exl = expr2LISP(code)
println(exl)
Sys.cpu_info()
Sys.CPU_NAME
Sys.ARCH
Sys.iswindows()
Sys.isapple()


s_expr2Expr(test_arr)
s_expr2Expr(test_arr) |> eval

begin
    test = """(block (call + 1 1.0) (call println 1) (macrocall @eval "x = x+1") (macrocall @doc "这是一个文档字符串" (function (call f x y) (block (return (call + x y))))))"""
    test_arr = parse_s_expr(test)
end

begin
    v = parse_s_expr("(a 1 1 \"sp ace\" 'c' symbol)")
    v[2]
    string(v)
end

:(@eval 1)
Expr(
    :macrocall,
    Symbol("@eval"),
    LineNumberNode(0, "none"),
    1
)

run_julisp(test)
run_julisp(exl)
run_julisp(quote
    a = $exl
end |> expr2LISP)
