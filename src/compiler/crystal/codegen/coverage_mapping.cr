require "crystal/digest/md5"

module Crystal
  # Encodes the coverage mapping data that `llvm-cov` reads from a binary
  # to map profile counters back to source regions.
  #
  # See https://llvm.org/docs/CoverageMappingFormat.html
  module CoverageMapping
    # Format version 6, the first one that stores the compilation directory
    # as the first entry of the filenames table. The header stores the
    # version minus one.
    VERSION = 5

    enum CounterKind
      Zero
      Reference
      Subtract
      Add
    end

    # A counter reference, or an arithmetic expression over counters.
    record Counter, kind : CounterKind, id : Int32 do
      def self.zero : self
        new(:zero, 0)
      end

      def self.reference(id : Int32) : self
        new(:reference, id)
      end

      def encode : UInt64
        (id.to_u64 << 2) | kind.value
      end
    end

    # An expression combining two counters with the kind of the counter that
    # refers to it: `lhs - rhs` for `CounterKind::Subtract`, `lhs + rhs` for
    # `CounterKind::Add`.
    record Expression, lhs : Counter, rhs : Counter

    # A region in the file at index *file_id* of a function's file table.
    # Lines and columns are 1-based; *column_end* is exclusive.
    #
    # A gap region covers source between code, such as between a condition
    # and the body of a branch. It doesn't count as executed code of the
    # lines it covers, but it sets the count of the lines that follow it.
    record Region, counter : Counter, file_id : Int32,
      line_start : Int32, column_start : Int32,
      line_end : Int32, column_end : Int32, gap : Bool = false

    # Returns the hash `llvm-cov` uses to identify function names and
    # filenames tables: the first 8 bytes of the MD5 digest, as a
    # little-endian integer.
    def self.md5_hash(data : String | Bytes) : UInt64
      IO::ByteFormat::LittleEndian.decode(UInt64, Crystal::Digest::MD5.digest(data)[0, 8])
    end

    # Encodes a filenames table, uncompressed. The first entry must be the
    # compilation directory, which `llvm-cov` uses to resolve the other
    # entries if they are relative paths.
    def self.encode_filenames(filenames : Array(String)) : Bytes
      names = IO::Memory.new
      filenames.each do |filename|
        write_uleb128(names, filename.bytesize)
        names << filename
      end

      io = IO::Memory.new
      write_uleb128(io, filenames.size)
      write_uleb128(io, names.size)
      write_uleb128(io, 0) # compressed size, 0 means uncompressed
      io.write(names.to_slice)
      io.to_slice
    end

    # Encodes a function's mapping. *filename_indices* maps the file IDs of
    # *regions* to entries of the filenames table.
    def self.encode_function(filename_indices : Array(Int32), expressions : Array(Expression), regions : Array(Region)) : Bytes
      io = IO::Memory.new

      write_uleb128(io, filename_indices.size)
      filename_indices.each { |index| write_uleb128(io, index) }

      write_uleb128(io, expressions.size)
      expressions.each do |expression|
        write_uleb128(io, expression.lhs.encode)
        write_uleb128(io, expression.rhs.encode)
      end

      sorted_regions = regions.sort_by { |region| {region.file_id, region.line_start, region.column_start} }
      filename_indices.each_index do |file_id|
        file_regions = sorted_regions.select { |region| region.file_id == file_id }
        write_uleb128(io, file_regions.size)

        # Each region's start line is a delta from the previous region's
        # start line in the same file.
        previous_line = 0
        file_regions.each do |region|
          write_uleb128(io, region.counter.encode)
          write_uleb128(io, region.line_start - previous_line)
          write_uleb128(io, region.column_start)
          write_uleb128(io, region.line_end - region.line_start)
          write_uleb128(io, region.gap ? (region.column_end.to_u64 | 1_u64 << 31) : region.column_end)
          previous_line = region.line_start
        end
      end

      io.to_slice
    end

    private def self.write_uleb128(io : IO, value : Int) : Nil
      value = value.to_u64
      loop do
        byte = (value & 0x7f).to_u8
        value >>= 7
        if value == 0
          io.write_byte(byte)
          break
        end
        io.write_byte(byte | 0x80)
      end
    end
  end
end
