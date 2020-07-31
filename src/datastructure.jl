using DataStructures
using AbstractTrees
import AbstractTrees: children

export name, path
struct NoValue end

struct DirTree
    parent::Union{DirTree, Nothing}
    name::String
    children::Vector
    value::Any
end

DirTree(parent, name, children) = DirTree(parent, name, children, NoValue())

# convenience method to replace a few parameters
# and leave others unchanged
function DirTree(t::DirTree; parent=t.parent, name=t.name, children=t.children, value=t.value)
    DirTree(parent, name, children, value)
end

DirTree(dir) = DirTree(nothing, dir)

function DirTree(parent, dir)
    children = []
    parent′ = DirTree(parent, dir, children)

    ls = readdir(dir)
    cd(dir) do
        children′ = map(ls) do f
            if isdir(f)
                DirTree(parent′, f)
            else
                File(parent′, f)
            end
        end
        append!(children, children′)
    end

    parent′
end

children(d::DirTree) = d.children

parent(f::DirTree) = f.parent

name(f::DirTree) = f.name

Base.isempty(d::DirTree) = isempty(d.children)

function rename(x::DirTree, newname)
    set_parent(DirTree(x, name=newname))
end

function set_parent(x::DirTree, parent=x.parent)
    p = DirTree(x, parent=parent, children=copy(x.children))
    copy!(p.children, set_parent.(x.children, (p,)))
    p
end

Base.show(io::IO, d::DirTree) = AbstractTrees.print_tree(io, d)

struct File
    parent::Union{Nothing, DirTree}
    name::String
    value::Any
end

File(parent, name) = File(parent, name, NoValue())

function File(f::File; parent=f.parent, name=f.name, value=f.value)
    File(parent, name, value)
end

Base.show(io::IO, f::File) = print(io, "File(" * path(f) * ")")

function AbstractTrees.printnode(io::IO, f::Union{DirTree, File})
    print(io, name(f))
    if hasvalue(f)
        T = typeof(value(f))
        print(io," (", repr(T), ")")
    end
end


File(parent, name::String) = File(parent, name, NoValue())

children(d::File) = ()

parent(f::File) = f.parent

name(f::File) = f.name

Base.isempty(d::File) = false

set_parent(x::File, parent=x.parent) = File(x, parent=parent)

files(tree::DirTree) = DirTree(tree; children=filter(x->x isa File, tree.children))

subdirs(tree::DirTree) = DirTree(tree; children=filter(x->x isa DirTree, tree.children))

Base.getindex(tree::DirTree, i::Int) = tree.children[i]

function Base.getindex(tree::DirTree, ix::Vector)
    DirTree(tree;
            children=vcat(map(i->(x=tree[i]; i isa Regex ? x.children :  x), ix)...))
end

function Base.getindex(tree::DirTree, i::String)
    idx = findfirst(x->name(x)==i, children(tree))
    if idx === nothing
        error("No file matched getindex $repr")
    end
    tree[idx]
end

function Base.getindex(tree::DirTree, i::Regex)
    filtered = filter(r->match(i, r.name) !== nothing, tree.children)
    DirTree(tree.parent, tree.name, filtered)
end

Base.filter(f, x::DirTree; walk=postwalk) =
    walk(x->f(x) ? x : nothing, t; collect_children=cs->filter(!isnothing, cs))

rename(x::File, newname) = File(x, name=newname)

### Stuff agnostic to Dir or File nature of "Node"s

const Node = Union{DirTree, File}

Base.basename(d::Node) = d.name

path(d::Node) = d.parent === nothing ? d.name : joinpath(path(d.parent), d.name)

Base.dirname(d::Node) = dirname(path(d))

value(d::Node) = d.value

hasvalue(x::Node) = !(value(x) isa NoValue)

## Tree walking

function prewalk(f, t::DirTree; collect_children=identity)
    x = f(t)
    if x isa DirTree
        cs = map(c->prewalk(f, c; collect_children=collect_children), t.children)
        DirTree(x; children=collect_children(cs))
    else
        return x
    end
end

prewalk(f, t::File; collect_children=identity) = f(t)

function postwalk(f, t::DirTree; collect_children=identity)
    cs = map(c->postwalk(f, c; collect_children=collect_children), t.children)
    f(DirTree(t; children=collect_children(cs)))
end

postwalk(f, t::File; collect_children=identity) = f(t)

function flatten(t::DirTree; joinpath=joinpath)
    postwalk(t) do x
        if x isa DirTree
            cs = map(filter(x->x isa DirTree, children(x))) do sd
                map(children(sd)) do thing
                    newname = joinpath(name(sd), name(thing))
                    typeof(thing)(thing; name=newname, parent=x)
                end
            end |> Iterators.flatten |> collect
            return DirTree(x; children=vcat(cs, filter(x->!(x isa DirTree), children(x))))
        else
            return x
        end
    end
end

_merge_error(x, y) = error("Files with same name $(name(x)) found at $(dirname(x)) while merging")

"""
    merge(t1, t2)

Merge two DirTrees
"""
function merge(t1::DirTree, t2::DirTree; combine=_merge_error)
    if name(t1) == name(t2)
        t2_names = name.(children(t2))
        t2_merged = zeros(Bool, length(t2_names))
        cs = []
        for x in children(t1)
            idx = findfirst(==(name(x)), t2_names)
            if !isnothing(idx)
                y = t2[idx]
                if t2[idx] isa DirTree
                    push!(cs, merge(x, y))
                else
                    push!(cs, combine(x, y))
                end
                t2_merged[idx] = true
            else
                push!(cs, x)
            end
        end
        DirTree(t1; children=vcat(cs, children(t2)[map(!, t2_merged)])) |> set_parent
    else
        DirTree(nothing, ".", [t1, t2], NoValue())
    end
end
