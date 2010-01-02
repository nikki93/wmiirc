#--
# Copyright protects this work.
# See LICENSE file for details.
#++

require 'wmiirc'
require 'yaml'

module Wmiirc
  class Config < Hash

    def initialize name
      @source_by_value = {}
      import name, self
    end

    def apply
      script 'before'
      display
      control
      script 'after'
    end

    ##
    # Qualifies the given section name with the YAML file
    # from which the given value originated.  If this is
    # not possible, the given section name is returned.
    #
    def source value, section
      if source = @source_by_value[value]
        "#{source}:in section #{section.inspect}"
      else
        section
      end
    end

    private

    def script key
      Array(self['script']).each do |hash|
        if script = hash[key]
          SANDBOX.eval script, source(script, "script:#{key}")
        end
      end
    end

    def display
      Wmiirc.launch 'xsetroot', '-solid', self['display']['color']['desktop']

      font   = ENV['WMII_FONT']        = self['display']['font']
      focus  = ENV['WMII_FOCUSCOLORS'] = self['display']['color']['focus']
      normal = ENV['WMII_NORMCOLORS']  = self['display']['color']['normal']

      settings = {
        'font'        => font,
        'focuscolors' => focus,
        'normcolors'  => normal,
        'border'      => self['display']['border'],
        'bar on'      => self['display']['bar'],
        'colmode'     => self['display']['column']['mode'],
        'grabmod'     => self['control']['keyboard']['grabmod'],
      }

      begin
        Rumai.fs.ctl.write settings.map {|pair| pair.join(' ') }.join("\n")
        Rumai.fs.colrules.write self['display']['column']['rule']
      rescue Rumai::IXP::Error => e
        #
        # settings that are not supported in a particular wmii version
        # are ignored, and those that are supported are (silently)
        # applied.  but a "bad command" error is raised nevertheless!
        #
        warn e.inspect
        warn e.backtrace.join("\n")
      end
    end

    def control
      %w[event action keyboard_action].each do |section|
        if settings = self['control'][section]
          settings.each do |key, code|
            if section == 'keyboard_action'
              # expand ${...} in keyboard shortcuts
              key = key.gsub(/\$\{(.+?)\}/) do
                self['control']['keyboard'][$1]
              end

              meth = 'key'
              name = code
              code = self['control']['action'][name]
            else
              name = key
              meth = section
            end

            SANDBOX.eval(
              "#{meth}(#{key.inspect}) {|*argv| #{code} }",
              source(code, "control:#{section}:#{name}")
            )
          end
        end
      end

      # register keyboard shortcuts
      SANDBOX.eval do
        fs.keys.write keys.join("\n")
        event('Key') {|*a| key(*a) }
      end
    end

    def import paths, merged = {}, imported = []
      Array(paths).each do |path|
        path = File.join(Wmiirc::DIR, path) + '.yaml'
        partial = YAML.load_file(path)

        trace partial, path

        imports = Array(partial['import'])

        # prevent cycles
        imports -= imported
        imported.concat imports

        import imports, merged, imported
        merge partial, merged, path
      end

      merged
    end

    def trace partial, source
      if partial.kind_of? String
        @source_by_value[partial] = source

      elsif partial.respond_to? :each
        partial.each do |*values|
          values.each do |v|
            trace v, source
          end
        end
      end
    end

    def merge src_hash, dst_hash, src_file
      src_hash.each_pair do |key, src_val|
        next if src_val.nil?

        if dst_val = dst_hash[key]
          # merge the values
          case dst_val
          when Hash
            merge src_val, dst_val, src_file

          when Array
            case src_val
            when Array
              dst_val.concat src_val
            else
              dst_val.push src_val
            end

          else
            raise NotImplementedError, 'merge %s into %s for key %s in %s' % [
              src_val.inspect, dst_val.inspect, key.inspect, src_file.inspect
            ]
          end
        else
          # inherit the value
          dst_hash[key] = src_val
        end
      end
    end

  end
end
