module JVMEval

using ZMQ, Serialization

export startjvm, eval!, readstdout!, readstderr!, closejvm!, restartjvm!

const NOK = "__DATATYPE_UNKWOWN_TO_LOOPOS_JVM__"

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
    eval!(jvm::JVMStruct, code::AbstractString) -> Any

Evaluate `code` inside the isolated process.

Returns the eval result xor its string representation on success xor the error xor its string representation on failure.
Printed output is pushed into `jvm.outbuffer`. Errors go into `jvm.errbuffer`.

If the process has already died, it is automatically restarted before the
evaluation.
"""
function eval!(jvm::JVMStruct, code)
    if !process_running(jvm.process)
        restartjvm!(jvm)
    end
    ZMQ.send(jvm.insocket, String(code))
    message = ZMQ.recv(jvm.insocket)
    buffer = IOBuffer(message)
    try 
        deserialize(buffer)
    catch _
        NOK
    end
end

function receiveandeval(socket)
    while true
        yield()
        code = ZMQ.recv(socket, String)
        result = try
            Base.invokelatest(Core.eval, Main, Meta.parseall(code))
        catch e
            @error e
            e
        end
        buffer = IOBuffer()
        serialize(buffer, result)
        ZMQ.send(socket, take!(buffer))
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

function receivetobuffer!(socket, buffer)
    while true
        yield()
        push!(buffer, ZMQ.recv(socket, String))
    end
end

function readbuffer!(buffer)
    result = join(buffer)
    empty!(buffer)
    result
end
"""
    readstdout!(jvm::JVMStruct) -> String

Drain and return the contents of the jvm stdout buffer, then empty it.
"""
readstdout!(jvm::JVMStruct) = readbuffer!(jvm.outbuffer)
"""
    readstderr!(jvm::JVMStruct) -> String

Drain and return the contents of the jvm stderr buffer, then empty it.
"""
readstderr!(jvm::JVMStruct) = readbuffer!(jvm.errbuffer)

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

"""
    startjvm(path = mktempdir()) -> JVMStruct

Start a new isolated Julia process whose working directory is a tmp dir.

The child is launched with the same project environment as the caller
(`Base.active_project()`). Returns a [`JVMStruct`](@ref) that can be used with
[`eval!`](@ref), [`readstdout!`](@ref), [`readstderr!`](@ref), etc.
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
    process = run(`$(Base.julia_cmd()) --depwarn=error -t auto --project=$project -e "using JVMEval;JVMEval.initjvm($(repr(path)), $(repr(inpath)), $(repr(outpath)), $(repr(errpath)))"`; wait=false)
    outbuffer = String[]
    errbuffer = String[]
    outtask = @async receivetobuffer!(outsocket, outbuffer)
    errtask = @async receivetobuffer!(errsocket, errbuffer)
    intask = Task(() -> nothing)
    JVMStruct(path, insocket, outsocket, errsocket, intask, outtask, errtask, outbuffer, errbuffer, process)
end

"""
    restartjvm!(jvm::JVMStruct) -> JVMStruct

Kill the current process (if still running) and start a fresh one in the same
working directory. The `JVMStruct` is updated in-place.
"""
function restartjvm!(jvm::JVMStruct)
    if process_running(jvm.process)
        kill(jvm.process)
    end
    closejvm!(jvm)
    newjvm = startjvm(jvm.path)
    jvm.insocket = newjvm.insocket
    jvm.outsocket = newjvm.outsocket
    jvm.errsocket = newjvm.errsocket
    jvm.intask = newjvm.intask
    jvm.outtask = newjvm.outtask
    jvm.errtask = newjvm.errtask
    jvm.outbuffer = newjvm.outbuffer
    jvm.errbuffer = newjvm.errbuffer
    jvm.process = newjvm.process
    jvm
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

end
