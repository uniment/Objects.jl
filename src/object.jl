"""
    Object{[TypeTag]}([StorageType] [; kwargs...])

Create a structured `Object` with properties specified by keyword arguments `kwargs`. Object type can be specified by `StorageType`, and additional type parameters can be specified by `TypeTag`. Later properties override earlier ones.

Other iterable key=>value mappings, as from generators, dictionaries, named tuples, and other `Object`s, can be splatted into the keyword arguments as well.

`StorageType` can be `Static`, `Mutable`, or `Dynamic`, depending on performance needs. If not specified, default is `Mutable`.

`TypeTag` is optional and does not affect `Object` behavior, but can be used to leverage Julia's type inference engine for multiple method dispatch.

    Object{[TypeTag]}([StorageType,] props::AbstractDict)

Create an `Object` from a dictionary recursively.

    Object{[TypeTag]}([StorageType,] obj::Any)

Create an `Object` from an arbitrary composite type.

    Object{[TypeTag]}([StorageType,] obj::Object)

Convert an `Object` from one set of `StorageType` and `TypeTag` to another, keeping prototype. 

    (proto::Object)([; kwargs...])

Every `Object` is a constructor. Call on the object to use it as a template for creating a new object with the exact same property names and types.

    Object{[TypeTag]}([StorageType,] (proto::Object,) [; kwargs...])

Create a new object which references object `proto` as its prototype. Notice that `proto` has been placed into a single-element Tuple.

    obj.meth = function(self, a, b, c) #=...=# end
    obj.meth(a, b, c)

Call a member method `meth`, passing `obj` as the first argument.

    obj[k]

access obj.k

    obj[(:k1,:k2,:k3)]

return new object with properties specified by tuple of symbols

    obj[::Base.Generator]

return new object with properties set by generator

    drop(obj, :k1, :k2)

return new object with keys removed (own keys only; prototype unchanged)

    (; obj...)

splat object into a named tuple

    (obj...,)

splat into a tuple of values (useful for splatting into a constructor, e.g. MyStruct(obj...))

    ((k,v) for (k,v) ∈ zip(keys(obj),values(obj)))

generator to iterate over object's property names and values

    (; x, y, z) = obj

Destructure properties `x`, `y`, and `z` out of `obj`.
"""
struct Object{UserType, StorageType}
    store::StorageType
end


# default constructors
Object{UT}(store::OT) where {UT,OT<:StorageType} = Object{UT,OT}(store)
Object(store::OT) where {OT<:StorageType} = Object{Nothing,OT}(store)

# constructing from scratch
# too much copypasta ... fix this up someday like a real programmer

# splatted objects and keyword arguments
Object{UT}(OT::Type{<:StorageType}; kwargs...) where {UT} = Object{UT}(OT(nothing, kwargs))
Object(OT::Type{<:StorageType}; kwargs...) = Object{Nothing}(OT(nothing, kwargs))
Object{UT}(; kwargs...) where {UT} = Object{UT}(DEFAULT_STORAGE_TYPE(nothing, kwargs))
Object(; kwargs...) = Object{Nothing}(; kwargs...)


# cute utility taken shamelessly from ConstructionBase.jl
@generated function _constructorof(::Type{T}) where T
    getfield(parentmodule(T), nameof(T))
end

# conversion
# arbitrary composite types
Object{UT}(OT::Type{<:StorageType}, obj) where {UT} = Object{UT}(OT(nothing, (; (k => getproperty(obj,k) for k ∈ propertynames(obj))...)))
Object(OT::Type{<:StorageType}, obj) = Object{Nothing}(OT, obj)
Object{UT}(obj) where {UT} = Object{UT}(DEFAULT_STORAGE_TYPE, obj)
Object(obj) = Object{Nothing}(obj)

# object type
Object{UTnew}(OTnew::Type{<:StorageType}, obj::Object) where UTnew = Object{UTnew}(OTnew(_getproto(getfield(obj, :store)), _getprops(getfield(obj, :store))))
Object(OTnew::Type{<:StorageType}, obj::Object{UT,OT}) where {UT,OT} = Object{UT}(OTnew(_getproto(getfield(obj, :store)), _getprops(getfield(obj, :store))))
Object{UTnew}(obj::Object{UT,OT}) where {UTnew,UT,OT} = Object{UTnew}(_constructorof(OT)(_getproto(getfield(obj, :store)), _getprops(getfield(obj, :store))))
Object(obj::Object) = obj

# recursive dict expansion
Object{UT}(OT::Type{<:StorageType}, dict::AbstractDict) where {UT} = 
    Object{UT}(OT(nothing, (; (Symbol(k) => v isa AbstractDict ? Object{UT}(OT, v) : v for (k,v) ∈ dict)...)))
Object(OT::Type{<:StorageType}, dict::AbstractDict) = 
    Object{Nothing}(OT(nothing, (; (Symbol(k) => v isa AbstractDict ? Object(OT, v) : v for (k,v) ∈ dict)...)))
Object{UT}(dict::AbstractDict) where {UT} =
    Object{UT}(DEFAULT_STORAGE_TYPE(nothing, (; (Symbol(k) => v isa AbstractDict ? Object{UT}(v) : v for (k,v) ∈ dict)...)))
Object(dict::AbstractDict) = Object{Nothing}(dict)


