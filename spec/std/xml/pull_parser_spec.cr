require "spec"
require "xml"

private def xml
  <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <people>
    <person id="1">
      <name>John</name>
    </person>
    <person id="2">
      <name>Peter</name>
    </person>
  </people>
  XML
end

module XML
  describe PullParser do
    describe ".new" do
      context "with default parser options" do
        it "can be initialized from a string" do
          pull = PullParser.new("<root/>")
          pull.should be_a(XML::PullParser)
        end

        it "can be initialized from an io" do
          io = IO::Memory.new("<root/>")
          pull = PullParser.new(io)
          pull.should be_a(XML::PullParser)
        end
      end

      context "with custom parser options" do
        it "can be initialized from a string with options" do
          pull = PullParser.new(xml, XML::ParserOptions::NOBLANKS)
          pull.read.should eq(PullParser::Kind::StartElement)
          pull.name.should eq("people")
          pull.read.should eq(PullParser::Kind::StartElement)
          pull.name.should eq("person")
        end

        it "can be initialized from an io with options" do
          io = IO::Memory.new(xml)
          pull = PullParser.new(io, XML::ParserOptions::NOBLANKS)
          pull.read.should eq(PullParser::Kind::StartElement)
          pull.name.should eq("people")
          pull.read.should eq(PullParser::Kind::StartElement)
          pull.name.should eq("person")
        end
      end
    end

    describe "#kind" do
      it "starts as EOF before first read" do
        pull = PullParser.new("<root/>")
        pull.kind.should eq(PullParser::Kind::EOF)
      end
    end

    describe "#read" do
      it "returns StartElement for opening tags" do
        pull = PullParser.new("<root/>")
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("root")
      end

      it "returns EndElement for closing tags" do
        pull = PullParser.new("<root></root>")
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.read.should eq(PullParser::Kind::EndElement)
        pull.name.should eq("root")
      end

      it "returns Text for text content" do
        pull = PullParser.new("<root>hello</root>")
        pull.read # start element
        pull.read.should eq(PullParser::Kind::Text)
        pull.value.should eq("hello")
      end

      it "returns CData for CDATA sections" do
        pull = PullParser.new("<root><![CDATA[hello]]></root>")
        pull.read # start element
        pull.read.should eq(PullParser::Kind::CData)
        pull.value.should eq("hello")
      end

      it "returns Comment for comments" do
        pull = PullParser.new("<root><!-- hello --></root>")
        pull.read # start element
        pull.read.should eq(PullParser::Kind::Comment)
        pull.value.should eq(" hello ")
      end

      it "returns Whitespace for whitespace-only content" do
        pull = PullParser.new("<root>\n  </root>")
        pull.read # start element
        pull.read.should eq(PullParser::Kind::Whitespace)
      end

      it "returns EOF at end of document" do
        pull = PullParser.new("<root/>")
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.read.should eq(PullParser::Kind::EOF)
        pull.read.should eq(PullParser::Kind::EOF)
      end

      it "reads nested elements" do
        pull = PullParser.new("<a><b><c/></b></a>")
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("a")
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("b")
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("c")
        pull.read.should eq(PullParser::Kind::EndElement)
        pull.name.should eq("b")
        pull.read.should eq(PullParser::Kind::EndElement)
        pull.name.should eq("a")
        pull.read.should eq(PullParser::Kind::EOF)
      end

      it "reads processing instructions" do
        pull = PullParser.new("<root><?target data?></root>")
        pull.read # start element
        pull.read.should eq(PullParser::Kind::ProcessingInstruction)
        pull.name.should eq("target")
        pull.value.should eq("data")
      end
    end

    describe "#name" do
      it "returns element name" do
        pull = PullParser.new("<root/>")
        pull.read
        pull.name.should eq("root")
      end

      it "returns empty string before first read" do
        pull = PullParser.new("<root/>")
        pull.name.should eq("")
      end
    end

    describe "#value" do
      it "returns text content" do
        pull = PullParser.new("<root>hello</root>")
        pull.read
        pull.read
        pull.value.should eq("hello")
      end

      it "returns empty string for elements" do
        pull = PullParser.new("<root/>")
        pull.read
        pull.value.should eq("")
      end
    end

    describe "#depth" do
      it "returns 0 for root element" do
        pull = PullParser.new("<root/>")
        pull.read
        pull.depth.should eq(0)
      end

      it "returns correct depth for nested elements" do
        pull = PullParser.new("<a><b><c/></b></a>")
        pull.read
        pull.depth.should eq(0)
        pull.read
        pull.depth.should eq(1)
        pull.read
        pull.depth.should eq(2)
      end
    end

    describe "#empty_element?" do
      it "returns true for self-closing elements" do
        pull = PullParser.new("<root/>")
        pull.read
        pull.empty_element?.should be_true
      end

      it "returns false for elements with content" do
        pull = PullParser.new("<root></root>")
        pull.read
        pull.empty_element?.should be_false
      end
    end

    describe "#has_attributes?" do
      it "returns true when element has attributes" do
        pull = PullParser.new(%{<root id="1"/>})
        pull.read
        pull.has_attributes?.should be_true
      end

      it "returns false when element has no attributes" do
        pull = PullParser.new("<root/>")
        pull.read
        pull.has_attributes?.should be_false
      end
    end

    describe "#attributes_count" do
      it "returns number of attributes" do
        pull = PullParser.new(%{<root a="1" b="2" c="3"/>})
        pull.read
        pull.attributes_count.should eq(3)
      end

      it "returns 0 for elements without attributes" do
        pull = PullParser.new("<root/>")
        pull.read
        pull.attributes_count.should eq(0)
      end
    end

    describe "#[]" do
      it "returns attribute value" do
        pull = PullParser.new(%{<root id="42"/>})
        pull.read
        pull["id"].should eq("42")
      end

      it "raises KeyError for missing attribute" do
        pull = PullParser.new("<root/>")
        pull.read
        expect_raises(KeyError) { pull["missing"] }
      end
    end

    describe "#[]?" do
      it "returns attribute value or nil" do
        pull = PullParser.new(%{<root id="42"/>})
        pull.read
        pull["id"]?.should eq("42")
        pull["missing"]?.should be_nil
      end
    end

    describe "#each_attribute" do
      it "yields each attribute name and value" do
        pull = PullParser.new(%{<root a="1" b="2"/>})
        pull.read

        attrs = {} of String => String
        pull.each_attribute do |name, value|
          attrs[name] = value
        end

        attrs.should eq({"a" => "1", "b" => "2"})
      end

      it "does nothing for elements without attributes" do
        pull = PullParser.new("<root/>")
        pull.read

        called = false
        pull.each_attribute { called = true }
        called.should be_false
      end
    end

    describe "#skip" do
      it "skips self-closing element" do
        pull = PullParser.new("<a><b/><c/></a>")
        pull.read # a
        pull.read # b
        pull.skip
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("c")
      end

      it "skips element with children" do
        pull = PullParser.new("<a><b><c><d/></c></b><e/></a>")
        pull.read # a
        pull.read # b
        pull.skip
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("e")
      end

      it "skips element with text content" do
        pull = PullParser.new("<a><b>text</b><c/></a>")
        pull.read # a
        pull.read # b
        pull.skip
        pull.read.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("c")
      end
    end

    describe "#read_start_element" do
      it "returns element name and advances" do
        pull = PullParser.new("<root><child/></root>")
        pull.read
        name = pull.read_start_element
        name.should eq("root")
        pull.kind.should eq(PullParser::Kind::StartElement)
        pull.name.should eq("child")
      end

      it "raises if not on start element" do
        pull = PullParser.new("<root>text</root>")
        pull.read
        pull.read # text
        expect_raises(XML::Error, /read_start_element: expected StartElement/) do
          pull.read_start_element
        end
      end
    end

    describe "#read_end_element" do
      it "advances past end element" do
        pull = PullParser.new("<root></root>")
        pull.read
        pull.read
        pull.read_end_element
        pull.kind.should eq(PullParser::Kind::EOF)
      end

      it "raises if not on end element" do
        pull = PullParser.new("<root/>")
        pull.read
        expect_raises(XML::Error, /read_end_element: expected EndElement/) do
          pull.read_end_element
        end
      end
    end

    describe "#read_text" do
      it "returns text content" do
        pull = PullParser.new("<root>hello</root>")
        pull.read
        pull.read
        pull.read_text.should eq("hello")
      end

      it "returns CDATA content" do
        pull = PullParser.new("<root><![CDATA[hello]]></root>")
        pull.read
        pull.read
        pull.read_text.should eq("hello")
      end

      it "raises if not on text content" do
        pull = PullParser.new("<root/>")
        pull.read
        expect_raises(XML::Error, /Expected text content/) do
          pull.read_text
        end
      end
    end

    describe "#read_content" do
      it "reads all text content" do
        pull = PullParser.new("<root>hello world</root>")
        pull.read
        pull.read # move to text
        pull.read_content.should eq("hello world")
      end

      it "concatenates multiple text nodes" do
        pull = PullParser.new("<root>hello<!-- comment -->world</root>")
        pull.read
        pull.read # move to first text
        pull.read_content.should eq("helloworld")
      end
    end

    describe "#read_element" do
      it "yields for element content" do
        pull = PullParser.new("<root><child/></root>")
        pull.read

        yielded = false
        pull.read_element do
          yielded = true
          pull.kind.should eq(PullParser::Kind::StartElement)
          pull.name.should eq("child")
          pull.skip
          pull.read
        end

        yielded.should be_true
        pull.kind.should eq(PullParser::Kind::EOF)
      end

      it "works with empty elements" do
        pull = PullParser.new("<root/>")
        pull.read

        pull.read_element { }
        pull.kind.should eq(PullParser::Kind::EOF)
      end
    end

    describe "#read_children" do
      it "yields for each child" do
        pull = PullParser.new("<root><a/><b/><c/></root>")
        pull.read

        names = [] of String
        pull.read_children do
          if pull.kind.start_element?
            names << pull.name
            pull.skip
          end
          pull.read
        end

        names.should eq(["a", "b", "c"])
      end

      it "works with mixed content" do
        pull = PullParser.new("<root>text<child/>more</root>")
        pull.read

        kinds = [] of PullParser::Kind
        pull.read_children do
          kinds << pull.kind
          if pull.kind.start_element?
            pull.skip
          end
          pull.read
        end

        kinds.should eq([
          PullParser::Kind::Text,
          PullParser::Kind::StartElement,
          PullParser::Kind::Text,
        ])
      end
    end

    describe "#on_element" do
      it "calls block for matching element" do
        pull = PullParser.new("<root><name>John</name><age>30</age></root>")
        pull.read

        result = pull.on_element("name") do |p|
          p.read # consume start element
          p.read_text
        end

        result.should eq("John")
      end

      it "returns nil if element not found" do
        pull = PullParser.new("<root><other/></root>")
        pull.read

        result = pull.on_element("name") { "found" }
        result.should be_nil
      end
    end

    describe "#errors" do
      it "collects parsing errors" do
        options = XML::ParserOptions::RECOVER | XML::ParserOptions::NONET
        pull = PullParser.new(%(<root></wrong>), options)
        pull.read
        pull.read

        pull.errors.size.should be > 0
        pull.errors.first.to_s.should contain("mismatch")
      end
    end

    describe "full document parsing" do
      it "can parse the example document" do
        pull = PullParser.new(xml, XML::ParserOptions::NOBLANKS)

        # Skip to root element
        pull.read

        names = [] of String
        pull.read_children do
          if pull.kind.start_element? && pull.name == "person"
            id = pull["id"]
            pull.read_children do
              if pull.kind.start_element? && pull.name == "name"
                pull.read
                names << "#{pull.read_text} (id=#{id})"
              else
                if pull.kind.start_element?
                  pull.skip
                end
                pull.read
              end
            end
          else
            if pull.kind.start_element?
              pull.skip
            end
            pull.read
          end
        end

        names.should eq(["John (id=1)", "Peter (id=2)"])
      end
    end
  end
end
