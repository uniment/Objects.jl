const PrototypeTypes = Union{Object, Nothing}

struct Dynamic{PT<:PrototypeTypes, PP<:Dict{Symbol,Any}} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Dynamic(prototype::PT, properties::Base.Pairs) where {PT<:PrototypeTypes} =
    Dynamic{PT,Dict{Symbol,Any}}(prototype, Dict{Symbol,Any}(properties))
Dynamic(prototype::PrototypeTypes, properties::NamedTuple) =
    Dynamic(prototype, Dict{Symbol,Any}(k=>properties[k] for k ∈ keys(properties)))

# to handle template construction (this explicitly forces typechecks for behavioral consistency with Static and Mutable Objects)
Dynamic{PT,PP}(::Val{:template}, store::Dynamic, kwargs) where {PT,PP} = begin
    storecopy = Dynamic(_getproto(store), _getprops(store))
    for (k,v) ∈ kwargs    storecopy[k] = convert(typeof(storecopy[k]), v)    end
    storecopy
end



# access
_getprops(store::Dynamic) = NamedTuple{Tuple(keys(store.properties))}(values(store.properties))


Base.getindex(store::Dynamic, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s]
    isnothing(store.prototype) && throw("property $s not found")
    getfield(store.prototype, :store)[s]
end
Base.setindex!(store::Dynamic, v, s::Symbol) = (store.properties[s] = v)
#zr