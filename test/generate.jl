module GenerateTests

using Test
using Documenter

@testset "Generate" begin
    mktempdir() do root
        let path = joinpath(root, "docs")
            Documenter.generate("DocumenterTestPackage", dir = path)
            @test isdir(path)
            @test isfile(joinpath(path, "mkdocs.yml"))
            @test isfile(joinpath(path, ".gitignore"))
            @test isfile(joinpath(path, "make.jl"))
            @test isdir(joinpath(path, "src"))
            @test isfile(joinpath(path, "src", "index.md"))
        end
    end

    # TODO: these tests should be reviewed. Documenter.generate() does not really
    # support Pkg3 / Julia 0.7 at the moment.
    @test_throws ErrorException Documenter.generate("Documenter")
    @test_throws MethodError Documenter.generate(randstring())
end

end