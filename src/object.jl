"""
    Object{[TypeTag]}([StorageType,] [args...]; kwargs...)

Create a structured `Object` with properties specified by pairs `args` or keyword arguments `props`. Object type can be specified by `StorageType`, and additional type parameters can be specified by `TypeTag`. Later properties override earlier ones.

`StorageType` can be `Static`, `Mutable`, or `Dynamic`, depending on performance needs. If not specified, default is `Mutable`.

`TypeTag` is optional and does not affect `Object` behavior, but can be used to leverage Julia's type inference engine for multiple method dispatch.

    Object{[TypeTag]}([StorageType,] props::AbstractDict)

Create an `Object` from a dictionary recursively.

    Object{[TypeTag]}([StorageType,] obj::Any)

Create an `Object` from an arbitrary composite type.    

    Object{[TypeTag]}([StorageType,] props::Object)

Convert an `Object` from one set of `StorageType` and `TypeTag` to another. 

    Object{[TypeTag]}([StorageType,] ((obj::Object)...)...; [props...])

Splat and flatten the contents of `obj` to create an independent object with the same properties. Can splat more than one object, with later splatted objects overriding earlier ones. `props` sets instance-specific properties and overrides all.

    (proto::Object)([StorageType;] [((obj::Object)...)...]; props...)

Every `Object` is a constructor. Call on the object to use it as a template for creating a new object with the exact same property names and types.

    Prototype{[TypeTag]}([StorageType,] proto::Object[, args...] [kwargs...])

Create a new object using object `proto` as a prototype.

    obj.meth = function(self, a, b, c) #=...=# end
    obj.meth(a, b, c)

Calls a member method `meth` and passes `obj` as the first argument.

    (; x, y, z) = obj

Destructure properties `x`, `y`, and `z` out of `obj`.
"""
struct Object{UserType, StorageType}
    store::StorageType
end

# default constructor
Object{UT}(store::OT) where {UT,OT<:StorageType} = Object{UT,OT}(store)

# constructing from scratch
# too much copypasta ... fix this up someday like a real programmer

# splatted objects and keyword arguments
Object{UT}(OT::Type{<:StorageType}, args::Pair...; kwargs...) where {UT} = Object{UT}(OT(nothing, (args...,kwargs...)))
Object(OT::Type{<:StorageType}, args::Pair...; kwargs...) = Object{Nothing}(OT(nothing, (args...,kwargs...)))
Object{UT}(args::Pair...; kwargs...) where {UT} = Object{UT}(DEFAULT_OBJECT_TYPE(nothing, (args...,kwargs...)))
Object(args::Pair...; kwargs...) = Object{Nothing}(args...; kwargs...)

# recursive dict expansion
Object{UT}(OT::Type{<:StorageType}, dict::AbstractDict, args::Pair...; kwargs...) where {UT} = 
    Object{UT}(OT(nothing, ((Symbol(k) => v isa AbstractDict ? Object{UT}(OT, v) : v for (k,v) ∈ dict)...,args...,kwargs...)))
Object(OT::Type{<:StorageType}, dict::AbstractDict, args::Pair...; kwargs...) = 
    Object{Nothing}(OT(nothing, ((Symbol(k) => v isa AbstractDict ? Object(OT, v) : v for (k,v) ∈ dict)...,args...,kwargs...)))
Object{UT}(dict::AbstractDict, args::Pair...; kwargs...) where {UT} =
    Object{UT}(DEFAULT_OBJECT_TYPE(nothing, ((Symbol(k) => v isa AbstractDict ? Object{UT}(v) : v for (k,v) ∈ dict)...,args...,kwargs...)))
Object(dict::AbstractDict, args::Pair...; kwargs...) = Object{Nothing}(dict, args...; kwargs...)

# user-custom composite types
Object{UT}(OT::Type{<:StorageType}, obj, args::Pair...; kwargs...) where {UT} = 
    Object{UT}(OT(nothing, ((k => getproperty(obj,k) for k ∈ propertynames(obj))...,args...,kwargs...)))
Object(OT::Type{<:StorageType}, obj, args::Pair...; kwargs...) =
    Object{Nothing}(OT, obj, args...; kwargs...)
Object{UT}(obj, args::Pair...; kwargs...) where {UT} = 
    Object{UT}(DEFAULT_OBJECT_TYPE, obj, args...; kwargs...)
Object(obj, args::Pair...; kwargs...) = Object{Nothing}(obj, args...; kwargs...)

_storeof(obj::Object) = getfield(obj, :store)

# cute utility taken shamelessly from ConstructionBase.jl
@generated function _constructorof(::Type{T}) where T
    getfield(parentmodule(T), nameof(T))
end

