module OccamsRecord
  # Classes and methods for handing query results.
  module Results
    # ActiveRecord's internal type casting API changes from version to version.
    CASTER = case ActiveRecord::VERSION::MAJOR
             when 4 then :type_cast_from_database
             when 5, 6, 7 then :deserialize
             else raise "OccamsRecord::Results::CASTER does yet support this version of ActiveRecord"
             end

    #
    # Dynamically build a class for a specific set of result rows. It inherits from OccamsRecord::Results::Row, and optionall prepends
    # user-defined modules.
    #
    # @param column_names [Array<String>] the column names in the result set. The order MUST match the order returned by the query.
    # @param column_types [Hash] Column name => type from an ActiveRecord::Result
    # @param association_names [Array<String>] names of associations that will be eager loaded into the results.
    # @param model [ActiveRecord::Base] the AR model representing the table (it holds column & type info).
    # @param modules [Array<Module>] (optional)
    # @param tracer [OccamsRecord::EagerLoaders::Tracer] the eager loaded that loaded this class of records
    # @param active_record_fallback [Symbol] If passed, missing methods will be forwarded to an ActiveRecord instance. Options are :lazy (allow lazy loading in the AR record) or :strict (require strict loading)
    # @return [OccamsRecord::Results::Row] a class customized for this result set
    #
    def self.klass(column_names, column_types, association_names = [], model: nil, modules: nil, tracer: nil, active_record_fallback: nil)
      raise ArgumentError, "Invalid active_record_fallback option :#{active_record_fallback}. Valid options are :lazy, :strict" if active_record_fallback and !%i(lazy strict).include?(active_record_fallback)
      raise ArgumentError, "Option active_record_fallback is not allowed when no model is present" if active_record_fallback and model.nil?

      Class.new(Results::Row) do
        Array(modules).each { |mod| prepend mod } if modules

        self.columns = column_names.map(&:to_s)
        self.associations = association_names.map(&:to_s)
        self._model = model
        self.model_name = model ? model.name : nil
        self.table_name = model ? model.table_name : nil
        self.eager_loader_trace = tracer
        self.active_record_fallback = active_record_fallback
        self.primary_key = if model&.primary_key and (pkey = model.primary_key.to_s) and columns.include?(pkey)
                             pkey
                           end

        # Build getters & setters for associations. (We need setters b/c they're set AFTER the row is initialized
        attr_accessor(*association_names)

        # Build a getter for each attribute returned by the query. The values will be type converted on demand.
        model_column_types = model ? model.attributes_builder.types : nil
        self.columns.each_with_index do |col, idx|
          #
          # NOTE there's lots of variation between DB adapters and AR versions here. Some notes:
          # * Postgres AR < 6.1 `column_types` will contain entries for every column.
          # * Postgres AR >= 6.1 `column_types` only contains entries for "exotic" types. Columns with "common" types have already been converted by the PG adapter.
          # * SQLite `column_types` will always be empty. Some types will have already been convered by the SQLite adapter, but others will depend on
          #   `model_column_types` for converstion. See test/raw_query_test.rb#test_common_types for examples.
          # * MySQL ?
          #
          type = column_types[col] || model_column_types&.[](col)

          #
          # NOTE is also some variation in when enum values are mapped in different AR versions.
          # In >=5.0, <=7.0, ActiveRecord::Result objects contain the human-readable values. In 4.2 and
          # pre-release versions of 7.1, they instead have the RAW values (e.g. integers) which we must map ourselves.
          #
          enum = model&.defined_enums&.[](col)
          inv_enum = enum&.invert

          case type&.type
          when nil
            if enum
              define_method(col) {
                val = @raw_values[idx]
                enum.has_key?(val) ? val : inv_enum[val]
              }
            else
              define_method(col) { @raw_values[idx] }
            end
          when :datetime
            define_method(col) { @cast_values[idx] ||= type.send(CASTER, @raw_values[idx])&.in_time_zone }
          when :boolean
            define_method(col) { @cast_values[idx] ||= type.send(CASTER, @raw_values[idx]) }
            define_method("#{col}?") { !!send(col) }
          else
            if enum
              define_method(col) {
                @cast_values[idx] ||= (
                  val = type.send(CASTER, @raw_values[idx])
                  enum.has_key?(val) ? val : inv_enum[val]
                )
              }
            else
              define_method(col) { @cast_values[idx] ||= type.send(CASTER, @raw_values[idx]) }
            end
          end
        end
      end
    end
  end
end
