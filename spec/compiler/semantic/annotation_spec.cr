require "../../spec_helper"

describe "Semantic: annotation" do
  it "declares annotation" do
    result = semantic(<<-CRYSTAL)
      annotation Foo
      end
      CRYSTAL

    type = result.program.types["Foo"]
    type.should be_a(AnnotationType)
    type.name.should eq("Foo")
  end

  describe "arguments" do
    describe "#args" do
      it "returns an empty TupleLiteral if there are none defined" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo]
          module Moo
          end

          {% if (pos_args = Moo.annotation(Foo).args) && pos_args.is_a? TupleLiteral && pos_args.empty? %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "returns a TupleLiteral if there are positional arguments defined" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo(1, "foo", true)]
            module Moo
          end

          {% if Moo.annotation(Foo).args == {1, "foo", true} %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end
    end

    describe "#named_args" do
      it "returns an empty NamedTupleLiteral if there are none defined" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo]
          module Moo
          end

          {% if (args = Moo.annotation(Foo).named_args) && args.is_a? NamedTupleLiteral && args.empty? %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "returns a NamedTupleLiteral if there are named arguments defined" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo(extra: "three", "foo": 99)]
            module Moo
          end

          {% if Moo.annotation(Foo).named_args == {extra: "three", foo: 99} %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end
    end

    it "returns a correctly with named and positional args" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo(1, "foo", true, foo: "bar", "cat": 0..0)]
          module Moo
        end

        {% if Moo.annotation(Foo).args == {1, "foo", true} && Moo.annotation(Foo).named_args == {foo: "bar", cat: 0..0} %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end
  end

  describe "#annotations" do
    describe "all types" do
      it "returns an empty array if there are none defined" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end

          module Moo
          end

          {% if Moo.annotations.empty? %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations on a module" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          @[Foo]
          @[Bar]
          module Moo
          end

          {% if Moo.annotations.map(&.name.id) == [Foo.id, Bar.id] %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations on a class" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          @[Foo]
          @[Bar]
          class Moo
          end

          {% if Moo.annotations.map(&.name.id) == [Foo.id, Bar.id] %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations on a struct" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          @[Foo]
          @[Bar]
          struct Moo
          end

          {% if Moo.annotations.map(&.name.id) == [Foo.id, Bar.id] %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations on a enum" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          @[Foo]
          @[Bar]
          enum Moo
            A = 1
          end

          {% if Moo.annotations.map(&.name.id) == [Foo.id, Bar.id] %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations on a lib" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          @[Foo]
          @[Bar]
          lib Moo
            A = 1
          end

          {% if Moo.annotations.map(&.name.id) == [Foo.id, Bar.id] %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations in instance var (declaration)" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          class Moo
            @[Foo]
            @[Bar]
            @x : Int32 = 1

            def foo
              {% if @type.instance_vars.first.annotations.size == 2 %}
                1
              {% else %}
                'a'
              {% end %}
            end
          end

          Moo.new.foo
          CRYSTAL
      end

      it "finds annotations in instance var (declaration, generic)" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          class Moo(T)
            @[Foo]
            @[Bar]
            @x : T

            def initialize(@x : T)
            end

            def foo
              {% if @type.instance_vars.first.annotations.size == 2 %}
                1
              {% else %}
                'a'
              {% end %}
            end
          end

          Moo.new(1).foo
          CRYSTAL
      end

      it "adds annotations on def" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          class Moo
            @[Foo]
            @[Bar]
            def foo
            end
          end

          {% if Moo.methods.first.annotations.size == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations in generic parent (#7885)" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          @[Foo(1)]
          @[Bar(2)]
          class Parent(T)
          end

          class Child < Parent(Int32)
          end

          {% if Child.superclass.annotations.map(&.[0]) == [1, 2] %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "find annotations on method parameters" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          class Moo
            def foo(@[Foo] @[Bar] value)
            end
          end

          {% if Moo.methods.first.args.first.annotations.size == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end
    end

    describe "of a specific type" do
      it "returns an empty array if there are none defined" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          module Moo
          end

          {% if Moo.annotations(Foo).size == 0 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations on a module" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo]
          @[Foo]
          module Moo
          end

          {% if Moo.annotations(Foo).size == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "uses annotations value, positional" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo(1)]
          @[Foo(2)]
          module Moo
          end

          {% if Moo.annotations(Foo)[0][0] == 1 && Moo.annotations(Foo)[1][0] == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "uses annotations value, keyword" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo(x: 1)]
          @[Foo(x: 2)]
          module Moo
          end

          {% if Moo.annotations(Foo)[0][:x] == 1 && Moo.annotations(Foo)[1][:x] == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations in class" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo]
          @[Foo]
          @[Foo]
          class Moo
          end

          {% if Moo.annotations(Foo).size == 3 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations in struct" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo]
          @[Foo]
          @[Foo]
          @[Foo]
          struct Moo
          end

          {% if Moo.annotations(Foo).size == 4 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations in enum" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo]
          enum Moo
            A = 1
          end

          {% if Moo.annotations(Foo).size == 1 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations in lib" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo]
          @[Foo]
          lib Moo
            A = 1
          end

          {% if Moo.annotations(Foo).size == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "can't find annotations in instance var" do
        assert_type(<<-CRYSTAL) { char }
          annotation Foo
          end

          class Moo
            @x : Int32 = 1

            def foo
              {% unless @type.instance_vars.first.annotations(Foo).empty? %}
                1
              {% else %}
                'a'
              {% end %}
            end
          end

          Moo.new.foo
          CRYSTAL
      end

      it "can't find annotations in instance var, when other annotations are present" do
        assert_type(<<-CRYSTAL) { char }
          annotation Foo
          end

          annotation Bar
          end

          class Moo
            @[Bar]
            @x : Int32 = 1

            def foo
              {% unless @type.instance_vars.first.annotations(Foo).empty? %}
                1
              {% else %}
                'a'
              {% end %}
            end
          end

          Moo.new.foo
          CRYSTAL
      end

      it "finds annotations in instance var (declaration)" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          class Moo
            @[Foo]
            @[Foo]
            @x : Int32 = 1

            def foo
              {% if @type.instance_vars.first.annotations(Foo).size == 2 %}
                1
              {% else %}
                'a'
              {% end %}
            end
          end

          Moo.new.foo
          CRYSTAL
      end

      it "finds annotations in instance var (declaration, generic)" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          class Moo(T)
            @[Foo]
            @x : T

            def initialize(@x : T)
            end

            def foo
              {% if @type.instance_vars.first.annotations(Foo).size == 1 %}
                1
              {% else %}
                'a'
              {% end %}
            end
          end

          Moo.new(1).foo
          CRYSTAL
      end

      it "collects annotations values in type" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          @[Foo(1)]
          module Moo
          end

          @[Foo(2)]
          module Moo
          end

          {% if Moo.annotations(Foo)[0][0] == 1 && Moo.annotations(Foo)[1][0] == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "overrides annotations value in type" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          class Moo
            @[Foo(1)]
            @x : Int32 = 1
          end

          class Moo
            @[Foo(2)]
            @x : Int32 = 1

            def foo
              {% if @type.instance_vars.first.annotations(Foo).size == 1 && @type.instance_vars.first.annotations(Foo)[0][0] == 2 %}
                1
              {% else %}
                'a'
              {% end %}
            end
          end

          Moo.new.foo
          CRYSTAL
      end

      it "adds annotations on def" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo
          end

          class Moo
            @[Foo]
            @[Foo]
            def foo
            end
          end

          {% if Moo.methods.first.annotations(Foo).size == 2 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "can't find annotations on def" do
        assert_type(<<-CRYSTAL) { char }
          annotation Foo
          end

          class Moo
            def foo
            end
          end

          {% unless Moo.methods.first.annotations(Foo).empty? %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "can't find annotations on def, when other annotations are present" do
        assert_type(<<-CRYSTAL) { char }
          annotation Foo
          end

          annotation Bar
          end

          class Moo
            @[Bar]
            def foo
            end
          end

          {% unless Moo.methods.first.annotations(Foo).empty? %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end

      it "finds annotations in generic parent (#7885)" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Ann
          end

          @[Ann(1)]
          class Parent(T)
          end

          class Child < Parent(Int32)
          end

          {{ Child.superclass.annotations(Ann)[0][0] }}
          CRYSTAL
      end

      it "find annotations on method parameters" do
        assert_type(<<-CRYSTAL) { int32 }
          annotation Foo; end
          annotation Bar; end

          class Moo
            def foo(@[Foo] @[Bar] value)
            end
          end

          {% if Moo.methods.first.args.first.annotations(Foo).size == 1 %}
            1
          {% else %}
            'a'
          {% end %}
          CRYSTAL
      end
    end
  end

  describe "#annotation" do
    it "can't find annotation in module" do
      assert_type(<<-CRYSTAL) { char }
        annotation Foo
        end

        module Moo
        end

        {% if Moo.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "can't find annotation in module, when other annotations are present" do
      assert_type(<<-CRYSTAL) { char }
        annotation Foo
        end

        annotation Bar
        end

        @[Bar]
        module Moo
        end

        {% if Moo.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation in module" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo]
        module Moo
        end

        {% if Moo.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "uses annotation value, positional" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo(1)]
        module Moo
        end

        {% if Moo.annotation(Foo)[0] == 1 %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "uses annotation value, keyword" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo(x: 1)]
        module Moo
        end

        {% if Moo.annotation(Foo)[:x] == 1 %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation in class" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo]
        class Moo
        end

        {% if Moo.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation in struct" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo]
        struct Moo
        end

        {% if Moo.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation in enum" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo]
        enum Moo
          A = 1
        end

        {% if Moo.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation in lib" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo]
        lib Moo
          A = 1
        end

        {% if Moo.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "can't find annotation in instance var" do
      assert_type(<<-CRYSTAL) { char }
        annotation Foo
        end

        class Moo
          @x : Int32 = 1

          def foo
            {% if @type.instance_vars.first.annotation(Foo) %}
              1
            {% else %}
              'a'
            {% end %}
          end
        end

        Moo.new.foo
        CRYSTAL
    end

    it "can't find annotation in instance var, when other annotations are present" do
      assert_type(<<-CRYSTAL) { char }
        annotation Foo
        end

        annotation Bar
        end

        class Moo
          @[Bar]
          @x : Int32 = 1

          def foo
            {% if @type.instance_vars.first.annotation(Foo) %}
              1
            {% else %}
              'a'
            {% end %}
          end
        end

        Moo.new.foo
        CRYSTAL
    end

    it "finds annotation in instance var (declaration)" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        class Moo
          @[Foo]
          @x : Int32 = 1

          def foo
            {% if @type.instance_vars.first.annotation(Foo) %}
              1
            {% else %}
              'a'
            {% end %}
          end
        end

        Moo.new.foo
        CRYSTAL
    end

    it "finds annotation in instance var (assignment)" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        class Moo
          @[Foo]
          @x = 1

          def foo
            {% if @type.instance_vars.first.annotation(Foo) %}
              1
            {% else %}
              'a'
            {% end %}
          end
        end

        Moo.new.foo
        CRYSTAL
    end

    it "finds annotation in instance var (declaration, generic)" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        class Moo(T)
          @[Foo]
          @x : T

          def initialize(@x : T)
          end

          def foo
            {% if @type.instance_vars.first.annotation(Foo) %}
              1
            {% else %}
              'a'
            {% end %}
          end
        end

        Moo.new(1).foo
        CRYSTAL
    end

    it "overrides annotation value in type" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo(1)]
        module Moo
        end

        @[Foo(2)]
        module Moo
        end

        {% if Moo.annotation(Foo)[0] == 2 %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "overrides annotation in instance var" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        class Moo
          @[Foo(1)]
          @x : Int32 = 1
        end

        class Moo
          @[Foo(2)]
          @x : Int32 = 1

          def foo
            {% if @type.instance_vars.first.annotation(Foo)[0] == 2 %}
              1
            {% else %}
              'a'
            {% end %}
          end
        end

        Moo.new.foo
        CRYSTAL
    end

    it "errors if annotation doesn't exist" do
      assert_error <<-CRYSTAL, "undefined constant DoesntExist"
        @[DoesntExist]
        class Moo
        end
        CRYSTAL
    end

    it "errors if annotation doesn't point to an annotation type" do
      assert_error <<-CRYSTAL, "Int32 is not an annotation, it's a struct"
        @[Int32]
        class Moo
        end
        CRYSTAL
    end

    it "errors if using annotation other than ThreadLocal for class vars" do
      assert_error <<-CRYSTAL, "class variables can only be annotated with ThreadLocal"
        annotation Foo
        end

        class Moo
          @[Foo]
          @@x = 0
        end
        CRYSTAL
    end

    it "adds annotation on def" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        class Moo
          @[Foo]
          def foo
          end
        end

        {% if Moo.methods.first.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "can't find annotation on def" do
      assert_type(<<-CRYSTAL) { char }
        annotation Foo
        end

        class Moo
          def foo
          end
        end

        {% if Moo.methods.first.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "can't find annotation on def, when other annotations are present" do
      assert_type(<<-CRYSTAL) { char }
        annotation Foo
        end

        annotation Bar
        end

        class Moo
          @[Bar]
          def foo
          end
        end

        {% if Moo.methods.first.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "errors if using invalid annotation on fun" do
      assert_error <<-CRYSTAL, "funs can only be annotated with: NoInline, AlwaysInline, Naked, ReturnsTwice, Raises, CallConvention"
        annotation Foo
        end

        @[Foo]
        fun foo : Void
        end
        CRYSTAL
    end

    it "doesn't carry link annotation from lib to fun" do
      assert_no_errors <<-CRYSTAL
        @[Link("foo")]
        lib LibFoo
          fun foo
        end
        CRYSTAL
    end

    it "finds annotation in generic parent (#7885)" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Ann
        end

        @[Ann(1)]
        class Parent(T)
        end

        class Child < Parent(Int32)
        end

        {{ Child.superclass.annotation(Ann)[0] }}
        CRYSTAL
    end

    it "finds annotation on method arg" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Ann; end

        def foo(
          @[Ann] foo : Int32
        )
        end

        {% if @top_level.methods.find(&.name.==("foo")).args.first.annotation(Ann) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation on method splat arg" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Ann; end

        def foo(
          id : Int32,
          @[Ann] *nums : Int32
        )
        end

        {% if @top_level.methods.find(&.name.==("foo")).args[1].annotation(Ann) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation on method double splat arg" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Ann; end

        def foo(
          id : Int32,
          @[Ann] **nums
        )
        end

        {% if @top_level.methods.find(&.name.==("foo")).double_splat.annotation(Ann) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds annotation on an restricted method block arg" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Ann; end

        def foo(
          id : Int32,
          @[Ann] &block : Int32 ->
        )
          yield 10
        end

        {% if @top_level.methods.find(&.name.==("foo")).block_arg.annotation(Ann) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end
  end

  it "errors when annotate instance variable in subclass" do
    assert_error <<-CRYSTAL, "can't annotate @x in Child because it was first defined in Base"
      annotation Foo
      end

      class Base
        @x : Nil
      end

      class Child < Base
        @[Foo]
        @x : Nil
      end
      CRYSTAL
  end

  it "errors if wanting to add type inside annotation (1) (#8614)" do
    assert_error <<-CRYSTAL, "can't declare type inside annotation Ann"
      annotation Ann
      end

      class Ann::Foo
      end

      Ann::Foo.new
      CRYSTAL
  end

  it "errors if wanting to add type inside annotation (2) (#8614)" do
    assert_error <<-CRYSTAL, "can't declare type inside annotation Ann"
      annotation Ann
      end

      class Ann::Foo::Bar
      end

      Ann::Foo::Bar.new
      CRYSTAL
  end

  it "doesn't bleed annotation from class into class variable (#8314)" do
    assert_no_errors <<-CRYSTAL
      annotation Attr; end

      @[Attr]
      class Bar
        @@x = 0
      end
      CRYSTAL
  end

  describe "annotation class" do
    it "declares annotation class" do
      result = semantic(<<-CRYSTAL)
        annotation class Foo
        end
        CRYSTAL

      type = result.program.types["Foo"]
      type.should be_a(NonGenericClassType)
      type.as(ClassType).annotation_class?.should be_true
      type.name.should eq("Foo")
    end

    it "declares annotation struct" do
      result = semantic(<<-CRYSTAL)
        annotation struct Foo
        end
        CRYSTAL

      type = result.program.types["Foo"]
      type.should be_a(NonGenericClassType)
      type.as(ClassType).annotation_class?.should be_true
      type.as(ClassType).struct?.should be_true
    end

    it "declares abstract annotation class" do
      result = semantic(<<-CRYSTAL)
        abstract annotation class Foo
        end
        CRYSTAL

      type = result.program.types["Foo"]
      type.should be_a(NonGenericClassType)
      type.as(ClassType).annotation_class?.should be_true
      type.as(ClassType).abstract?.should be_true
    end

    it "allows using annotation class as @[Foo]" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
        end

        @[Foo]
        class Bar
        end

        {% if Bar.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "allows annotation class inheritance" do
      assert_no_errors <<-CRYSTAL
        abstract annotation class Constraint
        end

        annotation class NotBlank < Constraint
        end
        CRYSTAL
    end

    it "finds child annotations via parent type" do
      assert_type(<<-CRYSTAL) { int32 }
        abstract annotation class Constraint
        end

        annotation class NotBlank < Constraint
        end

        @[NotBlank]
        class Foo
        end

        {% if Foo.annotation(Constraint) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds all child annotations via parent type" do
      assert_type(<<-CRYSTAL) { int32 }
        abstract annotation class Constraint
        end

        annotation class NotBlank < Constraint
        end

        annotation class Length < Constraint
        end

        @[NotBlank]
        @[Length]
        class Foo
        end

        {% if Foo.annotations(Constraint).size == 2 %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "new_instance generates .new call" do
      assert_type(<<-CRYSTAL) { types["NotBlank"] }
        annotation class NotBlank
          def initialize(@message : String = "cannot be blank")
          end

          def message
            @message
          end
        end

        @[NotBlank]
        class Foo
        end

        {% begin %}
          {{ Foo.annotation(NotBlank).new_instance }}
        {% end %}
        CRYSTAL
    end

    it "new_instance passes named args" do
      assert_type(<<-CRYSTAL) { string }
        annotation class NotBlank
          def initialize(@message : String = "cannot be blank")
          end

          def message
            @message
          end
        end

        @[NotBlank(message: "custom message")]
        class Foo
        end

        {% begin %}
          {{ Foo.annotation(NotBlank).new_instance }}.message
        {% end %}
        CRYSTAL
    end

    it "errors when reopening non-annotation class as annotation class" do
      assert_error <<-CRYSTAL, "Foo is not an annotation class"
        class Foo
        end

        annotation class Foo
        end
        CRYSTAL
    end

    it "errors when reopening annotation class as non-annotation class" do
      assert_error <<-CRYSTAL, "Foo is not an annotation class"
        annotation class Foo
        end

        class Foo
        end
        CRYSTAL
    end

    # Validation tests
    it "validates named arg exists in initialize" do
      assert_error <<-CRYSTAL, "@[Foo] has no parameter 'unknown'"
        annotation class Foo
          def initialize(@message : String)
          end
        end

        @[Foo(unknown: "value")]
        class Bar
        end
        CRYSTAL
    end

    it "validates positional arg count" do
      assert_error <<-CRYSTAL, "@[Foo] argument at position 1 doesn't match any constructor parameter"
        annotation class Foo
          def initialize(@message : String)
          end
        end

        @[Foo("hello", "extra")]
        class Bar
        end
        CRYSTAL
    end

    it "validates named arg type (string vs number)" do
      assert_error <<-CRYSTAL, "@[Foo] has no parameter 'message'"
        annotation class Foo
          def initialize(@message : String)
          end
        end

        @[Foo(message: 123)]
        class Bar
        end
        CRYSTAL
    end

    it "validates positional arg type" do
      assert_error <<-CRYSTAL, "@[Foo] argument at position 0 doesn't match any constructor parameter"
        annotation class Foo
          def initialize(@count : Int32)
          end
        end

        @[Foo("not a number")]
        class Bar
        end
        CRYSTAL
    end

    it "accepts valid args with correct types" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@message : String, @count : Int32)
          end
        end

        @[Foo("hello", 42)]
        class Bar
        end

        {% if Bar.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "accepts valid named args" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@message : String, @count : Int32 = 0)
          end
        end

        @[Foo(message: "hello", count: 10)]
        class Bar
        end

        {% if Bar.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "accepts union types" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@value : String | Int32)
          end
        end

        @[Foo("string")]
        class Bar
        end

        @[Foo(123)]
        class Baz
        end

        {% if Bar.annotation(Foo) && Baz.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "validates union type mismatch" do
      assert_error <<-CRYSTAL, "@[Foo] argument at position 0 doesn't match any constructor parameter"
        annotation class Foo
          def initialize(@value : String | Int32)
          end
        end

        @[Foo(:symbol)]
        class Bar
        end
        CRYSTAL
    end

    it "rejects no args when initialize requires arguments" do
      assert_error <<-CRYSTAL, "@[Foo] is missing required arguments"
        annotation class Foo
          def initialize(@message : String)
          end
        end

        @[Foo]
        class Bar
        end
        CRYSTAL
    end

    it "accepts no args when initialize has defaults" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@message : String = "default")
          end
        end

        @[Foo]
        class Bar
        end

        {% if Bar.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "validates with multiple overloads - accepts if any matches" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@message : String, @count : Int32 = 0)
          end

          def initialize(@count : Int32, @message : String = "")
          end
        end

        @[Foo("string")]
        class Bar
        end

        @[Foo(123)]
        class Baz
        end

        {% if Bar.annotation(Foo) && Baz.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "errors when no args but initialize requires them" do
      assert_error <<-CRYSTAL, "@[Foo] has arguments but Foo has no constructor"
        annotation class Foo
        end

        @[Foo("arg")]
        class Bar
        end
        CRYSTAL
    end

    it "accepts double splat for any named args" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(**options)
          end
        end

        @[Foo(any_name: "value", another: 123)]
        class Bar
        end

        {% if Bar.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "accepts array literal for Array type" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@items : Array(String))
          end
        end

        @[Foo(["a", "b", "c"])]
        class Bar
        end

        {% if Bar.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "accepts hash literal for Hash type" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@map : Hash(String, Int32))
          end
        end

        @[Foo({"a" => 1, "b" => 2})]
        class Bar
        end

        {% if Bar.annotation(Foo) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    # Default value tests
    it "ann[:field] returns default from initialize when not explicitly set" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@message : String = "default_message")
          end
        end

        @[Foo]
        class Bar
        end

        {% if Bar.annotation(Foo)[:message] == "default_message" %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "ann[:field] returns explicit value over default" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@message : String = "default_message")
          end
        end

        @[Foo(message: "explicit")]
        class Bar
        end

        {% if Bar.annotation(Foo)[:message] == "explicit" %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "ann[:field] returns nil for non-existent field without default" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@message : String)
          end
        end

        @[Foo("hello")]
        class Bar
        end

        {% if Bar.annotation(Foo)[:nonexistent] == nil %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "ann[:field] returns default from any overload" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def initialize(@count : Int32, @message : String = "from_int")
          end

          def initialize(@message : String, @count : Int32 = 0)
          end
        end

        @[Foo(42)]
        class Bar
        end

        {% if Bar.annotation(Foo)[:message] == "from_int" %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "does not allow providing a parent initializer's params when child defines own" do
      assert_error <<-CRYSTAL, "@[Child] has no parameter 'message'"
          abstract annotation class Parent
            def initialize(@message : String)
            end
          end

          annotation class Child < Parent
            def initialize(@id : Int32)
              super "foo"
            end
          end

          @[Child(message: "bar")]
          class Bar
          end
        CRYSTAL
    end

    it "accepts parent's initialize params when child has no initialize" do
      assert_type(<<-CRYSTAL) { int32 }
        abstract annotation class Parent
          def initialize(@message : String)
          end
        end

        annotation class Child < Parent
          def initialize(@id : Int32)
            super "foo"
          end
        end

        @[Child(id: 123)]
        class Bar
        end

        {% if Bar.annotation(Child) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    # self.new validation tests
    it "validates against self.new parameters" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Size
          def self.new(range : Range(Int32, Int32))
            new range.begin, range.end
          end

          def initialize(@min : Int32, @max : Int32)
          end
        end

        @[Size(1..10)]
        class Bar
        end

        {% if Bar.annotation(Size) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "rejects args not matching any self.new or initialize" do
      assert_error <<-CRYSTAL, "@[Size] has no parameter 'invalid'"
        annotation class Size
          def self.new(range : Range(Int32, Int32))
            new range.begin, range.end
          end

          def initialize(@min : Int32, @max : Int32)
          end
        end

        @[Size(invalid: "value")]
        class Bar
        end
        CRYSTAL
    end

    it "accepts self.new positional arg even if initialize is private" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Size
          def self.new(range : Range(Int32, Int32))
            new range.begin, range.end
          end

          private def initialize(@min : Int32, @max : Int32)
          end
        end

        @[Size(1..10)]
        class Bar
        end

        {% if Bar.annotation(Size) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "rejects private initialize params when self.new exists" do
      assert_error <<-CRYSTAL, "@[Size] argument at position 0 doesn't match any constructor parameter"
        annotation class Size
          def self.new(range : Range(Int32, Int32))
            new range.begin, range.end
          end

          private def initialize(@min : Int32, @max : Int32)
          end
        end

        @[Size(1, 10)]
        class Bar
        end
        CRYSTAL
    end

    it "gets default value from self.new parameter" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation class Foo
          def self.new(range : Range(Int32, Int32) = 1..10)
            new range.begin, range.end
          end

          private def initialize(@min : Int32, @max : Int32)
          end
        end

        @[Foo]
        class Bar
        end

        {% if Bar.annotation(Foo)[:range] == (1..10) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end
  end
end
