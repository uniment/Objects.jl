# Things to do

Mull over objects.jl for "OT.name.wrapper" vs. "getfield(parentmodule(OT), nameof(OT))".


- Make Tests
- Refactor the various `Object{[TypeTag]}([ObjectType] ... )` definitions into generated functions 
- add args...;kwargs... constructor syntax to argument of type `Dict`
- when `Object`ifying arbitrary objects, can we access their base address?


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
