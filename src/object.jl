"""
    Object{[TypeTag]}([StorageType] [; kwargs...])

Create a structured `Object` with properties specified by keyword arguments `kwargs`. Object type can be specified by `StorageType`, and additional type parameters can be specified by `TypeTag`. Later properties override earlier ones.

Other iterable key=>value mappings, as from generators and other `Object`s, can be splatted into the keyword arguments as well.

`StorageType` can be `Static`, `Mutable`, or `Dynamic`, depending on performance needs. If not specified, default is `Mutable`.

`TypeTag` is optional and does not affect `Object` behavior, but can be used to leverage Julia's type inference engine for multiple method dispatch.

    Object{[TypeTag]}([StorageType,] props::AbstractDict [; kwargs...])

Create an `Object` from a dictionary recursively with optional overriding properties set by `kwargs`.

    Object{[TypeTag]}([StorageType,] obj::Any [; kwargs...])

Create an `Object` from an arbitrary composite type with optional overriding properties set by `kwargs`.

    Object{[TypeTag]}([StorageType,] obj::Object [; kwargs...])

Convert an `Object` from one set of `StorageType` and `TypeTag` to another, keeping prototype, with optional overriding properties set by `kwargs`. 

    (proto::Object)([StorageType] [; kwargs...])

Every `Object` is a constructor. Call on the object to use it as a template for creating a new object with the exact same property names and types. Replicating a template is fast and efficient, especially for `Static` and `Mutable` types.

    Prototype{[TypeTag]}([StorageType,] proto::Object [; kwargs...])

Create a new object which references object `proto` as its prototype.

    obj.meth = function(self, a, b, c) #=...=# end
    obj.meth(a, b, c)

Calls a member method `meth` and passes `obj` as the first argument.

    (; x, y, z) = obj

Destructure properties `x`, `y`, and `z` out of `obj`.
"""
struct Object{UserType, StorageType}
    store::StorageType
end


_storeof(obj::Object) = getfield(obj, :store)

# default constructor
Object{UT}(store::OT) where {UT,OT<:StorageType} = Object{UT,OT}(store)
Object(store::OT) where {OT<:StorageType} = Object{Nothing,OT}(store)

# constructing from scratch
# too much copypasta ... fix this up someday like a real programmer

# splatted objects and keyword arguments
Object{UT}(OT::Type{<:StorageType}; kwargs...) where {UT} = Object{UT}(OT(nothing, kwargs))
Object(OT::Type{<:StorageType}; kwargs...) = Object{Nothing}(OT(nothing, kwargs))
Object{UT}(; kwargs...) where {UT} = Object{UT}(DEFAULT_OBJECT_TYPE(nothing, kwargs))
Object(; kwargs...) = Object{Nothing}(; kwargs...)

# recursive dict expansion
Object{UT}(OT::Type{<:StorageType}, dict::AbstractDict; kwargs...) where {UT} = 
    Object{UT}(OT(nothing, ((Symbol(k) => v isa AbstractDict ? Object{UT}(OT, v) : v for (k,v) ∈ dict)...,kwargs...)))
Object(OT::Type{<:StorageType}, dict::AbstractDict; kwargs...) = 
    Object{Nothing}(OT(nothing, ((Symbol(k) => v isa AbstractDict ? Object(OT, v) : v for (k,v) ∈ dict)...,kwargs...)))
Object{UT}(dict::AbstractDict; kwargs...) where {UT} =
    Object{UT}(DEFAULT_OBJECT_TYPE(nothing, ((Symbol(k) => v isa AbstractDict ? Object{UT}(v) : v for (k,v) ∈ dict)...,kwargs...)))
Object(dict::AbstractDict; kwargs...) = Object{Nothing}(dict; kwargs...)

# user-custom composite types
Object{UT}(OT::Type{<:StorageType}, obj; kwargs...) where {UT} = 
    Object{UT}(OT(nothing, ((k => getproperty(obj,k) for k ∈ propertynames(obj))...,kwargs...)))
Object(OT::Type{<:StorageType}, obj; kwargs...) =
    Object{Nothing}(OT, obj; kwargs...)
Object{UT}(obj; kwargs...) where {UT} = 
    Object{UT}(DEFAULT_OBJECT_TYPE, obj; kwargs...)
Object(obj; kwargs...) = Object{Nothing}(obj; kwargs...)


# cute utility taken shamelessly from ConstructionBase.jl
@generated function _constructorof(::Type{T}) where T
    getfield(parentmodule(T), nameof(T))
end

# constructing from a template
@inline (template::Object{UT,OT})(; kwargs...) where {UT,OT} = 
    Object{UT,OT}(OT(Val(:template), _storeof(template), kwargs)) 

# object type conversion
Object{UTnew}(OTnew::Type{<:StorageType}, obj::Object; kwargs...) where UTnew = 
    Object{UTnew}(OTnew(_getproto(_storeof(obj)), merge(_getprops(_storeof(obj)), kwargs)))
Object(OTnew::Type{<:StorageType}, obj::Object{UT,OT}; kwargs...) where {UT,OT} = 
    Object{UT}(OTnew(_getproto(_storeof(obj)), merge(_getprops(_storeof(obj)), kwargs)))
Object{UTnew}(obj::Object{UT,OT}; kwargs...) where {UTnew,UT,OT} = 
    Object{UTnew}(_constructorof(OT)(_getproto(_storeof(obj)), merge(_getprops(_storeof(obj)), kwargs)))
Object(obj::Object{UT,OT}; kwargs...) where {UT,OT} = Object{UT}(obj; kwargs...)
Object(obj::Object) = obj

# prototype inheritance
Prototype{UT}(OT::Type{<:StorageType}, proto::Object; kwargs...) where {UT} = Object{UT}(OT(proto, kwargs))
Prototype(OT::Type{<:StorageType}, proto::Object; kwargs...) = Object{Nothing}(OT(proto, kwargs))
Prototype{newUT}(proto::Object{UT,OT}; kwargs...) where {newUT,UT,OT} = Object{newUT}(_constructorof(OT)(proto, kwargs))
Prototype(proto::Object{UT,OT}; kwargs...) where {UT,OT} = Object{UT}(_constructorof(OT)(proto, kwargs))

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
        replace(join([(v isa Object ? "\n" : "")*"$k = $v" for (k,v) ∈ zip(keys(props), values(props))], ", "), "\n"=>"\n    "), "⟩\n)")
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