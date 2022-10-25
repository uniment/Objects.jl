const PrototypeTypes = Union{Object, Nothing}

struct Dynamic{PT<:PrototypeTypes, PP<:Dict{Symbol,Any}} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Dynamic(prototype::PT, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) where {PT<:PrototypeTypes} =
    Dynamic{PT,Dict{Symbol,Any}}(prototype, Dict{Symbol,Any}(properties))
Dynamic(prototype::PrototypeTypes, properties::NamedTuple) =
    Dynamic(prototype, Dict{Symbol,Any}(k=>properties[k] for k ∈ keys(properties)))

# to handle template construction (this approach explicitly forces typechecks on new values for consistency with Static and Mutable Objects)
Dynamic{PT,PP}(::Val{:template}, store::Dynamic, kwargs) where {PT,PP} = begin
    storecopy = Dynamic(_getproto(store), _getprops(store))
    for (k,v) ∈ kwargs    storecopy[k] = convert(typeof(storecopy[k]), v)    end
    storecopy
end


# access
_getprops(store::Dynamic) = (; ((k,v[]) for (k,v) ∈ store.properties)...) 
# this crashes:(; zip(zip(store.properties...)...)...)

Base.getindex(store::Dynamic, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Dynamic, v, s::Symbol) = (store.properties[s] = v)
#zr