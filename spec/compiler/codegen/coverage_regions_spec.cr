require "../../spec_helper"

private def counter_string(counter : Crystal::CoverageMapping::Counter)
  case counter.kind
  in .zero?      then "0"
  in .reference? then "c#{counter.id}"
  in .subtract?  then "e#{counter.id}"
  in .add?       then "e#{counter.id}"
  end
end

private def region_strings(function)
  function.regions.map do |region|
    location = "#{region.line_start}:#{region.column_start}-#{region.line_end}:#{region.column_end}"
    case region.kind
    in .code?    then "#{counter_string(region.counter)} #{location}"
    in .gap?     then "#{counter_string(region.counter)} #{location} gap"
    in .skipped? then "skip #{location}"
    in .branch?  then "#{counter_string(region.counter)}/#{counter_string(region.false_counter)} #{location} branch"
    end
  end
end

private def expression_strings(function)
  function.expressions.map do |expression|
    "#{counter_string(expression.lhs)}, #{counter_string(expression.rhs)}"
  end
end

private def new_builder(function, source_lines = nil)
  entry_counters = Crystal::CoverageRegionBuilder::NodeCounters.new.compare_by_identity
  continuation_counters = Crystal::CoverageRegionBuilder::NodeCounters.new.compare_by_identity
  {Crystal::CoverageRegionBuilder.new(function, entry_counters, continuation_counters, source_lines), entry_counters, continuation_counters}
end

private def build_def(a_def : Crystal::Def, source_lines = nil)
  function = Crystal::CoverageFunction.new("foo", "")
  builder, entry_counters, continuation_counters = new_builder(function, source_lines)
  builder.build_def(a_def)
  {function, entry_counters, continuation_counters}
end

private def build_def(code : String)
  build_def(Crystal::Parser.parse(code).as(Crystal::Def), code.lines)
end

