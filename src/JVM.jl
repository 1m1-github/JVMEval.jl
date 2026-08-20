module JVM

using ZMQ

export JVMStruct, startjvm, eval!, readjvmbuffer!, restartjvm!, closejvm!

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

function closejvm!(jvm::JVMStruct)
    ZMQ.close(jvm.insocket)
    ZMQ.close(jvm.outsocket)
    ZMQ.close(jvm.errsocket)
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
            ZMQ.send(socket, "OK")
        catch e
            @error e
            ZMQ.send(socket, "ERROR")
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

function startjvm(path)
    ctx = Context()
    inpath = "ipc://$(tempname())"
    insocket = Socket(ctx, REQ)
    bind(insocket, inpath)
    outpath = "ipc://$(tempname())"
    outsocket = Socket(ctx, PULL)
    bind(outsocket, outpath)
    errpath = "ipc://$(tempname())"
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

function readjvmbuffer!(buffer)
    result = join(buffer)
    empty!(buffer)
    result
end

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
