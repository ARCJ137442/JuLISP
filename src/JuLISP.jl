"""
主模块
- 利用Julia与LISP相似的语言特性，把Julia的语法以LISP的风格重现
  - 可将Julia的抽象语法树「正向转换」成类LISP的S-表达式（故称「JuLISP」）
  - 亦可将字符串形式的「JuLISP」反向解析成Julia代码

一些需要特殊注意的语法@2023-09-26：
- （Julia原无）使用`(Q ...)`或`Expr(:Q, ...)`表示原先的QuoteNode类型（当然用函数调用也非不可）
- 该语言基本继承了LISP系的注释（单行注释「;」），但使用类似字符串的`# ... #`表示多行注释
"""
module JuLISP

# Julia AST⇒JuLISP文本
export expr2JuLISP
# JuLISP文本⇒S-表达式
export s_expr, str2sexpr, str2sexpr_all
# S-表达式⇒Julia AST
export sexpr2expr, parse_julisp
# 面向用户
export julia2julisp, run_julisp, include_julisp, @julisp_str, @jls_str

begin
    "Julia代码 => Julia AST => JuLISP"

    "把表达式里面的LineNumberNode全部去掉——即便是变成构造函数，也不应影响代码"
    filter_expr(e::Any) = e
    filter_expr(e::Expr) = Expr(
        e.head,
        map(filter_expr, filter(x -> !(x isa LineNumberNode), e.args))...
    )

    "默认的缩进单元：四个空格"
    const DEFAULT_INDENT_UNIT::String = "    "

    """
    将Julia语法树转换成Lisp风格，简称「JuLISP」
    - 可选的「缩进层级」与「缩进单元」（空白符的种类与长度不影响语义）
    """
    expr2JuLISP(s::String; kw...)::String = repr(s) # 自动带上括弧
    expr2JuLISP(c::Char; kw...)::String = repr(c) # 自动带上括弧
    expr2JuLISP(c::Cmd; kw...)::String = repr(c) # 自动带上括弧
    expr2JuLISP(i::Integer; kw...)::String = repr(i)
    expr2JuLISP(f::AbstractFloat; kw...)::String = repr(f)
    expr2JuLISP(s::Symbol; kw...)::String = String(s)
    "主代码：数组⇒批量加入+子缩进递增"
    expr2JuLISP(args::Vector; indent::Int=1, indent_unit::AbstractString=DEFAULT_INDENT_UNIT)::String = join(
        filter!(
            !isempty, # 非空过滤
            [
                expr2JuLISP(ex; indent=indent + 1) # 批量转换，缩进+1
                for ex in args
            ]
        ), _expr_indent(indent_unit, indent)
    )
    "删掉LineNumberNode（暂时的？）"
    expr2JuLISP(lnn::LineNumberNode; indent::Int=1, indent_unit::AbstractString=DEFAULT_INDENT_UNIT)::String = ""
    "主代码之一：拆分成「头」「参数集」"
    expr2JuLISP(e::Expr; indent::Int=1, indent_unit::AbstractString=DEFAULT_INDENT_UNIT)::String = (
        "($(e.head)$(_expr_indent(indent_unit, indent))$(expr2JuLISP(e.args; indent=indent)))"
    )
    "📌这个在文档字符串中出现。【2023-09-26 16:26:09】目前的解决办法：转换为「Code.var\"@doc\"」"
    expr2JuLISP(gr::GlobalRef; kw...)::String = expr2JuLISP(Expr(
            :.,
            Symbol(gr.mod),
            Expr(:quote, Symbol(gr.name))
        ); kw...) #= 这里需要继续传参 =#
    "处理「串联引用」的情况" # 这个其实更像LISP的「quote」列表
    expr2JuLISP(qn::QuoteNode; kw...)::String = expr2JuLISP(
        Expr(:Q, qn.value); # `qn.value`会在后续被遍历到
        kw...
    )

    "生成缩进"
    _expr_indent(unit::AbstractString, n::Integer; newline::Bool=true)::String = (
        (newline ? "\n" : "") * unit^n # （换行）+n*单元
    )

end

