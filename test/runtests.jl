using Test
using JVMEval

@testset "JVMEval basic" begin
    jvm = startjvm()
    try
        @test process_running(jvm.process)
        status = eval!(jvm, "1 + 1")
        @test status == "ok"
        sleep(0.2)
        out = readjvmbuffer!(jvm.outbuffer)
        @test occursin("2", out)
        status = eval!(jvm, "println(\"hello from jvm\")")
        @test status == "ok"
        sleep(0.2)
        out = readjvmbuffer!(jvm.outbuffer)
        @test occursin("hello from jvm", out)
        restartjvm!(jvm)
        @test process_running(jvm.process)
        status = eval!(jvm, "2 + 2")
        @test status == "ok"
    finally
        if process_running(jvm.process)
            kill(jvm.process)
        end
        closejvm!(jvm)
        rm(path; recursive=true, force=true)
    end
end
