module Objects

export Object, Prototype, Dynamic, Mutable, Static, getprototype, ownpropertynames, ownproperties

abstract type StorageType end

# core `Object` type:
include("object.jl")

# object storage types
include("storage.jl")

const DEFAULT_STORAGE_TYPE = Mutable

end
#zr