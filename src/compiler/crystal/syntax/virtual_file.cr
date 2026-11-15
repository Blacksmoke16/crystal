# A VirtualFile is used as a Location's filename when
# expanding a macro. It contains the macro expanded source
# code so the user can debug it as if there was a file in the
# filesystem with those contents.
class Crystal::VirtualFile
  # The macro that produced this VirtualFile
  getter macro : Macro

  # The expanded source code of the macro
  getter source : String

  # The location where the macro was expanded (where the macro was invoked).
  getter expanded_location : Location?

  # The location in the macro's source code where each line of `source` starts,
  # by line number, for the lines that start in the macro's literal text.
  getter line_locations : Hash(Int32, Location)?

  def initialize(@macro : Macro, @source : String, @expanded_location : Location?, @line_locations : Hash(Int32, Location)? = nil)
  end

  # Returns the location in the macro's source code of *line_number* and *column_number* of `source`,
  # if that line starts in the macro's literal text.
  def line_location(line_number : Int32, column_number : Int32) : Location?
    if line_location = @line_locations.try &.[line_number]?
      Location.new(line_location.filename, line_location.line_number, column_number)
    end
  end

  def to_s(io : IO) : Nil
    io << "expanded macro: " << @macro.name
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end

  def pretty_print(pp)
    pp.text inspect
  end
end
