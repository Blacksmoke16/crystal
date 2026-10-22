require "../../spec_helper"

# Defines `main` for programs compiled with the empty prelude.
private MAIN_SOURCE = <<-CRYSTAL
  require "primitives"

  lib LibCrystalMain
    fun __crystal_main(argc : Int32, argv : UInt8**)
  end

  fun main(argc : Int32, argv : UInt8**) : Int32
    LibCrystalMain.__crystal_main(argc, argv)
    0
  end
  CRYSTAL

# Compiles *code* with coverage instrumentation, runs it, and returns the
# hits of each line of *code* that `llvm-cov` reports: the execution count,
# or the number of branch outcomes taken and the number of branch outcomes,
# for executed lines with branches.
private def coverage_hits(code, prelude) : Hash(Int32, Int32 | String)
  with_tempfile("coverage.cr", "coverage_main.cr", "coverage", "coverage.profraw", "coverage.profdata") do |source_path, main_path, executable, profraw, profdata|
    sources = [Crystal::Compiler::Source.new(source_path, code)]
    sources << Crystal::Compiler::Source.new(main_path, MAIN_SOURCE) if prelude == "empty"
    sources.each { |source| File.write(source.filename, source.code) }

    compiler = Crystal::Compiler.new
    compiler.prelude = prelude
    compiler.coverage = true
    compiler.compile sources, executable

    Process.run(executable, env: {"LLVM_PROFILE_FILE" => profraw}).success?.should be_true
    Process.run("llvm-profdata", ["merge", "-sparse", profraw, "-o", profdata], error: :inherit).success?.should be_true
    lcov = Process.run("llvm-cov", ["export", executable, "-instr-profile=#{profdata}", "-format=lcov", source_path], error: :inherit) do |process|
      process.output.gets_to_end
    end

    parse_lcov_hits(lcov, source_path)
  end
end

private def parse_lcov_hits(lcov, filename)
  counts = {} of Int32 => Int32
  branches = Hash(Int32, Array(Bool)).new { |hash, line| hash[line] = [] of Bool }
  in_file = false

  lcov.each_line do |line|
    case line
    when .starts_with?("SF:")
      in_file = line.lchop("SF:") == filename
    when .starts_with?("DA:")
      next unless in_file
      line_number, count = line.lchop("DA:").split(',')
      counts[line_number.to_i] = count.to_i
    when .starts_with?("BRDA:")
      next unless in_file
      line_number, _, _, taken = line.lchop("BRDA:").split(',')
      branches[line_number.to_i] << (taken != "-" && taken.to_i > 0)
    end
  end

  counts.to_h do |line_number, count|
    outcomes = branches[line_number]?
    if outcomes && count > 0
      {line_number, "#{outcomes.count(true)}/#{outcomes.size}".as(Int32 | String)}
    else
      {line_number, count.as(Int32 | String)}
    end
  end
end

private def assert_coverage(code, expected_coverage, *, prelude = "empty", focus : Bool = false, spec_file = __FILE__, spec_line = __LINE__)
  it focus: focus, file: spec_file, line: spec_line do
    pending_interpreted! "Can't compile programs in interpreted code"
    unless Process.find_executable("llvm-profdata") && Process.find_executable("llvm-cov")
      pending! "llvm-profdata and llvm-cov are required"
    end

    coverage_hits(code, prelude).should eq(expected_coverage), file: spec_file, line: spec_line
  end
end

