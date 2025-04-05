require "../../spec_helper"

describe "Normalize: or" do
  it "normalizes or without variable" do
    assert_expand "a || b", "if __temp_1 = a; __temp_1; else; b; end"
  end

  it "normalizes or with variable on the left" do
    assert_expand_second "a = 1; a || b", "if a; a; else; b; end"
  end

  it "normalizes or with assignment on the left" do
    assert_expand "(a = 1) || b", "if a = 1; a; else; b; end"
  end

  it "normalizes or with is_a? on var" do
    assert_expand_second "a = 1; a.is_a?(Foo) || b", "if a.is_a?(Foo); a.is_a?(Foo); else; b; end"
  end

  it "normalizes or with ! on var" do
    assert_expand_second "a = 1; !a || b", "if !a; !a; else; b; end"
  end

  it "normalizes or with ! on var.is_a?(...)" do
    assert_expand_second "a = 1; !a.is_a?(Int32) || b", "if !a.is_a?(Int32); !a.is_a?(Int32); else; b; end"
  end
end
