const PrototypeTypes = Union{Object, Nothing}

struct Mutable{PT<:PrototypeTypes, PP<:NamedTuple{S,<:NTuple{N,Base.RefValue}} where {S,N}} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Mutable(prototype::PrototypeTypes, properties::Base.Pairs) = 
    Mutable(prototype, NamedTuple(properties))
Mutable(prototype::PrototypeTypes, properties::NamedTuple{K,V}) where {K,V} =
    Mutable(prototype, NamedTuple{K}(map(v -> Ref(v), properties)))

# to handle template construction
Mutable{PT,PP}(::Val{:template}, store::Mutable{PT,PP}, kwargs) where {PT,PP} = begin
    any(k ∉ keys(store.properties) for k ∈ keys(kwargs)) && Mutable{PT,PP}(_getproto(store), merge(store.properties, kwargs)) # forces error with ok message
    a, b = store.properties, kwargs
    propscopy = PP(typeof(a[k])(k ∈ keys(b) ? b[k] : a[k][]) for k ∈ keys(a))
    Mutable{PT,PP}(_getproto(store), propscopy)
end


# access
_getprops(store::Mutable) = (; map(v->(v,store.properties[v][]), keys(store.properties))...)

Base.getindex(store::Mutable, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s][]
    isnothing(store.prototype) && throw("property $s not found")
    getfield(store.prototype, :store)[s]
end
Base.setindex!(store::Mutable, v, s::Symbol) = (store.properties[s][] = v)
#zr