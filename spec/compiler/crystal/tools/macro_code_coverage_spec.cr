require "../../../spec_helper"
include Crystal

private def assert_coverage(code, expected_coverage, file = __FILE__, line = __LINE__)
  it do
    compiler = Compiler.new true
    compiler.prelude = "empty"
    compiler.no_codegen = true
    result = compiler.compile(Compiler::Source.new(".", code), "fake-no-build")

    hits = MacroCoverageProcessor.new.compute_coverage(result)
    hits = hits["."]?.should_not be_nil

    hits.each do |line, count|
      expected_hits = expected_coverage[line]?.should_not be_nil

      count.should eq expected_hits
    end
  end
end

describe "macro_code_coverage", focus: true do
  assert_coverage <<-'CR', {1 => 1}
    {{ "foo" }}
    CR

  assert_coverage <<-'CR', {1 => "1/2"}
    {{ true ? 1 : 0 }}
    CR

  assert_coverage <<-'CR', {1 => "1/3"}
    {{ true ? 1 : x == 2 ? 2 : 3 }}
    CR

  assert_coverage <<-'CR', {2 => "2/3"}
    macro test(x)
    {{ x == 1 ? 1 : x == 2 ? 2 : 3 }}
    end

    test(1)
    test(2)
    CR

  assert_coverage <<-'CR', {2 => "3/3"}
    macro test(x)
    {{ x == 1 ? 1 : x == 2 ? 2 : 3 }}
    end

    test(1)
    test(2)
    test(3)
    CR

  assert_coverage <<-'CR', {2 => 4}
    macro test(x)
    {{ x == 1 ? 1 : x == 2 ? 2 : 3 }}
    end

    test(1)
    test(2)
    test(3)
    test(4)
    CR

  assert_coverage <<-'CR', {1 => 1, 2 => 1, 3 => 1, 4 => 1, 5 => 0, 7 => 2, 8 => 2}
    {% begin %}
      {% for v in {1, 2, 3} %}
        {% if v == 2 %}
          {{v * 2}}
        {% elsif v > 5 %}
          {{v * 5}}
        {% else %}
          {{v}}
        {% end %}
      {% end %}
    {% end %}
    CR
end
