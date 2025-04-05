require "../../spec_helper"

describe "Normalize: and" do
  it "normalizes and without variable" do
    assert_expand "a && b", "if __temp_1 = a; b; else; __temp_1; end"
  end

  it "normalizes and with variable on the left" do
    assert_expand_second "a = 1; a && b", "if a; b; else; a; end"
  end

  it "normalizes and with is_a? on var" do
    assert_expand_second "a = 1; a.is_a?(Foo) && b", "if a.is_a?(Foo); b; else; a.is_a?(Foo); end"
  end

  it "normalizes and with ! on var" do
    assert_expand_second "a = 1; !a && b", "if !a; b; else; !a; end"
  end

  it "normalizes and with ! on var.is_a?(...)" do
    assert_expand_second "a = 1; !a.is_a?(Int32) && b", "if !a.is_a?(Int32); b; else; !a.is_a?(Int32); end"
  end

  it "normalizes and with is_a? on exp" do
    assert_expand_second "a = 1; 1.is_a?(Foo) && b", "if __temp_1 = 1.is_a?(Foo); b; else; __temp_1; end"
  end

  it "normalizes and with assignment" do
    assert_expand "(a = 1) && b", "if a = 1; b; else; a; end"
  end
end