# code reuse
# constructing from a template
(template::Object{UT,OT})(; kwargs...) where {UT,OT} = Object{UT,OT}(OT(Val(:template), getfield(template, :store), kwargs))

# prototype inheritance
const PrototypeTypes = Union{Object, Nothing}
Object{UT}(OT::Type{<:StorageType}, proto::Tuple{PrototypeTypes}; kwargs...) where {UT} = Object{UT}(OT(first(proto), kwargs))
Object(OT::Type{<:StorageType}, proto::Tuple{PrototypeTypes}; kwargs...) = Object{Nothing}(OT(first(proto), kwargs))
Object{newUT}(proto::Tuple{Object{UT,OT}}; kwargs...) where {newUT,UT,OT} = Object{newUT}(_constructorof(OT)(first(proto), kwargs))
Object(proto::Tuple{Object{UT,OT}}; kwargs...) where {UT,OT} = Object{UT}(_constructorof(OT)(first(proto), kwargs))

# interface
Base.getproperty(obj::Object, s::Symbol) = begin
    v = getfield(obj, :store)[s]
    v isa Function && return (a...; k...) -> v(obj, a...; k...)
    v
end
Base.setproperty!(obj::Object, s::Symbol, v) = (getfield(obj, :store)[s] = v)
Base.propertynames(obj::Object) = (keys(getfield(obj, :store))...,)

Base.keys(obj::Object) = (keys(getfield(obj, :store))...,)
Base.values(obj::Object) = (values(getfield(obj, :store))...,) # if you don't splat first, then sending values(obj) to NamedTuple in merge() is super slow 
#Base.iterate(obj::Object, itr=zip(keys(obj), values(obj))) = Iterators.peel(itr) # keys,values
Base.iterate(obj::Object, itr=values(obj)) = Iterators.peel(itr) # values only!
Base.merge(nt::NamedTuple, obj::Object) = (; nt..., NamedTuple{keys(obj)}(values(obj))...)

Base.length(obj::Object) = length(keys(getfield(obj, :store)))
Base.getindex(obj::Object, n) = getproperty(obj, Symbol(n))
Base.getindex(obj::Object{UT,OT}, n::NTuple{N,Symbol}) where {N,UT,OT} =
    Object{UT}(_constructorof(OT); NamedTuple{n}((; obj...))...)
Base.getindex(obj::Object, n::Base.Generator) = getindex(obj, (n...,))
Base.setindex!(obj::Object, x, n) = setproperty!(obj, Symbol(n), x)

drop(obj::Object{UT,OT}, n::Symbol...) where {UT,OT} = begin
    store = getfield(obj, :store)
    ownkeys = keys(store.properties)
    newkeys = (k for k ∈ ownkeys if k ∉ (n...,))
    valgen = (store[k] for k ∈ ownkeys)
    Object{UT}(_constructorof(OT), (getprototype(obj),); NamedTuple{(newkeys...,)}((; zip(keys(store.properties), valgen)...))...)
end

Base.show(io::IO, obj::Object{UT,OT}) where {UT,OT} = begin
    store = getfield(obj, :store); props = _getprops(store)
    print(io, "Object{",(UT isa Symbol ? ":" : ""), string(UT),", ", string(nameof(OT)), "}(\n    prototype: ", 
        replace(string(isnothing(_getproto(store)) ? "none" : _getproto(store)), "\n"=>"\n    "), ",\n    properties: ⟨", 
        replace(join([(v isa Object ? "\n" : "")*"$k = $v" for (k,v) ∈ zip(keys(props), values(props))], ", "), "\n"=>"\n    "), "⟩\n)")
end
Base.copy(obj::Object) = begin
    store = getfield(obj, :store)
    typeof(obj)(typeof(store)(_getproto(store), copy(store.properties)))
end
Base.deepcopy(obj::Object) = begin
    store = getfield(obj, :store)
    typeof(obj)(typeof(store)(deepcopy(_getproto(store)), copy(store.properties)))
end
Base.:<<(a::Object, b::Object) = (aproto = getfield(a, :store).prototype; isnothing(aproto) ? false : (aproto==b || aproto<<b))
Base.:>>(a::Object, b::Object) = b << a
Base.:(==)(a::Object, b::Object) = (typeof(a) == typeof(b)) && (getprototype(a) == getprototype(b)) && ((a...,) == (b...,))

# Object-to-Dictionary conversions
Base.convert(T::Type{<:AbstractDict}, obj::Object) = begin
    store = getfield(obj, :store); props = _getprops(store)
    isnothing(_getproto(store)) ? T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))) :
    merge(convert(T, _getproto(store)), T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))))
end

"""
    getprototype(obj::Object)::Union{Object, Nothing}

Retrieves `obj`'s prototype object.
"""
getprototype(obj::Object) = _getproto(getfield(obj, :store))

"""
    ownpropertynames(obj::Object)::Tuple

Retrieves `obj`'s property names, excluding those of its prototype
"""
ownpropertynames(obj::Object) = Tuple(keys(_getprops(getfield(obj, :store))))
"""
    ownproperties(obj::Object)::Base.Generator

Returns a generator for splatting `obj`'s own properties.
"""
ownproperties(obj::Object) = _ownprops_itr(getfield(obj, :store))

#zr