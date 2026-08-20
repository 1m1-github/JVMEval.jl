using Test
using JVM

@testset "JVM basic" begin
    path = mktempdir()
    jvm = startjvm(path)
    try
        @test process_running(jvm.process)
        status = eval!(jvm, "1 + 1")
        @test status == "OK"
        sleep(0.2)
        out = readjvmbuffer!(jvm.outbuffer)
        @test occursin("2", out)
        status = eval!(jvm, "println(\"hello from jvm\")")
        @test status == "OK"
        sleep(0.2)
        out = readjvmbuffer!(jvm.outbuffer)
        @test occursin("hello from jvm", out)
        restartjvm!(jvm)
        @test process_running(jvm.process)
        status = eval!(jvm, "2 + 2")
        @test status == "OK"
    finally
        if process_running(jvm.process)
            kill(jvm.process)
        end
        closejvm!(jvm)
        rm(path; recursive=true, force=true)
    end
end
