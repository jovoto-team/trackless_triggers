require 'active_record/connection_adapters/abstract_mysql_adapter'

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

      # dump stored procedures
      dump_stored_procedures(stream)
    end

    def dump_table_triggers(table, stream)
      triggers = @connection.triggers(table)
      triggers.each do |trigger|
        stream.print "  add_trigger \"#{trigger.name}\", :on => \"#{trigger.reference_table}\", :timing => \"#{trigger.timing}\", :event => \"#{trigger.event}\", :statement => \"#{trigger.statement}\""
        stream.puts
      end
    end

    def dump_functions(stream)
      functions = @connection.functions
      functions.each do |function|
        stream.print "  add_function \"#{function.definition.gsub(/DEFINER=`\S*`@`\S*` /i,'')}\"" if function.definition.present?
        stream.puts
      end
    end

    def dump_stored_procedures(stream)
      stored_procedures = @connection.stored_procedures
      stored_procedures.each do |stored_procedure|
        stream.print "  add_stored_procedure \"#{stored_procedure.definition.gsub(/DEFINER=`\S*`@`\S*` /i,'')}\"" if stored_procedure.definition.present?
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
          triggers <<  TriggerDefinition.new(*row)
        end

        triggers
      end

      def functions(name = nil)
        function_names = []
        functions = []

        # read the database name from the connection pool - compatible with Padrino and Rails
        dbname = ActiveRecord::Base.connection_db_config.database

        execute("SHOW FUNCTION STATUS WHERE DB='#{dbname}'").each do |row|
          func_info = FunctionInfoDefinition.new(*row)
          function_names << func_info.name
        end

        function_names.each do |name|
          execute("SHOW CREATE FUNCTION #{name}").each do |row|
            functions << FunctionDefinition.new(*row)
          end
        end

        functions
      end

      def stored_procedures(name = nil)
        stored_procedure_names = []
        stored_procedures = []

        # read the database name from the connection pool - compatible with Padrino and Rails
        dbname = ActiveRecord::Base.connection_db_config.database

        execute("SHOW PROCEDURE STATUS WHERE DB='#{dbname}'").each do |row|
          sp_info = FunctionInfoDefinition.new(*row) # ok to use FunctionInfoDefinition to describe SP
          stored_procedure_names << sp_info.name
        end

        stored_procedure_names.each do |name|
          execute("SHOW CREATE PROCEDURE #{name}").each do |row|
            stored_procedures << FunctionDefinition.new(*row) # ok to use FunctionDefinition to describe SP
          end
        end

        stored_procedures
      end

    end

    class MysqlAdapter < AbstractMysqlAdapter
      include TriggerFunc
    end

    class Mysql2Adapter < AbstractMysqlAdapter
      include TriggerFunc
    end

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

      def add_stored_procedure(sql)
        execute sql
      end

      def drop_stored_proceduren(name)
        execute("DROP STORED PROCEDURE #{name}")
      end
    end

  end
end