begin
    "JuLISP => S-Expr"

    # "设置「原子对象」的类型"
    const JuLISPAtom = Union{Symbol,String,Char,Number,Bool}

    """
    字符串 → S-表达式の值
    - 若其中含有空白符，需要使用引号转义
        - 示例：`123 123` --> `"123 123"`
        - 转义：使用`Base.repr`方法
        - 逆转义：使用`Meta.parse`方法（不执行代码）
    """
    s_expr(str::AbstractString; always_escape::Bool=false)::AbstractString = (
        always_escape || any(isspace, str) ?
        Base.repr(str) : # 需要转义
        str # 无需转义
    )

    """
    原生数组→S-表达式

    示例：
        `["A", "sp ace", ["2", "3"], "B"]` --> `(A "sp ace" (2 3) B)`
    """
    s_expr(obj::Vector{Union{Vector,JuLISPAtom}}; always_escape::Bool=false)::String = '(' * join(s_expr.(obj; always_escape), ' ') * ')'

    "开/闭括弧 + 引号 + 注释标识"
    const S_EXPR_OPEN_BRACKET::Char = '('
    const S_EXPR_CLOSE_BRACKET::Char = ')'
    const S_EXPR_QUOTE::Char = '"'
    const S_EXPR_SEMI_QUOTE::Char = '\''
    const S_EXPR_BACK_QUOTE::Char = '`'
    const S_EXPR_COMMENT_SINGLE::Char = ';'
    const S_EXPR_COMMENT_SINGLE_END::Char = '\n' # 单行注释的终止符是换行符，没毛病
    const S_EXPR_COMMENT_MULTILINE::Char = '#'

    """
    S-表达式 → Tuple{Vararg{Vector}}（主入口）
    """
    function str2sexpr_all(str::AbstractString)::Tuple{Vararg{Vector}}

        # * 直接用局部变量
        str = strip(str)

        "返回值类型"
        exprs::Vector{Vector} = []

        "起始值"
        local tempSExpr::Vector, next_start::Int = _str2sexpr(str, 1)
        while !isempty(str)
            # 新增结果
            push!(exprs, tempSExpr)
            # * 裁剪表达式之间的空白符（若有）
            str = strip(@view str[nextind(str, next_start, 1):end])
            # * 裁剪没了⇒解析完成⇒结束
            if isempty(str)
                return tuple(exprs...)
            end
            # 删去前面的字符
            # * 继续计算（注意：索引需要步进）
            tempSExpr, next_start = _str2sexpr(str,)
        end
        error("你似乎来到了没有结果的荒原")
    end

    """
    S-表达式 → 数组（单个）
    - 参数集：
        - str：被解析的字符串整体
        - start：解析的开始位置
            - 决定会在解析到何时停止（与start位置同级的下一个闭括弧）
            - 用于递归解析

    示例：`(A (B C D) E "spa ce" 'c')` --> `[:A, [:B, :C, :D], :E, "spa ce", 'c']`
    """
    str2sexpr(str::AbstractString)::Vector = _str2sexpr(str)[1] # [1]是「最终结果」

    """
    内部的解析逻辑：
    - 返回: (值, 原字串str上解析的最后一个索引)

    参考：LISP的注释语法
    - 几乎所有LISP方言均使用分号「; ...」作为单行注释
    - 进一步地，Common LISP还能使用「#| ... |#」作为多行注释
    
    目前的注释方案（2023-09-26）
    - 在解析「原子值」时判断「是否为注释」⇒注释起始符与原子符间不能没有空白符
    - 参考一众LISP方言，使用「;」作为单行注释
    - 参考Common LISP，更简单地使用「# ... #」作为多行注释
    """
    function _str2sexpr(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Vector,Int}
        # 判断首括弧
        s[start] === S_EXPR_OPEN_BRACKET || throw(ArgumentError("S-表达式必须以『(』为起始字符：$s"))

        local result::Vector{Union{Vector,JuLISPAtom}} = []
        local i::Int = start
        local si::Char
        local next_index::Int

        while true
            # 先步进，跳过start处的开括弧
            i = nextind(s, i)

            # nextind在lastindex时也会正常工作，但此时返回的新索引会跳转到
            i > end_i && error("在索引「$start:$i:$end_i」处发现无效的S-表达式「$s」$result")

            # 获取当前字符
            si = s[i]

            # * 中途遇到字串外开括弧：递归解析下一层，并将返回值添加进「内容」
            if si === S_EXPR_OPEN_BRACKET
                # 递归解析
                vec::Vector, i_sub_end = _str2sexpr(s, i; end_i) # （复用end_i变量）
                # 添加值
                push!(result, vec)
                # 跳过已解析处，步进交给前面
                i = i_sub_end
                # * 中途遇到字串外闭括弧（一定是同级闭括弧）：结束解析，返回值
            elseif si === S_EXPR_CLOSE_BRACKET
                return result, i # 闭括弧所在处
            # * 非空白、非括弧字符：注释|原子值
            elseif !isspace(si) # 注释：单行与多行
                # 识别并跳过注释
                if si === S_EXPR_COMMENT_SINGLE # 单行注释（跳过终止符，但这不影响后续解析）
                    i_sub_end = str2sexpr_skip_comment(
                        S_EXPR_COMMENT_SINGLE_END,
                        s, i; end_i
                    )
                elseif si === S_EXPR_COMMENT_MULTILINE # 多行注释
                    i_sub_end = str2sexpr_skip_comment(
                        S_EXPR_COMMENT_MULTILINE,
                        s, i; end_i
                    )
                else
                    # 解析原子值
                    str::JuLISPAtom, i_sub_end = str2sexpr_atom(s, si; start_i=i, end_i)
                    # 添加值
                    push!(result, str)
                end
                # 跳过已解析处
                i = i_sub_end
            end
            # 空白符⇒跳过
        end
    end

    """
    特殊：解析S-表达式中的原子值（表达式）
    - 未转义：开头无引号
    - 已转义：开头有引号(另外实现，同时包括用单引号括起来的「字符」)
    - 数字：开头是数值字符（整数/浮点数在更细一步的地方判断）
    - ⚠只关注「是否有空格/是否遇到未转义引号」，不检测括弧

    返回值：
    - (解析好的字符串/符号值/数值（需要转义的也已经转义）, 原字串str上解析的最后一个索引)

    示例：
    `A123` --> :A123
    `137.442` --> 137.442
    `'c'` --> 'c'
    `"sp ace()"` --> "sp ace()"
    """
    str2sexpr_atom(s::AbstractString, si::AbstractChar=s[1]; start_i=1, end_i::Int=lastindex(s))::Tuple{JuLISPAtom,Int} = (
        # 双引号⇒字符串（复用end_i变量）
        si === S_EXPR_QUOTE ? _parse_escaped_s_expr_string(s, start_i; end_i) :
        # 单引号⇒字符（复用end_i变量）
        si === S_EXPR_SEMI_QUOTE ? _parse_escaped_s_expr_char(s, start_i; end_i) :
        # 反引号⇒字符（复用end_i变量）
        si === S_EXPR_BACK_QUOTE ? _parse_escaped_s_expr_cmd(s, start_i; end_i) :
        # 数字⇒数值（复用end_i变量）
        isdigit(si) ? _parse_s_expr_number(s, start_i; end_i) :
        # 指定开头⇒布尔值
        startswith(s[start_i:end], "true") ? (true, nextind(s, start_i, 3)) :
        startswith(s[start_i:end], "false") ? (false, nextind(s, start_i, 4)) :
        # 否则⇒符号
        _str2sexpr_symbol(s, start_i; end_i)
    )

    """
    特殊：解析S-表达式中的符号
    """
    function _str2sexpr_symbol(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Symbol,Int}
        # 初始化
        local start_i::Int = start # 用于字符串截取
        local i::Int = start
        local si::Char = s[i] # 当前字符

        # 一路识别到第一个空白字符/闭括弧（不允许「f(x)」这样的紧凑格式）
        while !isspace(si) && si != S_EXPR_CLOSE_BRACKET
            i = nextind(s, i) # 直接步进
            i > end_i && error("无效的S-表达式符号「$s」")
            si = s[i] # 更新si
        end # 循环退出时，s[i]已为空白符

        # 返回符号
        return Symbol(@view s[start_i:prevind(s, i)]), prevind(s, i) # 最后一个非空白字符处
    end

    """
    解析「需要转义的字符串」
    - start：需转义字符串在一开始所处的位置（左侧引号「"」的位置）
    """
    _parse_escaped_s_expr_string(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{String,Int} = _parse_escaped_s_expr_str(
        S_EXPR_QUOTE, s, start; end_i
    )

    """
    解析「需要转义的字符」

    【2023-09-26 15:10:31】现在需要考虑解决「偶数个转义符」的情况
    - 如`'asd fgh \\\\'`
    """
    _parse_escaped_s_expr_char(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Char,Int} = _parse_escaped_s_expr_str(
        S_EXPR_SEMI_QUOTE, s, start; end_i
    )

    """
    解析「需要转义的命令」
    - start：需转义字符串在一开始所处的位置（左侧引号「`」的位置）
    """
    _parse_escaped_s_expr_cmd(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{String,Int} = _parse_escaped_s_expr_str(
        S_EXPR_BACK_QUOTE, s, start; end_i
    )

    """
    通用的解析「前后引用」的方式
    - 字符串「"」
    - 字符「'」
    - 命令「`」
    """
    function _parse_escaped_s_expr_str(embrace::AbstractChar, s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Any,Int}
        # 初始化
        local num_backslash::Int = 0

        local start_i::Int = nextind(s, start) # 用于字符串截取
        local i::Int = start_i
        i > end_i && error("无效的S-表达式串「$s」")

        # 跳转到下一个非「\'」的「'」
        while true
            si = s[i]
            # 反斜杠计数
            if si === '\\'
                num_backslash += 1
            else
                # 终止条件：非转义单引号&偶数个反斜杠
                if si == embrace && iseven(num_backslash)
                    # 直接调用Julia解析器返回相应的原子值
                    return Meta.parse(@view s[start:i]), i
                end
                # 非反斜杠⇒清零
                num_backslash = 0
            end
            # 步进
            i = nextind(s, i)
            i > end_i && error("无效的S-表达式串「$s」")
        end
    end

    """
    专用的「跳过注释」方式
    - 单行注释「; ... \\n」
    - 多行注释「# ... #」
    """
    function str2sexpr_skip_comment(terminal::AbstractChar, s::AbstractString, start::Integer=1; end_i::Int=lastindex(s))::Int
        # 初始化
        local i::Int = nextind(s, start)
        i > end_i && error("无效的S-表达式注释「$s」")

        # 跳转到下一个非「\'」的「'」
        while true
            si = s[i]
            # 终止条件：特定的终止符
            si === terminal && return i # 返回的是终止符的位置
            # 步进
            i = nextind(s, i)
            i > end_i && error("无效的S-表达式注释「$s」")
        end
    end

    "解析数值"
    function _parse_s_expr_number(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Number,Int}
        # 初始化
        local i::Int = nextind(s, start)
        i > end_i && error("无效的S-表达式数值「$s」")

        # 跳转到下一个非「\'」的「'」
        while true
            si = s[i]
            # 终止条件：空格/闭括弧
            if isspace(si) || si === S_EXPR_CLOSE_BRACKET
                # 直接调用Julia的解析函数 # ! 但要记得把解析后的「数值外的索引」还回去
                return Meta.parse(@view s[start:prevind(s, i, 1)]), prevind(s, i, 1)
            end
            # 步进
            i = nextind(s, i)
            i > end_i && error("无效的S-表达式数值「$s」")
        end
    end

end

begin
    "S-Expr => Julia AST"

    "（只会在:macrocall语境下执行）识别是否是先前打包的GlobalRef"
    _isPackedGlobalRef(v::Vector) = (
        length(v) > 1 &&
        (@inbounds v[1]) === :call &&
        (@inbounds v[2]) === :GlobalRef
    )

    "数组类型⇒取头映射 | 对「宏调用」添加行号"
    function sexpr2expr(s_arr::Vector{Union{Vector,JuLISPAtom}}; l_num::Int=0)::Union{Expr,QuoteNode}
        length(s_arr) < 1 && error("表达式「$s_arr」至少得有一个元素！")
        return (
            # * 处理宏调用 :macrocall
            (@inbounds s_arr[1]) === :macrocall ? Expr(
                (@inbounds s_arr[1]),
                ( # ! 处理GlobalRef
                # _isPackedGlobalRef(s_arr[2]) ? eval(s_arr[2])
                    sexpr2expr(s_arr[2])
                ),
                # ! 宏调用必须得有「上下文信息」即LineNumberNode
                LineNumberNode(l_num, "none"),
                map(sexpr2expr, @inbounds s_arr[3:end])...
            ) :
            # * 处理引用节点 :Q => QuoteNode
            (@inbounds s_arr[1]) === :Q ? QuoteNode(
                sexpr2expr(s_arr[2])
            ) :
            # * 正常解析
            Expr(
                (@inbounds s_arr[1]),
                map(sexpr2expr, @inbounds s_arr[2:end])...
            )
        )
    end

    "基础类型⇒原样返回"
    sexpr2expr(s_val::JuLISPAtom)::JuLISPAtom = s_val

    """
    类似`Meta.parse`，把JuLISP字符串转换成Julia表达式
    - 不会像`Meta.parse`那样对顶层的多个表达式报错
    """
    parse_julisp(str::AbstractString)::Expr = str |> str2sexpr |> sexpr2expr

    "（不导出）上面`parse_julisp`的别名"
    parse(str::AbstractString)::Expr = parse_julisp(str)

    "类似`Meta.parseall`：会自动把「多个文本」"
    parseall_julisp(str::AbstractString)::Expr = str |> str2sexpr_all .|> sexpr2expr |> _auto_toplevel
    parseall(str::AbstractString)::Expr = parseall_julisp(str)

    "自动根据「表达式是否只有一个」添加「顶层」表达式头:toplevel"
    _auto_toplevel(exs::Tuple{Vararg{Expr}})::Expr = (
        length(exs) === 1 ? (@inbounds exs[1]) :
        Expr(:toplevel, exs...)
    )

end

begin
    "临门一脚：组合&执行"

    """
    Julia源码⇒JuLISP
    原理：Meta.parse + 
    """
    julia2julisp(julia_code::AbstractString)::AbstractString = julia_code |> Meta.parseall |> expr2JuLISP

    """
    （无错误检查功能）入口方法：运行JuLISP代码
    """
    run_julisp(str::AbstractString; eval_F::Function=Main.eval)::Any = (
        str|>str2sexpr_all.|>sexpr2expr.|>eval_F
    )[end] # 所有表达式都会依次执行，但只取最后一个结果

    "（不导出）上面`run_julisp`的别名"
    run(str::AbstractString; eval_F::Function=Main.eval)::Any = run_julisp(str; eval_F)

    """
    入口方法：运行JuLISP代码
    - 逻辑：将JuLISP代码解析成S-表达式，再翻译成Julia AST，然后直接执行
      - 其返回值同Julia，也是最后一个表达式返回的值
    - 参数 `tryEval`：是否使用try-catch的方式运行代码
      - 不提供⇒直接解释执行
      - `true`⇒每次try & catch后继续执行
      - `false`⇒每次try & catch后不再执行
    """
    function run_julisp(str::AbstractString, try_eval::Bool; eval_F::Function=Main.eval)::Any
        local exprs::Tuple{Vararg{Expr}} = str |> str2sexpr_all .|> sexpr2expr
        local current_result::Any
        for expr::Expr in exprs
            try
                current_result = eval_F(expr)
            catch e
                @error "执行表达式时出错！" expr e
                # 清空「当前返回值」
                current_result = nothing
                # false⇒不再继续执行
                try_eval || break
            end
        end
        # 所有表达式都会依次执行，但只取最后一个结果
        return current_result
    end

    "写一个字符串宏，直接执行✓"
    function JuLISP_str_macro(str::AbstractString; eval_F::Function=Main.eval)::Expr
        return :(
            run_julisp($str)
        )
    end

    "通过简单的字符串调用，自动解释执行JuLISP代码"
    macro julisp_str(str::AbstractString)
        return JuLISP_str_macro(str)
    end

    "（简写名）通过简单的字符串调用，自动解释执行JuLISP代码"
    macro jls_str(str::AbstractString)
        return JuLISP_str_macro(str)
    end

    "读取一个文件，自动解释执行其中的JuLISP代码"
    include_julisp(path::AbstractString, args...; kw...)::Any = run_julisp(path |> read |> String, args...; kw...)

    "（不导出）上面`include_julisp`的别名"
    include(str::AbstractString, args...; kw...)::Any = include_julisp(str, args...; kw...)

end

end # module
