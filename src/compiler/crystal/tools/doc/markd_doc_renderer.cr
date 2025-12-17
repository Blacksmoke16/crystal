{% if !flag?(:without_libxml2) %}
  require "sanitize"
{% end %}

class Crystal::Doc::MarkdDocRenderer < Markd::HTMLRenderer
  {% if !flag?(:without_libxml2) %}
    SANITIZER = Sanitize::Policy::HTMLSanitizer.common
  {% else %}
    SANITIZER = nil
  {% end %}

  @anchor_map = Hash(String, Int32).new(0)

  def initialize(@type : Crystal::Doc::Type, options)
    super(options)
  end

  def self.new(obj : Constant | Macro | Method, options)
    new obj.type, options
  end

  def heading(node : Markd::Node, entering : Bool)
    tag_name = HEADINGS[node.data["level"].as(Int32) - 1]
    if entering
      anchor = collect_text(node)
        .underscore                # Underscore the string
        .gsub(/[^\w\d\s\-.~]/, "") # Delete unsafe URL characters
        .strip                     # Strip leading/trailing whitespace
        .gsub(/[\s_-]+/, '-')      # Replace `_` and leftover whitespace with `-`

      seen_count = @anchor_map[anchor] += 1

      if seen_count > 1
        anchor += "-#{seen_count - 1}"
      end

      tag(tag_name, attrs(node))
      literal Crystal::Doc.anchor_link(anchor)
    else
      tag(tag_name, end_tag: true)
      newline
    end
  end

  def collect_text(main)
    String.build do |io|
      walker = main.walker
      while item = walker.next
        node, entering = item
        if entering && (text = node.text)
          io << text
        end
      end
    end
  end

  def code_body(node : Markd::Node)
    if in_link?(node)
      output(node.text)
    else
      literal(expand_code_links(escape(node.text)))
    end
  end

  def in_link?(node)
    parent = node.parent?
    return false unless parent
    return true if parent.type.link?

    in_link?(parent)
  end

  def expand_code_links(text : String) : String
    # Check method reference (without #, but must be the whole text)
    if text =~ /\A([\w<=>+\-*\/\[\]&|?!^~]+[?!]?)(?:\((.*?)\))?\Z/
      name = $1
      args = $2? || ""

      method = lookup_method @type, name, args
      if method
        return method_link method, "#{method.prefix}#{text}"
      end
    end

    # Check Type#method(...) or Type or #method(...)
    text.gsub %r(
      ((?:\B::)?\b[A-Z]\w*(?:\:\:[A-Z]\w*)*|\B|(?<=\bself))(?<!\.)([#.])([\w<=>+\-*\/\[\]&|?!^~]+[?!]?)(?:\((.*?)\))?
        |
      ((?:\B::)?\b[A-Z]\w*(?:\:\:[A-Z]\w*)*)
      )x do |match_text|
      if $5?
        # Type
        another_type = @type.lookup_path(match_text)
        if another_type && another_type.must_be_included?
          next type_link another_type, match_text
        end
        next match_text
      end

      type_name = $1.presence
      instance_methods_first = $2 == "#"
      method_name = $3
      method_args = $4? || ""

      if type_name
        # Type#method(...)
        another_type = @type.lookup_path(type_name)
        if another_type && @type.must_be_included?
          method = lookup_method another_type, method_name, method_args, instance_methods_first
          if method
            next method_link method, match_text
          end
        end
      else
        # #method(...)
        method = lookup_method @type, method_name, method_args, instance_methods_first
        if method && method.must_be_included?
          next method_link method, match_text
        end
      end

      match_text
    end
  end

  def code_block_language(languages)
    language = languages.try(&.first?).try(&.strip.presence)
    if language.nil? || language == "cr"
      language = "crystal"
    end
    language
  end

  def code_block_body(node : Markd::Node, language : String?)
    code = node.text.chomp
    if language == "crystal"
      literal(SyntaxHighlighter::HTML.highlight! code)
    else
      output(code)
    end
  end

  private def type_link(type, text)
    %(<a href="#{type.path_from(@type)}">#{text}</a>)
  end

  private def method_link(method, text)
    %(<a href="#{method.type.path_from(@type)}#{method.anchor}">#{text}</a>)
  end

  private def split_args(args : String, &)
    current = String::Builder.new
    depth = 0

    args.each_char do |c|
      case c
      when '(', '[', '{' then depth += 1
      when ')', ']', '}' then depth -= 1
      when ','
        if depth == 0
          yield current.to_s
          current = String::Builder.new
          next
        end
      end
      current << c
    end
    yield current.to_s
  end

  private def parse_arg_specs(args : String) : Array(Crystal::Doc::ArgSpec)?
    return nil if args.empty?

    specs = [] of Crystal::Doc::ArgSpec
    split_args(args) do |arg|
      arg = arg.strip
      if arg[0]?.try(&.uppercase?)
        specs << Crystal::Doc::ArgSpec.new(nil, arg)
      else
        specs << Crystal::Doc::ArgSpec.new(arg, nil)
      end
    end
    specs
  end

  private def lookup_method(type, name, args, instance_methods_first = true)
    arg_specs = parse_arg_specs(args)

    base_match =
      if instance_methods_first
        type.lookup_method(name, arg_specs) || type.lookup_class_method(name, arg_specs)
      else
        type.lookup_class_method(name, arg_specs) || type.lookup_method(name, arg_specs)
      end
    base_match ||
      type.lookup_macro(name, arg_specs) ||
      type.program.lookup_macro(name, arg_specs)
  end

  def text(node : Markd::Node, entering : Bool)
    output(sanitize(node))
  end

  def html_block(node : Markd::Node, entering : Bool)
    newline
    content = @options.safe? ? "<!-- raw HTML omitted -->" : sanitize(node)
    literal(content)
    newline
  end

  def html_inline(node : Markd::Node, entering : Bool)
    content = @options.safe? ? "<!-- raw HTML omitted -->" : sanitize(node)
    literal(content)
  end

  def sanitize(node : Markd::Node) : String
    {% if !flag?(:without_libxml2) %}
      SANITIZER.process(node.text)
    {% else %}
      node.text
    {% end %}
  end
end
