require "../../spec_helper"

describe "Normalize: return next break" do
  ["return", "next", "break"].each do |keyword|
    it "removes nodes after #{keyword}" do
      assert_normalize "#{keyword} 1; 2", "#{keyword} 1"
    end
  end

  it "doesn't remove after return when there's an unless" do
    assert_normalize "return 1 unless 2; 3", "if 2; ; else; return 1; end\n3"
  end

  it "removes nodes after if that returns in both branches" do
    assert_normalize "if true; break; else; return; end; 1", "if true; break; else; return; end"
  end

  it "doesn't remove nodes after if that returns in one branch" do
    assert_normalize "if true; 1; else; return; end; 1", "if true; 1; else; return; end\n1"
  end
end
