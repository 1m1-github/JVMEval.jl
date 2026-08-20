using JVMEval
using Documenter

DocMeta.setdocmeta!(JVMEval, :DocTestSetup, :(using JVMEval); recursive=true)

makedocs(;
    modules=[JVMEval],
    authors="i",
    sitename="JVMEval.jl",
    format=Documenter.HTML(;
        canonical="https://1m1-github.github.io/JVMEval.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/1m1-github/JVMEval.jl",
    devbranch="main",
)