describe Crystal::CoverageRegionBuilder do
  it "maps a def to its entry counter" do
    function, _, _ = build_def <<-CRYSTAL
      def foo
        1
      end
      CRYSTAL

    region_strings(function).should eq(["c0 1:1-3:4", "skip 3:0-3:0"])
    function.num_counters.should eq(1)
  end

  it "maps a def expanded from a macro to the macro call" do
    source = "def foo\n  1\nend"
    parser = Crystal::Parser.new(source)
    parser.filename = Crystal::VirtualFile.new(Crystal::Macro.new("gen"), source, Crystal::Location.new("", 7, 3))
    function, _, _ = build_def(parser.parse.as(Crystal::Def))

    region_strings(function).should eq(["c0 7:3-7:4"])
  end

  it "counts the then branch of an if, and derives the else branch" do
    code = <<-CRYSTAL
      def foo(x)
        if x
          1
        else
          2
        end
      end
      CRYSTAL
    a_def = Crystal::Parser.parse(code).as(Crystal::Def)
    function, entry_counters, _ = build_def(a_def, code.lines)

    region_strings(function).should eq([
      "c0 1:1-7:4", "skip 4:0-4:0", "skip 6:0-7:0",
      "c1/e0 2:6-2:7 branch",
      "c1 2:7-3:5 gap", "c1 3:5-3:6",
      "e0 3:6-5:5 gap", "e0 5:5-5:6",
    ])
    expression_strings(function).should eq(["c0, c1"])
    entry_counters[a_def.body.as(Crystal::If).then].should eq({function, 1})
  end

  it "counts the statements after one that may not complete" do
    code = <<-CRYSTAL
      def foo(x)
        return 1 if x
        2
      end
      CRYSTAL
    a_def = Crystal::Parser.parse(code).as(Crystal::Def)
    function, _, continuation_counters = build_def(a_def, code.lines)

    region_strings(function).should eq([
      "c0 1:1-4:4", "skip 4:0-4:0",
      "c0 2:3-2:16", "c1/e0 2:15-2:16 branch", "c1 2:3-2:11",
      "c2 2:16-3:3 gap", "c2 3:3-3:4",
    ])
    continuation_counters[a_def.body.as(Crystal::Expressions).expressions.first].should eq({function, 2})
  end

  it "maps statements removed after one that doesn't complete to zero" do
    # Typed defs are clones, which store the end location of all the parsed
    # statements, before the ones that can't run are removed
    code = <<-CRYSTAL
      def foo
        return 1
        2
      end
      CRYSTAL
    a_def = Crystal::Parser.parse(code).as(Crystal::Def).clone
    a_def.body.as(Crystal::Expressions).expressions.pop
    function, _, _ = build_def(a_def, code.lines)

    region_strings(function).should eq(["c0 1:1-4:4", "skip 4:0-4:0", "c0 2:3-2:11", "0 2:11-3:4 gap"])
  end

  it "precedes each statement after a continuation counter with a gap" do
    function, _, _ = build_def <<-CRYSTAL
      def foo
        return if x
        bar 1, 2
        y = baz.qux
      end
      CRYSTAL

    region_strings(function).should eq([
      "c0 1:1-5:4", "skip 5:0-5:0",
      "c0 2:3-2:14", "c1/e0 2:13-2:14 branch", "c1 2:3-2:9",
      "c2 2:14-3:3 gap", "c2 3:3-3:11",
      "c2 3:11-4:3 gap", "c2 4:3-4:14",
    ])
  end

  it "doesn't map statements of expansions, which repeat source locations" do
    hash_literal = Crystal::Parser.parse(%({"a" => -> { 1 }})).as(Crystal::HashLiteral)
    expansion = Crystal::LiteralExpander.new(Crystal::Program.new).expand(hash_literal)
    a_def = Crystal::Def.new("foo", body: expansion).at(Crystal::Location.new("", 1, 1))
    a_def.end_location = Crystal::Location.new("", 1, 19)
    function, _, _ = build_def(a_def)

    region_strings(function).should eq(["c0 1:1-1:20"])
  end

  it "counts the body of a while, and derives the condition" do
    function, _, _ = build_def <<-CRYSTAL
      def foo
        while x
          y
        end
      end
      CRYSTAL

    region_strings(function).should eq([
      "c0 1:1-5:4", "skip 4:0-5:0",
      "c1/c0 2:9-2:10 branch", "e0 2:9-2:10",
      "c1 2:10-3:5 gap", "c1 3:5-3:6",
    ])
    expression_strings(function).should eq(["c0, c1"])
  end

  it "counts the body of a block" do
    function, _, _ = build_def <<-CRYSTAL
      def foo
        bar do |x|
          x
        end
      end
      CRYSTAL

    region_strings(function).should eq([
      "c0 1:1-5:4", "skip 4:0-5:0",
      "c1 2:7-3:5 gap", "c1 3:5-3:6",
    ])
  end

  it "skips lines without code: blank, comments, and closing keywords only" do
    function, _, _ = build_def <<-CRYSTAL
      def foo
        # comment

        bar(
          1,
        )
        begin
          baz
        end.qux
      end
      CRYSTAL

    region_strings(function).select(&.starts_with?("skip")).should eq(["skip 2:0-3:0", "skip 6:0-7:0", "skip 10:0-10:0"])
  end

  it "doesn't skip lines without source" do
    function, _, _ = build_def(Crystal::Parser.parse("def foo\n  1\nend").as(Crystal::Def))

    region_strings(function).should eq(["c0 1:1-3:4"])
  end

  it "counts rescue and ensure bodies" do
    function, _, _ = build_def <<-CRYSTAL
      def foo
        bar
      rescue
        baz
      ensure
        qux
      end
      CRYSTAL

    region_strings(function).should eq([
      "c0 1:1-7:4", "skip 5:0-5:0", "skip 7:0-7:0",
      "c1 2:6-4:3 gap", "c1 4:3-4:6",
      "c2 4:6-6:3 gap", "c2 6:3-6:6",
    ])
  end

  it "doesn't map the left operand of && twice" do
    and_node = Crystal::Parser.parse("a && b").as(Crystal::And)
    if_node = Crystal::LiteralExpander.new(Crystal::Program.new).expand(and_node)
    a_def = Crystal::Def.new("foo", body: if_node).at(Crystal::Location.new("", 1, 1))
    a_def.end_location = Crystal::Location.new("", 1, 6)
    function, _, _ = build_def(a_def)

    region_strings(function).should eq(["c0 1:1-1:7", "c1/e0 1:1-1:2 branch", "c1 1:6-1:7"])
  end

  it "maps executable top-level statements" do
    statements = Crystal::Parser.parse(<<-CRYSTAL).as(Crystal::Expressions).expressions
      a
      class Foo
      end
      return if b
      c
      CRYSTAL
    function = Crystal::CoverageFunction.new("main", "")
    builder, entry_counters, _ = new_builder(function)
    builder.build_top_level(statements)

    region_strings(function).should eq([
      "c0 1:1-1:2",
      "c0 4:1-4:12", "c1/e0 4:11-4:12 branch", "c1 4:1-4:7",
      "c2 5:1-5:2",
    ])
    entry_counters[statements.first].should eq({function, 0})
  end
end
