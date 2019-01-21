module OccamsRecord
  # Classes and methods for handing query results.
  module Results
    # ActiveRecord's internal type casting API changes from version to version.
    CASTER = case ActiveRecord::VERSION::MAJOR
             when 4 then :type_cast_from_database
             when 5 then :deserialize
             end

    #
    # Dynamically build a class for a specific set of result rows. It inherits from OccamsRecord::Results::Row, and optionall includes
    # a user-defined module.
    #
    # @param column_names [Array<String>] the column names in the result set. The order MUST match the order returned by the query.
    # @param column_types [Hash] Column name => type from an ActiveRecord::Result
    # @param association_names [Array<String>] names of associations that will be eager loaded into the results.
    # @param model [ActiveRecord::Base] the AR model representing the table (it holds column & type info).
    # @param modules [Array<Module>] (optional)
    # @return [OccamsRecord::Results::Row] a class customized for this result set
    #
    def self.klass(column_names, column_types, association_names = [], model: nil, modules: nil)
      Class.new(Results::Row) do
        Array(modules).each { |mod| prepend mod } if modules

        self.columns = column_names.map(&:to_s)
        self.associations = association_names.map(&:to_s)
        self.model_name = model ? model.name : nil
        self.table_name = model ? model.table_name : nil
        self.primary_key = model&.primary_key&.to_s

        # Build getters & setters for associations. (We need setters b/c they're set AFTER the row is initialized
        attr_accessor(*association_names)

        # Build id getters for associations, e.g. "widget_ids" for "widgets"
        self.associations.each do |assoc|
          if (ref = model.reflections[assoc]) and !ref.polymorphic? and (ref.macro == :has_many or ref.macro == :has_and_belongs_to_many)
            pkey = ref.association_primary_key.to_sym
            define_method "#{assoc.singularize}_ids" do
              begin
                self.send(assoc).map(&pkey).uniq
              rescue NoMethodError => e
                raise MissingColumnError.new(self, e.name)
              end
            end
          end
        end if model

        # Build a getter for each attribute returned by the query. The values will be type converted on demand.
        model_column_types = model ? model.attributes_builder.types : {}
        self.columns.each_with_index do |col, idx|
          type =
            column_types[col] ||
            model_column_types[col] ||
            raise("OccamsRecord: Column `#{col}` does not exist on model `#{self.model_name}`")

          case type.type
          when :datetime
            define_method(col) { @cast_values[idx] ||= type.send(CASTER, @raw_values[idx])&.in_time_zone }
          when :boolean
            define_method(col) { @cast_values[idx] ||= type.send(CASTER, @raw_values[idx]) }
            define_method("#{col}?") { !!send(col) }
          else
            define_method(col) { @cast_values[idx] ||= type.send(CASTER, @raw_values[idx]) }
          end
        end
      end
    end
  end
end