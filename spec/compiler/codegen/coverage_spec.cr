require "../../spec_helper"

private def codegen_coverage(code)
  codegen(code, single_module: true, coverage: true).to_s
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
