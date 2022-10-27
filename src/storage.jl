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

Base.keys(store::StorageType) = (k for k ∈ _union_names(keys(store.properties), isnothing(store.prototype) ? () : keys(getfield(store.prototype, :store))))
Base.values(store::StorageType) = (store[k] for k ∈ keys(store))
Base.iterate(store::StorageType, itr=zip(keys(store), values(store))) = Iterators.peel(itr)

#zr