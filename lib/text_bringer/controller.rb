# frozen_string_literal: true

require "text_bringer/buffer"
require "text_bringer/window"
require "curses"

module TextBringer
  class Controller
    def initialize
      @buffer = nil
      @window = nil
      @key_sequence =[]
      @global_key_map = {}
      setup_keys
    end

    def start(args)
      if args.size > 0
        @buffer = Buffer.open(args[0])
      else
        @buffer = Buffer.new
      end
      Curses.init_screen
      Curses.noecho
      Curses.raw
      begin
        @window = TextBringer::Window.new(@buffer,
                                          Curses.lines - 1, Curses.cols, 0, 0)
        @status_window = Curses::Window.new(1, Curses.cols, Curses.lines - 1, 0)
        @status_message = @status_window << "Quit by C-x C-c"
        @status_window.noutrefresh
        @window.redisplay
        Curses.doupdate
        command_loop
      ensure
        Curses.echo
        Curses.noraw
      end
    end

    private

    def set_key(key_map, key, &command)
      *ks, k = kbd(key)
      ks.inject(key_map) { |map, key|
        map[key] ||= {}
      }[k] = command
    end

    def kbd(key)
      case key
      when Integer
        [key]
      when String
        key.unpack("C*")
      else
        raise TypeError, "invalid key type #{key.class}"
      end
    end

    def key_binding(key_map, key_sequence)
      key_sequence.inject(key_map) { |map, key|
        return nil if map.nil?
        map[key]
      }
    end

    def setup_keys
      set_key(@global_key_map, Curses::KEY_RESIZE) {
        @window.resize(Curses.lines - 1, Curses.cols)
        @status_window.move(Curses.lines - 1, 0)
        @status_window.resize(1, Curses.cols)
        @status_window.noutrefresh
      }
      set_key(@global_key_map, "\C-x\C-c") { exit }
      set_key(@global_key_map, "\C-x\C-s") { @buffer.save }
      set_key(@global_key_map, Curses::KEY_RIGHT) { @buffer.forward_char }
      set_key(@global_key_map, ?\C-f) { @buffer.forward_char }
      set_key(@global_key_map, Curses::KEY_LEFT) { @buffer.backward_char }
      set_key(@global_key_map, ?\C-b) { @buffer.backward_char }
      set_key(@global_key_map, Curses::KEY_DOWN) { @buffer.next_line }
      set_key(@global_key_map, ?\C-n) { @buffer.next_line }
      set_key(@global_key_map, Curses::KEY_UP) { @buffer.previous_line }
      set_key(@global_key_map, ?\C-p) { @buffer.previous_line }
      set_key(@global_key_map, Curses::KEY_DC) { @buffer.delete_char }
      set_key(@global_key_map, ?\C-d) { @buffer.delete_char }
      set_key(@global_key_map, Curses::KEY_BACKSPACE) { @buffer.backward_delete_char }
      set_key(@global_key_map, ?\C-h) { @buffer.backward_delete_char }
      set_key(@global_key_map, ?\C-a) { @buffer.beginning_of_line }
      set_key(@global_key_map, ?\C-e) { @buffer.end_of_line }
      set_key(@global_key_map, "\e<") { @buffer.beginning_of_buffer }
      set_key(@global_key_map, "\e>") { @buffer.end_of_buffer }
      (0x20..0x7e).each do |c|
        set_key(@global_key_map, c) { @buffer.insert(c.chr) }
      end
      set_key(@global_key_map, ?\n) { @buffer.newline }
      set_key(@global_key_map, ?\t) { @buffer.insert("\t") }
      set_key(@global_key_map, "\C- ") { @buffer.set_mark }
      set_key(@global_key_map, "\ew") { @buffer.copy_region }
      set_key(@global_key_map, "\C-w") { @buffer.kill_region }
      set_key(@global_key_map, "\C-k") { @buffer.kill_line }
      set_key(@global_key_map, "\C-y") { @buffer.yank }
    end

    def command_loop
      while c = @window.getch
        if @status_message
          @status_window.erase
          @status_window.noutrefresh
          @status_message = nil
        end
        @key_sequence << c.ord
        cmd = key_binding(@global_key_map, @key_sequence)
        begin
          if cmd.respond_to?(:call)
            @key_sequence.clear
            cmd.call
          else
            if @key_sequence.all? { |c| 0x80 <= c && c <= 0xff }
              s = @key_sequence.pack("C*").force_encoding("utf-8")
              if s.valid_encoding?
                @key_sequence.clear
                @buffer.insert(s)
              end
            elsif cmd.nil?
              keys = @key_sequence.map { |c| Curses.keyname(c) }.join(" ")
              @key_sequence.clear
              @status_message = @status_window << "#{keys} is undefined"
              @status_window.noutrefresh
            end
          end
        rescue => e
          @status_message = @status_window << e.to_s.chomp
          @status_window.noutrefresh
        end
        @window.redisplay
        Curses.doupdate
      end
    end
  end
end