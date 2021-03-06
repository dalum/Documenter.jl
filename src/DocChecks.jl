"""
Provides the [`missingdocs`](@ref), [`footnotes`](@ref) and [`linkcheck`](@ref) functions
for checking docs.
"""
module DocChecks

import ..Documenter:
    Documents,
    Utilities,
    IdDict

using Compat, DocStringExtensions
import Compat: Markdown

# Missing docstrings.
# -------------------

"""
$(SIGNATURES)

Checks that a [`Documents.Document`](@ref) contains all available docstrings that are
defined in the `modules` keyword passed to [`Documenter.makedocs`](@ref).

Prints out the name of each object that has not had its docs spliced into the document.
"""
function missingdocs(doc::Documents.Document)
    doc.user.checkdocs === :none && return
    println(" > checking for missing docstrings.")
    bindings = allbindings(doc.user.checkdocs, doc.user.modules)
    for object in keys(doc.internal.objects)
        if haskey(bindings, object.binding)
            signatures = bindings[object.binding]
            if object.signature ≡ Union{} || length(signatures) ≡ 1
                delete!(bindings, object.binding)
            elseif object.signature in signatures
                delete!(signatures, object.signature)
            end
        end
    end
    n = Compat.reduce(+, map(length, values(bindings)), init=0)
    if n > 0
        b = IOBuffer()
        println(b, "$n docstring$(n ≡ 1 ? "" : "s") potentially missing:\n")
        for (binding, signatures) in bindings
            for sig in signatures
                println(b, "    $binding", sig ≡ Union{} ? "" : " :: $sig")
            end
        end
        push!(doc.internal.errors, :missing_docs)
        Utilities.warn(String(take!(b)))
    end
end

function allbindings(checkdocs::Symbol, mods)
    out = Dict{Utilities.Binding, Set{Type}}()
    for m in mods
        allbindings(checkdocs, m, out)
    end
    out
end

function allbindings(checkdocs::Symbol, mod::Module, out = Dict{Utilities.Binding, Set{Type}}())
    for (obj, doc) in meta(mod)
        isa(obj, IdDict) && continue
        name = nameof(obj)
        isexported = Base.isexported(mod, name)
        if checkdocs === :all || (isexported && checkdocs === :exports)
            out[Utilities.Binding(mod, name)] = Set(sigs(doc))
        end
    end
    out
end

meta(m) = Docs.meta(m)

nameof(x::Function)          = typeof(x).name.mt.name
nameof(b::Base.Docs.Binding) = b.var
nameof(x::DataType)          = x.name.name
nameof(m::Module)            = Compat.nameof(m)

sigs(x::Base.Docs.MultiDoc) = x.order
sigs(::Any) = Type[Union{}]


# Footnote checks.
# ----------------

function footnotes(doc::Documents.Document)
    println(" > checking footnote links.")
    # A mapping of footnote ids to a tuple counter of how many footnote references and
    # footnote bodies have been found.
    #
    # For all ids the final result should be `(N, 1)` where `N > 1`, i.e. one or more
    # footnote references and a single footnote body.
    footnotes = Dict{Documents.Page, Dict{String, Tuple{Int, Int}}}()
    for (src, page) in doc.internal.pages
        empty!(page.globals.meta)
        orphans = Dict{String, Tuple{Int, Int}}()
        for element in page.elements
            Documents.walk(page.globals.meta, page.mapping[element]) do block
                footnote(block, orphans)
            end
        end
        footnotes[page] = orphans
    end
    for (page, orphans) in footnotes
        for (id, (ids, bodies)) in orphans
            # Multiple footnote bodies.
            if bodies > 1
                push!(doc.internal.errors, :footnote)
                Utilities.warn(page.source, "Footnote '$id' has $bodies bodies.")
            end
            # No footnote references for an id.
            if ids === 0
                push!(doc.internal.errors, :footnote)
                Utilities.warn(page.source, "Unused footnote named '$id'.")
            end
            # No footnote bodies for an id.
            if bodies === 0
                push!(doc.internal.errors, :footnote)
                Utilities.warn(page.source, "No footnotes found for '$id'.")
            end
        end
    end
end

function footnote(fn::Markdown.Footnote, orphans::Dict)
    ids, bodies = get(orphans, fn.id, (0, 0))
    if fn.text === nothing
        # Footnote references: syntax `[^1]`.
        orphans[fn.id] = (ids + 1, bodies)
        return false # No more footnotes inside footnote references.
    else
        # Footnote body: syntax `[^1]:`.
        orphans[fn.id] = (ids, bodies + 1)
        return true # Might be footnotes inside footnote bodies.
    end
end

footnote(other, orphans::Dict) = true

# Link Checks.
# ------------

hascurl() = (try; success(`curl --version`); catch err; false; end)

function linkcheck(doc::Documents.Document)
    if doc.user.linkcheck
        if hascurl()
            println(" > checking external URLs:")
            for (src, page) in doc.internal.pages
                println("   - ", src)
                for element in page.elements
                    Documents.walk(page.globals.meta, page.mapping[element]) do block
                        linkcheck(block, doc)
                    end
                end
            end
        else
            push!(doc.internal.errors, :linkcheck)
            Utilities.warn("linkcheck requires `curl`.")
        end
    end
    return nothing
end

function linkcheck(link::Markdown.Link, doc::Documents.Document)
    INDENT = " "^6

    # first, make sure we're not supposed to ignore this link
    for r in doc.user.linkcheck_ignore
        if linkcheck_ismatch(r, link.url)
            printstyled(INDENT, "--- ", link.url, "\n", color=:normal)
            return false
        end
    end

    if !haskey(doc.internal.locallinks, link)
        local result
        try
            result = read(`curl -sI $(link.url)`, String)
        catch err
            push!(doc.internal.errors, :linkcheck)
            Utilities.warn("`curl -sI $(link.url)` failed:\n\n$(err)")
            return false
        end
        local STATUS_REGEX   = r"^HTTP/(1.1|2) (\d+) (.+)$"m
        if occursin(STATUS_REGEX, result)
            status = parse(Int, match(STATUS_REGEX, result).captures[2])
            if status < 300
                printstyled(INDENT, "$(status) ", link.url, "\n", color=:green)
            elseif status < 400
                LOCATION_REGEX = r"^Location: (.+)$"m
                if occursin(LOCATION_REGEX, result)
                    location = strip(match(LOCATION_REGEX, result).captures[1])
                    printstyled(INDENT, "$(status) ", link.url, "\n", color=:yellow)
                    printstyled(INDENT, " -> ", location, "\n\n", color=:yellow)
                else
                    printstyled(INDENT, "$(status) ", link.url, "\n", color=:yellow)
                end
            else
                push!(doc.internal.errors, :linkcheck)
                printstyled(INDENT, "$(status) ", link.url, "\n", color=:red)
            end
        else
            push!(doc.internal.errors, :linkcheck)
            Utilities.warn("invalid result returned by `curl -sI $(link.url)`:\n\n$(result)")
        end
    end
    return false
end
linkcheck(other, doc::Documents.Document) = true

linkcheck_ismatch(r::String, url) = (url == r)
linkcheck_ismatch(r::Regex, url) = occursin(r, url)

end
