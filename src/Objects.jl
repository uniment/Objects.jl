module Objects

export Object, Dynamic, Mutable, Static

abstract type ObjectType end

# core `Object` type:
include("object.jl")

# object storage types
include("dynamic.jl")
include("mutable.jl")
include("static.jl")
include("common.jl")    # common to all types

DEFAULT_OBJECT_TYPE = Mutable

end
#zr