include("../src/JuLISP.jl")

import .JuLISP: s_expr2Expr, parse_s_expr, parse_s_expr_atom

"""
尝试估值成S-表达式/原始值
- 应用：判断用户「是否要输入多行字符串」，兼容直接输入原始值（符号等）的做法
"""
function try_evaluate(s::AbstractString)
    # 括号数都不相等⇒直接否决
    count('(', s) === count(')', s) || return nothing
    # 先尝试解析成S-表达式
    try
        return parse_s_expr(s)
    catch
    end
    # 再尝试解析成原始值
    try
        return parse_s_expr_atom(s)[1]
    catch
    end
    # 返回空值
    return nothing
end

function JuLISP_REPL(eval_F::Function=Main.eval)

    local input::String = ""
    local s_expr::Any
    local result::Any

    while true
        # R
        isempty(input) && printstyled("JuLISP> "; color=:light_blue)
        input *= readline(stdin) * '\n'
        s_arr = try_evaluate(input)
        # E
        isnothing(s_arr) || begin
            try # 执行单条命令
                result = (
                    s_arr isa Vector ?
                    s_expr2Expr(s_arr) : # S-表达式⇒进一步解析
                    s_arr # 原始值⇒直接计算
                ) |> eval_F
                # P
                isnothing(result) || begin
                    printstyled("      < "; color=:dark_blue)
                    show(result)
                end
                println()
            catch e # 打印堆栈
                Base.printstyled("ERROR: "; color=:red, bold=true)
                Base.showerror(stdout, e)
                Base.show_backtrace(stdout, Base.catch_backtrace())
                println()
            end
            println()
            input = ""
        end
        # L
    end
end

JuLISP_REPL()
