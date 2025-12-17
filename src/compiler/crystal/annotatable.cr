module Crystal
  module Annotatable
    # Annotations on this instance
    property annotations : Hash(AnnotationType, Array(Annotation))?

    # Adds an annotation with the given type and value
    def add_annotation(annotation_type : AnnotationType, value : Annotation)
      annotations = @annotations ||= {} of AnnotationType => Array(Annotation)
      annotations[annotation_type] ||= [] of Annotation
      annotations[annotation_type] << value
    end

    # Returns the last defined annotation with the given type, if any, or `nil` otherwise.
    # Also returns annotations whose type inherits from annotation_type.
    def annotation(annotation_type : AnnotationType) : Annotation?
      annotations = @annotations
      return nil unless annotations

      # First check for exact match
      if exact = annotations[annotation_type]?.try(&.last?)
        return exact
      end

      # Check for child annotations (annotations whose type inherits from annotation_type)
      annotations.each do |type, anns|
        if type.inherits_from?(annotation_type)
          return anns.last?
        end
      end

      nil
    end

    # Returns all annotations with the given type, if any, or `nil` otherwise.
    # Also returns annotations whose type inherits from annotation_type.
    def annotations(annotation_type : AnnotationType) : Array(Annotation)?
      annotations = @annotations
      return nil unless annotations

      result = [] of Annotation

      # Collect exact matches
      if exact = annotations[annotation_type]?
        result.concat(exact)
      end

      # Collect child annotations (annotations whose type inherits from annotation_type)
      annotations.each do |type, anns|
        next if type == annotation_type # Already added
        if type.inherits_from?(annotation_type)
          result.concat(anns)
        end
      end

      result.empty? ? nil : result
    end

    # Returns all annotations on this type, if any, or `nil` otherwise
    def all_annotations : Array(Annotation)?
      @annotations.try &.values.flatten
    end
  end
end
