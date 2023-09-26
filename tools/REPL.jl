(@isdefined JuLISP) || include("../src/JuLISP.jl")

import .JuLISP: sexpr2expr, str2sexpr, str2sexpr_atom

"""
尝试估值成S-表达式/原始值
- 应用：判断用户「是否要输入多行字符串」，兼容直接输入原始值（符号等）的做法
"""
function try_evaluate(s::AbstractString)
    # 先尝试解析成S-表达式
    try
        return str2sexpr(s)
    catch
    end
    # 括号数都不相等⇒直接否决 # ! 【2023-09-27 01:51:30】现在是在「完整解析失败」时做决策，避免「把单个括号当符号」的事情发生
    count('(', s) === count(')', s) || return nothing
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
                (isempty(input) ? "julisp> " : "      | "); # 多行输入的第一行与其余行不同
                color=:light_blue, bold=true
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
                        # printstyled("      < "; color=:dark_blue) # ! 现在与Julia REPL一致，不再使用类似浏览器控制台的输出格式
                        show(stdout, "text/plain", result)
                        println() # 因为只输出值，所以需要额外换行
                    end
                    println()
                catch e # 打印堆栈
                    Base.printstyled("ERROR: "; color=:red, bold=true)
                    Base.showerror(stdout, e)
                    Base.show_backtrace(stdout, Base.catch_backtrace())
                    println()
                end
                input = "" # 执行后清除输入
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
