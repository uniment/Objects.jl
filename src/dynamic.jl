const ProtoType = Union{Object, Nothing}

struct Dynamic{PT<:ProtoType, PP<:Dict{Symbol,Any}} <: ObjectType
    prototype::PT
    properties::PP
end

# Constructors
Dynamic(prototype::ProtoType, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) = 
    Dynamic(prototype, Dict{Symbol,Any}(properties))
Dynamic(prototype::ProtoType, properties::NamedTuple) =
    Dynamic(prototype, Dict{Symbol,Any}(k=>properties[k] for k ∈ keys(properties)))

# access
getprops(store::Dynamic) = NamedTuple(store.properties)

Base.getindex(store::Dynamic, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Dynamic, v, s::Symbol) = (store.properties[s] = v)
#zr