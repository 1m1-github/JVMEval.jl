# JVMEval.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://1m1-github.github.io/JVMEval.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://1m1-github.github.io/JVMEval.jl/dev/)
[![Build Status](https://github.com/1m1-github/JVMEval.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/1m1-github/JVMEval.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/1m1-github/JVMEval.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/1m1-github/JVMEval.jl)

Julia Virtual Machine — run Julia code in an isolated separate process with automatic restart on crash.

Uses ZMQ for IPC. Captures stdout and stderr into buffers. Designed for reliable isolated evaluation (agents, untrusted snippets, crash-prone computations).

## Installation

```julia
using Pkg
Pkg.add("JVMEval")
```

Or develop locally after cloning.

## Usage

```julia
using JVMEval

jvm = startjvm()

out = eval!(jvm, "x = 40 + 2") # 42

# if the process dies, the next eval! restarts it automatically
run(`kill $(getpid(jvm.process))`)

eval!(jvm, "println(\"hello\")") # ""
out = readstdout!(jvm) # "hello\n"

closejvm!(jvm) # closes the ZMQ sockets and kills the Julia process
```

`eval!(jvm, code)` returns `string(eval(Meta.parseall(code)))` or `"error"`. Printed output goes into the outbuffer (and errors into errbuffer). Use `readstdout!` and `readstderr!` to drain them.

The child process is started with the same project as the parent (`Base.active_project()`), so packages available in the current environment are available inside the VM.

## Notes

- Minimal surface: string code in, status + captured streams out.
- Automatic restart on process death.

## See also

- [RemoteREPL.jl](https://github.com/JuliaWeb/RemoteREPL.jl) — interactive remote REPL with SSH support and variable transfer
- [DaemonMode.jl](https://github.com/dmolina/DaemonMode.jl) — persistent daemon for fast repeated script / expression evaluation
- [CodeEvaluation.jl](https://github.com/JuliaDocs/CodeEvaluation.jl) — same-process clean `Main`-like evaluation
- [Distributed.jl](https://docs.julialang.org/en/v1/manual/distributed-computing/) (stdlib) — full multi-process / cluster computing

The main difference of `JVMEval` vs the above existing `Pkg`s is that `JVMEval` starts a independent `Julia` process, uses `ZMQ` to ssend `eval` commands and receive both `stdout` and `stderr` and restarts a new `Julia` process in case the old one crashed.
