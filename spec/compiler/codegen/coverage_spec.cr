require "../../spec_helper"

private def codegen_coverage(code, coverage_filter = nil)
  codegen(code, single_module: true, coverage: true, coverage_filter: coverage_filter).to_s
end

private def increment_of(name)
  "call void @llvm.instrprof.increment(ptr @\"__profn_#{name}\""
end

describe "Code gen: coverage" do
  it "counts executions of a def" do
    ir = codegen_coverage <<-CRYSTAL
      def foo(x)
        x &+ 1
      end

      foo(1)
      CRYSTAL

    ir.should contain(increment_of("*foo<Int32>:Int32"))
    ir.should match(/@__covrec_[0-9A-F]+u = linkonce_odr hidden constant .* section "__llvm_covfun", comdat, align 8/)
    ir.should match(/@__llvm_coverage_mapping = private constant .* section "__llvm_covmap", align 8/)
    ir.should contain(%(@llvm.used = appending global))
  end

  it "counts executions of a def inlined at its call site" do
    ir = codegen_coverage <<-CRYSTAL
      def foo(&)
        yield
      end

      class Foo
        def initialize(@x : Int32)
        end

        def x
          @x
        end
      end

      foo { }
      Foo.new(1).x
      CRYSTAL

    ir.should contain(increment_of("*foo:Nil"))
    ir.should contain(increment_of("*Foo#x:Int32"))
  end

  it "doesn't count the new expanded from initialize" do
    ir = codegen_coverage <<-CRYSTAL
      class Foo
        def initialize(@x : Int32)
        end
      end

      Foo.new(1)
      CRYSTAL

    ir.should contain(increment_of("*Foo#initialize<Int32>:Int32"))
    ir.should_not contain(increment_of("*Foo::new"))
  end

  it "counts branches whose type checks are folded into literals" do
    # The then branch of the `||` repeats `x.nil?`, which is true there.
    # `bar`'s check is also true. Each must be its own node to keep its own
    # counter.
    ir = codegen_coverage <<-CRYSTAL
      def foo(x : Int32?)
        x.nil? || x > 0
      end

      def bar(y : Int32)
        y.is_a?(Int32)
      end

      foo(1.as(Int32?))
      a = bar(1)
      CRYSTAL

    ir.scan(/llvm\.instrprof\.increment\(ptr @"__profn_\*foo[^"]*", i64 -?\d+, i32 \d+, i32 1\)/).size.should eq(1)
  end

  it "counts instance variable initializers" do
    ir = codegen_coverage <<-CRYSTAL
      def one
        1
      end

      class Foo
        @x : Int32 = one
      end

      Foo.new
      CRYSTAL

    ir.should contain(increment_of("Foo@x initializer"))
  end

  it "counts constant initializers expanded from macros" do
    ir = codegen_coverage <<-CRYSTAL
      class Foo
        def initialize(@x : Int32)
        end
      end

      FOO = {{ "Foo.new(1)".id }}
      FOO
      CRYSTAL

    ir.should contain(increment_of("FOO initializer"))
  end

  it "counts defs expanded from macros" do
    ir = codegen_coverage <<-CRYSTAL
      macro def_foo
        def foo(x)
          x &+ 1
        end
      end

      def_foo
      foo(1)
      CRYSTAL

    ir.should contain(increment_of("*foo<Int32>:Int32"))
  end

  it "doesn't instrument code that the filter excludes" do
    ir = codegen_coverage <<-CRYSTAL, Crystal::PathFilter.new(excludes: [__FILE__])
      def foo(x)
        x &+ 1
      end

      def bar(x)
      end

      FOO = foo(1)
      foo(FOO)
      CRYSTAL

    ir.should_not contain("llvm.instrprof.increment")
    ir.should_not contain("__llvm_coverage_names")
  end

  it "maps defs that are never called" do
    ir = codegen_coverage <<-CRYSTAL
      def foo(x)
        x
      end
      CRYSTAL

    ir.should contain("@\"__profn_::foo at #{__FILE__}")
    ir.should contain(%(@__llvm_coverage_names = internal constant))
    ir.should match(/@__covrec_[0-9A-F]+ = linkonce_odr hidden constant/)
  end
end
