# Annotation is the base type of all annotations.
#
# Annotations are compile-time metadata that can be attached to types, methods,
# instance variables, and other language constructs. They allow you to provide
# additional information to the compiler or to macros that can be accessed via
# reflection at compile time.
#
# Each annotation type is declared using the `annotation` keyword:
#
# ```
# annotation MyAnnotation
# end
# ```
#
# Annotations can be applied using the `@[...]` syntax:
#
# ```
# @[MyAnnotation]
# class MyClass
# end
# ```
#
# Each annotation type has the type of its annotation class:
#
# ```
# annotation Foo
# end
#
# annotation Bar
# end
#
# # All annotations inherit from Annotation
# typeof(Foo) # => Foo.class
# Foo.class.superclass # => Annotation.class
# ```
#
# ### Accessing annotations
#
# Annotations are accessible in macros:
#
# ```
# annotation MyAnnotation
# end
#
# @[MyAnnotation(value: 42)]
# class Example
# end
#
# {% if ann = Example.annotation(MyAnnotation) %}
#   {{ ann[:value] }} # => 42
# {% end %}
# ```
struct Annotation
end
