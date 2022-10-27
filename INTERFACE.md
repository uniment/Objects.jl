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
    Object{[TypeTag]}([StorageType] [; kwargs...])                             # normal construction
# changing type ("converting")
    Object{[TypeTag]}([StorageType,] obj::Object [; kwargs...])                 # creates new object, preserves prototype
    Object{[TypeTag]}([StorageType,] obj::Any [; kwargs...])                    # copies properties of arbitrary types
    Object{[TypeTag]}([StorageType,] props::AbstractDict [; kwargs...])         # recursing through dictionary
# constructing from template
    (template::Object)([; kwargs...])                                           # replicate with new values
# inheritance
    Prototype{[TypeTag]}([StorageType,] proto::Object [; kwargs...])
```

newest interface


```julia
# constructing from scratch
    Object{[TypeTag]}([StorageType] [; kwargs...])                             # normal construction
# changing type ("converting")
    Object{[TypeTag]}([StorageType,] obj::Object)                               # change type of object
    Object{[TypeTag]}([StorageType,] obj::Any)                                  # copies properties of arbitrary types
    Object{[TypeTag]}([StorageType,] props::AbstractDict)                       # recursing through dictionary
# constructing from template
    (template::Object)([; kwargs...])                                           # replicate with new values
# inheritance
    Object{[TypeTag]}([StorageType,] (proto::Object,) [; kwargs...])            # notice the one-size tuple
```