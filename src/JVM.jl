module JVMEval

using ZMQ

export JVMStruct, startjvm, eval!, readjvmbuffer!, restartjvm!, closejvm!

"""
    JVMStruct

Mutable handle to an isolated Julia process (the "virtual machine").

Contains the ZMQ sockets, output buffers, background tasks and the underlying
`Base.Process`. Created by [`startjvm`](@ref).
"""
mutable struct JVMStruct
    path::String
    insocket::Socket
    outsocket::Socket
    errsocket::Socket
    intask::Task
    outtask::Task
    errtask::Task
    outbuffer::Vector{String}
    errbuffer::Vector{String}
    process::Base.Process
end

"""
    closejvm!(jvm::JVMStruct)

Close the ZMQ sockets belonging to `jvm`.
"""
function closejvm!(jvm::JVMStruct)
    ZMQ.close(jvm.insocket)
    ZMQ.close(jvm.outsocket)
    ZMQ.close(jvm.errsocket)
    killjvm!(jvm)
end

function killjvm!(jvm::JVMStruct)
    if process_running(jvm.process)
        kill(jvm.process)
        if timedwait(() -> !process_running(jvm.process), 1.0) ≠ :ok
            kill(jvm.process, Base.SIGKILL)
        end
        wait(jvm.process)
    end
end

function initjvm(path, inpath, outpath, errpath)
    cd(path)
    ctx = Context()
    insocket = Socket(ctx, REP)
    connect(insocket, inpath)
    outsocket = Socket(ctx, PUSH)
    connect(outsocket, outpath)
    errsocket = Socket(ctx, PUSH)
    connect(errsocket, errpath)
    @async receiveandeval(insocket)
    @async jvmsend(redirect_stdout, stdout, outsocket)
    @async jvmsend(redirect_stderr, stderr, errsocket)
    wait(Condition())
end

function receiveandeval(socket)
    while true
        yield()
        code = ZMQ.recv(socket, String)
        try
            result = eval(Meta.parseall(code))
            if !isnothing(result)
                show(stdout, "text/plain", result)
                println()
            end
            flush(stdout)
            Base.Libc.flush_cstdio()
            ZMQ.send(socket, "ok")
        catch e
            @error e
            ZMQ.send(socket, "error")
        end
    end
end

function jvmsend(redirect, io, socket)
    iobak = io
    rd, wr = redirect()
    while isopen(rd)
        yield()
        data = readavailable(rd)
        isempty(data) && continue
        ZMQ.send(socket, String(data))
    end
    redirect(iobak)
    close(wr)
    close(socket)
end

"""
    startjvm(path = mktempdir()) -> JVMStruct

Start a new isolated Julia process whose working directory is a tmp dir.

The child is launched with the same project environment as the caller
(`Base.active_project()`). Returns a [`JVMStruct`](@ref) that can be used with
[`eval!`](@ref), [`readjvmbuffer!`](@ref), etc.
"""
function startjvm(path = mktempdir())
    ctx = Context()
    inpath = "ipc://$(tempname(path))"
    insocket = Socket(ctx, REQ)
    bind(insocket, inpath)
    outpath = "ipc://$(tempname(path))"
    outsocket = Socket(ctx, PULL)
    bind(outsocket, outpath)
    errpath = "ipc://$(tempname(path))"
    errsocket = Socket(ctx, PULL)
    bind(errsocket, errpath)
    project = Base.active_project()
    process = run(`$(Base.julia_cmd()) --depwarn=error -t auto --project=$(project) -e "using JVM; JVM.initjvm($(repr(path)), $(repr(inpath)), $(repr(outpath)), $(repr(errpath)))"`; wait=false)
    outbuffer = String[]
    errbuffer = String[]
    outtask = @async receivetobuffer!(outsocket, outbuffer)
    errtask = @async receivetobuffer!(errsocket, errbuffer)
    intask = Task(() -> nothing)
    JVMStruct(path, insocket, outsocket, errsocket, intask, outtask, errtask, outbuffer, errbuffer, process)
end

"""
    eval!(jvm::JVMStruct, code::AbstractString) -> String

Evaluate `code` inside the isolated process.

Returns `"ok"` on success or `"error"` on failure.
Printed output and the `show` representation of a non-`nothing` result are
pushed into `jvm.outbuffer`. Errors go into `jvm.errbuffer`.

If the process has already died, it is automatically restarted before the
evaluation.
"""
function eval!(jvm::JVMStruct, code)
    if !process_running(jvm.process)
        restartjvm!(jvm)
    end
    ZMQ.send(jvm.insocket, String(code))
    String(ZMQ.recv(jvm.insocket))
end

function receivetobuffer!(socket, buffer)
    while true
        yield()
        push!(buffer, ZMQ.recv(socket, String))
    end
end

"""
    readjvmbuffer!(buffer::Vector{String}) -> String

Drain and return the contents of a buffer (normally `jvm.outbuffer` or
`jvm.errbuffer`), then empty it.
"""
function readjvmbuffer!(buffer)
    result = join(buffer)
    empty!(buffer)
    result
end

function readjvmbuffer!(buffer)
    result = join(buffer)
    empty!(buffer)
    result
end
"""
    readjvmstdout!(jvm::JVMStruct) -> String

Drain and return the contents of the jvm stdout buffer, then empty it.
"""
readjvmstdout!(jvm::JVMStruct) = readjvmbuffer!(jvm.outbuffer)
"""
    readjvmstderr!(jvm::JVMStruct) -> String

Drain and return the contents of the jvm stderr buffer, then empty it.
"""
readjvmstderr!(jvm::JVMStruct) = readjvmbuffer!(jvm.errbuffer)

function restartjvm!(jvm::JVMStruct)
    if process_running(jvm.process)
        kill(jvm.process)
    end
    closejvm!(jvm)
    new = startjvm(jvm.path)
    jvm.insocket = new.insocket
    jvm.outsocket = new.outsocket
    jvm.errsocket = new.errsocket
    jvm.intask = new.intask
    jvm.outtask = new.outtask
    jvm.errtask = new.errtask
    jvm.outbuffer = new.outbuffer
    jvm.errbuffer = new.errbuffer
    jvm.process = new.process
    jvm
end

end
