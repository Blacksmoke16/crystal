module Crystal
  # Types that can be used as annotation keys: traditional annotations or @[Annotation] classes
  alias AnnotationKey = AnnotationType | ClassType

  module Annotatable
    property annotations : Hash(AnnotationKey, Array(Annotation))?

    # Adds an annotation with the given type and value
    def add_annotation(annotation_type : AnnotationKey, value : Annotation)
      annotations = @annotations ||= {} of AnnotationKey => Array(Annotation)
      annotations[annotation_type] ||= [] of Annotation
      annotations[annotation_type] << value
    end

    # Returns the last defined annotation with the given type, if any, or `nil` otherwise.
    # For annotation classes, also checks if the stored annotation inherits from annotation_type.
    def annotation(annotation_type : AnnotationKey) : Annotation?
      # Direct match first
      if result = @annotations.try &.[annotation_type]?.try &.last?
        return result
      end

      # Check for inheritance (annotation classes only)
      @annotations.try &.each do |stored_type, anns|
        next if stored_type == annotation_type
        if stored_type.is_a?(ClassType) && stored_type.annotation_class?
          if stored_type.ancestors.includes?(annotation_type)
            return anns.last?
          end
        end
      end

      nil
    end

    # Returns all annotations with the given type, if any, or `nil` otherwise.
    # For annotation classes, also returns annotations that inherit from annotation_type.
    def annotations(annotation_type : AnnotationKey) : Array(Annotation)?
      results = [] of Annotation

      # Direct matches
      if direct = @annotations.try &.[annotation_type]?
        results.concat(direct)
      end

      # Check for inheritance (annotation classes only)
      @annotations.try &.each do |stored_type, anns|
        next if stored_type == annotation_type
        if stored_type.is_a?(ClassType) && stored_type.annotation_class?
          if stored_type.ancestors.includes?(annotation_type)
            results.concat(anns)
          end
        end
      end

      results.empty? ? nil : results
    end

    # Returns all annotations on this type, if any, or `nil` otherwise
    def all_annotations : Array(Annotation)?
      @annotations.try &.values.flatten
    end
  end
end
