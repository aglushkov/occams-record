module OccamsRecord
  module EagerLoaders
    # Eager loader for has_one associations.
    class HasOne < Base
      private

      #
      # Yield one or more ActiveRecord::Relation objects to a given block.
      #
      # @param rows [Array<OccamsRecord::Results::Row>] Array of rows used to calculate the query.
      # @yield
      #
      def query(rows)
        return if rows.empty?

        ids = rows.map { |row|
          begin
            row.send @ref.active_record_primary_key
          rescue NoMethodError => e
            raise MissingColumnError.new(row, e.name)
          end
        }.compact.uniq

        q = base_scope.where(@ref.foreign_key => ids)
        q.where!(@ref.type => rows[0].class&.model_name) if @ref.options[:as]
        yield q if ids.any?
      end

      #
      # Merge the association rows into the given rows.
      #
      # @param assoc_rows [Array<OccamsRecord::Results::Row>] rows loaded from the association
      # @param rows [Array<OccamsRecord::Results::Row>] rows loaded from the main model
      #
      def merge!(assoc_rows, rows)
        Merge.new(rows, name).
          single!(assoc_rows, {@ref.active_record_primary_key.to_s => @ref.foreign_key.to_s})
      end
    end
  end
end
