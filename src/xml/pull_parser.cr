require "./libxml2"
require "./parser_options"
require "./error"

# `XML::PullParser` is a streaming parser for XML that processes documents
# token by token, similar to `JSON::PullParser`.
#
# Unlike `XML.parse` which loads the entire document into memory as a DOM tree,
# `XML::PullParser` reads tokens sequentially, making it suitable for processing
# large XML documents with minimal memory usage.
#
# ```
# require "xml"
#
# xml = <<-XML
#   <person id="1">
#     <name>John</name>
#   </person>
#   XML
#
# pull = XML::PullParser.new(xml)
# pull.read  # => XML::PullParser::Kind::StartElement
# pull.name  # => "person"
# pull["id"] # => "1"
# pull.read  # => XML::PullParser::Kind::StartElement
# pull.name  # => "name"
# pull.read  # => XML::PullParser::Kind::Text
# pull.value # => "John"
# ```
#
# WARNING: This type is not concurrency-safe.
class XML::PullParser
  # The kind of token currently being read.
  enum Kind
    # Start of an element, e.g., `<foo>` or `<foo attr="value">`.
    StartElement

    # End of an element, e.g., `</foo>` or the implicit end of `<foo/>`.
    EndElement

    # Text content within an element.
    Text

    # CDATA section content.
    CData

    # XML comment content.
    Comment

    # Processing instruction, e.g., `<?target data?>`.
    ProcessingInstruction

    # Whitespace-only text content.
    Whitespace

    # End of the document.
    EOF
  end

  # Returns the kind of the current token.
  getter kind : Kind = Kind::EOF

  # Returns any errors reported while parsing.
  getter errors : Array(XML::Error)

  @reader : XML::Reader

  # Creates a new pull parser from a string.
  #
  # See `XML::ParserOptions.default` for default options.
  def initialize(str : String, options : XML::ParserOptions = XML::ParserOptions.default)
    @reader = XML::Reader.new(str, options)
    @errors = @reader.errors
  end

  # Creates a new pull parser from an IO.
  #
  # See `XML::ParserOptions.default` for default options.
  def initialize(io : IO, options : XML::ParserOptions = XML::ParserOptions.default)
    @reader = XML::Reader.new(io, options)
    @errors = @reader.errors
  end

  # Advances to the next token and returns its kind.
  #
  # Returns `Kind::EOF` when there are no more tokens.
  def read : Kind
    loop do
      unless @reader.read
        @kind = Kind::EOF
        return @kind
      end

      case @reader.node_type
      when .element?
        @kind = Kind::StartElement
        return @kind
      when .end_element?
        @kind = Kind::EndElement
        return @kind
      when .text?
        @kind = Kind::Text
        return @kind
      when .cdata?
        @kind = Kind::CData
        return @kind
      when .comment?
        @kind = Kind::Comment
        return @kind
      when .processing_instruction?
        @kind = Kind::ProcessingInstruction
        return @kind
      when .whitespace?, .significant_whitespace?
        @kind = Kind::Whitespace
        return @kind
      else
        # Skip internal types: NONE, ATTRIBUTE, ENTITY*, DOCUMENT*, NOTATION, XML_DECLARATION
        next
      end
    end
  end

  # Returns the name of the current element or processing instruction target.
  #
  # For elements, this is the tag name (e.g., "person" for `<person>`).
  # If the element has a namespace prefix, this includes it (e.g., "ns:person").
  # For processing instructions, this is the target (e.g., "xml" for `<?xml ...?>`).
  # For other token types, returns an empty string.
  def name : String
    @reader.name
  end

  # Returns the local name of the current element (without namespace prefix).
  #
  # For `<ns:person>`, this returns "person".
  def local_name : String
    @reader.local_name
  end

  # Returns the namespace prefix of the current element, or an empty string if none.
  #
  # For `<ns:person>`, this returns "ns".
  def prefix : String
    @reader.prefix
  end

  # Returns the namespace URI of the current element, or an empty string if none.
  def namespace_uri : String
    @reader.namespace_uri
  end

  # Returns the text content of the current token.
  #
  # For `Text`, `CData`, `Comment`, and `Whitespace` tokens, returns the content.
  # For `ProcessingInstruction`, returns the data portion.
  # For elements, returns an empty string.
  def value : String
    @reader.value
  end

  # Returns the current nesting depth.
  #
  # The root element is at depth 0.
  def depth : Int32
    @reader.depth
  end

  # Returns `true` if the current element is self-closing (e.g., `<br/>`).
  def empty_element? : Bool
    @reader.empty_element?
  end

  # Returns `true` if the current element has attributes.
  def has_attributes? : Bool
    @reader.has_attributes?
  end

  # Returns the number of attributes on the current element.
  def attributes_count : Int32
    @reader.attributes_count
  end

  # Gets the attribute value for the given name.
  #
  # Raises `KeyError` if the attribute doesn't exist.
  def [](attribute : String) : String
    @reader[attribute]
  end

  # Gets the attribute value for the given name, or `nil` if it doesn't exist.
  def []?(attribute : String) : String?
    @reader[attribute]?
  end

  # Yields each attribute name and value on the current element.
  #
  # ```
  # pull.each_attribute do |name, value|
  #   puts "#{name}=#{value}"
  # end
  # ```
  def each_attribute(& : String, String ->) : Nil
    return unless has_attributes?

    if @reader.move_to_first_attribute
      loop do
        yield @reader.name, @reader.value
        break unless @reader.move_to_next_attribute
      end
      @reader.move_to_element
    end
  end

  # Skips the current element and all its children.
  #
  # After calling this, the parser will be positioned at the next sibling
  # or at the parent's end element.
  def skip : Nil
    return if @kind.eof?

    case @kind
    when .start_element?
      if empty_element?
        # Self-closing elements have no children to skip
        return
      end

      # Skip to the matching end element
      start_depth = depth
      loop do
        read
        break if @kind.eof?
        break if @kind.end_element? && depth == start_depth
      end
    else
      # For non-elements, nothing to skip
    end
  end

  # Reads a start element, returns its name, and advances to the next token.
  #
  # Raises if the current token is not a start element.
  def read_start_element : String
    expect_kind Kind::StartElement, "read_start_element"
    name = self.name
    read
    name
  end

  # Reads an end element and advances to the next token.
  #
  # Raises if the current token is not an end element.
  def read_end_element : Nil
    expect_kind Kind::EndElement, "read_end_element"
    read
    nil
  end

  # Reads text content and advances to the next token.
  #
  # Accepts `Text`, `CData`, or `Whitespace` tokens.
  # Raises if the current token is not one of these types.
  def read_text : String
    case @kind
    when .text?, .c_data?, .whitespace?
      value.tap { read }
    else
      raise "Expected text content but was #{@kind}"
    end
  end

  # Reads all text content until the current element ends.
  #
  # This concatenates all text, CDATA, and whitespace content within
  # the current element, ignoring any nested elements.
  def read_content : String
    content = String::Builder.new
    start_depth = depth

    loop do
      case @kind
      when .text?, .c_data?, .whitespace?
        content << value
        read
      when .start_element?
        # Skip nested elements
        skip
        read
      when .end_element?
        break if depth <= start_depth
        read
      when .eof?
        break
      else
        read
      end
    end

    content.to_s
  end

  # Reads an element and yields for processing its content.
  #
  # The block is called after reading the start element, and the method
  # ensures the end element is consumed after the block returns.
  #
  # ```
  # pull.read_element do
  #   # Process element content
  #   puts pull.read_text
  # end
  # ```
  def read_element(& : ->) : Nil
    expect_kind Kind::StartElement, "read_element"
    start_name = name
    start_depth = depth

    if empty_element?
      read
      return
    end

    read

    yield

    # Ensure we're at the end element
    while @kind != Kind::EndElement || depth != start_depth
      if @kind.eof?
        raise "Unexpected EOF, expected </#{start_name}>"
      end
      read
    end

    read
  end

  # Yields for each child of the current element.
  #
  # The parser must be positioned on a start element. The block is called
  # once for each child token until the matching end element is reached.
  #
  # ```
  # pull.read_children do
  #   case pull.kind
  #   when .start_element?
  #     puts "Child element: #{pull.name}"
  #     pull.skip
  #   when .text?
  #     puts "Text: #{pull.value}"
  #   end
  #   pull.read
  # end
  # ```
  def read_children(& : ->) : Nil
    expect_kind Kind::StartElement, "read_children"
    start_depth = depth

    if empty_element?
      read
      return
    end

    read

    while @kind != Kind::EndElement || depth != start_depth
      if @kind.eof?
        raise "Unexpected EOF while reading children"
      end
      yield
    end

    read
  end

  # Calls the block if the next child element matches the given name.
  #
  # Other children are skipped. Returns the block's return value, or `nil`
  # if the named element was not found.
  #
  # ```
  # result = pull.on_element("name") do
  #   pull.read # consume start element
  #   pull.read_text
  # end
  # ```
  def on_element(name : String, & : self -> T) : T? forall T
    result = nil

    read_children do
      if @kind.start_element? && self.name == name
        result = yield self
      else
        if @kind.start_element?
          skip
        end
        read
      end
    end

    result
  end

  # Raises an `XML::Error` with the given message.
  def raise(message : String) : NoReturn
    ::raise XML::Error.new(message, 0)
  end

  private def expect_kind(expected : Kind, method_name : String)
    unless @kind == expected
      raise "#{method_name}: expected #{expected} but was #{@kind}"
    end
  end
end
