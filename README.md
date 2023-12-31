# JuLISP

「让写Julia如同写LISP一般」

一个（非常简单的）支持Julia Expr与S-表达式互转，从而可用LISP风格书写Julia代码的「LISP风Julia」解释器。

## 特性

- 使用LISP的风格书写Julia AST，并即时解释执行
- 使用LISP风格的单行注释`; ...`，附加更易用的多行注释`# ... #`
- 支持`include`函数，可直接读取JuLISP文件并执行其内代码
- 拥有一个简单的REPL，可以直接运行`REPL.jl`以启动交互式解释器

## 作者的话

这是一个非常小的项目。

写这个项目主要是为了复习Julia的宏功能，以及LISP风格的代码书写。

以及，最近阅读《黑客与画家》时，作者在书中提到，LISP是一种「最优雅的编程语言」——实际上，对我个人而言，最吸引我的并非其语法，而是其特性与背后的思想。

援引其中提到的「格林斯潘第十定律」（Greenspun's Tenth Rule）：
> 任何C或Fortran程序复杂到一定程度之后，都会包含一个临时开发的、只有一半功能的、不完全符合规格的、到处都是bug的、运行速度很慢的Common Lisp实现。

相比于C、C++和Java，我想Julia并不用担心这一点——Julia在很大一方面继承了LISP的各种思想（比如「数据⇔程序」「动态解释/静态编译执行均可」……）

但就在此时，心中闪念一系列想法：

> 既然Julia在「元编程」的思想上与LISP这么相似，为何不试试把用LISP的风格表达Julia的AST呢？
>
> 既然能直接表达Julia的AST，那不就能直接解释执行了么？
>
> 既然都直接能解释执行了，那我岂不是新发明了一种LISP方言？

「发明新事物，把想象变作现实」本身是我一直感兴趣并追求的，「发明新语言」也不例外。
于是，一不做二不休，这个项目就开始了。

本项目的第一版，为数小时仓促写就，唯一的「JuLISP」模块中只有「直接解释执行的`run_julisp`」「读取文件并执行其内代码的`include_julisp`」以及相应的几个字符串宏——功能实现略显粗糙，只是「应该能用」的水平。

但随着后续对LISP的了解，以及对Julia AST对象的逐渐熟络，这个项目也渐渐有了第二版。
现在的版本是在开发的第二天写成的，基本支持了所有Julia中的语言特性，并支持LISP风格的分号「;」单行注释（同时使用井号「#」实现了轻量级的多行注释）；进一步地，这个版本已经有了一个基本可用、易用的REPL，可以交互式输入并即时解释执行代码——这使得它更像一门LISP方言了。

虽说这只是自己研究需要+突发奇想做出的一个「实验产品」，但「创造了一门语言」足以让我觉得「这样的项目是有新意的」——至少也有满满的成就感。

註：本项目在写就（时间：2023-09-25 21:43:45）之时，并未在网上查阅任何有关「LISP风Julia」的信息——一切均为原创，如有雷同，纯属巧合。

若觉得这个项目有魅力，或者有什么问题，欢迎提Issues。
