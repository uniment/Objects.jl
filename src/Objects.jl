module Objects

export Object, Prototype, Dynamic, Mutable, Static, getprototype, ownpropertynames, ownproperties

abstract type Prototype{A,B} end
abstract type StorageType end

# core `Object` type:
include("object.jl")

# object storage types
include("common.jl") # rename this file one day

const DEFAULT_STORAGE_TYPE = Mutable

end
#zr