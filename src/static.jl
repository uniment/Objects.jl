const PrototypeTypes = Union{Object, Nothing}

struct Static{PT<:PrototypeTypes, PP<:NamedTuple} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Static(prototype::PrototypeTypes, properties::Union{Base.Pairs}) = 
    Static(prototype, NamedTuple(properties))



# to handle template construction
Static{PT,PP}(::Val{:template}, store::Static, kwargs) where {PT,PP} = begin
    Static{PT,PP}(_getproto(store), merge(_getprops(store), NamedTuple(kwargs)))
end





# access
_getprops(store::Static) = store.properties

Base.getindex(store::Static, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s]
    isnothing(store.prototype) && throw("property $s not found")
    getfield(store.prototype, :store)[s]
end
Base.setindex!(store::Static, v, s::Symbol) = throw("cannot change property $s of a `Static` object")
#zr