getproto(store) = store.prototype


Base.keys(store::ObjectType) = union(
    keys(store.properties),
    isnothing(store.prototype) ? () : propertynames(store.prototype)
)

#zr