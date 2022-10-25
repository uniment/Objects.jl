const PrototypeTypes = Union{Object, Nothing}

struct Mutable{PT<:PrototypeTypes, PP<:NamedTuple{S,<:NTuple{N,Base.RefValue}} where {S,N}} <: StorageType
    prototype::PT
    properties::PP
end

# Constructors
Mutable(prototype::PrototypeTypes, properties::Union{Base.Pairs, NTuple{N,Pair} where N}) = 
    Mutable(prototype, NamedTuple(properties))
Mutable(prototype::PrototypeTypes, properties::NamedTuple{K,V}) where {K,V} =
    Mutable(prototype, NamedTuple{K}(map(k -> Ref(properties[k]), keys(properties))))

# to handle template construction
Mutable{PT,PP}(::Val{:template}, store::Mutable{PT,PP}, kwargs) where {PT,PP} = begin
    a, b = store.properties, (; kwargs...) # NamedTuples of Ref's and normal vars, but both can be deref'd with []
    propscopy = PP(map(k -> typeof(a[k])(getfield(k ∈ keys(b) ? b : a, k)[]), keys(a))) # what a wonderful way to learn the benefits of `map`
    Mutable{PT,PP}(_getproto(store), propscopy)
end


# access
_getprops(store::Mutable) = (; ((k,v[]) for (k,v) ∈ zip(keys(store.properties), store.properties))...)

Base.getindex(store::Mutable, s::Symbol) = begin
    s ∈ keys(store.properties) && return store.properties[s][]
    isnothing(store.prototype) && throw("property $s not found")
    getproperty(store.prototype, s; iscaller=false)
end
Base.setindex!(store::Mutable, v, s::Symbol) = (store.properties[s][] = v)
#zr