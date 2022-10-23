const ProtoType = Union{Object, Nothing}

struct Static{PT<:ProtoType, PP<:NamedTuple} <: ObjectType
    prototype::PT
    properties::PP
end

# Constructors
Static(prototype::ProtoType, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) = 
    Static(prototype, NamedTuple(properties))



# access
getprops(store::Static) = store.properties

Base.getindex(store::Static, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Static, v, s::Symbol) = throw("cannot change property $s of a static object")
#zr