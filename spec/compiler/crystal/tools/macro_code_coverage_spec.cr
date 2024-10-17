require "../../../spec_helper"
include Crystal

private def assert_coverage(code, expected_coverage, *, focus : Bool = false, spec_file = __FILE__, spec_line = __LINE__)
  it file: spec_file, line: spec_line, focus: focus do
    compiler = Compiler.new true
    compiler.prelude = "empty"
    compiler.no_codegen = true
    result = compiler.compile(Compiler::Source.new(".", code), "fake-no-build")

    begin
      hits = MacroCoverageProcessor.new.compute_coverage(result)
    rescue ex
      fail ex.message, file: spec_file, line: spec_line
    end

    unless hits = hits["."]?
      fail "Failed to generate coverage", file: spec_file, line: spec_line
    end

    hits.each do |line, count|
      unless expected_hits = expected_coverage[line]?
        fail "Expected coverage data for line: #{line.inspect}", file: spec_file, line: spec_line
      end

      if count != expected_hits
        fail "Expected line #{line.inspect} to be #{expected_hits} but got #{count.inspect}", file: spec_file, line: spec_line
      end
    end
  end
end

describe "macro_code_coverage" do
  assert_coverage <<-'CR', {1 => 1}
    {{ "foo" }}
    CR

  assert_coverage <<-'CR', {1 => "1/2"}
    {{ true ? raise("err") : 0 }}
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

  assert_coverage <<-'CR', {1 => 1, 2 => "1/2"}
    {% begin %}
      {{true ? 1 : 0}} + {{2}}
    {% end %}
    CR

  # assert_coverage <<-'CR', {1 => "1/2"},
  #   {% if true %}1{% else %}0{% end %}
  #   CR

  assert_coverage <<-'CR', {2 => 4}
    macro test(x)
      {{ x == 1 ? 1 : x == 2 ? 2 : 3 }}
    end

    test(1)
    test(2)
    test(3)
    test(4)
    CR

  assert_coverage <<-'CR', {2 => "2/2"}
    macro test(x)
      {{ 1 == x ? raise("err") : 0 }}
    end

    test(2)
    test(1)
    CR

  assert_coverage <<-'CR', {2 => "1/2"}
    macro test(x)
      {{ 1 == x ? raise("err") : 0 }}
    end

    test(1)
    test(2)
    CR

  assert_coverage <<-'CR', {1 => 1}
    {% raise "foo" %}
    {{ 2 }}
    CR

  assert_coverage <<-'CR', {1 => 1, 2 => 0, 3 => 1}
    {% 1 %}
    {% 2 if false %}
    {% 3 %}
    CR

  assert_coverage <<-'CR', {1 => 1, 2 => 1, 3 => 1}
    {% 1 %}
    {% 2 if true %}
    {% 3 %}
    CR

  assert_coverage <<-'CR', {1 => 1, 2 => 0, 3 => 1}
    {% 1 %}
    {% 2 unless true %}
    {% 3 %}
    CR

  assert_coverage <<-'CR', {1 => 1, 2 => 1, 3 => 1}
    {% 1 %}
    {% 2 unless false %}
    {% 3 %}
    CR

  assert_coverage <<-'CR', {1 => 0, 3 => 1, 4 => 1}
    {% unless true %}
      {{0}}
    {% else %}
      {{1}}
    {% end %}
    CR

  assert_coverage <<-'CR', {1 => 1, 2 => 1, 3 => 0}
    {% unless false %}
      {{0}}
    {% else %}
      {{1}}
    {% end %}
    CR

  assert_coverage <<-'CR', {2 => 2, 6 => 1, 10 => 1}
    macro test(&)
      {{yield}}
    end

    test do
      {{2 + 1}}
    end

    test do
      {{9 + 12}}
    end
    CR

  assert_coverage <<-'CR', {2 => 1, 3 => 0, 4 => 1}
    macro test(&)
      {{ 1 + 1 }}
      {{yield if false}}
      {{ 2 + 2 }}
    end

    test do
      {{2 + 1}}
    end
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

  assert_coverage <<-'CR', {1 => 1, 2 => 1, 4 => 2, 5 => 2, 7 => 2}
    {% begin %}
      {% for v in [1, 2] %}
        {%
          pp(10 * 10)
          20 * 20
        %}
        {% 30 * 30 %}
      {% end %}
    {% end %}
    CR

  assert_coverage <<-'CR', {1 => 1, 2 => 1, 4 => 0, 5 => 2, 7 => 2}
    {% begin %}
      {% for v in [1, 2] %}
        {%
          pp(10 * 10) if false
          20 * 20
        %}
        {% 30 * 30 %}
      {% end %}
    {% end %}
    CR
end
