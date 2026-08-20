using Test
using JVMEval

@testset "JVMEval basic" begin
    jvm = startjvm()
    try
        @test process_running(jvm.process)
        status = eval!(jvm, "1 + 1")
        @test status == "ok"
        sleep(0.2)
        out = readjvmstdout!(jvm)
        @test occursin("2", out)
        status = eval!(jvm, "println(\"hello from jvm\")")
        @test status == "ok"
        sleep(0.2)
        out = readjvmstdout!(jvm)
        @test occursin("hello from jvm", out)
        JVMEval.restartjvm!(jvm)
        @test process_running(jvm.process)
        status = eval!(jvm, "2 + 2")
        out = readjvmstdout!(jvm)
        @test status == "ok"
        @test occursin("4", out)
    finally
        closejvm!(jvm)
        rm(jvm.path; recursive=true, force=true)
    end
end
