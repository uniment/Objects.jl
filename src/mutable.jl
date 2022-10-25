const PrototypeTypes = Union{Object, Nothing}

struct Mutable{PT<:PrototypeTypes, PP<:NamedTuple{S,<:NTuple{N,Base.RefValue}} where {S,N}} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Mutable(prototype::PrototypeTypes, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) = 
    Mutable(prototype, NamedTuple(k=>Ref(v) for (k,v) ∈ properties))
Mutable(prototype::PrototypeTypes, properties::NamedTuple) =
    Mutable(prototype, NamedTuple(k=>Ref(v) for (k,v) ∈ zip(keys(properties), values(properties))))

# to handle template construction
Mutable{PT,PP}(store::Mutable, args, kwargs) where {PT,PP} = begin
    newvals = (k=>Ref(v) for (k,v) ∈ (args..., kwargs...))
    Mutable(_getproto(store), NamedTuple((_ownprops_itr(store)...,newvals...)))
end

# access
_getprops(store::Mutable) = NamedTuple((k,v[]) for (k,v) ∈ zip(keys(store.properties), values(store.properties)))

Base.getindex(store::Mutable, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s][]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Mutable, v, s::Symbol) = (store.properties[s][] = v)
#zr