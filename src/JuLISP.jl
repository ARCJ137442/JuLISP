"""
主模块
- 利用Julia与LISP相似的语言特性，把Julia的语法以LISP的风格重现
  - 可将Julia的抽象语法树「正向转换」成类LISP的S-表达式（故称「JuLISP」）
  - 亦可将字符串形式的「JuLISP」反向解析成Julia代码
- ⚠注意：目前的「正向转换」在处理QuoteNode即「\$」的特性上仍不完善
  - 若想贡献可参照
"""

# begin
module JuLISP

export filterExpr, expr2JuLISP
export s_expr, parse_s_expr, parse_s_expr_all
export s_expr2Expr
export run_julisp, include_julisp, @julisp_str, @jls_str

begin
    "Julia代码 => Julia AST => JuLISP"

    "把表达式里面的LineNumberNode全部去掉——即便是变成构造函数，也不应影响代码"
    filterExpr(e::Any) = e
    filterExpr(e::Expr) = Expr(
        e.head,
        map(filterExpr, filter(x -> !(x isa LineNumberNode), e.args))...
    )

    "将Julia语法树转换成Lisp风格，简称「JuLISP」"
    expr2JuLISP(s::String)::String = "\"$s\""
    expr2JuLISP(s::Char)::String = "\'$s\'"
    expr2JuLISP(s::Integer)::String = string(s)
    expr2JuLISP(s::AbstractFloat)::String = string(s)
    expr2JuLISP(s::Symbol)::String = String(s)
    expr2JuLISP(args::Vector)::String = join(filter!(!isempty, [expr2JuLISP(ex) for ex in args]), " ")
    expr2JuLISP(lnn::LineNumberNode)::String = ""
    expr2JuLISP(e::Expr)::String = "($(e.head) $(expr2JuLISP(e.args)))"
    "这个在文档字符串中出现，似乎没有什么解决方法。。。。"
    expr2JuLISP(gr::GlobalRef)::String = String(gr.name)
    "处理「串联引用」的情况"
    expr2JuLISP(qn::QuoteNode)::String = expr2JuLISP(Expr(:$, qn.value))

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

    "开/闭括弧 + 引号"
    const S_EXPR_OPEN_BRACKET::Char = '('
    const S_EXPR_CLOSE_BRACKET::Char = ')'
    const S_EXPR_QUOTE::Char = '"'
    const S_EXPR_SEMI_QUOTE::Char = '\''

    """
    S-表达式 → Tuple{Vararg{Vector}}（主入口）
    """
    function parse_s_expr_all(str::AbstractString)::Tuple{Vararg{Vector}}

        # * 直接用局部变量
        str = strip(str)

        "返回值类型"
        exprs::Vector{Vector} = []

        "起始值"
        local tempSExpr::Vector, next_start::Int = _parse_s_expr(str, 1)
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
            tempSExpr, next_start = _parse_s_expr(str,)
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
    parse_s_expr(str::AbstractString)::Vector = _parse_s_expr(str)[1] # [1]是「最终结果」

    """
    内部的解析逻辑：
    - 返回: (值, 原字串str上解析的最后一个索引)
    """
    function _parse_s_expr(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Vector,Int}
        # 判断首括弧
        s[start] == S_EXPR_OPEN_BRACKET || throw(ArgumentError("S-表达式必须以『(』为起始字符：$s"))

        local result::Vector{Union{Vector,JuLISPAtom}} = Union{Vector,String}[]
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
            if si == S_EXPR_OPEN_BRACKET
                # 递归解析
                vec::Vector, i_sub_end = _parse_s_expr(s, i; end_i=end_i) # （复用end_i变量）
                # 添加值
                push!(result, vec)
                # 跳过已解析处，步进交给前面
                i = i_sub_end
                # 中途遇到字串外闭括弧（一定是同级闭括弧）：结束解析，返回值
            elseif si == S_EXPR_CLOSE_BRACKET
                return result, i # 闭括弧所在处
            # * 非空白、非括弧字符：解析原子值
            elseif !isspace(si)
                # 递归解析
                str::JuLISPAtom, i_sub_end = parse_s_expr_atom(s, si; start_i=i, end_i=end_i)
                # 添加值
                push!(result, str)
                # 跳过已解析处
                i = i_sub_end
            end
            # 空白符⇒跳过
        end
    end

    parse_s_expr_atom(s::AbstractString, si::AbstractChar=s[1]; start_i=1, end_i=lastindex(s))::Tuple{JuLISPAtom,Int} = (
        # 双引号⇒字符串（复用end_i变量）
        si === S_EXPR_QUOTE ? _parse_escaped_s_expr_string(s, start_i; end_i) :
        # 单引号⇒字符（复用end_i变量）
        si === S_EXPR_SEMI_QUOTE ? _parse_escaped_s_expr_char(s, start_i; end_i) :
        # 数字⇒数值（复用end_i变量）
        isdigit(si) ? _parse_escaped_s_expr_number(s, start_i; end_i) :
        # 否则⇒符号
        _parse_s_expr_symbol(s, start_i; end_i)
    )

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
    `"spac e()"` --> "spac e()"
    """
    function _parse_s_expr_symbol(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Symbol,Int}
        # 初始化
        local start_i::Int = start # 用于字符串截取
        local i::Int = start
        local si::Char = s[i] # 当前字符

        # 一路识别到第一个空白字符/闭括弧（不允许「f(x)」这样的紧凑格式）
        while !isspace(si) && si != S_EXPR_CLOSE_BRACKET
            i = nextind(s, i) # 直接步进
            i > end_i && error("无效的S-表达式「$s」")
            si = s[i] # 更新si
        end # 循环退出时，s[i]已为空白符

        # 返回符号
        return Symbol(@view s[start_i:prevind(s, i)]), prevind(s, i) # 最后一个非空白字符处
    end

    """
    解析「需要转义的字符串」
    - start：需转义字符串在一开始所处的位置（左侧引号「"」的位置）
    """
    function _parse_escaped_s_expr_string(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{String,Int}
        # 初始化
        local last_si::Char = s[start] # 这时候是引号

        local start_i::Int = nextind(s, start) # 首先步进，用于字符串截取
        local i::Int = start_i
        i > end_i && error("无效的S-表达式「$s」")

        # 跳转到下一个非「\"」的「"」
        while true
            si = s[i]
            # 终止条件：非转义引号
            if si == S_EXPR_QUOTE && last_si != '\\'
                # 返回逆转义后的字符串(截取包括引号)
                return Meta.parse(@view s[start:i]), i
            end
            # 步进
            last_si = s[i]
            i = nextind(s, i)
            i > end_i && error("无效的S-表达式「$s」")
            si = s[i]
        end
    end

    """
    解析「需要转义的字符」
    """
    function _parse_escaped_s_expr_char(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Char,Int}
        # 初始化
        local last_si::Char = s[start]

        local start_i::Int = nextind(s, start) # 用于字符串截取
        local i::Int = start_i
        i > end_i && error("无效的S-表达式「$s」")

        # 跳转到下一个非「\'」的「'」
        while true
            si = s[i]
            # 终止条件：非转义单引号
            if si == S_EXPR_SEMI_QUOTE && last_si != '\\'
                # 直接调用Julia解析器返回相应的原子值
                return Meta.parse(@view s[start:i]), i
            end
            # 步进
            last_si = s[i]
            i = nextind(s, i)
            i > end_i && error("无效的S-表达式「$s」")
            si = s[i]
        end
    end

    "解析数值"
    function _parse_escaped_s_expr_number(s::AbstractString, start::Integer=1; end_i=lastindex(s))::Tuple{Number,Int}
        # 初始化
        local last_si::Char = s[start]

        local start_i::Int = nextind(s, start) # 用于字符串截取
        local i::Int = start_i
        i > end_i && error("无效的S-表达式「$s」")

        # 跳转到下一个非「\'」的「'」
        while true
            si = s[i]
            # 终止条件：空格/闭括弧
            if isspace(si) || si === S_EXPR_CLOSE_BRACKET
                # 直接调用Julia的解析函数 # ! 但要记得把解析后的「数值外的索引」还回去
                return Meta.parse(@view s[start:prevind(s, i, 1)]), prevind(s, i, 1)
            end
            # 步进
            last_si = s[i]
            i = nextind(s, i)
            i > end_i && error("无效的S-表达式「$s」")
            si = s[i]
        end
    end

end

begin
    "S-Expr => Julia AST"


    "数组类型⇒取头映射 | 对「宏调用」添加行号"
    function s_expr2Expr(s_arr::Vector{Union{Vector,JuLISPAtom}}; l_num::Int=0)::Expr
        length(s_arr) < 1 && error("表达式「$s_arr」至少得有一个元素！")
        return (
            (@inbounds s_arr[1]) === :macrocall ?
            Expr( # ! 宏调用必须得有「上下文信息」即LineNumberNode
                (@inbounds s_arr[1]),
                s_arr[2],
                LineNumberNode(l_num, "none"),
                map(s_expr2Expr, @inbounds s_arr[3:end])...
            ) :
            Expr(
                (@inbounds s_arr[1]),
                map(s_expr2Expr, @inbounds s_arr[2:end])...
            )
        )
    end

    "基础类型⇒原样返回"
    s_expr2Expr(s_val::JuLISPAtom)::JuLISPAtom = s_val

end

"""
（无错误检查功能）入口方法：运行JuLISP代码
"""
run_julisp(str::AbstractString; eval_F::Function=Main.eval)::Any = (
    str|>parse_s_expr_all.|>s_expr2Expr.|>eval_F
)[end] # 所有表达式都会依次执行，但只取最后一个结果

begin
    "临门一脚：组合&执行"

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
        local exprs::Tuple{Vararg{Expr}} = str |> parse_s_expr_all .|> s_expr2Expr
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

end

end # module
