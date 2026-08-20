# JVM.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://1m1-github.github.io/JVM.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://1m1-github.github.io/JVM.jl/dev/)
[![Build Status](https://github.com/1m1-github/JVM.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/1m1-github/JVM.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/1m1-github/JVM.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/1m1-github/JVM.jl)

Julia Virtual Machine — run Julia code in an isolated separate process with automatic restart on crash.

Uses ZMQ for IPC. Captures stdout and stderr into buffers. Designed for reliable isolated evaluation (agents, untrusted snippets, crash-prone computations).

## Installation

```julia
using Pkg
Pkg.add("JVM")
```

Or develop locally after cloning.

## Usage

```julia
using JVM

path = mktempdir()          # working directory for the VM
jvm = startjvm(path)

status = eval!(jvm, "x = 40 + 2")
# "OK"

sleep(0.1)
out = readjvmbuffer!(jvm.outbuffer)
# contains the printed representation of the result

status = eval!(jvm, "println(\"hello\")")
out = readjvmbuffer!(jvm.outbuffer)

# if the process dies, the next eval! restarts it automatically
# or call restartjvm!(jvm) yourself

closejvm!(jvm)
kill(jvm.process)           # when finished
```

`eval!` returns `"OK"` or `"ERROR"`. Printed output and `show` of non-nothing results go into the outbuffer (and errors into errbuffer). Use `readjvmbuffer!` to drain them.

The child process is started with the same project as the parent (`Base.active_project()`), so packages available in the current environment are available inside the VM.

## Notes

- Minimal surface: string code in, status + captured streams out.
- Automatic restart on process death.

## See also

- [RemoteREPL.jl](https://github.com/JuliaWeb/RemoteREPL.jl) — interactive remote REPL with SSH support and variable transfer
- [DaemonMode.jl](https://github.com/dmolina/DaemonMode.jl) — persistent daemon for fast repeated script / expression evaluation
- [CodeEvaluation.jl](https://github.com/JuliaDocs/CodeEvaluation.jl) — same-process clean `Main`-like evaluation
- [Distributed.jl](https://docs.julialang.org/en/v1/manual/distributed-computing/) (stdlib) — full multi-process / cluster computing
