# 离散随机变量
struct RandomVarDiscrete{N,R} <: Number
    disp::Dict{N,R}

    RandomVarDiscrete(pairs::Vararg{Pair{<:N,<:R}}) where {N,R<:Real} = RandomVarDiscrete{N,R}(pairs...)

    function RandomVarDiscrete{N,R}(pairs::Vararg{Pair{<:N,<:R}}) where {N,R<:Real}
        sum::Real = zero(R)
        for (n, p) in pairs
            # 验证所有概率的非负0~1性
            0 <= p <= 1 || error("$(n)的概率值$(p)非法")
            # 验证所有概率之和为1
            sum += p
        end
        sum == 1 || error("参数集$(pairs)的概率值总和$(sum)不为1")
        return new{N,R}(Dict{N,R}(pairs...))
    end

    """
    用于类型转换
    - 兼容一些`RandomVarDiscrete{Number, Real}`转`RandomVarDiscrete{Int64, Rational{BigInt}}`的问题
    - 隐式使用在`convert`上
    """
    RandomVarDiscrete{N,R}(rv::RandomVarDiscrete{N2,R2}) where {N,R,N2,R2} = new{N,R}(Dict{N,R}(rv.disp))
end

"可迭代对象展开"
RandomVarDiscrete(arr::Union{AbstractArray,Tuple,Base.Generator})::RandomVarDiscrete = RandomVarDiscrete(arr...)

# 别名
RVD{N,R} = RandomVarDiscrete{N,R} where {N,R}

# 复制
Base.copy(x::T) where {T<:RandomVarDiscrete} = T(x.disp...)

# 标准化
function regularize!(d::Dict{N,R})::Dict{N,R} where {N,R}
    s::R = sum(values(d))
    for (k, _) in d
        d[k] /= s
    end
    return d
end

function regularize!(rv::RVD{N,R})::RVD{N,R} where {N,R}
    regularize!(rv.disp)
    return rv
end

"获取概率：有则作概率，无则0(重载getindex歧义！)"
(P(rv::RVD{N,R}, n::N)::R) where {N,R} = Base.get(rv.disp, n, zero(R))
(Base.get(rv::RVD{N,R}, n::N)::R) where {N,R} = P(rv, n)

"添加概率，使得在这一点的概率为其定值"
function Base.setindex!(rv::RVD{N,R}, n::N, p::R) where {N,R}
    rv.disp[n] = rv.disp[n] += p / (1 - p)
    regularize!(rv)
end

# 应用映射：值改变，概率不变
"一元就地"
function apply!(f, X::RVD{N,R})::RVD{N,R} where {N,R}
    # 键值对的键改变了
    d2 = copy(X.disp)
    for (n, p) in X.disp
        # 「是概率对应的值」被映射了，而不是「概率」被映射了
        d2[f(n)] = p # 这其中f(n)可能不再与n是一个类型
    end
    empty!(X.disp)
    merge!(X.disp, d2)
    return X
end

"一元非就地"
# (apply(f, X::RVD{N,R})::RVD{N,R}) where {N,R} = apply!(f, copy(X))
(apply(f, X::RVD{N,R})::RVD{N,R}) where {N,R} = RVD(
    f(n) => p
    for (n::N, p::R) in X.disp
)
# @show f X collect(keys(X.disp))[1] f(collect(keys(X.disp))[1])
# a = [
#     f(n) => p
#     for (n::N, p::R) in X.disp
# ]
# RVD(
#     @show a
# )

# 迁移自Dict的显示方法
function Base.show(io::IO, t::RVD{N,R}) where {N,R}
    recur_io = IOContext(
        io, :SHOWN_SET => t,
        :typeinfo => eltype(t)
    )

    limit = get(io, :limit, false)::Bool
    # show in a Julia-syntax-like form: Dict(k=>v, ...)
    print(io, Base.typeinfo_prefix(io, t)[1])
    print(io, '(')
    if !isempty(t) && !Base.show_circular(io, t)
        first = true
        n = 0
        for pair in t.disp
            first || print(io, ", ")
            first = false
            show(recur_io, pair)
            n += 1
            limit && n >= 10 && (print(io, "…"); break)
        end
    end
    print(io, ')')
end

"广播"
(apply(f, k::Number, X::RVD{N,R})::RVD{N,R}) where {N,R} = apply(x -> f(k, x), X)
(apply(f, X::RVD{N,R}, k::Number)::RVD{N,R}) where {N,R} = apply(x -> f(x, k), X)

"""
多元非就地(独立)
"""
function apply(f, Xs::Vararg{RVD})::RVD
    local d::Dict = Dict()
    local fv
    # 提升类型
    P = promote_type((X -> typeof(X.disp).parameters[2]).(Xs)...)
    # 遍历应用
    for pairs::Tuple{Vararg{Pair}} in Iterators.product((X -> X.disp).(Xs)...)
        fv = f(first.(pairs)...)
        d[fv] = get(d, fv, zero(P)) + *(last.(pairs)...) # 增量：假设随机变量相互独立，便是如此
    end

    # 计算类型
    N = promote_type((d |> keys |> collect .|> typeof)...)
    # 转换类型！！！
    return RVD{N,P}(
        ( # 不能直接用生成器，否则「no method matching RandomVarDiscrete{Rational{Int64}, Real}(::Base.Generator{Dict{Any, Any}, var"#9#10"{DataType, DataType}})」
            k => v
            for (k::N, v::P) in d
        )...
    )
end

"判等：等号用于分派随机变量, `isequal`也不能动（不要再指定类型了……）"
(isequalRV(X::RVD, Y::RVD)::Bool) = X.disp == Y.disp

