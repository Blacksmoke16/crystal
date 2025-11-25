# `Annotation` is the base type for all annotation types.
#
# All annotation types (defined with the `annotation` keyword) have
# `Annotation` as their metaclass. This allows using `Annotation`
# as a type constraint for any annotation type:
#
# ```
# annotation Foo; end
# annotation Bar; end
#
# Foo.class        # => Annotation
# Bar.class        # => Annotation
# Annotation.class # => Annotation
# ```
#
# Annotation types cannot be instantiated.
struct Annotation
  def inspect(io : IO) : Nil
    to_s(io)
  end

  # See `Object#hash(hasher)`
  def hash(hasher)
    hasher.class(self)
  end

  # Returns whether this annotation type is the same as *other*.
  def ==(other : Annotation) : Bool
    crystal_type_id == other.crystal_type_id
  end

  def to_s(io : IO) : Nil
    io << {{ @type.name.stringify }}
  end

  def dup
    self
  end

  def clone
    self
  end
end
