const ProtoType = Union{Object, Nothing}

struct Mutable{PT<:ProtoType, PP<:NamedTuple{S,<:NTuple{N,Base.RefValue}} where {S,N}} <: ObjectType
    prototype::PT
    properties::PP
end

# Constructors
Mutable(prototype::ProtoType, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) = 
    Mutable(prototype, NamedTuple(k=>Ref(v) for (k,v) ∈ properties))
Mutable(prototype::ProtoType, properties::NamedTuple) =
    Mutable(prototype, NamedTuple(k=>Ref(v) for (k,v) ∈ zip(keys(properties), values(properties))))

# access
getprops(store::Mutable) = NamedTuple((k,v[]) for (k,v) ∈ zip(keys(store.properties), values(store.properties)))

Base.getindex(store::Mutable, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s][]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Mutable, v, s::Symbol) = (store.properties[s][] = v)
#zr