# 运算符重载
operators::Vector{Symbol} = [
    :(+)
    :(-)
    :(*)
    :(/)
    :(÷)
    :(∈)
    :(//)
    :(^)
    :(>)
    :(<)
    :(<=)
    :(>=)
    :(≤)
    :(≥)
    :(==)
    :(!=)
    :(≠)
]

for op::Symbol in operators
    # 多个随机变量（使用Vararg的话，会有「类型提升错误」）：promotion of types Int64 and RandomVarDiscrete{Int64, Rational{Int64}} failed to change any arguments
    @eval Base.$(op)(X::RVD, Y::RVD, others::Vararg{RVD}) = apply(Base.$op, X, Y, others...)
    @eval Base.$(op)(X::RVD, Y::RVD, others::Vararg{RVD}) = apply(Base.$op, X, Y, others...)
    # 和数值的广播
    @eval Base.$(op)(n::Number, X::RVD) = apply(Base.$op, n, X)
    @eval Base.$(op)(X::RVD, n::Number) = apply(Base.$op, X, n)
    # 对于下面的「整数乘方」，为了「消歧义」
    @eval Base.$(op)(n::Integer, X::RVD) = apply(Base.$op, n, X)
    @eval Base.$(op)(X::RVD, n::Integer) = apply(Base.$op, X, n)
end

# 期望
E(X::RVD{N,R}) where {N,R} = begin
    l = [
        n * p
        for (n::N, p::R) in X.disp
    ]
    return sum(l)
end

# Cov(X::RVD{N,R}, Y::RVD{N,R}) = 

# 方差
# "方差：原始定义"
# D(X::RVD{N,R}) where {N,R} = begin
#     e = E(X)
#     sum(
#         ((n - e)^2) * p
#         for (n, p) in X.disp
#     )
# end
"方差：数学等价于「平方の期望-期望の平方」"
D(X::RVD{N,R}) where {N,R} = E(X^2) - E(X)^2

"协方差"
Cov(X::RVD{N,R}, Y::RVD{N,R}) where {N,R} = E((X - E(X)) * (Y - E(Y)))

# 测试
X::RVD{<:Number,<:Real} = RVD{Number,Real}(1 => 1 // 2, 2 => 1 // 2)
Y::RVD{<:Number,<:Real} = RVD{Number,Real}(1 => 1 // 3, 2 => 2 // 3)
Z::RVD{<:Number,<:Real} = RVD{Number,Real}(1 => 1 // 4, 2 => 3 // 4)
# @show RandomVarDiscrete(1 => 0.5, 2 => 1//4, 3 => -1//4) # 非法
# @show RandomVarDiscrete(1 => 0.5, 2 => 1//4, 3 => 0.35) # 不为一
begin # 基础运算
    @info "期望、方差、协方差" E(X) D(X) Cov(X, Y)
    @info "和" X + Y E(X + Y) D(X + Y)
    @info "期望の和=和の期望" E(X + Y) == E(X) + E(Y) E(X + Y + Z) == E(X) + E(Y) + E(Z)
    @info "加法交换律&乘法交换律" X + 2 2 + X X + 2 == 2 + X X * 2 2 * X == X * 2 2 * X
    @info "加乘组合运算" 2X - Y
    @info "方差=平方の期望-期望の平方" E(X^2) - E(X)^2
end

begin # 二重随机变量Ⅰ
    "随机变量の随机变量" # 这里的精度过高，Int64会溢出，所以要用BigInt
    XY = RVD(X => 1 // 2, Y => 1 // 2)
    @info "二重随机变量的「期望」「方差」仍然是一个随机变量（一重随机变量）" E(XY) D(XY)
    @show "二重随机变量的「二重期望」「二重方差」「方差の期望」「期望の方差」终于是一个数了" E(E(XY)) D(D(XY)) E(D(XY)) D(E(XY))
end

begin
    @info "对乘法满足交换律" X * Y Y * X isequalRV(X * Y, Y * X)
    @info "对乘法满足结合律" (X * Y) * Z X * (Y * Z) isequalRV((X * Y) * Z, X * (Y * Z))
    @info "不满足乘加分配律" (X + Y) * Z X * Z + Y * Z isequalRV((X + Y) * Z, X * Z + Y * Z)
    @info "对数值仅部分满足" (X + Y) * 3 X * 3 + Y * 3 isequalRV((X + Y) * 3, X * 3 + Y * 3) (1 + 2) * Z 1 * Z + 2 * Z isequalRV((1 + 2) * Z, 1 * Z + 2 * Z)
    #= 
        这里的表示方式是不同的
            每一次随机变量的出现，都意味着出现了一个「独立的维度」
            二维≠一维，所以是不能等价的
    =#
    @info "平方不等于自乘" X^2 X * X isequalRV(X^2, X * X)
    @info "完全平方公式失效" X^2 + 2X + 1 (X + 1) * (X + 1) (X + 1)^2 isequalRV(X^2 + 2X + 1, (X + 1)^2) isequalRV(X^2 + 2X + 1, (X + 1) * (X + 1))
end

begin # 二重随机变量Ⅱ
    "随机变量の随机变量：XYZ版"
    W = RVD(X => 1 // 3, Y => 1 // 3, Z => 1 // 3)
    @info "期望、方差还是随机变量（一重）" E(W) D(W)
    @info "二重期望与二重方差" E(E(W)) D(D(W))
    @info "方差の期望🆚期望の方差" E(D(W)) D(E(W))
end

begin # 逻辑运算
    @info "等号运算" X Y Z X == Y Y == Z X == Z
    @info "算不等式" X > Y X < Y
    @info "分式构造" X // Y
    @info "区间构造" apply(:, X, Y, Z)
    @info "配对构造" apply(Pair, X, Y)
    @info "元组构造" apply(tuple, X, Y, Z)
    @info "数组构造" apply(collect ∘ tuple, X, Y, Z)
end
