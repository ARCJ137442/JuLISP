# JuLISP-Translation: 根据传入的参数，把指定的所有Julia脚本转译成JuLISP脚本
(@isdefined JuLISP) || include("../src/JuLISP.jl")

"文件：读取⇒解析⇒转译⇒保存"
@inline function julisp_translate_file(path::AbstractString)
    try
        # 分析并更改路径 #
        local file_name::AbstractString = basename(path)
        # 新路径：直接替换`.jl`到`.jls`| 追加扩展名`.jls`
        new_file_name::String = (
            length(file_name) > 2 && (@inbounds file_name[end-2:end] == ".jl") ? file_name * "s" : # 就是.jl"s"
            file_name * ".jls"
        ) # * 目前使用`.jls`作为JuLISP脚本的扩展名
        local new_path::String = joinpath(dirname(path), new_file_name) # 新路径=旧父路径+新文件名

        # 读取Julia中间码
        local julia_AST::Expr = path |> read |> String |> Meta.parseall
        # 任一地方读取错误⇒报错
        any(
            ex isa Expr && ex.head === :error
            for ex in julia_AST.args
        ) && error("Error: parse \"$path\" failed: $(julia_AST.args[1])")

        # 开始使用Julia语法解析，并在转译后直接写入
        write(
            new_path,
            # 顶层有多个符号⇒拆分成多份→转换→合并入一起
            julia_AST.head === :toplevel ? join(
                julia_AST.args .|> JuLISP.expr2JuLISP, # 这里不用all了
                '\n' # 用换行符分隔
            ) :
            # 没有「顶层」符号⇒直接转换语法树
            JuLISP.expr2JuLISP(julia_AST)
        )
        @info "Translated $path => $new_path"
    catch e # 打印堆栈
        Base.printstyled("TRANSLATION ERROR: "; color=:red, bold=true)
        Base.showerror(stdout, e)
        Base.show_backtrace(stdout, Base.catch_backtrace())
    end
end

"文件夹：递归遍历"
@inline function julisp_translate_folder(path::AbstractString)
    # 使用`readdir`遍历文件夹下所有路径
    for file_name in readdir(path)
        julisp_translate(@show joinpath(path, file_name))
    end
    isempty(ARGS) || @info "文件夹「$path」翻译完成！"
end

"主转译函数"
function julisp_translate(paths...)
    for path::AbstractString in paths
        # 文件夹 ? 翻译其中所有文件 : 正常文件
        if isdir(path)
            julisp_translate_folder(path)
        else
            julisp_translate_file(path)
        end
    end
end

julisp_translate(ARGS...)
isempty(ARGS) || @info "所有文件翻译完成！"
