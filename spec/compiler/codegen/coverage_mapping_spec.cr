require "../../spec_helper"

describe Crystal::CoverageMapping do
  describe ".md5_hash" do
    it "returns the first 8 bytes of the MD5 digest as little-endian" do
      Crystal::CoverageMapping.md5_hash("main").should eq(0xDB956436E78DD5FA_u64)
    end
  end

  describe ".encode_filenames" do
    it "encodes uncompressed" do
      Crystal::CoverageMapping.encode_filenames(["/tmp", "a.cr"]).should eq(
        Bytes[2, 10, 0, 4, '/'.ord, 't'.ord, 'm'.ord, 'p'.ord, 4, 'a'.ord, '.'.ord, 'c'.ord, 'r'.ord])
    end
  end

  describe ".encode_function" do
    it "encodes a region (same as Clang)" do
      region = Crystal::CoverageMapping::Region.new(
        counter: Crystal::CoverageMapping::Counter.reference(0), file_id: 0,
        line_start: 2, column_start: 33, line_end: 2, column_end: 56)
      Crystal::CoverageMapping.encode_function([1], [] of Crystal::CoverageMapping::Expression, [region]).should eq(
        Bytes[1, 1, 0, 1, 1, 2, 33, 0, 56])
    end

    it "sorts regions and encodes start lines as deltas within each file" do
      counter = Crystal::CoverageMapping::Counter.reference(1)
      regions = [
        Crystal::CoverageMapping::Region.new(counter, file_id: 1, line_start: 3, column_start: 1, line_end: 3, column_end: 2),
        Crystal::CoverageMapping::Region.new(counter, file_id: 0, line_start: 9, column_start: 1, line_end: 10, column_end: 4),
        Crystal::CoverageMapping::Region.new(counter, file_id: 0, line_start: 5, column_start: 1, line_end: 5, column_end: 200),
      ]
      Crystal::CoverageMapping.encode_function([4, 7], [] of Crystal::CoverageMapping::Expression, regions).should eq(
        Bytes[2, 4, 7, 0,
          2, 5, 5, 1, 0, 200, 1, 5, 4, 1, 1, 4,
          1, 5, 3, 1, 0, 2])
    end

    it "encodes a gap region (same as Clang)" do
      region = Crystal::CoverageMapping::Region.new(
        counter: Crystal::CoverageMapping::Counter.reference(1), file_id: 0,
        line_start: 1, column_start: 26, line_end: 1, column_end: 27, kind: :gap)
      Crystal::CoverageMapping.encode_function([1], [] of Crystal::CoverageMapping::Expression, [region]).should eq(
        Bytes[1, 1, 0, 1, 5, 1, 26, 0, 0x9B, 0x80, 0x80, 0x80, 0x08])
    end

    it "encodes a branch region (same as Clang)" do
      region = Crystal::CoverageMapping::Region.new(
        counter: Crystal::CoverageMapping::Counter.reference(1), file_id: 0,
        line_start: 1, column_start: 20, line_end: 1, column_end: 25, kind: :branch,
        false_counter: Crystal::CoverageMapping::Counter.new(:subtract, 0))
      Crystal::CoverageMapping.encode_function([1], [] of Crystal::CoverageMapping::Expression, [region]).should eq(
        Bytes[1, 1, 0, 1, 0x20, 5, 2, 1, 20, 0, 25])
    end

    it "encodes a skipped region" do
      region = Crystal::CoverageMapping::Region.new(
        counter: Crystal::CoverageMapping::Counter.zero, file_id: 0,
        line_start: 3, column_start: 0, line_end: 5, column_end: 0, kind: :skipped)
      Crystal::CoverageMapping.encode_function([1], [] of Crystal::CoverageMapping::Expression, [region]).should eq(
        Bytes[1, 1, 0, 1, 0x10, 3, 0, 2, 0])
    end

    it "encodes expressions" do
      expression = Crystal::CoverageMapping::Expression.new(
        Crystal::CoverageMapping::Counter.reference(0), Crystal::CoverageMapping::Counter.reference(1))
      Crystal::CoverageMapping.encode_function([1], [expression], [] of Crystal::CoverageMapping::Region).should eq(
        Bytes[1, 1, 1, 1, 5, 0])
    end
  end
end
