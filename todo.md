# Things to do

Is there a way to construct objects off of a *template*? To use the template as a faster constructor?

Syntax:

```julia
    Object(template::Object; kwargs...)
```




Mull over objects.jl for "OT.name.wrapper" vs. "getfield(parentmodule(OT), nameof(OT))".





- Make Tests
- Refactor the various `Object{[TypeTag]}([StorageType] ... )` definitions into generated functions 
- add args...;kwargs... constructor syntax to argument of type `Dict`? 
- when `Object`ifying arbitrary objects, can we access their base address?
- Use an ordered dict for Dynamic type?
- add name and type checking to make `Dynamic` template constructor


## Strings and numbers

currently can access not just by symbol, but by string and number
```julia
obj = Object(a=1, b=2)
obj["a"]
```

but cannot set by string or number
```julia
obj = Object("a"=>1) # fail
```

Should this be made more consistent?
