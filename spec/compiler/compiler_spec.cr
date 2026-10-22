require "../spec_helper"
require "./spec_helper"

describe "Compiler" do
  it "has a valid version" do
    SemanticVersion.parse(Crystal::Config.version)
  end

  it "compiles a file" do
    with_temp_executable "compiler_spec_output" do |path|
      Crystal::Command.run ["build"].concat(program_flags_options).concat([compiler_datapath("compiler_sample"), "-o", path])

      File.exists?(path).should be_true

      Process.capture(path).should eq("Hello!")
    end
  end

  it "doesn't instrument lib and the standard library for coverage by default" do
    compiler = Crystal::Compiler.new
    compiler.coverage_includes << "lib/shard"
    compiler.coverage_excludes << "/project/spec"
    filter = compiler.coverage_filter

    filter.match?("/project/src/foo.cr").should be_true
    filter.match?("/project/spec/foo_spec.cr").should be_false
    filter.match?(File.expand_path("lib/shard/src/foo.cr")).should be_true
    Crystal::CrystalPath.default_paths.each do |path|
      filter.match?(File.join(File.expand_path(path), "foo.cr")).should be_false
    end
  end

  it "runs subcommand in preference to a filename " do
    Dir.cd compiler_datapath do
      with_temp_executable "compiler_spec_output" do |path|
        Crystal::Command.run ["build"].concat(program_flags_options).concat(["compiler_sample", "-o", path])

        File.exists?(path).should be_true

        Process.capture(path).should eq("Hello!")
      end
    end
  end
end
