include("dynamic.jl")
include("mutable.jl")
include("static.jl")

_getproto(store::StorageType) = store.prototype
_ownprops_itr(store::StorageType) = ((k=>v) for (k,v) ∈ zip(keys(store.properties), values(store.properties)))

_union_names(a, b) = begin # feed in symbols
    names = Symbol[a...]
    for k ∈ b
        k ∈ a || push!(names, k)
    end
    names
end
_union_names(a, ::Tuple{}) = a

# new
Base.keys(store::StorageType) = begin
    ownpropkeys = keys(store.properties)
    isnothing(store.prototype) && return ownpropkeys
    reduce(keys(getfield(store.prototype, :store)); init=ownpropkeys) do acc, k
        k ∈ acc ? acc : (acc..., k)
    end
end
Base.values(store::StorageType) = begin
    ownpropkeys = keys(store.properties)
    ownpropvals = (store[k] for k ∈ keys(store.properties))
    isnothing(store.prototype) && return ownpropvals
    reduce(keys(getfield(store.prototype, :store)); init=ownpropvals) do acc, k
        k ∈ ownpropkeys ? acc : (acc..., getfield(store.prototype, :store)[k])
    end
end


#Base.keys(store::StorageType) = (k for k ∈ _union_names(keys(store.properties), isnothing(store.prototype) ? () : keys(getfield(store.prototype, :store))))
#Base.values(store::StorageType) = (store[k] for k ∈ keys(store))
#Base.iterate(store::StorageType, itr=zip(keys(store), values(store))) = Iterators.peel(itr)

#zr