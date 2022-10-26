include("dynamic.jl")
include("mutable.jl")
include("static.jl")

_getproto(store::StorageType) = store.prototype
_ownprops_itr(store::StorageType) = ((k=>v) for (k,v) ∈ zip(keys(store.properties), values(store.properties)))


Base.keys(store::StorageType) = union(
    keys(store.properties),
    isnothing(store.prototype) ? () : propertynames(store.prototype)
)


#zr