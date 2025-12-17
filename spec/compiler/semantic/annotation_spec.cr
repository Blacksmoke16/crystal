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

  # Annotations 2.0: Typed fields, inheritance, and runtime class generation

  describe "typed fields" do
    it "declares annotation with typed fields" do
      result = semantic(<<-CRYSTAL)
        annotation Foo
          message : StringLiteral
          count : NumberLiteral = 0
        end
        CRYSTAL

      type = result.program.types["Foo"].as(AnnotationType)
      type.should be_a(AnnotationType)
      type.has_fields?.should be_true

      fields = type.all_fields
      fields.size.should eq(2)
      fields[0].name.should eq("message")
      fields[1].name.should eq("count")
    end

    it "declares annotation with default values" do
      result = semantic(<<-CRYSTAL)
        annotation NotBlank
          message : StringLiteral = "must not be blank"
          allow_nil : BoolLiteral = false
        end
        CRYSTAL

      type = result.program.types["NotBlank"].as(AnnotationType)
      fields = type.all_fields
      fields[0].default_value.should be_a(Crystal::StringLiteral)
      fields[1].default_value.should be_a(Crystal::BoolLiteral)
    end

    it "accesses field values via [] in macro" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation NotBlank
          message : StringLiteral = "default"
        end

        @[NotBlank(message: "custom")]
        class Foo
        end

        {% if Foo.annotation(NotBlank)[:message] == "custom" %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "uses default value when field not provided" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end

        @[NotBlank]
        class Foo
        end

        {% if Foo.annotation(NotBlank)[:message] == "must not be blank" %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "supports ArrayLiteral field type with default" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        @[Constraint]
        class Foo
        end

        {% if Foo.annotation(Constraint)[:groups].is_a?(ArrayLiteral) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "allows custom array values" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        @[Constraint(groups: ["validation", "security"])]
        class Foo
        end

        {% if Foo.annotation(Constraint)[:groups].size == 2 %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end
  end

  describe "annotation inheritance" do
    it "declares annotation with superclass" do
      result = semantic(<<-CRYSTAL)
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral = "must not be blank"
        end
        CRYSTAL

      constraint = result.program.types["Constraint"].as(AnnotationType)
      not_blank = result.program.types["NotBlank"].as(AnnotationType)

      not_blank.superclass.should eq(constraint)
    end

    it "inherits fields from parent annotation" do
      result = semantic(<<-CRYSTAL)
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral = "must not be blank"
        end
        CRYSTAL

      not_blank = result.program.types["NotBlank"].as(AnnotationType)
      all_fields = not_blank.all_fields

      all_fields.size.should eq(2)
      all_fields[0].name.should eq("groups")  # inherited
      all_fields[1].name.should eq("message") # own
    end

    it "accesses inherited field values in macro" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral = "must not be blank"
        end

        @[NotBlank(groups: ["validation"])]
        class Foo
        end

        {% if Foo.annotation(NotBlank)[:groups].size == 1 %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "finds child annotations via parent type" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral
        end

        @[NotBlank(message: "required")]
        class Foo
        end

        # annotations(Parent) should return child annotations too
        {% if Foo.annotation(Constraint) %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end
  end

  describe "private fields" do
    it "declares private fields" do
      result = semantic(<<-CRYSTAL)
        annotation FullName
          private first_name : StringLiteral
          private last_name : StringLiteral
          name : StringLiteral = "computed"
        end
        CRYSTAL

      type = result.program.types["FullName"].as(AnnotationType)
      fields = type.all_fields

      fields.size.should eq(3)
      fields[0].visibility.private?.should be_true
      fields[1].visibility.private?.should be_true
      fields[2].visibility.private?.should be_false
    end

    it "accesses private fields in macro" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation FullName
          private first_name : StringLiteral
          private last_name : StringLiteral
          name : StringLiteral = "computed"
        end

        @[FullName(first_name: "John", last_name: "Doe", name: "John Doe")]
        class Person
        end

        {% if Person.annotation(FullName)[:first_name] == "John" %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "has_public_fields? returns false when only private fields" do
      result = semantic(<<-CRYSTAL)
        annotation Internal
          private data : StringLiteral
        end
        CRYSTAL

      type = result.program.types["Internal"].as(AnnotationType)
      type.has_fields?.should be_true
      type.has_public_fields?.should be_false
    end

    it "has_public_fields? returns true when mixed visibility" do
      result = semantic(<<-CRYSTAL)
        annotation Mixed
          private internal : StringLiteral
          public_field : StringLiteral
        end
        CRYSTAL

      type = result.program.types["Mixed"].as(AnnotationType)
      type.has_public_fields?.should be_true
    end
  end

  describe "Instance class generation" do
    it "generates Instance class for annotation with public fields" do
      result = semantic(<<-CRYSTAL)
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end
        CRYSTAL

      # The Instance class should be generated with suffix naming
      instance_class = result.program.types["NotBlankInstance"]?
      instance_class.should_not be_nil
      instance_class.should be_a(NonGenericClassType)
    end

    it "Instance class has getters for public fields" do
      assert_type(<<-CRYSTAL) { string }
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end

        instance = NotBlankInstance.new
        instance.message
        CRYSTAL
    end

    it "Instance class has initialize with defaults" do
      assert_type(<<-CRYSTAL) { types["NotBlankInstance"] }
        annotation NotBlank
          message : StringLiteral = "must not be blank"
          allow_nil : BoolLiteral = false
        end

        NotBlankInstance.new
        CRYSTAL
    end

    it "Instance class accepts custom values" do
      assert_type(<<-CRYSTAL) { string }
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end

        instance = NotBlankInstance.new(message: "custom message")
        instance.message
        CRYSTAL
    end

    it "Instance class inherits from parent Instance class" do
      result = semantic(<<-CRYSTAL)
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral = "must not be blank"
        end
        CRYSTAL

      ci = result.program.types["ConstraintInstance"]?.as(Crystal::NonGenericClassType)
      nbi = result.program.types["NotBlankInstance"]?.as(Crystal::NonGenericClassType)
      nbi.superclass.should eq(ci)
    end

    it "child Instance class has parent's fields" do
      assert_type(<<-CRYSTAL) { tuple_of([array_of(string), string]) }
        require "prelude"

        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral = "must not be blank"
        end

        instance = NotBlankInstance.new(groups: ["validation"])
        {instance.groups, instance.message}
        CRYSTAL
    end

    it "does not generate Instance class when only private fields" do
      result = semantic(<<-CRYSTAL)
        annotation Internal
          private data : StringLiteral
        end
        CRYSTAL

      instance_class = result.program.types["InternalInstance"]?
      instance_class.should be_nil
    end

    it "Instance class uses element type from 'of' clause for arrays" do
      assert_type(<<-CRYSTAL) { array_of(int32) }
        require "prelude"

        annotation Scores
          values : ArrayLiteral = [] of Int32
        end

        instance = ScoresInstance.new(values: [1, 2, 3])
        instance.values
        CRYSTAL
    end

    it "Instance class uses key/value types from 'of' clause for hashes" do
      assert_type(<<-CRYSTAL) { hash_of(string, int32) }
        require "prelude"

        annotation Config
          settings : HashLiteral = {} of String => Int32
        end

        instance = ConfigInstance.new(settings: {"a" => 1})
        instance.settings
        CRYSTAL
    end

    it "type restrictions work with Instance class inheritance" do
      assert_no_errors(<<-CRYSTAL)
        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral = "must not be blank"
        end

        def process(c : ConstraintInstance)
          c.groups
        end

        process(NotBlankInstance.new)
        CRYSTAL
    end
  end

  describe "to_runtime_representation" do
    it "generates Instance class instantiation" do
      assert_type(<<-CRYSTAL) { types["NotBlankInstance"] }
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end

        @[NotBlank]
        class Foo
        end

        {{ Foo.annotation(NotBlank).to_runtime_representation }}
        CRYSTAL
    end

    it "uses provided values in instantiation" do
      assert_type(<<-CRYSTAL) { string }
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end

        @[NotBlank(message: "custom")]
        class Foo
        end

        instance = {{ Foo.annotation(NotBlank).to_runtime_representation }}
        instance.message
        CRYSTAL
    end

    it "uses default values when not provided" do
      assert_type(<<-CRYSTAL) { string }
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end

        @[NotBlank]
        class Foo
        end

        instance = {{ Foo.annotation(NotBlank).to_runtime_representation }}
        instance.message
        CRYSTAL
    end

    it "excludes private fields from Instance" do
      assert_type(<<-CRYSTAL) { string }
        annotation FullName
          private first_name : StringLiteral
          private last_name : StringLiteral
          name : StringLiteral
        end

        @[FullName(first_name: "John", last_name: "Doe", name: "John Doe")]
        class Person
        end

        instance = {{ Person.annotation(FullName).to_runtime_representation }}
        instance.name
        CRYSTAL
    end

    it "includes inherited fields" do
      assert_type(<<-CRYSTAL) { tuple_of([array_of(string), string]) }
        require "prelude"

        annotation Constraint
          groups : ArrayLiteral = [] of String
        end

        annotation NotBlank < Constraint
          message : StringLiteral = "must not be blank"
        end

        @[NotBlank(groups: ["validation"])]
        class Foo
        end

        instance = {{ Foo.annotation(NotBlank).to_runtime_representation }}
        {instance.groups, instance.message}
        CRYSTAL
    end

    it "errors when annotation has no typed fields" do
      assert_error(<<-CRYSTAL, "annotation Foo has no typed fields; to_runtime_representation requires typed fields")
        annotation Foo
        end

        @[Foo]
        class Bar
        end

        {{ Bar.annotation(Foo).to_runtime_representation }}
        CRYSTAL
    end
  end

  describe "field validation errors" do
    it "errors on unknown field in annotation with typed fields" do
      assert_error(<<-CRYSTAL, "unknown field 'unknown' for annotation NotBlank")
        annotation NotBlank
          message : StringLiteral = "must not be blank"
        end

        @[NotBlank(unknown: "value")]
        class Foo
        end
        CRYSTAL
    end

    it "errors when required field is missing" do
      assert_error(<<-CRYSTAL, "missing required field 'message' for annotation NotBlank")
        annotation NotBlank
          message : StringLiteral
        end

        @[NotBlank]
        class Foo
        end
        CRYSTAL
    end

    it "allows unknown fields when annotation has no typed fields (backwards compat)" do
      assert_no_errors(<<-CRYSTAL)
        annotation Foo
        end

        @[Foo(anything: "goes", here: 123)]
        class Bar
        end
        CRYSTAL
    end
  end

  describe "backwards compatibility" do
    it "annotation without fields works as before" do
      assert_type(<<-CRYSTAL) { int32 }
        annotation Foo
        end

        @[Foo(key: "value", count: 42)]
        class Bar
        end

        {% if Bar.annotation(Foo)[:key] == "value" %}
          1
        {% else %}
          'a'
        {% end %}
        CRYSTAL
    end

    it "annotation with empty body works" do
      assert_no_errors(<<-CRYSTAL)
        annotation Empty; end

        @[Empty]
        class Foo
        end
        CRYSTAL
    end
  end
end
