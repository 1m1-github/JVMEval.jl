using Test
using JVMEval

@testset "JVMEval basic" begin
    jvm = startjvm()
    try
        @test process_running(jvm.process)
        out = eval!(jvm, "1 + 1")
        @test out == 2
        out = eval!(jvm, "println(\"hello from jvm\")")
        @test isnothing(out)
        sleep(0.2)
        out = readstdout!(jvm)
        @test out == "hello from jvm\n"
        JVMEval.restartjvm!(jvm)
        @test process_running(jvm.process)
        out = eval!(jvm, "2 + 2")
        @test out == 4
    finally
        closejvm!(jvm)
        rm(jvm.path; recursive=true, force=true)
    end
end
