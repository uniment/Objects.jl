const PrototypeTypes = Union{Object, Nothing}

struct Dynamic{PT<:PrototypeTypes, PP<:Dict{Symbol,Any}} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Dynamic(prototype::PrototypeTypes, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) = 
    Dynamic(prototype, Dict{Symbol,Any}(properties))
Dynamic(prototype::PrototypeTypes, properties::NamedTuple) =
    Dynamic(prototype, Dict{Symbol,Any}(k=>properties[k] for k ∈ keys(properties)))

# to handle template construction
Dynamic{PT,PP}(store::Dynamic, args, kwargs) where {PT,PP} = begin
    all((k ∈ keys(store.properties) || throw("property `$k` not in object")) && (v isa typeof(store[k]) || throw("property `$k` incorrect type")) for (k,v) ∈ (args...,kwargs...))
    Dynamic(_getproto(store), (_ownprops_itr(store)..., args..., kwargs...))
end

# access
_getprops(store::Dynamic) = NamedTuple(store.properties)

Base.getindex(store::Dynamic, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Dynamic, v, s::Symbol) = (store.properties[s] = v)
#zr