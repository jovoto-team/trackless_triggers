def load_adapter(path)
  begin
    require path
    true
  rescue LoadError
    false
  end
end

MYSQL_ADAPTER_AVAILABLE = load_adapter 'active_record/connection_adapters/mysql_adapter'
MYSQL2_ADAPTER_AVAILABLE = load_adapter 'active_record/connection_adapters/mysql2_adapter'
MYSQL_JDBC_ADAPTER_AVAILABLE = load_adapter 'arjdbc/mysql/adapter'


module ActiveRecord
  class SchemaDumper

    private

    alias trigger_old_tables tables

    def tables(stream)
      trigger_old_tables(stream)

      # dump triggers 
      @connection.tables.sort.each do |tbl|
        next if tbl == 'schema_info'
        dump_table_triggers(tbl, stream)
      end

      # dump functions
      dump_functions(stream)
    end

    def dump_table_triggers(table, stream)
      triggers = @connection.triggers(table)
      triggers.each do |trigger|
        name = trigger.name
        name = name.last if name.is_a? Array

        reference_table = trigger.reference_table
        reference_table = reference_table.last if reference_table.is_a? Array

        timing = trigger.timing
        timing = timing.last if timing.is_a? Array

        event = trigger.event
        event = event.last if event.is_a? Array

        statement = trigger.statement
        statement = statement.last if statement.is_a? Array

        stream.print "  add_trigger \"#{name}\", :on => \"#{reference_table}\", :timing => \"#{timing}\", :event => \"#{event}\", :statement => \"#{statement}\""
        stream.puts
      end
    end

    def dump_functions(stream)
      functions = @connection.functions
      functions.each do |function|
        stream.print "  add_function \"#{function.definition.gsub(/DEFINER=`\w*`@`\w*` /i,'')}\"" if function.definition.present?
        stream.puts
      end
    end

  end

  module ConnectionAdapters
    class TriggerDefinition < Struct.new(:name, :event, :reference_table, :statement, :timing, :created, :sql_mode, :definer, :character_set_client, :collation_connection, :database_collation)
    end

    class FunctionInfoDefinition < Struct.new(:db, :name, :type, :definer, :modified, :created, :security_type, :comment, :charset, :collation, :db_collation)
    end

    class FunctionDefinition < Struct.new(:name, :sql_mode, :definition, :charset, :collation, :db_collation)
    end

    module TriggerFunc
      def triggers(table, name = nil)
        triggers = []
        execute("SHOW TRIGGERS LIKE '#{table}'", name).each do |row|
          row = row.values if row.is_a?(Hash)
          triggers <<  TriggerDefinition.new(*row)
        end

        triggers
      end

      def functions(name = nil)
        function_names = []
        functions = []

        dbname = ActiveRecord::Base.configurations[Rails.env]['database']
        execute("SHOW FUNCTION STATUS WHERE DB='#{dbname}'").each do |row|
          row = row.values if row.is_a?(Hash)
          func_info = FunctionInfoDefinition.new(*row)
          function_names << func_info.name
        end

        function_names.each do |name|
          execute("SHOW CREATE FUNCTION #{name}").each do |row|
            row = row.values if row.is_a?(Hash)
            functions << FunctionDefinition.new(*row)
          end
        end

        functions
      end

    end

    class MysqlAdapter
      include TriggerFunc
    end if MYSQL_JDBC_ADAPTER_AVAILABLE || MYSQL_ADAPTER_AVAILABLE

    class Mysql2Adapter
      include TriggerFunc
    end if MYSQL2_ADAPTER_AVAILABLE

    module SchemaStatements
      def add_trigger(name, opts = {})
        sql = "CREATE TRIGGER #{name} #{opts[:timing]} #{opts[:event]} ON #{opts[:on]} FOR EACH ROW #{opts[:statement]}"
        execute sql
      end

      def drop_trigger(name)
        execute("DROP TRIGGER #{name}")
      end

      def add_function(sql)
        execute sql
      end

      def drop_function(name)
        execute("DROP FUNCTION #{name}")
      end
    end

  end
end
