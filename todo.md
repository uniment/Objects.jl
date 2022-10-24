# Things to do

- Make Tests
- Refactor the various `Object{[TypeTag]}([ObjectType] ... )` definitions into generated functions 


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