describe "Code gen: coverage report" do
  assert_coverage <<-CRYSTAL, {1 => 2, 2 => 2, 5 => 1, 6 => 1}
    def foo(x)
      x &+ 1
    end

    foo(1)
    foo(2)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 0, 2 => 0}
    def foo
      1
    end
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => "1/2", 3 => 1, 5 => 0, 9 => 1}
    def foo(x)
      if x > 1
        1
      else
        2
      end
    end

    foo(2)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 2, 2 => "2/2", 5 => 1, 6 => 1}
    def foo(x)
      x > 1 ? 1 : 2
    end

    foo(2)
    foo(0)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 2, 2 => "3/4", 5 => 1, 6 => 1}
    def check(a, b, c)
      a || b || c
    end

    check(true, false, false)
    check(false, false, true)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => "2/2", 3 => 3}
    i = 0
    while i < 3
      i &+= 1
    end
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => "1/2", 3 => 0, 6 => 1}
    def foo(x)
      return 0 if x > 1
      x
    end

    foo(2)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => 1, 3 => 1, 6 => 2}
    def twice(&)
      yield
      yield
    end

    twice { 1 }
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 3, 2 => "4/4", 5 => 1, 6 => 1, 7 => 1}
    def check(a, b, c)
      a && b && c
    end

    check(true, true, false)
    check(false, true, true)
    check(true, false, true)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 2, 2 => "4/6", 3 => 2, 5 => 0, 9 => 1, 10 => 1}
    def check(a, b, c)
      if a || b || c
        1
      else
        2
      end
    end

    check(true, false, false)
    check(false, false, true)
    CRYSTAL

  # Each instance decides the type at compile time, but the instances add up
  assert_coverage <<-CRYSTAL, {1 => 3, 2 => 3, 3 => "2/2", 4 => 1, 5 => "2/2", 6 => 1, 8 => 1, 12 => 1, 13 => 1, 14 => 1}
    def kind(x)
      case x
      when Int32
        10
      when Float64
        20
      else
        30
      end
    end

    kind(1)
    kind(1.5)
    kind(true)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 2, 2 => "2/2", 5 => 1, 6 => 1}
    def foo(x)
      x.is_a?(Int32) ? 1 : 2
    end

    foo(1)
    foo(1.5)
    CRYSTAL

  # `while true` has no condition to report
  assert_coverage <<-CRYSTAL, {1 => 1, 2 => 3, 3 => 2, 4 => "2/2"}
    i = 0
    while true
      i &+= 1
      break if i == 2
    end
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => "1/2", 3 => 0, 5 => 1}
    x = 1
    unless x == 1
      x = 2
    end
    x
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => 1, 3 => 1, 6 => 1, 7 => 1, 8 => "2/2", 9 => 1, 11 => 1}
    def each_twice(&)
      yield 1
      yield 2
    end

    total = 0
    each_twice do |x|
      next if x == 1
      total &+= x
    end
    total
    CRYSTAL

  # A def expanded from a macro maps to the macro call
  assert_coverage <<-CRYSTAL, {7 => 1, 8 => 1}
    macro define_foo
      def foo(x)
        x &+ 1
      end
    end

    define_foo
    foo(1)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {2 => 1, 3 => 1, 6 => 0, 7 => 0, 11 => 1}
    class Foo
      def used
        1
      end

      def unused
        2
      end
    end

    Foo.new.used
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => "1/2", 2 => 1}
    f = ->(x : Int32) { x > 1 ? x : 0 }
    f.call(2)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 2, 2 => 2, 3 => 1, 4 => 1, 6 => 2, 9 => 1, 10 => 1}, prelude: "prelude"
    def div(a, b)
      a // b
    rescue DivisionByZeroError
      0
    ensure
      a
    end

    div(4, 2)
    div(1, 0)
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 2, 2 => "2/2", 3 => 1, 6 => 1, 8 => 1, 9 => 1}, prelude: "prelude"
    def check(x)
      raise "bad" if x < 0
      x
    end

    check(1)
    begin
      check(-1)
    rescue
    end
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => 1, 3 => "2/2", 5 => 1}, prelude: "prelude"
    total = 0
    [1, 2, 3].each do |x|
      total += x if x.odd?
    end
    total
    CRYSTAL

  # Accessors map to the macro call, the default values to themselves
  assert_coverage <<-CRYSTAL, {2 => 1, 3 => 1, 6 => 1, 7 => 1, 8 => 1}, prelude: "prelude"
    class Foo
      getter x : Int32 = 1
      property y = 2
    end

    foo = Foo.new
    foo.x
    foo.y = 3
    CRYSTAL

  assert_coverage <<-CRYSTAL, {1 => 1, 2 => 1, 5 => 1, 6 => 1}, prelude: "prelude"
    def compute
      1 + 1
    end

    FOO = compute
    FOO
    CRYSTAL
end
