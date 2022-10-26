const PrototypeTypes = Union{Object, Nothing}

struct Static{PT<:PrototypeTypes, PP<:NamedTuple} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Static(prototype::PrototypeTypes, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) = 
    Static(prototype, NamedTuple(properties))



# to handle template construction
Static{PT,PP}(::Val{:template}, store::Static; kwargs...) where {PT,PP} = begin
    Static{PT,PP}(_getproto(store), PP(getindex(k ∈ keys(kwargs) ? kwargs : _getprops(store), k) for k ∈ keys(_getprops(store))))
end




# access
_getprops(store::Static) = store.properties

Base.getindex(store::Static, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Static, v, s::Symbol) = throw("cannot change property $s of a `Static` object")
#zr