require "test_helper"

class RailsNexusTest < ActiveSupport::TestCase
  test "it has a version number" do
    assert RailsNexus::VERSION
  end

  test "legacy RailsOps exception logging namespace remains bootable" do
    assert_same RailsNexus::ExceptionLoggable, RailsOps::ExceptionLoggable

    controller = Class.new(ActionController::API) do
      include RailsOps::ExceptionLoggable
    end

    assert_includes controller.ancestors, RailsNexus::ExceptionLoggable
  end

  test "exception handler captures application errors and re-raises them" do
    controller = Class.new do
      include RailsNexus::ExceptionLoggable
      attr_reader :captured

      def log_exception(exception)
        @captured = exception
      end
    end.new
    error = RuntimeError.new("application failure")

    assert_same error, assert_raises(RuntimeError) { controller.log_exception_handler(error) }
    assert_same error, controller.captured
  end

  test "exception handler does not capture fatal exceptions" do
    controller = Class.new do
      include RailsNexus::ExceptionLoggable
      attr_reader :captured

      def log_exception(exception)
        @captured = exception
      end
    end.new
    fatal = SystemExit.new(1)

    assert_same fatal, assert_raises(SystemExit) { controller.log_exception_handler(fatal) }
    assert_nil controller.captured
  end

  test "exception handler preserves the application exception when capture fails" do
    controller = Class.new do
      include RailsNexus::ExceptionLoggable

      def log_exception(_exception)
        raise ActiveRecord::ConnectionNotEstablished, "logging database unavailable"
      end
    end.new
    application_error = RuntimeError.new("application failure")

    raised = assert_raises(RuntimeError) { controller.log_exception_handler(application_error) }

    assert_same application_error, raised
    assert_equal "application failure", raised.message
  end
end
