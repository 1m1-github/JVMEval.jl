using JVM
using Documenter

DocMeta.setdocmeta!(JVM, :DocTestSetup, :(using JVM); recursive=true)

makedocs(;
    modules=[JVM],
    authors="i",
    sitename="JVM.jl",
    format=Documenter.HTML(;
        canonical="https://1m1-github.github.io/JVM.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/1m1-github/JVM.jl",
    devbranch="main",
)