# constructing from a template
@inline (template::Object{UT,OT})(args::Pair...; kwargs...) where {UT,OT} = 
    try Object{UT,OT}(OT(_storeof(template), args, kwargs)) 
    catch e; throw("cannot form argument(s) into template for `Dynamic` or `Mutable` Object.") end

# object type conversion
Object{UTnew}(OTnew::Type{<:StorageType}, obj::Object) where UTnew = 
    Object{UTnew}(OTnew(_getproto(_storeof(obj)), _getprops(_storeof(obj))))
Object(OTnew::Type{<:StorageType}, obj::Object{UT,OT}) where {UT,OT} = 
    Object{UT}(OTnew(_getproto(_storeof(obj)), _getprops(_storeof(obj))))
Object{UTnew}(obj::Object{UT,OT}) where {UTnew,UT,OT} = 
    Object{UTnew}(_constructorof(OT)(_getproto(_storeof(obj)), _getprops(_storeof(obj))))
Object(obj::Object) = obj

# prototype inheritance
Prototype{UT}(OT::Type{<:StorageType}, proto::Object, args::Pair...; kwargs...) where {UT} = Object{UT}(OT(proto, (args...,kwargs...)))
Prototype(OT::Type{<:StorageType}, proto::Object, args::Pair...; kwargs...) = Object{Nothing}(OT(proto, (args...,kwargs...)))
Prototype{newUT}(proto::Object{UT,OT}, args::Pair...; kwargs...) where {newUT,UT,OT} = Object{newUT}(_constructorof(OT)(proto, (args...,kwargs...)))
Prototype(proto::Object{UT,OT}, args::Pair...; kwargs...) where {UT,OT} = Object{UT}(_constructorof(OT)(proto, (args...,kwargs...)))

# interface
Base.getproperty(obj::Object, s::Symbol; iscaller=true) = begin # iscaller is false for nested prototype access
    v = _storeof(obj)[s]
    v isa Function && return iscaller ? ((a...; k...) -> v(obj, a...; k...)) : v
    v
end
Base.setproperty!(obj::Object, s::Symbol, v) = (_storeof(obj)[s] = v)
Base.propertynames(obj::Object) = Tuple(keys(_storeof(obj)))
Base.iterate(obj::Object, state=0, propnames=propertynames(obj)) = begin
    i = state + firstindex(propnames)
    i > lastindex(propnames) && return nothing
    ((propnames[i] => getproperty(obj, propnames[i]; iscaller=false)), state+1)
end
Base.getindex(obj::Object, n) = getproperty(obj, Symbol(n))
Base.setindex!(obj::Object, x, n) = setproperty!(obj, Symbol(n), x)
Base.show(io::IO, obj::Object{UT,OT}) where {UT,OT} = begin
    store = _storeof(obj); props = _getprops(store)
    print(io, "Object{",(UT isa Symbol ? ":" : ""), string(UT),", ", string(nameof(OT)), "}(\n    prototype: ", 
        replace(string(isnothing(_getproto(store)) ? "none" : _getproto(store)), "\n"=>"\n    "), ",\n    properties: ⟨", 
        replace(join(((v isa Object ? "\n" : "")*"$k = $v" for (k,v) ∈ zip(keys(props), values(props))), ", "), "\n"=>"\n    "), "⟩\n)")
end
Base.copy(obj::Object) = begin
    store = _storeof(obj)
    typeof(obj)(typeof(store)(_getproto(store), copy(store.properties)))
end
Base.deepcopy(obj::Object) = begin
    store = _storeof(obj)
    typeof(obj)(typeof(store)(deepcopy(_getproto(store)), copy(store.properties)))
end
Base.:<<(a::Object, b::Object) = (aproto = getfield(a, :store).prototype; isnothing(aproto) ? false : (aproto==b || aproto<<b))

# Object-to-Dictionary conversions
Base.convert(T::Type{<:AbstractDict}, obj::Object) = begin
    store = _storeof(obj); props = _getprops(store)
    isnothing(_getproto(store)) ? T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))) :
    merge(convert(T, _getproto(store)), T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))))
end

"""
    getprototype(obj::Object)::Union{Object, Nothing}

Retrieves `obj`'s prototype object.
"""
getprototype(obj::Object) = _getproto(_storeof(obj))

"""
    ownpropertynames(obj::Object)::Tuple

Retrives `obj`'s property names, excluding those of its prototype
"""
ownpropertynames(obj::Object) = Tuple(keys(_getprops(_storeof(obj))))
"""
    ownproperties(obj::Object)::Base.Generator

Returns a generator for splatting `obj`'s own properties.
"""
ownproperties(obj::Object) = _ownprops_itr(_storeof(obj))

#zr