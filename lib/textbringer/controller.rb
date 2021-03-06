# frozen_string_literal: true

module Textbringer
  TOP_LEVEL_TAG = Object.new
  RECURSIVE_EDIT_TAG = Object.new

  class Controller
    attr_reader :this_command_keys
    attr_accessor :this_command, :last_command, :overriding_map
    attr_accessor :prefix_arg, :current_prefix_arg
    attr_reader :key_sequence, :last_key, :recursive_edit_level
    attr_reader :last_keyboard_macro

    @@current = nil

    def self.current
      @@current
    end

    def self.current=(controller)
      @@current = controller
    end

    def initialize
      @top_self = eval("self", TOPLEVEL_BINDING)
      @key_sequence = []
      @last_key = nil
      @recursive_edit_level = 0
      @this_command_keys = nil
      @this_command = nil
      @last_command = nil
      @overriding_map = nil
      @prefix_arg = nil
      @current_prefix_arg = nil
      @echo_immediately = false
      @recording_keyboard_macro = nil
      @last_keyboard_macro = nil
      @executing_keyboard_macro = nil
    end

    def command_loop(tag)
      catch(tag) do
        loop do
          begin
            echo_input
            c = read_char
            break if c.nil?
            Window.echo_area.clear_message
            @last_key = c
            @key_sequence << @last_key
            cmd = key_binding(@key_sequence)
            if cmd.is_a?(Symbol) || cmd.respond_to?(:call)
              @this_command_keys = @key_sequence
              @key_sequence = []
              @this_command = cmd
              @current_prefix_arg = @prefix_arg
              @prefix_arg = nil
              begin
                run_hooks(:pre_command_hook, remove_on_error: true)
                if cmd.is_a?(Symbol)
                  @top_self.send(cmd)
                else
                  cmd.call
                end
              ensure
                run_hooks(:post_command_hook, remove_on_error: true)
                @last_command = @this_command
                @this_command = nil
              end
            else
              if cmd.nil?
                keys = Keymap.key_sequence_string(@key_sequence)
                @key_sequence.clear
                @prefix_arg = nil
                message("#{keys} is undefined")
              end
            end
            Window.redisplay
          rescue Exception => e
            show_exception(e)
            @prefix_arg = nil
            @recording_keyboard_macro = nil
            Window.redisplay
            if Window.echo_area.active?
              wait_input(2000)
              Window.echo_area.clear_message
              Window.redisplay
            end
          end
        end
      end
    end

    def wait_input(msecs)
      if executing_keyboard_macro?
        return @executing_keyboard_macro.first
      end
      Window.current.wait_input(msecs)
    end

    def read_char
      read_char_with_keyboard_macro(:read_char)
    end

    def read_char_nonblock
      read_char_with_keyboard_macro(:read_char_nonblock)
    end

    def received_keyboard_quit?
      while key = read_char_nonblock
        if GLOBAL_MAP.lookup([key]) == :keyboard_quit
          return true
        end
      end
      false
    end

    def recursive_edit
      @recursive_edit_level += 1
      begin
        if command_loop(RECURSIVE_EDIT_TAG)
          raise Quit
        end
      ensure
        @recursive_edit_level -= 1
      end
    end

    def echo_input
      return if executing_keyboard_macro?
      if @prefix_arg || !@key_sequence.empty?
        if !@echo_immediately
          return if wait_input(1000)
        end
        @echo_immediately = true
        s = String.new
        if @prefix_arg
          s << "C-u"
          if @prefix_arg != [4]
            s << "(#{@prefix_arg.inspect})"
          end
        end
        if !@key_sequence.empty?
          s << " " if !s.empty?
          s << Keymap.key_sequence_string(@key_sequence)
        end
        s << "-"
        Window.echo_area.show(s)
        Window.echo_area.redisplay
        Window.current.window.noutrefresh
        Window.update
      else
        @echo_immediately = false
      end
    end

    def start_keyboard_macro
      if @recording_keyboard_macro
        @recording_keyboard_macro = nil
        raise EditorError, "Already recording keyboard macro"
      end
      @recording_keyboard_macro = []
    end

    def end_keyboard_macro
      if @recording_keyboard_macro.nil?
        raise EditorError, "Not recording keyboard macro"
      end
      if @recording_keyboard_macro.empty?
        raise EditorError, "Empty keyboard macro"
      end
      @recording_keyboard_macro.pop(@this_command_keys.size)
      @last_keyboard_macro = @recording_keyboard_macro
      @recording_keyboard_macro = nil
    end

    def execute_keyboard_macro(macro, n = 1)
      n.times do
        @executing_keyboard_macro = macro.dup
        begin
          recursive_edit
        ensure
          @executing_keyboard_macro = nil
        end
      end
    end

    def call_last_keyboard_macro(n)
      if @last_keyboard_macro.nil?
        raise EditorError, "Keyboard macro not defined"
      end
      execute_keyboard_macro(@last_keyboard_macro, n)
    end

    def recording_keyboard_macro?
      !@recording_keyboard_macro.nil?
    end

    def executing_keyboard_macro?
      !@executing_keyboard_macro.nil?
    end

    def key_binding(key_sequence)
      @overriding_map&.lookup(key_sequence) ||
      Buffer.current&.keymap&.lookup(key_sequence) ||
        GLOBAL_MAP.lookup(key_sequence)
    end

    private

    def read_char_with_keyboard_macro(read_char_method)
      if !executing_keyboard_macro?
        c = call_read_char_method(read_char_method)
        if @recording_keyboard_macro
          @recording_keyboard_macro.push(c)
        end
        c
      else
        @executing_keyboard_macro.shift
      end
    end

    def call_read_char_method(read_char_method)
      Window.current.send(read_char_method)
    end
  end
end
