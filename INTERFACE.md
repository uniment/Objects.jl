old interface

```julia
# constructing from scratch
    Object{[TypeTag]}([StorageType,] [args::Pair{Symbol,V} where V...] [; kwargs...])            # normal construction
    Object{[TypeTag]}([StorageType,] obj::Any[, args::Pair{Symbol,V} where V...] [; kwargs...])  # taking in arbitrary types
    Object{[TypeTag]}([StorageType,] props::AbstractDict)                                        # recursing through dictionary
# changing type
    Object{[TypeTag]}([StorageType,] obj::Object)                                                
# inheritance
    (proto::Object)([StorageType,] [args::Pair{Symbol, T} where T...] [; props...])              # inherit from proto
```

new interface

```julia
# constructing from scratch
    Object{[TypeTag]}([StorageType,] [args::Pair...] [; kwargs...])                              # normal construction
# changing type ("converting")
    Object{[TypeTag]}([StorageType,] obj::Object[, args::Pair...] [; kwargs...])
    Object{[TypeTag]}([StorageType,] obj::Any[, args::Pair...] [; kwargs...])                    # taking in arbitrary types
    Object{[TypeTag]}([StorageType,] props::AbstractDict[, args::Pair...] [; kwargs...])         # recursing through dictionary
# constructing from template
    (template::Object)([args::Pair...] [; props...])                                             # replicate with new values
# inheritance
    Prototype{[TypeTag]}([StorageType,] obj::Object[, args::Pair...] [; kwargs...])
```

