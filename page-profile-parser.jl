const doc = """page-profile-parser.jl -- Parses a page profile JSON file
Usage:
    page-profile-parser.jl [<name>] [--page-size=<size>]
    page-profile-parser.jl -h | --help
    page-profile-parser.jl --version
"""

using DocOpt
using JSON3
using Printf

const args = docopt(doc, version = v"0.1.1")
PAGE_SIZE = 4096

function main()
    global PAGE_SIZE
    name = args["<name>"]
    if name === nothing
        error("Missing argument <name>")
    end
    if args["--page-size"] !== nothing
        PAGE_SIZE *= parse(UInt64, args["--page-size"])
    else
        error("Missing argument --page-size")
    end
    parse_page_profile(name)
end

mutable struct HeapPage
    address::String
    object_size::Int64
    type_count::Dict{String,UInt64}
    function HeapPage(address::String, object_size::Int64)
        new(address, object_size, Dict{String,UInt64}())
    end
end

function insert_object!(page::HeapPage, object_type::String)
    if haskey(page.type_count, object_type)
        page.type_count[object_type] += 1
    else
        page.type_count[object_type] = 1
    end
end

mutable struct PageProfile
    types::Set{String}
    pages::Vector{HeapPage}
    function PageProfile()
        new(Set{String}(), Vector{HeapPage}())
    end
end

function insert_type!(profile::PageProfile, type::String)
    push!(profile.types, type)
end

function insert_page!(profile::PageProfile, page::HeapPage)
    push!(profile.pages, page)
end

function compute_average_utilization(profile::PageProfile, type::String)
    object_bytes = 0
    page_bytes = 0
    for page in profile.pages
        if haskey(page.type_count, type)
            object_bytes += page.type_count[type] * page.object_size
            page_bytes += PAGE_SIZE
        end
    end
    return object_bytes / page_bytes
end

function Base.show(io::IO, profile::PageProfile)
    @printf(
        io,
        "PageProfile(%d pages, %.2f MiB)",
        length(profile.pages),
        length(profile.pages) * PAGE_SIZE / 1024 / 1024
    )
    d = Dict{String,UInt64}()
    for page in profile.pages
        for (type, count) in page.type_count
            if haskey(d, type)
                d[type] += 1
            else
                d[type] = 1
            end
        end
    end
    types = sort(collect(profile.types), by = ty -> d[ty])
    reverse!(types)
    for type in types
        npages = d[type]
        @printf(
            io,
            "\n  %s: %.2f%% utilization %d pages (%.2f MiB)",
            type,
            compute_average_utilization(profile, type) * 100,
            npages,
            npages * PAGE_SIZE / 1024 / 1024
        )
    end
    for page in profile.pages
        if isempty(page.type_count)
            continue
        end
        @printf(io, "\n    Page(%s, %d bytes)", page.address, page.object_size)
        if isempty(page.type_count)
            @printf(io, "\n      empty")
        else
            for (type, count) in page.type_count
                @printf(io, "\n      %s: %d", type, count)
            end
        end
    end
end

function parse_page_profile(filename::String)
    profile = PageProfile()
    dict = JSON3.read(filename)
    for page in dict["pages"]
        address = page["address"]
        object_size = page["object_size"]
        heap_page = HeapPage(address, object_size)
        for object in page["objects"]
            if object == "empty" || object == "garbage"
                continue
            end
            insert_object!(heap_page, object)
            insert_type!(profile, object)
        end
        if !isempty(heap_page.type_count)
            insert_page!(profile, heap_page)
        end
    end
    @show profile
end

main()
