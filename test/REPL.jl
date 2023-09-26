include("../src/JuLISP.jl")

import .JuLISP: sexpr2expr, str2sexpr, str2sexpr_atom

"""
尝试估值成S-表达式/原始值
- 应用：判断用户「是否要输入多行字符串」，兼容直接输入原始值（符号等）的做法
"""
function try_evaluate(s::AbstractString)
    # # 括号数都不相等⇒直接否决 # ! 现在不能使用「括号数」判断「是否完成」——因为有可能在注释里
    # count('(', s) === count(')', s) || return nothing
    # 先尝试解析成S-表达式
    try
        return str2sexpr(s)
    catch
    end
    # 再尝试解析成原始值
    try
        return str2sexpr_atom(s)[1]
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
        try
            # R
            printstyled(
                (isempty(input) ? "JuLISP> " : "      | "); # 多行输入的第一行与其余行不同
                color=:light_blue
            )
            input *= readline(stdin) * '\n'
            s_arr = try_evaluate(input)
            # E
            if (@inbounds input[1]) === '\n'  # 空白输入⇒自动跳过
                println()
                input = "" # 清除输入
                continue
            end
            isnothing(s_arr) || begin
                try # 执行单条命令
                    result = (
                        s_arr isa Vector ?
                        sexpr2expr(s_arr) : # S-表达式⇒进一步解析
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
                input = "" # 执行后清除输入
                println() # 执行后总是空一行
            end
            # L
        catch e
            if e isa InterruptException  # Ctrl+C中断输入
                input = ""
                println()
            else
                rethrow(e)
            end
        end
    end
end

JuLISP_REPL()
