require "../../spec_helper"

describe Crystal::PathFilter do
  it "selects everything by default" do
    Crystal::PathFilter.new.match?("/src/foo.cr").should be_true
  end

  it "excludes paths in an excluded directory" do
    filter = Crystal::PathFilter.new(excludes: ["/lib"])
    filter.match?("/lib/shard/src/foo.cr").should be_false
    filter.match?("/src/foo.cr").should be_true
  end

  it "includes paths in an included directory, even if excluded" do
    filter = Crystal::PathFilter.new(includes: ["/lib/shard"], excludes: ["/lib"])
    filter.match?("/lib/shard/src/foo.cr").should be_true
    filter.match?("/lib/other/src/foo.cr").should be_false
  end

  it "matches globs" do
    filter = Crystal::PathFilter.new(excludes: ["/src/*_spec.cr"])
    filter.match?("/src/foo_spec.cr").should be_false
    filter.match?("/src/foo.cr").should be_true
  end
end
