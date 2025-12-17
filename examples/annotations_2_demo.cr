# Annotations 2.0 Demo - Validation Framework
# This example demonstrates all features of the enhanced annotation system.

# =============================================================================
# 1. ANNOTATION INHERITANCE WITH TYPED FIELDS
# =============================================================================

# Base constraint annotation - all validators inherit from this
annotation Constraint
  # Public field with typed array - element type extracted from 'of' clause
  groups : ArrayLiteral = [] of String

  # Private field - accessible in macros but NOT on runtime Instance class
  private priority : NumberLiteral = 0
end

# Child annotation inherits 'groups' from Constraint
annotation NotBlank < Constraint
  message : StringLiteral = "must not be blank"
  allow_nil : BoolLiteral = false
end

# Another child with different defaults
annotation Length < Constraint
  message : StringLiteral = "has invalid length"
  min : NumberLiteral = 0
  max : NumberLiteral = 255
end

# Annotation with typed hash field
annotation Metadata
  tags : HashLiteral = {} of String => String
end

# =============================================================================
# 2. USING ANNOTATIONS ON A MODEL CLASS
# =============================================================================

class User
  @[NotBlank(message: "Name is required", groups: ["registration", "update"])]
  property name : String = ""

  @[NotBlank(message: "Email cannot be empty")]
  @[Length(min: 5, max: 100, message: "Email must be 5-100 characters")]
  property email : String = ""

  @[Length(min: 8, message: "Password must be at least 8 characters", groups: ["registration"])]
  property password : String = ""

  @[Metadata(tags: {"source" => "user_input", "sensitive" => "true"})]
  property notes : String = ""
end

# =============================================================================
# 3. VALIDATION FRAMEWORK USING MACROS
# =============================================================================

class User
  # Validate the user, optionally filtering by group
  def validate(group : String? = nil) : Array(String)
    errors = [] of String

    {% for ivar in @type.instance_vars %}
      {% for ann in ivar.annotations(Constraint) %}
        constraint = {{ ann.to_runtime_representation }}

        # Check if this constraint applies to the requested group
        applies = if group.nil?
          true
        else
          constraint.groups.empty? || constraint.groups.includes?(group)
        end

        if applies
          value = @{{ ivar.name }}

          # NotBlank validation
          {% if ann.name.stringify == "NotBlank" %}
            if value.is_a?(String) && value.blank?
              unless {{ ann[:allow_nil] }} && value.nil?
                errors << "{{ ivar.name }}: #{constraint.message}"
              end
            end
          {% end %}

          # Length validation
          {% if ann.name.stringify == "Length" %}
            if value.is_a?(String)
              len = value.size
              min = {{ ann[:min] }}.to_i
              max = {{ ann[:max] }}.to_i
              if len < min || len > max
                errors << "{{ ivar.name }}: #{constraint.message}"
              end
            end
          {% end %}
        end
      {% end %}
    {% end %}

    errors
  end
end

# =============================================================================
# 4. DEMONSTRATING THE FEATURES
# =============================================================================

puts "=" * 60
puts "ANNOTATIONS 2.0 DEMO - VALIDATION FRAMEWORK"
puts "=" * 60

# --- Feature: Auto-generated Instance classes ---
puts "\n1. AUTO-GENERATED INSTANCE CLASSES"
puts "-" * 40

not_blank = NotBlankInstance.new(
  message: "Field is required",
  allow_nil: true,
  groups: ["api", "web"]
)
puts "NotBlankInstance:"
puts "  message: #{not_blank.message}"
puts "  allow_nil: #{not_blank.allow_nil}"
puts "  groups: #{not_blank.groups.inspect}"

# --- Feature: Inheritance - child Instance inherits from parent ---
puts "\n2. INSTANCE CLASS INHERITANCE"
puts "-" * 40

length = LengthInstance.new(min: 1, max: 50)
puts "LengthInstance inherits from ConstraintInstance:"
puts "  Is a ConstraintInstance? #{length.is_a?(ConstraintInstance)}"
puts "  groups (inherited): #{length.groups.inspect}"
puts "  min: #{length.min}"
puts "  max: #{length.max}"

# --- Feature: Type-safe arrays and hashes ---
puts "\n3. TYPED ARRAYS AND HASHES"
puts "-" * 40

metadata = MetadataInstance.new(tags: {"env" => "production", "version" => "2.0"})
puts "MetadataInstance with Hash(String, String):"
puts "  tags: #{metadata.tags.inspect}"
puts "  tags type: #{metadata.tags.class}"

# --- Feature: Macro access to annotation fields ---
puts "\n4. MACRO ACCESS TO ANNOTATION FIELDS"
puts "-" * 40

class User
  def self.show_annotations
    {% for ivar in @type.instance_vars %}
      {% for ann in ivar.annotations(Constraint) %}
        puts "  {{ ivar.name }}:"
        puts "    annotation: {{ ann.name }}"
        puts "    message: #{{{ ann[:message] }}}"
        puts "    groups: #{{{ ann[:groups] }}}"
        # Private fields are still accessible in macros
        puts "    priority (private): #{{{ ann[:priority] }}}"
      {% end %}
    {% end %}
  end
end

puts "Annotations on User class:"
User.show_annotations

# --- Feature: to_runtime_representation in action ---
puts "\n5. TO_RUNTIME_REPRESENTATION"
puts "-" * 40

class User
  def self.first_constraint
    {% for ivar in @type.instance_vars %}
      {% if ann = ivar.annotation(Constraint) %}
        return {{ ann.to_runtime_representation }}
      {% end %}
    {% end %}
    raise "No constraints found"
  end
end

first_constraint = User.first_constraint
puts "First constraint from User (via to_runtime_representation):"
puts "  Type: #{first_constraint.class}"
puts "  Message: #{first_constraint.message}"
puts "  Groups: #{first_constraint.groups.inspect}"

# --- Feature: Validation using collected constraints ---
puts "\n6. VALIDATION IN ACTION"
puts "-" * 40

user = User.new
user.name = ""
user.email = "ab"
user.password = "123"

puts "Validating empty user (all groups):"
user.validate.each { |e| puts "  ❌ #{e}" }

puts "\nValidating for 'registration' group only:"
user.validate("registration").each { |e| puts "  ❌ #{e}" }

user.name = "Alice"
user.email = "alice@example.com"
user.password = "securepassword123"

puts "\nValidating valid user:"
errors = user.validate
if errors.empty?
  puts "  ✓ All validations passed!"
else
  errors.each { |e| puts "  ❌ #{e}" }
end

# --- Feature: Polymorphism with Instance classes ---
puts "\n7. POLYMORPHISM WITH CONSTRAINT INSTANCES"
puts "-" * 40

def describe_constraint(c : ConstraintInstance)
  puts "  Constraint type: #{c.class}"
  puts "  Groups: #{c.groups.inspect}"
end

constraints = [
  NotBlankInstance.new(message: "Required"),
  LengthInstance.new(min: 1, max: 100),
  NotBlankInstance.new(message: "Cannot be empty", groups: ["strict"])
] of ConstraintInstance

puts "Processing constraints polymorphically:"
constraints.each_with_index do |c, i|
  puts "Constraint ##{i + 1}:"
  describe_constraint(c)
end

puts "\n" + "=" * 60
puts "Demo complete! All Annotations 2.0 features demonstrated."
puts "=" * 60
