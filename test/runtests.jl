using Objects
using Test

@testset verbose=true "Objects.jl" begin
    @testset "Constructors" begin
        # Constructing from a Dict
        # Constructing from kwargs...
        # Constructing from args::Pair... 

        # Constructing without Inheritance
        # Constructing with Inheritance

        # Setting param P during construction
        # Setting param T during construction
            # -> as {T,P} type parameterizations, or as (T,P) arguments

            
        # some scattered tests
        a = Object(a=1)
        @test a.a==1
        @test_throws MethodError Object(Number)(Int)

    end

    @testset "Converters" begin
        @test begin obj = Object(Any); obj==Object(obj) end
    end

    @testset "Inheritance" begin
    end

    @testset "Getting and Setting" begin
        #@inferred 
        # Locking
    end

    @testset "Base Methods" begin
    end

    @testset "Interface Methods" begin
    end
end
